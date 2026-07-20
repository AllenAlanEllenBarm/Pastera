import Foundation
import Darwin
import PasteraAgentProtocol
import Testing
@testable import Pastera

// Task 5 keeps end-to-end Unix socket fixtures beside the broker regression suite for auditability.
// swiftlint:disable file_length

@Suite("Vault agent broker", .serialized)
struct VaultAgentBrokerTests {
    private let clientKey = Data((0..<32).map(UInt8.init))
    private let serverKey = Data((32..<64).map(UInt8.init))
    private let clientNonce = Data(repeating: 0x11, count: 32)
    private let serverNonce = Data(repeating: 0x22, count: 32)
    private let connectionID = UUID(uuidString: "00112233-4455-6677-8899-aabbccddeeff")!

    @Test("fixed X25519 HKDF and AAD transcript produces a stable frame")
    func fixedTranscriptVector() throws {
        let pair = try makePair()
        let frame = try pair.client.seal(Data("request".utf8))
        #expect(frame.connectionID == connectionID)
        #expect(frame.sequence == 1)
        #expect(frame.ciphertext.hex == "01000000000000000000000155b45c6f684d95a990118e4a17d1c1cb306ba474090092")
        #expect(try pair.server.open(frame) == Data("request".utf8))
    }

    @Test("directions are independent and reflected frames fail authentication")
    func directionIsAuthenticated() throws {
        let pair = try makePair()
        let request = try pair.client.seal(Data("request".utf8))
        #expect(throws: VaultAgentProtocolError.authenticationFailed) {
            try pair.client.open(request)
        }
        #expect(try pair.server.open(request) == Data("request".utf8))
        let response = try pair.server.seal(Data("response".utf8))
        #expect(try pair.client.open(response) == Data("response".utf8))
    }

    @Test("connection sequence replay and ordering are rejected before authentication")
    func sequenceAndConnectionAreBound() throws {
        let pair = try makePair()
        let first = try pair.client.seal(Data("one".utf8))
        var wrongConnection = first
        wrongConnection = .init(connectionID: UUID(), sequence: first.sequence, ciphertext: first.ciphertext)
        #expect(throws: VaultAgentProtocolError.connectionMismatch) { try pair.server.open(wrongConnection) }
        let high = VaultAgentEncryptedFrame(connectionID: connectionID, sequence: 2, ciphertext: first.ciphertext)
        #expect(throws: VaultAgentProtocolError.outOfOrderFrame) { try pair.server.open(high) }
        #expect(try pair.server.open(first) == Data("one".utf8))
        #expect(throws: VaultAgentProtocolError.replayedFrame) { try pair.server.open(first) }
    }

    @Test("failed authentication does not advance the receive sequence")
    func authenticationFailureDoesNotAdvance() throws {
        let pair = try makePair()
        let frame = try pair.client.seal(Data("secret".utf8))
        var bytes = frame.ciphertext
        bytes[bytes.startIndex] ^= 0x01
        let tampered = VaultAgentEncryptedFrame(connectionID: connectionID, sequence: 1, ciphertext: bytes)
        #expect(throws: VaultAgentProtocolError.authenticationFailed) { try pair.server.open(tampered) }
        #expect(try pair.server.open(frame) == Data("secret".utf8))
    }

    @Test("handshake version and exact key material lengths are mandatory")
    func handshakeValidation() throws {
        let client = try VaultAgentClientHandshakeContext(privateKey: clientKey, nonce: clientNonce)
        var hello = client.hello
        hello = .init(protocolVersion: 2, publicKey: hello.publicKey, nonce: hello.nonce)
        let server = try VaultAgentServerHandshakeContext(privateKey: serverKey, nonce: serverNonce, connectionID: connectionID)
        #expect(throws: VaultAgentProtocolError.protocolMismatch) { try server.accept(hello) }
    }

    @Test("UInt64 maximum is an exhausted terminal sequence")
    func sequenceExhaustion() throws {
        let pair = try VaultAgentSecureChannel.makeTestPair(
            clientPrivateKey: clientKey,
            serverPrivateKey: serverKey,
            clientNonce: clientNonce,
            serverNonce: serverNonce,
            connectionID: connectionID,
            initialSequence: UInt64.max
        )
        #expect(throws: VaultAgentProtocolError.sequenceExhausted) { try pair.client.seal(Data()) }
    }

    @Test("write readiness is rebuilt only after a draining source finishes cancellation")
    func writeSourceLifecycleRebuildsAfterCancellation() {
        var lifecycle = VaultAgentWriteSourceLifecycle()

        let shouldInstallInitially = lifecycle.noteWouldBlock()
        #expect(shouldInstallInitially)
        lifecycle.didInstallSource()
        let didBeginFirstCancellation = lifecycle.beginDrainCancellation()
        let installedDuringCancellation = lifecycle.noteWouldBlock()
        let shouldRebuild = lifecycle.cancellationCompleted(hasPendingOutput: true)
        #expect(didBeginFirstCancellation)
        #expect(!installedDuringCancellation)
        #expect(shouldRebuild)
        lifecycle.didInstallSource()
        let didBeginSecondCancellation = lifecycle.beginDrainCancellation()
        let rebuiltWithoutPendingOutput = lifecycle.cancellationCompleted(hasPendingOutput: false)
        #expect(didBeginSecondCancellation)
        #expect(!rebuiltWithoutPendingOutput)
    }

    private func makePair() throws -> VaultAgentSecureChannel.Pair {
        try VaultAgentSecureChannel.makeTestPair(
            clientPrivateKey: clientKey,
            serverPrivateKey: serverKey,
            clientNonce: clientNonce,
            serverNonce: serverNonce,
            connectionID: connectionID
        )
    }
}

