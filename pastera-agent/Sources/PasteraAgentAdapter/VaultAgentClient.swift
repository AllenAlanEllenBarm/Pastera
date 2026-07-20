import CryptoKit
import Darwin
import Foundation
import PasteraAgentProtocol
import Security

// The task boundary requires the complete client transport and crypto channel in this file.
// swiftlint:disable file_length

public protocol VaultAgentRequesting: Sendable {
    func request(_ operation: VaultAgentOperation) async throws -> VaultAgentResponseBody
}

enum VaultAgentClientError: Error, Equatable {
    case unavailable
    case timedOut
    case cancelled
    case protocolFailure
}

struct VaultAgentApplicationSupportFileManager: Sendable {
    static let live = Self {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
    }

    private let locate: @Sendable () throws -> URL

    init(applicationSupportURL: URL) {
        locate = { applicationSupportURL }
    }

    private init(locate: @escaping @Sendable () throws -> URL) {
        self.locate = locate
    }

    func applicationSupportURL() throws -> URL { try locate() }
}

enum VaultAgentConnectionRetrier {
    static let delays = [50, 100, 200, 400, 800]

    static func connect<Value: Sendable>(
        connect: @Sendable () throws -> Value,
        launch: @Sendable () throws -> Void,
        sleep: @Sendable (Int) async throws -> Void
    ) async throws -> Value {
        do {
            return try connect()
        } catch {
            do {
                try launch()
            } catch {
                throw VaultAgentClientError.unavailable
            }
        }

        for delay in delays {
            do {
                try await sleep(delay)
            } catch is CancellationError {
                throw VaultAgentClientError.cancelled
            } catch {
                throw VaultAgentClientError.unavailable
            }
            do {
                return try connect()
            } catch {
                continue
            }
        }
        throw VaultAgentClientError.unavailable
    }
}

public actor VaultAgentClient: VaultAgentRequesting {
    struct Dependencies: @unchecked Sendable {
        var socketURL: @Sendable () throws -> URL
        var executableURL: @Sendable () -> URL?
        var launch: @Sendable (URL) throws -> Void
        var sleep: @Sendable (Int) async throws -> Void
        var connect: @Sendable (URL, UInt64) throws -> Int32
        var nonce: @Sendable () throws -> Data
        var privateKey: @Sendable () throws -> Curve25519.KeyAgreement.PrivateKey
        var now: @Sendable () -> UInt64

        static let live = Self(
            socketURL: { try VaultAgentClient.defaultSocketURL() },
            executableURL: { Bundle.main.executableURL },
            launch: VaultAgentClient.launchApplication,
            sleep: { milliseconds in
                try await Task.sleep(for: .milliseconds(milliseconds))
            },
            connect: VaultAgentClient.connectSocket,
            nonce: VaultAgentClient.randomNonce,
            privateKey: { Curve25519.KeyAgreement.PrivateKey() },
            now: { DispatchTime.now().uptimeNanoseconds }
        )
    }

    private final class Connection {
        let fileDescriptor: Int32
        let channel: VaultAgentClientSecureChannel

        init(fileDescriptor: Int32, channel: VaultAgentClientSecureChannel) {
            self.fileDescriptor = fileDescriptor
            self.channel = channel
        }

        deinit { Darwin.close(fileDescriptor) }
    }

    private static let requestTimeoutNanoseconds: UInt64 = 10_000_000_000
    private let client: VaultAgentClientKind
    private let dependencies: Dependencies
    private var connection: Connection?

    public init(client: VaultAgentClientKind) {
        self.client = client
        dependencies = .live
    }

    init(client: VaultAgentClientKind, dependencies: Dependencies) {
        self.client = client
        self.dependencies = dependencies
    }

    public func request(_ operation: VaultAgentOperation) async throws -> VaultAgentResponseBody {
        let deadline = dependencies.now().addingReportingOverflow(Self.requestTimeoutNanoseconds)
        guard !deadline.overflow else { throw VaultAgentClientError.timedOut }
        do {
            try Task.checkCancellation()
            let activeConnection = try await activeConnection(deadline: deadline.partialValue)
            let requestID = UUID()
            let sequence = try activeConnection.channel.nextOutboundSequence()
            let request = VaultAgentRequestEnvelope(
                protocolVersion: VaultAgentLimits.protocolVersion,
                connectionID: activeConnection.channel.connectionID,
                sequence: sequence,
                requestID: requestID,
                operation: operation
            )
            let plaintext = try JSONEncoder().encode(request)
            guard plaintext.count <= VaultAgentLimits.maximumFrameBytes else {
                throw VaultAgentClientError.protocolFailure
            }
            let encrypted = try activeConnection.channel.seal(plaintext)
            guard encrypted.sequence == sequence else { throw VaultAgentClientError.protocolFailure }
            try Self.writeFrame(
                try JSONEncoder().encode(encrypted),
                fileDescriptor: activeConnection.fileDescriptor,
                deadline: deadline.partialValue,
                now: dependencies.now
            )
            let encryptedResponse = try Self.decodeStrict(
                VaultAgentEncryptedFrame.self,
                from: Self.readFrame(
                    fileDescriptor: activeConnection.fileDescriptor,
                    deadline: deadline.partialValue,
                    now: dependencies.now
                )
            )
            let responseData = try activeConnection.channel.open(encryptedResponse)
            guard responseData.count <= VaultAgentLimits.maximumResponseBytes else {
                throw VaultAgentClientError.protocolFailure
            }
            let response = try Self.decodeStrict(VaultAgentResponseEnvelope.self, from: responseData)
            guard response.protocolVersion == VaultAgentLimits.protocolVersion,
                  response.connectionID == activeConnection.channel.connectionID,
                  response.sequence == sequence,
                  response.requestID == requestID else {
                throw VaultAgentClientError.protocolFailure
            }
            return response.body
        } catch is CancellationError {
            connection = nil
            throw VaultAgentClientError.cancelled
        } catch let error as VaultAgentClientError {
            connection = nil
            throw error
        } catch {
            connection = nil
            throw VaultAgentClientError.protocolFailure
        }
    }

    func close() {
        connection = nil
    }
}