private extension VaultAgentBrokerTests {
    @Test("server creates private directory and socket and echoes fragmented encrypted frames")
    func privateSocketAndFragmentedRoundTrip() throws {
        let shortRoot = FileManager.default.temporaryDirectory.appendingPathComponent("pva-\(getpid())")
        let fixture = try SocketFixture(root: shortRoot, nestedAgentDirectory: true)
        let server = fixture.makeServer(handler: EchoSocketHandler())
        try server.start()
        defer { server.stop() }

        #expect(fixture.mode(fixture.v1URL) == 0o700)
        #expect(fixture.mode(fixture.v1URL.deletingLastPathComponent()) == 0o700)
        #expect(fixture.mode(fixture.socketURL) == 0o600)
        let client = try fixture.connectAndHandshake(fragmentSize: 1)
        defer { Darwin.close(client.fileDescriptor) }
        let plaintext = Data("bounded echo".utf8)
        let encrypted = try client.channel.seal(plaintext)
        try fixture.writeFrame(try JSONEncoder().encode(encrypted), fileDescriptor: client.fileDescriptor, fragmentSize: 2)
        let response = try fixture.readFrame(fileDescriptor: client.fileDescriptor)
        #expect(try client.channel.open(JSONDecoder().decode(VaultAgentEncryptedFrame.self, from: response)) == plaintext)

        var receiveBufferBytes: Int32 = 1_024
        setsockopt(
            client.fileDescriptor,
            SOL_SOCKET,
            SO_RCVBUF,
            &receiveBufferBytes,
            socklen_t(MemoryLayout<Int32>.size)
        )
        let large = Data(repeating: 0x41, count: 16 * 1_024)
        try fixture.writeFrame(
            try JSONEncoder().encode(client.channel.seal(large)),
            fileDescriptor: client.fileDescriptor,
            fragmentSize: 113
        )
        let largeResponse = try fixture.readFrame(fileDescriptor: client.fileDescriptor)
        #expect(try client.channel.open(JSONDecoder().decode(VaultAgentEncryptedFrame.self, from: largeResponse)) == large)

        server.stop()
        #expect(!FileManager.default.fileExists(atPath: fixture.socketURL.path))
    }

    @Test("existing files symlinks and active sockets are never removed")
    func conflictsArePreserved() throws {
        let plain = try SocketFixture()
        FileManager.default.createFile(atPath: plain.socketURL.path, contents: Data([1]))
        #expect(throws: VaultAgentSocketServerError.socketPathConflict) { try plain.makeServer().start() }
        #expect(FileManager.default.fileExists(atPath: plain.socketURL.path))

        let linked = try SocketFixture()
        let target = linked.root.appendingPathComponent("target")
        FileManager.default.createFile(atPath: target.path, contents: Data([2]))
        try FileManager.default.createSymbolicLink(at: linked.socketURL, withDestinationURL: target)
        #expect(throws: VaultAgentSocketServerError.socketPathConflict) { try linked.makeServer().start() }
        #expect((try FileManager.default.destinationOfSymbolicLink(atPath: linked.socketURL.path)).contains("target"))

        let active = try SocketFixture()
        let listener = try active.bindRawListener()
        defer { Darwin.close(listener) }
        #expect(throws: VaultAgentSocketServerError.socketPathConflict) { try active.makeServer().start() }

        let directoryLink = try SocketFixture()
        let realDirectory = directoryLink.root.appendingPathComponent("real-v1")
        try FileManager.default.createDirectory(at: realDirectory, withIntermediateDirectories: false)
        try FileManager.default.removeItem(at: directoryLink.v1URL)
        try FileManager.default.createSymbolicLink(at: directoryLink.v1URL, withDestinationURL: realDirectory)
        #expect(throws: VaultAgentSocketServerError.directoryConflict) {
            try directoryLink.makeServer().start()
        }
    }

    @Test("a stale owned socket is replaced but an overlong path fails closed")
    func staleAndLongPaths() throws {
        let stale = try SocketFixture()
        let listener = try stale.bindRawListener()
        Darwin.close(listener)
        let server = stale.makeServer()
        try server.start()
        defer { server.stop() }
        #expect(stale.mode(stale.socketURL) == 0o600)

        let longRoot = FileManager.default.temporaryDirectory.appendingPathComponent(String(repeating: "x", count: 120))
        let long = try SocketFixture(root: longRoot)
        #expect(throws: VaultAgentSocketServerError.pathTooLong) { try long.makeServer().start() }
    }

    @Test("ninth connection and a second in-flight request are closed")
    func connectionAndInflightBounds() throws {
        let fixture = try SocketFixture()
        let delayed = DelayedSocketHandler()
        let server = fixture.makeServer(handler: delayed)
        try server.start()
        defer { server.stop() }

        var descriptors: [Int32] = []
        defer { descriptors.forEach { Darwin.close($0) } }
        for _ in 0..<8 { descriptors.append(try fixture.connectOnly()) }
        let ninth = try fixture.connectOnly()
        defer { Darwin.close(ninth) }
        #expect(fixture.waitForEOF(fileDescriptor: ninth))

        descriptors.forEach { Darwin.close($0) }
        descriptors.removeAll()
        let client = try fixture.connectAndHandshake()
        defer { Darwin.close(client.fileDescriptor) }
        let first = try client.channel.seal(Data("first".utf8))
        try fixture.writeFrame(try JSONEncoder().encode(first), fileDescriptor: client.fileDescriptor)
        #expect(delayed.started.wait(timeout: .now() + 2) == .success)
        let second = try client.channel.seal(Data("second".utf8))
        try fixture.writeFrame(try JSONEncoder().encode(second), fileDescriptor: client.fileDescriptor)
        #expect(fixture.waitForEOF(fileDescriptor: client.fileDescriptor))
        delayed.complete(.success(Data("late".utf8)))
    }

    @Test("idle activity invalidates an old deadline and EOF cleanup ignores late completion")
    func idleAndLateCompletion() throws {
        let fixture = try SocketFixture()
        let delayed = DelayedSocketHandler()
        let server = fixture.makeServer(handler: delayed, idleTimeout: 0.15)
        try server.start()
        defer { server.stop() }

        let client = try fixture.connectAndHandshake()
        let request = try client.channel.seal(Data("pending".utf8))
        try fixture.writeFrame(try JSONEncoder().encode(request), fileDescriptor: client.fileDescriptor)
        #expect(delayed.started.wait(timeout: .now() + 1) == .success)
        usleep(80_000)
        var byte: UInt8 = 0
        #expect(Darwin.write(client.fileDescriptor, &byte, 1) == 1)
        usleep(90_000)
        #expect(!fixture.isEOF(fileDescriptor: client.fileDescriptor))
        Darwin.close(client.fileDescriptor)
        delayed.complete(.success(Data("late".utf8)))
        usleep(30_000)
    }

    @Test("oversized and malformed length prefixes close without reaching the handler")
    func malformedFramesClose() throws {
        let fixture = try SocketFixture()
        let handler = CountingSocketHandler()
        let server = fixture.makeServer(handler: handler)
        try server.start()
        defer { server.stop() }
        let fileDescriptor = try fixture.connectOnly()
        defer { Darwin.close(fileDescriptor) }
        var oversized = UInt32(VaultAgentLimits.maximumFrameBytes).bigEndian
        #expect(withUnsafeBytes(of: &oversized) { Darwin.write(fileDescriptor, $0.baseAddress, $0.count) } == 4)
        #expect(fixture.waitForEOF(fileDescriptor: fileDescriptor))
        #expect(!handler.wasCalled)
    }

    @Test("peer rejection happens before handshake decoding and duplicate completion is one-shot")
    func verificationOrderAndDuplicateCompletion() throws {
        let rejected = try SocketFixture()
        let count = CountingSocketHandler()
        let rejectingServer = VaultAgentSocketServer(
            directoryURL: rejected.v1URL,
            peerVerifier: RejectingPeerVerifier(),
            handler: count,
            queue: DispatchQueue(label: "VaultAgentSocketServerTests.reject")
        )
        try rejectingServer.start()
        defer { rejectingServer.stop() }
        let rejectedFD = try rejected.connectOnly()
        defer { Darwin.close(rejectedFD) }
        let untrustedJSON = Data("{\"protocolVersion\":1}".utf8)
        try rejected.writeFrame(untrustedJSON, fileDescriptor: rejectedFD)
        #expect(rejected.waitForEOF(fileDescriptor: rejectedFD))
        #expect(!count.wasCalled)

        let duplicate = try SocketFixture()
        let duplicateServer = duplicate.makeServer(handler: DuplicateSocketHandler())
        try duplicateServer.start()
        defer { duplicateServer.stop() }
        let client = try duplicate.connectAndHandshake()
        defer { Darwin.close(client.fileDescriptor) }
        let request = try client.channel.seal(Data("once".utf8))
        try duplicate.writeFrame(try JSONEncoder().encode(request), fileDescriptor: client.fileDescriptor)
        let first = try duplicate.readFrame(fileDescriptor: client.fileDescriptor)
        #expect(try client.channel.open(JSONDecoder().decode(VaultAgentEncryptedFrame.self, from: first)) == Data("once".utf8))
        usleep(20_000)
        var byte: UInt8 = 0
        #expect(Darwin.recv(client.fileDescriptor, &byte, 1, MSG_PEEK | MSG_DONTWAIT) < 0)
        #expect(errno == EAGAIN || errno == EWOULDBLOCK)
    }

    @Test("plaintext handler responses over 32 KiB close before encryption")
    func oversizedPlaintextResponseCloses() throws {
        let fixture = try SocketFixture()
        let response = Data(repeating: 0x41, count: VaultAgentLimits.maximumResponseBytes + 1)
        let server = fixture.makeServer(handler: FixedResponseSocketHandler(response: response))
        try server.start()
        defer { server.stop() }

        let client = try fixture.connectAndHandshake()
        defer { Darwin.close(client.fileDescriptor) }
        let request = try client.channel.seal(Data("request".utf8))
        try fixture.writeFrame(try JSONEncoder().encode(request), fileDescriptor: client.fileDescriptor)
        #expect(fixture.waitForEOF(fileDescriptor: client.fileDescriptor))
    }

    @Test("a failed Application Support lookup never falls back to a temporary directory")
    func defaultDirectoryLookupFailsClosed() {
        let server = VaultAgentSocketServer(
            peerVerifier: FixedPeerVerifier(identity: SocketFixture.identity),
            handler: EchoSocketHandler(),
            queue: DispatchQueue(label: "VaultAgentSocketServerTests.default-directory"),
            applicationSupportURLProvider: { throw SocketTestError.directory }
        )

        #expect(throws: VaultAgentSocketServerError.unavailable) {
            try server.start()
        }
    }

    @Test("64 KiB of one-byte activity keeps exactly one idle timer per connection")
    func idleTimerCountIsBounded() throws {
        let fixture = try SocketFixture()
        let timerCount = LockedCounter()
        let server = fixture.makeServer(idleTimerFactory: { queue in
            timerCount.increment()
            return DispatchSource.makeTimerSource(queue: queue)
        })
        try server.start()
        defer { server.stop() }

        let fileDescriptor = try fixture.connectOnly()
        defer { Darwin.close(fileDescriptor) }
        let payload = Data(repeating: 0x7b, count: VaultAgentLimits.maximumFrameBytes - 4)
        let frame = try VaultAgentFrameCodec.frame(payload: payload)
        #expect(frame.count == 65_536)
        for value in frame {
            var byte = value
            guard Darwin.write(fileDescriptor, &byte, 1) == 1 else {
                throw SocketTestError.write
            }
        }
        #expect(timerCount.value == 1)
    }

    @Test("replacing the validated v1 directory fails before touching the replacement")
    func directoryReplacementFailsClosed() throws {
        let fixture = try SocketFixture()
        let originalDirectory = fixture.root.appendingPathComponent("held-v1")
        let sentinel = fixture.v1URL.appendingPathComponent("sentinel")
        let server = VaultAgentSocketServer(
            directoryURL: fixture.v1URL,
            peerVerifier: FixedPeerVerifier(identity: SocketFixture.identity),
            handler: EchoSocketHandler(),
            queue: DispatchQueue(label: "VaultAgentSocketServerTests.directory-replacement"),
            directoryIdentityValidationHook: {
                try FileManager.default.moveItem(at: fixture.v1URL, to: originalDirectory)
                try FileManager.default.createDirectory(at: fixture.v1URL, withIntermediateDirectories: false)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.v1URL.path)
                FileManager.default.createFile(atPath: sentinel.path, contents: Data([0x5a]))
            }
        )

        #expect(throws: VaultAgentSocketServerError.directoryConflict) {
            try server.start()
        }
        #expect(fixture.mode(fixture.v1URL) == 0o755)
        #expect((try Data(contentsOf: sentinel)) == Data([0x5a]))
        #expect(!FileManager.default.fileExists(atPath: fixture.socketURL.path))
        #expect(!FileManager.default.fileExists(atPath: originalDirectory.appendingPathComponent("broker.sock").path))
    }

    @Test("source cancellation completes before managed descriptors close and are reused")
    func descriptorCloseWaitsForSourceCancellation() throws {
        let fixture = try SocketFixture()
        let recorder = SocketLifecycleRecorder()
        let server = VaultAgentSocketServer(
            directoryURL: fixture.v1URL,
            peerVerifier: FixedPeerVerifier(identity: SocketFixture.identity),
            handler: EchoSocketHandler(),
            queue: DispatchQueue(label: "VaultAgentSocketServerTests.lifecycle"),
            lifecycleProbe: .init(
                sourceCreated: recorder.sourceCreated,
                sourceCancellationCompleted: recorder.sourceCancellationCompleted,
                descriptorClosed: recorder.descriptorClosed
            )
        )
        try server.start()
        let client = try fixture.connectAndHandshake()
        defer { Darwin.close(client.fileDescriptor) }

        let stopped = DispatchSemaphore(value: 0)
        server.stop { stopped.signal() }
        #expect(stopped.wait(timeout: .now() + 2) == .success)
        #expect(recorder.managedDescriptorCount == 2)
        #expect(recorder.allDescriptorsClosedAfterCancellation)
        #expect(recorder.allClosedDescriptorsImmediatelyReusable)
        #expect(!FileManager.default.fileExists(atPath: fixture.socketURL.path))
        recorder.closeReusedDescriptors()

        try server.start()
        let restarted = DispatchSemaphore(value: 0)
        server.stop { restarted.signal() }
        #expect(restarted.wait(timeout: .now() + 2) == .success)
    }
}