extension VaultAgentClient {
    static func defaultSocketURL(
        fileManager: VaultAgentApplicationSupportFileManager = .live
    ) throws -> URL {
        try fileManager.applicationSupportURL()
            .appendingPathComponent("Pastera/Agent/v1/broker.sock")
    }

    private func activeConnection(deadline: UInt64) async throws -> Connection {
        if let connection { return connection }
        let dependencies = dependencies
        let client = client
        let fileDescriptor: Int32 = try await VaultAgentConnectionRetrier.connect(
            connect: {
                let socketURL = try dependencies.socketURL()
                return try dependencies.connect(socketURL, deadline)
            },
            launch: {
                guard let executableURL = dependencies.executableURL(),
                      let appURL = Self.containingApplication(
                        executableURL: executableURL,
                        client: client
                      ) else {
                    throw VaultAgentClientError.unavailable
                }
                try dependencies.launch(appURL)
            },
            sleep: dependencies.sleep
        )
        do {
            let established = try Self.handshake(
                fileDescriptor: fileDescriptor,
                deadline: deadline,
                dependencies: dependencies
            )
            connection = established
            return established
        } catch {
            Darwin.close(fileDescriptor)
            throw error
        }
    }

    private static func handshake(
        fileDescriptor: Int32,
        deadline: UInt64,
        dependencies: Dependencies
    ) throws -> Connection {
        let privateKey = try dependencies.privateKey()
        let clientNonce = try dependencies.nonce()
        guard clientNonce.count == VaultAgentLimits.nonceBytes else {
            throw VaultAgentClientError.protocolFailure
        }
        let hello = VaultAgentClientHello(
            protocolVersion: VaultAgentLimits.protocolVersion,
            publicKey: privateKey.publicKey.rawRepresentation,
            nonce: clientNonce
        )
        try writeFrame(
            JSONEncoder().encode(hello),
            fileDescriptor: fileDescriptor,
            deadline: deadline,
            now: dependencies.now
        )
        let serverHello = try decodeStrict(
            VaultAgentServerHello.self,
            from: readFrame(
                fileDescriptor: fileDescriptor,
                deadline: deadline,
                now: dependencies.now
            )
        )
        guard serverHello.protocolVersion == VaultAgentLimits.protocolVersion else {
            throw VaultAgentClientError.protocolFailure
        }
        let channel = try VaultAgentClientSecureChannel(
            privateKey: privateKey,
            peerPublicKey: serverHello.publicKey,
            clientNonce: clientNonce,
            serverNonce: serverHello.nonce,
            connectionID: serverHello.connectionID
        )
        return Connection(fileDescriptor: fileDescriptor, channel: channel)
    }