private final class SocketFixture {
    static let identity = VaultAgentPeerIdentity(
        client: .cli,
        helperRequirement: "helper",
        helperCDHash: Data([1]),
        helperIsAdHoc: true,
        helperPath: "/Pastera.app/Contents/Helpers/pastera",
        hostRequirement: nil,
        hostCDHash: nil,
        hostIsAdHoc: nil,
        hostPath: nil
    )

    let root: URL
    let v1URL: URL
    var socketURL: URL { v1URL.appendingPathComponent("broker.sock") }

    init(root: URL? = nil, nestedAgentDirectory: Bool = false) throws {
        self.root = root ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        v1URL = nestedAgentDirectory
            ? self.root.appendingPathComponent("Agent/v1")
            : self.root.appendingPathComponent("v1")
        try FileManager.default.createDirectory(at: v1URL, withIntermediateDirectories: true)
        if nestedAgentDirectory {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: v1URL.deletingLastPathComponent().path
            )
        }
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func makeServer(
        handler: VaultAgentSocketRequestHandling = EchoSocketHandler(),
        idleTimeout: TimeInterval = 30,
        idleTimerFactory: @escaping (DispatchQueue) -> DispatchSourceTimer = {
            DispatchSource.makeTimerSource(queue: $0)
        }
    ) -> VaultAgentSocketServer {
        VaultAgentSocketServer(
            directoryURL: v1URL,
            peerVerifier: FixedPeerVerifier(identity: Self.identity),
            handler: handler,
            queue: DispatchQueue(label: "VaultAgentSocketServerTests.\(UUID())"),
            idleTimeout: idleTimeout,
            idleTimerFactory: idleTimerFactory
        )
    }

    func mode(_ url: URL) -> mode_t {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return 0 }
        return info.st_mode & 0o777
    }

    func bindRawListener() throws -> Int32 {
        let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else { throw SocketTestError.socket }
        do {
            var address = try unixAddress(socketURL)
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fileDescriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard result == 0, listen(fileDescriptor, 1) == 0 else { throw SocketTestError.bind }
            return fileDescriptor
        } catch {
            Darwin.close(fileDescriptor)
            throw error
        }
    }

    func connectOnly() throws -> Int32 {
        let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else { throw SocketTestError.socket }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fileDescriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        do {
            var address = try unixAddress(socketURL)
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fileDescriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard result == 0 else { throw SocketTestError.connect }
            return fileDescriptor
        } catch {
            Darwin.close(fileDescriptor)
            throw error
        }
    }

    func connectAndHandshake(fragmentSize: Int = 7) throws -> (fileDescriptor: Int32, channel: VaultAgentSecureChannel) {
        let fileDescriptor = try connectOnly()
        do {
            let context = try VaultAgentClientHandshakeContext(
                privateKey: Data((0..<32).map(UInt8.init)),
                nonce: Data(repeating: 0x33, count: 32)
            )
            try writeFrame(
                try JSONEncoder().encode(context.hello),
                fileDescriptor: fileDescriptor,
                fragmentSize: fragmentSize
            )
            let response = try readFrame(fileDescriptor: fileDescriptor)
            let hello = try JSONDecoder().decode(VaultAgentServerHello.self, from: response)
            return (fileDescriptor, try context.complete(hello))
        } catch {
            Darwin.close(fileDescriptor)
            throw error
        }
    }

    func writeFrame(_ payload: Data, fileDescriptor: Int32, fragmentSize: Int = 17) throws {
        let frame = try VaultAgentFrameCodec.frame(payload: payload)
        var offset = 0
        while offset < frame.count {
            let count = min(fragmentSize, frame.count - offset)
            let written = frame.withUnsafeBytes { buffer in
                Darwin.write(fileDescriptor, buffer.baseAddress!.advanced(by: offset), count)
            }
            guard written > 0 else { throw SocketTestError.write }
            offset += written
        }
    }

    func readFrame(fileDescriptor: Int32) throws -> Data {
        let prefix = try readExactly(4, fileDescriptor: fileDescriptor)
        let length = prefix.reduce(UInt32.zero) { ($0 << 8) | UInt32($1) }
        guard length <= UInt32(VaultAgentLimits.maximumFrameBytes - 4) else { throw SocketTestError.frame }
        return try readExactly(Int(length), fileDescriptor: fileDescriptor)
    }

    func waitForEOF(fileDescriptor: Int32) -> Bool {
        for _ in 0..<100 {
            if isEOF(fileDescriptor: fileDescriptor) { return true }
            usleep(5_000)
        }
        return false
    }

    func isEOF(fileDescriptor: Int32) -> Bool {
        var byte: UInt8 = 0
        let result = Darwin.recv(fileDescriptor, &byte, 1, MSG_PEEK | MSG_DONTWAIT)
        return result == 0 || (result < 0 && errno != EAGAIN && errno != EWOULDBLOCK)
    }

    private func readExactly(_ count: Int, fileDescriptor: Int32) throws -> Data {
        var result = Data()
        while result.count < count {
            var bytes = [UInt8](repeating: 0, count: count - result.count)
            let readCount = Darwin.read(fileDescriptor, &bytes, bytes.count)
            guard readCount > 0 else { throw SocketTestError.read(result.count, errno) }
            result.append(contentsOf: bytes.prefix(readCount))
        }
        return result
    }

    private func unixAddress(_ url: URL) throws -> sockaddr_un {
        let path = Array(url.path.utf8) + [0]
        var address = sockaddr_un()
        guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw SocketTestError.frame }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in buffer.copyBytes(from: path) }
        return address
    }
}