    private static func containingApplication(
        executableURL: URL,
        client: VaultAgentClientKind
    ) -> URL? {
        let resolved = executableURL.resolvingSymlinksInPath().standardizedFileURL
        let expectedName: String
        switch client {
        case .codex: expectedName = "PasteraCodexMCP"
        case .claude: expectedName = "PasteraClaudeMCP"
        case .cli: expectedName = "pastera"
        }
        guard resolved.lastPathComponent == expectedName,
              resolved.deletingLastPathComponent().lastPathComponent == "Helpers" else {
            return nil
        }
        let contents = resolved.deletingLastPathComponent().deletingLastPathComponent()
        let app = contents.deletingLastPathComponent()
        guard contents.lastPathComponent == "Contents",
              app.lastPathComponent == "Pastera.app" else { return nil }
        return app
    }

    private static func launchApplication(_ applicationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-gj", applicationURL.path]
        try process.run()
    }

    private static func randomNonce() throws -> Data {
        var bytes = Data(repeating: 0, count: VaultAgentLimits.nonceBytes)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { throw VaultAgentClientError.unavailable }
        return bytes
    }

    private static func connectSocket(_ socketURL: URL, deadline: UInt64) throws -> Int32 {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw VaultAgentClientError.unavailable }
        do {
            try configure(descriptor)
            var address = try unixAddress(socketURL)
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(
                        descriptor,
                        $0,
                        socklen_t(MemoryLayout<sockaddr_un>.size)
                    )
                }
            }
            if result == 0 { return descriptor }
            guard errno == EINPROGRESS || errno == EALREADY else {
                throw VaultAgentClientError.unavailable
            }
            try wait(
                fileDescriptor: descriptor,
                events: Int16(POLLOUT),
                deadline: deadline,
                now: { DispatchTime.now().uptimeNanoseconds }
            )
            var socketError: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &socketError, &length) == 0,
                  socketError == 0 else {
                throw VaultAgentClientError.unavailable
            }
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    private static func configure(_ descriptor: Int32) throws {
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0,
              fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0,
              fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0 else {
            throw VaultAgentClientError.unavailable
        }
        var enabled: Int32 = 1
        guard setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &enabled,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            throw VaultAgentClientError.unavailable
        }
    }

    private static func unixAddress(_ socketURL: URL) throws -> sockaddr_un {
        let path = Array(socketURL.path.utf8) + [0]
        var address = sockaddr_un()
        guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw VaultAgentClientError.unavailable
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path) }
        return address
    }

    private static func writeFrame(
        _ payload: Data,
        fileDescriptor: Int32,
        deadline: UInt64,
        now: @Sendable () -> UInt64
    ) throws {
        let frame = try VaultAgentFrameCodec.frame(payload: payload)
        var offset = 0
        while offset < frame.count {
            try Task.checkCancellation()
            let written = frame.withUnsafeBytes { buffer in
                Darwin.write(
                    fileDescriptor,
                    buffer.baseAddress!.advanced(by: offset),
                    frame.count - offset
                )
            }
            if written > 0 {
                offset += written
                continue
            }
            if written < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                try wait(
                    fileDescriptor: fileDescriptor,
                    events: Int16(POLLOUT),
                    deadline: deadline,
                    now: now
                )
                continue
            }
            throw VaultAgentClientError.unavailable
        }
    }

    private static func readFrame(
        fileDescriptor: Int32,
        deadline: UInt64,
        now: @Sendable () -> UInt64
    ) throws -> Data {
        let prefix = try readExactly(
            4,
            fileDescriptor: fileDescriptor,
            deadline: deadline,
            now: now
        )
        let length = prefix.reduce(UInt32.zero) { ($0 << 8) | UInt32($1) }
        guard length <= UInt32(VaultAgentLimits.maximumFrameBytes - 4) else {
            throw VaultAgentClientError.protocolFailure
        }
        return try readExactly(
            Int(length),
            fileDescriptor: fileDescriptor,
            deadline: deadline,
            now: now
        )
    }

    private static func readExactly(
        _ count: Int,
        fileDescriptor: Int32,
        deadline: UInt64,
        now: @Sendable () -> UInt64
    ) throws -> Data {
        var result = Data()
        result.reserveCapacity(count)
        while result.count < count {
            try Task.checkCancellation()
            var bytes = [UInt8](repeating: 0, count: count - result.count)
            let readCount = Darwin.read(fileDescriptor, &bytes, bytes.count)
            if readCount > 0 {
                result.append(contentsOf: bytes.prefix(readCount))
                continue
            }
            if readCount < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                try wait(
                    fileDescriptor: fileDescriptor,
                    events: Int16(POLLIN),
                    deadline: deadline,
                    now: now
                )
                continue
            }
            throw VaultAgentClientError.unavailable
        }
        return result
    }

    private static func wait(
        fileDescriptor: Int32,
        events: Int16,
        deadline: UInt64,
        now: @Sendable () -> UInt64
    ) throws {
        try Task.checkCancellation()
        let current = now()
        guard current < deadline else { throw VaultAgentClientError.timedOut }
        let remainingMilliseconds = (deadline - current) / 1_000_000
        let timeout = Int32(max(1, min(50, remainingMilliseconds)))
        var descriptor = pollfd(fd: fileDescriptor, events: events, revents: 0)
        let result = Darwin.poll(&descriptor, 1, timeout)
        if result > 0 {
            guard descriptor.revents & Int16(POLLNVAL | POLLERR) == 0 else {
                throw VaultAgentClientError.unavailable
            }
            if descriptor.revents & events != 0 { return }
            if descriptor.revents & Int16(POLLHUP) != 0 {
                throw VaultAgentClientError.unavailable
            }
            return
        }
        if result == 0 { return }
        if errno == EINTR { return }
        throw VaultAgentClientError.unavailable
    }

    private static func decodeStrict<Value: Codable>(
        _ type: Value.Type,
        from data: Data
    ) throws -> Value {
        let decoded = try JSONDecoder().decode(type, from: data)
        let canonical = try JSONEncoder().encode(decoded)
        guard let originalObject = try JSONSerialization.jsonObject(with: data) as? NSObject,
              let canonicalObject = try JSONSerialization.jsonObject(with: canonical) as? NSObject,
              originalObject.isEqual(canonicalObject) else {
            throw VaultAgentClientError.protocolFailure
        }
        return decoded
    }
}