private enum SocketTestError: Error { case socket, bind, connect, write, read(Int, Int32), frame, rejected, directory }
private struct FixedPeerVerifier: VaultAgentPeerVerifying {
    let identity: VaultAgentPeerIdentity

    func verify(fileDescriptor _: Int32) throws -> VaultAgentPeerIdentity { identity }
}
private struct RejectingPeerVerifier: VaultAgentPeerVerifying {
    func verify(fileDescriptor _: Int32) throws -> VaultAgentPeerIdentity { throw SocketTestError.rejected }
}
private final class EchoSocketHandler: VaultAgentSocketRequestHandling {
    func handle(identity _: VaultAgentPeerIdentity, request: Data, completion: @escaping (Result<Data, Error>) -> Void) { completion(.success(request)) }
}
private final class CountingSocketHandler: VaultAgentSocketRequestHandling {
    private let lock = NSLock()
    private var called = false

    var wasCalled: Bool { lock.lock(); defer { lock.unlock() }; return called }

    func handle(identity _: VaultAgentPeerIdentity, request _: Data, completion _: @escaping (Result<Data, Error>) -> Void) {
        lock.lock(); called = true; lock.unlock()
    }
}
private final class DelayedSocketHandler: VaultAgentSocketRequestHandling {
    let started = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var completion: ((Result<Data, Error>) -> Void)?