final class VaultAgentClientSecureChannel: @unchecked Sendable {
    let connectionID: UUID
    private let key: SymmetricKey
    private let deterministicNonce: Bool
    private let lock = NSLock()
    private var outboundSequence: UInt64 = 1
    private var expectedInboundSequence: UInt64 = 1

    init(
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        peerPublicKey: Data,
        clientNonce: Data,
        serverNonce: Data,
        connectionID: UUID,
        deterministicNonce: Bool = false
    ) throws {
        guard clientNonce.count == VaultAgentLimits.nonceBytes,
              serverNonce.count == VaultAgentLimits.nonceBytes,
              peerPublicKey.count == VaultAgentLimits.publicKeyBytes else {
            throw VaultAgentClientError.protocolFailure
        }
        do {
            let peer = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKey)
            let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: peer)
            var info = Data("PasteraVaultAgent/v1".utf8)
            info.append(0)
            info.append(Self.uuidBytes(connectionID))
            key = sharedSecret.hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: clientNonce + serverNonce,
                sharedInfo: info,
                outputByteCount: 32
            )
        } catch {
            throw VaultAgentClientError.protocolFailure
        }
        self.connectionID = connectionID
        self.deterministicNonce = deterministicNonce
    }

    static func makeForTesting(
        privateKey: Data,
        peerPublicKey: Data,
        clientNonce: Data,
        serverNonce: Data,
        connectionID: UUID
    ) throws -> VaultAgentClientSecureChannel {
        try .init(
            privateKey: Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKey),
            peerPublicKey: peerPublicKey,
            clientNonce: clientNonce,
            serverNonce: serverNonce,
            connectionID: connectionID,
            deterministicNonce: true
        )
    }

    func nextOutboundSequence() throws -> UInt64 {
        try lock.withLock {
            guard outboundSequence < UInt64.max else {
                throw VaultAgentProtocolError.sequenceExhausted
            }
            return outboundSequence
        }
    }

    func seal(_ plaintext: Data) throws -> VaultAgentEncryptedFrame {
        try lock.withLock {
            guard outboundSequence < UInt64.max else {
                throw VaultAgentProtocolError.sequenceExhausted
            }
            let sequence = outboundSequence
            let authenticatedData = Self.authenticatedData(
                connectionID: connectionID,
                direction: 1,
                sequence: sequence
            )
            do {
                let sealed: ChaChaPoly.SealedBox
                if deterministicNonce {
                    var bytes = Data([1, 0, 0, 0])
                    var encoded = sequence.bigEndian
                    withUnsafeBytes(of: &encoded) { bytes.append(contentsOf: $0) }
                    sealed = try ChaChaPoly.seal(
                        plaintext,
                        using: key,
                        nonce: try ChaChaPoly.Nonce(data: bytes),
                        authenticating: authenticatedData
                    )
                } else {
                    sealed = try ChaChaPoly.seal(
                        plaintext,
                        using: key,
                        authenticating: authenticatedData
                    )
                }
                outboundSequence += 1
                return .init(
                    connectionID: connectionID,
                    sequence: sequence,
                    ciphertext: sealed.combined
                )
            } catch {
                throw VaultAgentProtocolError.authenticationFailed
            }
        }
    }

    func open(_ frame: VaultAgentEncryptedFrame) throws -> Data {
        try lock.withLock {
            guard frame.connectionID == connectionID else {
                throw VaultAgentProtocolError.connectionMismatch
            }
            guard expectedInboundSequence < UInt64.max else {
                throw VaultAgentProtocolError.sequenceExhausted
            }
            guard frame.sequence >= expectedInboundSequence else {
                throw VaultAgentProtocolError.replayedFrame
            }
            guard frame.sequence == expectedInboundSequence else {
                throw VaultAgentProtocolError.outOfOrderFrame
            }
            let authenticatedData = Self.authenticatedData(
                connectionID: connectionID,
                direction: 2,
                sequence: frame.sequence
            )
            do {
                let sealed = try ChaChaPoly.SealedBox(combined: frame.ciphertext)
                let plaintext = try ChaChaPoly.open(
                    sealed,
                    using: key,
                    authenticating: authenticatedData
                )
                expectedInboundSequence += 1
                return plaintext
            } catch {
                throw VaultAgentProtocolError.authenticationFailed
            }
        }
    }

    private static func authenticatedData(
        connectionID: UUID,
        direction: UInt8,
        sequence: UInt64
    ) -> Data {
        var data = Data("PVA1".utf8)
        var version = UInt32(VaultAgentLimits.protocolVersion).bigEndian
        withUnsafeBytes(of: &version) { data.append(contentsOf: $0) }
        data.append(uuidBytes(connectionID))
        data.append(direction)
        var encoded = sequence.bigEndian
        withUnsafeBytes(of: &encoded) { data.append(contentsOf: $0) }
        return data
    }

    private static func uuidBytes(_ value: UUID) -> Data {
        let bytes = value.uuid
        return Data([
            bytes.0, bytes.1, bytes.2, bytes.3,
            bytes.4, bytes.5, bytes.6, bytes.7,
            bytes.8, bytes.9, bytes.10, bytes.11,
            bytes.12, bytes.13, bytes.14, bytes.15
        ])
    }
}