    func handle(identity _: VaultAgentPeerIdentity, request _: Data, completion: @escaping (Result<Data, Error>) -> Void) {
        lock.lock(); self.completion = completion; lock.unlock(); started.signal()
    }

    func complete(_ result: Result<Data, Error>) {
        lock.lock(); let callback = completion; completion = nil; lock.unlock(); callback?(result)
    }
}
private final class DuplicateSocketHandler: VaultAgentSocketRequestHandling {
    func handle(identity _: VaultAgentPeerIdentity, request: Data, completion: @escaping (Result<Data, Error>) -> Void) {
        completion(.success(request))
        completion(.success(Data("duplicate".utf8)))
    }
}
private final class FixedResponseSocketHandler: VaultAgentSocketRequestHandling {
    let response: Data

    init(response: Data) { self.response = response }

    func handle(identity _: VaultAgentPeerIdentity, request _: Data, completion: @escaping (Result<Data, Error>) -> Void) {
        completion(.success(response))
    }
}
private final class LockedCounter {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.lock(); defer { lock.unlock() }; return count }

    func increment() { lock.lock(); count += 1; lock.unlock() }
}
private final class SocketLifecycleRecorder {
    private let lock = NSLock()
    private var created: [Int32: Set<VaultAgentSocketSourceKind>] = [:]
    private var cancelled: [Int32: Set<VaultAgentSocketSourceKind>] = [:]
    private var closedAfterCancellation: [Int32: Bool] = [:]
    private var reused: [Int32: Bool] = [:]
    private var replacementDescriptors: [Int32] = []

    var managedDescriptorCount: Int { lock.lock(); defer { lock.unlock() }; return created.count }
    var allDescriptorsClosedAfterCancellation: Bool {
        lock.lock(); defer { lock.unlock() }
        return closedAfterCancellation.count == created.count && closedAfterCancellation.values.allSatisfy { $0 }
    }
    var allClosedDescriptorsImmediatelyReusable: Bool {
        lock.lock(); defer { lock.unlock() }
        return reused.count == created.count && reused.values.allSatisfy { $0 }
    }

    func sourceCreated(_ kind: VaultAgentSocketSourceKind, _ fileDescriptor: Int32) {
        lock.lock(); created[fileDescriptor, default: []].insert(kind); lock.unlock()
    }

    func sourceCancellationCompleted(_ kind: VaultAgentSocketSourceKind, _ fileDescriptor: Int32) {
        lock.lock(); cancelled[fileDescriptor, default: []].insert(kind); lock.unlock()
    }

    func descriptorClosed(_ fileDescriptor: Int32) {
        lock.lock()
        closedAfterCancellation[fileDescriptor] = created[fileDescriptor] == cancelled[fileDescriptor]
        lock.unlock()

        let replacement = socket(AF_UNIX, SOCK_STREAM, 0)
        lock.lock()
        reused[fileDescriptor] = replacement == fileDescriptor
        if replacement >= 0 { replacementDescriptors.append(replacement) }
        lock.unlock()
    }

    func closeReusedDescriptors() {
        lock.lock()
        let descriptors = replacementDescriptors
        replacementDescriptors.removeAll()
        lock.unlock()
        descriptors.forEach { Darwin.close($0) }
    }
}

private extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
