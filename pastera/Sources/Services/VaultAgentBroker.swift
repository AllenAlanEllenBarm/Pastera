import CryptoKit
import Foundation
import PasteraAgentProtocol
import Security

// This Task 5 boundary intentionally keeps the handshake and socket state machine in one auditable file.
// swiftlint:disable file_length

struct VaultAgentClientHandshakeContext {
    let hello: VaultAgentClientHello
    private let privateKey: Curve25519.KeyAgreement.PrivateKey
    private let nonce: Data

    init() throws {
        try self.init(privateKey: nil, nonce: Self.randomNonce())
    }

    init(privateKey: Data, nonce: Data) throws {
        try self.init(privateKey: Optional(privateKey), nonce: nonce)
    }

    private init(privateKey bytes: Data?, nonce: Data) throws {
        guard nonce.count == VaultAgentLimits.nonceBytes else {
            throw VaultAgentProtocolError.protocolMismatch
        }
        let privateKey: Curve25519.KeyAgreement.PrivateKey
        do {
            privateKey = if let bytes {
                try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: bytes)
            } else {
                Curve25519.KeyAgreement.PrivateKey()
            }
        } catch {
            throw VaultAgentProtocolError.protocolMismatch
        }
        self.privateKey = privateKey
        self.nonce = nonce
        hello = .init(
            protocolVersion: VaultAgentLimits.protocolVersion,
            publicKey: privateKey.publicKey.rawRepresentation,
            nonce: nonce
        )
    }

    func complete(_ serverHello: VaultAgentServerHello) throws -> VaultAgentSecureChannel {
        guard serverHello.protocolVersion == VaultAgentLimits.protocolVersion,
              serverHello.publicKey.count == VaultAgentLimits.publicKeyBytes,
              serverHello.nonce.count == VaultAgentLimits.nonceBytes else {
            throw VaultAgentProtocolError.protocolMismatch
        }
        return try VaultAgentSecureChannel.make(
            privateKey: privateKey,
            peerPublicKey: serverHello.publicKey,
            clientNonce: nonce,
            serverNonce: serverHello.nonce,
            connectionID: serverHello.connectionID,
            role: .client
        )
    }

    private static func randomNonce() throws -> Data {
        var bytes = Data(repeating: 0, count: VaultAgentLimits.nonceBytes)
        let result = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard result == errSecSuccess else { throw VaultAgentProtocolError.authenticationFailed }
        return bytes
    }
}

struct VaultAgentServerHandshakeContext {
    private let privateKey: Curve25519.KeyAgreement.PrivateKey
    private let nonce: Data
    private let connectionID: UUID

    init() throws {
        try self.init(privateKey: nil, nonce: Self.randomNonce(), connectionID: UUID())
    }

    init(privateKey: Data, nonce: Data, connectionID: UUID) throws {
        try self.init(privateKey: Optional(privateKey), nonce: nonce, connectionID: connectionID)
    }

    private init(privateKey bytes: Data?, nonce: Data, connectionID: UUID) throws {
        guard nonce.count == VaultAgentLimits.nonceBytes else {
            throw VaultAgentProtocolError.protocolMismatch
        }
        do {
            privateKey = if let bytes {
                try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: bytes)
            } else {
                Curve25519.KeyAgreement.PrivateKey()
            }
        } catch {
            throw VaultAgentProtocolError.protocolMismatch
        }
        self.nonce = nonce
        self.connectionID = connectionID
    }

    func accept(_ clientHello: VaultAgentClientHello) throws -> (hello: VaultAgentServerHello, channel: VaultAgentSecureChannel) {
        guard clientHello.protocolVersion == VaultAgentLimits.protocolVersion,
              clientHello.publicKey.count == VaultAgentLimits.publicKeyBytes,
              clientHello.nonce.count == VaultAgentLimits.nonceBytes else {
            throw VaultAgentProtocolError.protocolMismatch
        }
        let hello = VaultAgentServerHello(
            protocolVersion: VaultAgentLimits.protocolVersion,
            connectionID: connectionID,
            publicKey: privateKey.publicKey.rawRepresentation,
            nonce: nonce
        )
        let channel = try VaultAgentSecureChannel.make(
            privateKey: privateKey,
            peerPublicKey: clientHello.publicKey,
            clientNonce: clientHello.nonce,
            serverNonce: nonce,
            connectionID: connectionID,
            role: .server
        )
        return (hello, channel)
    }

    private static func randomNonce() throws -> Data {
        var bytes = Data(repeating: 0, count: VaultAgentLimits.nonceBytes)
        let result = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard result == errSecSuccess else { throw VaultAgentProtocolError.authenticationFailed }
        return bytes
    }
}

final class VaultAgentSecureChannel {
    struct Pair {
        let client: VaultAgentSecureChannel
        let server: VaultAgentSecureChannel
    }

    enum Role { case client, server }
    private enum Direction: UInt8 { case clientToServer = 1, serverToClient = 2 }

    private let key: SymmetricKey
    private let connectionID: UUID
    private let outboundDirection: Direction
    private let inboundDirection: Direction
    private let usesDeterministicTestNonce: Bool
    private let lock = NSLock()
    private var outboundSequence: UInt64
    private var expectedInboundSequence: UInt64

    private init(
        key: SymmetricKey,
        connectionID: UUID,
        role: Role,
        initialSequence: UInt64 = 1,
        usesDeterministicTestNonce: Bool = false
    ) {
        self.key = key
        self.connectionID = connectionID
        switch role {
        case .client:
            outboundDirection = .clientToServer
            inboundDirection = .serverToClient
        case .server:
            outboundDirection = .serverToClient
            inboundDirection = .clientToServer
        }
        outboundSequence = initialSequence
        expectedInboundSequence = initialSequence
        self.usesDeterministicTestNonce = usesDeterministicTestNonce
    }

    func seal(_ plaintext: Data) throws -> VaultAgentEncryptedFrame {
        lock.lock()
        defer { lock.unlock() }
        guard outboundSequence < UInt64.max else {
            throw VaultAgentProtocolError.sequenceExhausted
        }
        let sequence = outboundSequence
        let aad = Self.additionalAuthenticatedData(
            connectionID: connectionID,
            direction: outboundDirection,
            sequence: sequence
        )
        do {
            let sealed: ChaChaPoly.SealedBox
            if usesDeterministicTestNonce {
                var nonceBytes = Data([outboundDirection.rawValue, 0, 0, 0])
                var encodedSequence = sequence.bigEndian
                withUnsafeBytes(of: &encodedSequence) { nonceBytes.append(contentsOf: $0) }
                sealed = try ChaChaPoly.seal(
                    plaintext,
                    using: key,
                    nonce: try ChaChaPoly.Nonce(data: nonceBytes),
                    authenticating: aad
                )
            } else {
                sealed = try ChaChaPoly.seal(plaintext, using: key, authenticating: aad)
            }
            outboundSequence += 1
            return .init(connectionID: connectionID, sequence: sequence, ciphertext: sealed.combined)
        } catch {
            throw VaultAgentProtocolError.authenticationFailed
        }
    }

    func open(_ frame: VaultAgentEncryptedFrame) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
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
        let aad = Self.additionalAuthenticatedData(
            connectionID: connectionID,
            direction: inboundDirection,
            sequence: frame.sequence
        )
        do {
            let sealed = try ChaChaPoly.SealedBox(combined: frame.ciphertext)
            let plaintext = try ChaChaPoly.open(sealed, using: key, authenticating: aad)
            expectedInboundSequence += 1
            return plaintext
        } catch {
            throw VaultAgentProtocolError.authenticationFailed
        }
    }

    static func makeTestPair(
        clientPrivateKey: Data,
        serverPrivateKey: Data,
        clientNonce: Data,
        serverNonce: Data,
        connectionID: UUID,
        initialSequence: UInt64 = 1
    ) throws -> Pair {
        let client = try VaultAgentClientHandshakeContext(privateKey: clientPrivateKey, nonce: clientNonce)
        let server = try VaultAgentServerHandshakeContext(privateKey: serverPrivateKey, nonce: serverNonce, connectionID: connectionID)
        let accepted = try server.accept(client.hello)
        _ = try client.complete(accepted.hello)
        if initialSequence == 1 {
            let key = try deriveKey(
                privateKey: Curve25519.KeyAgreement.PrivateKey(rawRepresentation: clientPrivateKey),
                peerPublicKey: Curve25519.KeyAgreement.PrivateKey(rawRepresentation: serverPrivateKey).publicKey.rawRepresentation,
                clientNonce: clientNonce,
                serverNonce: serverNonce,
                connectionID: connectionID
            )
            return .init(
                client: .init(key: key, connectionID: connectionID, role: .client, usesDeterministicTestNonce: true),
                server: .init(key: key, connectionID: connectionID, role: .server, usesDeterministicTestNonce: true)
            )
        }
        let key = try deriveKey(
            privateKey: Curve25519.KeyAgreement.PrivateKey(rawRepresentation: clientPrivateKey),
            peerPublicKey: Curve25519.KeyAgreement.PrivateKey(rawRepresentation: serverPrivateKey).publicKey.rawRepresentation,
            clientNonce: clientNonce,
            serverNonce: serverNonce,
            connectionID: connectionID
        )
        return .init(
            client: .init(key: key, connectionID: connectionID, role: .client, initialSequence: initialSequence, usesDeterministicTestNonce: true),
            server: .init(key: key, connectionID: connectionID, role: .server, initialSequence: initialSequence, usesDeterministicTestNonce: true)
        )
    }

    // swiftlint:disable:next function_parameter_count
    fileprivate static func make(
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        peerPublicKey: Data,
        clientNonce: Data,
        serverNonce: Data,
        connectionID: UUID,
        role: Role
    ) throws -> VaultAgentSecureChannel {
        let key = try deriveKey(
            privateKey: privateKey,
            peerPublicKey: peerPublicKey,
            clientNonce: clientNonce,
            serverNonce: serverNonce,
            connectionID: connectionID
        )
        return .init(key: key, connectionID: connectionID, role: role)
    }

    private static func deriveKey(
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        peerPublicKey: Data,
        clientNonce: Data,
        serverNonce: Data,
        connectionID: UUID
    ) throws -> SymmetricKey {
        guard clientNonce.count == VaultAgentLimits.nonceBytes,
              serverNonce.count == VaultAgentLimits.nonceBytes else {
            throw VaultAgentProtocolError.protocolMismatch
        }
        do {
            let peer = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKey)
            let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: peer)
            let salt = clientNonce + serverNonce
            var info = Data("PasteraVaultAgent/v1".utf8)
            info.append(0)
            info.append(uuidBytes(connectionID))
            return sharedSecret.hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: salt,
                sharedInfo: info,
                outputByteCount: 32
            )
        } catch let error as VaultAgentProtocolError {
            throw error
        } catch {
            throw VaultAgentProtocolError.authenticationFailed
        }
    }

    private static func additionalAuthenticatedData(
        connectionID: UUID,
        direction: Direction,
        sequence: UInt64
    ) -> Data {
        var data = Data("PVA1".utf8)
        var version = UInt32(VaultAgentLimits.protocolVersion).bigEndian
        withUnsafeBytes(of: &version) { data.append(contentsOf: $0) }
        data.append(uuidBytes(connectionID))
        data.append(direction.rawValue)
        var encodedSequence = sequence.bigEndian
        withUnsafeBytes(of: &encodedSequence) { data.append(contentsOf: $0) }
        return data
    }

    private static func uuidBytes(_ value: UUID) -> Data {
        let bytes = value.uuid
        return Data([
            bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5, bytes.6, bytes.7,
            bytes.8, bytes.9, bytes.10, bytes.11, bytes.12, bytes.13, bytes.14, bytes.15
        ])
    }
}

protocol VaultAgentSocketRequestHandling: AnyObject {
    func handle(
        identity: VaultAgentPeerIdentity,
        request: Data,
        completion: @escaping (Result<Data, Error>) -> Void
    )
}

enum VaultAgentSocketServerError: Error, Equatable {
    case directoryConflict
    case socketPathConflict
    case pathTooLong
    case unavailable
}

enum VaultAgentSocketSourceKind: Hashable {
    case listener
    case read
    case write
    case idle
}

struct VaultAgentSocketLifecycleProbe {
    var sourceCreated: ((VaultAgentSocketSourceKind, Int32) -> Void)?
    var sourceCancellationCompleted: ((VaultAgentSocketSourceKind, Int32) -> Void)?
    var descriptorClosed: ((Int32) -> Void)?
}

private struct VaultAgentDirectoryHandle {
    let fileDescriptor: Int32
    let device: UInt64
    let inode: UInt64
}

struct VaultAgentWriteSourceLifecycle {
    private enum State {
        case idle
        case active
        case cancelling(rebuildRequested: Bool)
    }

    private var state = State.idle

    mutating func noteWouldBlock() -> Bool {
        switch state {
        case .idle:
            return true
        case .active:
            return false
        case .cancelling:
            state = .cancelling(rebuildRequested: true)
            return false
        }
    }

    mutating func didInstallSource() {
        guard case .idle = state else {
            preconditionFailure("write source installation requires an idle lifecycle")
        }
        state = .active
    }

    mutating func beginDrainCancellation() -> Bool {
        guard case .active = state else { return false }
        state = .cancelling(rebuildRequested: false)
        return true
    }

    mutating func cancellationCompleted(hasPendingOutput: Bool) -> Bool {
        guard case let .cancelling(rebuildRequested) = state else { return false }
        state = .idle
        return rebuildRequested && hasPendingOutput
    }

    mutating func beginClose() -> Bool {
        switch state {
        case .idle:
            return false
        case .active:
            state = .cancelling(rebuildRequested: false)
            return true
        case .cancelling:
            state = .cancelling(rebuildRequested: false)
            return false
        }
    }
}

final class VaultAgentSocketServer {
    private final class Connection {
        // swiftlint:disable:next nesting
        enum Phase { case clientHello, encrypted }

        let id = UUID()
        let fileDescriptor: Int32
        let identity: VaultAgentPeerIdentity
        var phase = Phase.clientHello
        var channel: VaultAgentSecureChannel?
        var input = Data()
        var output = Data()
        var outputOffset = 0
        var inFlightID: UUID?
        var readSource: DispatchSourceRead?
        var writeSource: DispatchSourceWrite?
        var writeSourceLifecycle = VaultAgentWriteSourceLifecycle()
        var idleTimer: DispatchSourceTimer?
        var closed = false

        init(fileDescriptor: Int32, identity: VaultAgentPeerIdentity) {
            self.fileDescriptor = fileDescriptor
            self.identity = identity
        }
    }

    static let maximumConnections = 8
    static let defaultIdleTimeout: TimeInterval = 30

    private let applicationSupportURLProvider: () throws -> URL
    private var activeDirectoryURL: URL?
    private var directoryURL: URL {
        guard let activeDirectoryURL else {
            preconditionFailure("Vault agent directory used before resolution")
        }
        return activeDirectoryURL
    }
    var socketURL: URL { directoryURL.appendingPathComponent("broker.sock") }

    private let peerVerifier: VaultAgentPeerVerifying
    private let handler: VaultAgentSocketRequestHandling
    private let queue: DispatchQueue
    private let idleTimeout: TimeInterval
    private let idleTimerFactory: (DispatchQueue) -> DispatchSourceTimer
    private let directoryIdentityValidationHook: (() throws -> Void)?
    private let lifecycleProbe: VaultAgentSocketLifecycleProbe
    private let queueKey = DispatchSpecificKey<UInt8>()
    private var listener: Int32 = -1
    private var listenerSource: DispatchSourceRead?
    private var directoryDescriptor: Int32 = -1
    private var directoryDevice: UInt64?
    private var directoryInode: UInt64?
    private var boundDevice: UInt64?
    private var boundInode: UInt64?
    private var connections: [UUID: Connection] = [:]
    private var closingConnections: [UUID: Connection] = [:]
    private var stopCompletions: [() -> Void] = []
    private var running = false
    private var stopping = false
    private var shutdownRetention: VaultAgentSocketServer?

    init(
        directoryURL: URL? = nil,
        peerVerifier: VaultAgentPeerVerifying,
        handler: VaultAgentSocketRequestHandling,
        queue: DispatchQueue = DispatchQueue(label: "com.pastera-app.Pastera.vault-agent.socket"),
        idleTimeout: TimeInterval = defaultIdleTimeout,
        idleTimerFactory: @escaping (DispatchQueue) -> DispatchSourceTimer = {
            DispatchSource.makeTimerSource(queue: $0)
        },
        applicationSupportURLProvider: @escaping () throws -> URL = VaultAgentSocketServer.applicationSupportURL,
        directoryIdentityValidationHook: (() throws -> Void)? = nil,
        lifecycleProbe: VaultAgentSocketLifecycleProbe = .init()
    ) {
        activeDirectoryURL = directoryURL
        self.applicationSupportURLProvider = applicationSupportURLProvider
        self.peerVerifier = peerVerifier
        self.handler = handler
        self.queue = queue
        self.idleTimeout = idleTimeout
        self.idleTimerFactory = idleTimerFactory
        self.directoryIdentityValidationHook = directoryIdentityValidationHook
        self.lifecycleProbe = lifecycleProbe
        queue.setSpecific(key: queueKey, value: 1)
    }

    func start() throws {
        try onQueue {
            guard !running else { return }
            guard !stopping, listener < 0, directoryDescriptor < 0 else {
                throw VaultAgentSocketServerError.unavailable
            }
            try resolveDirectoryURL()
            try validateSocketPathLength()
            let directory = try ensurePrivateDirectory()
            directoryDescriptor = directory.fileDescriptor
            directoryDevice = directory.device
            directoryInode = directory.inode

            let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
            guard descriptor >= 0 else {
                closeDirectoryDescriptor()
                throw VaultAgentSocketServerError.unavailable
            }
            do {
                do {
                    try directoryIdentityValidationHook?()
                } catch {
                    throw VaultAgentSocketServerError.directoryConflict
                }
                try validateDirectoryIdentity()
                try resolveExistingSocket()
                try configure(descriptor)
                try validateDirectoryIdentity()
                var address = try makeAddress()
                let bindResult = withUnsafePointer(to: &address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                    }
                }
                guard bindResult == 0 else {
                    throw VaultAgentSocketServerError.unavailable
                }
                var boundInfo = stat()
                guard fstatat(directoryDescriptor, "broker.sock", &boundInfo, AT_SYMLINK_NOFOLLOW) == 0,
                      (boundInfo.st_mode & S_IFMT) == S_IFSOCK,
                      boundInfo.st_uid == getuid() else {
                    throw VaultAgentSocketServerError.unavailable
                }
                boundDevice = UInt64(boundInfo.st_dev)
                boundInode = UInt64(boundInfo.st_ino)
                try validateDirectoryIdentity()
                guard listen(descriptor, SOMAXCONN) == 0,
                      fchmodat(directoryDescriptor, "broker.sock", 0o600, AT_SYMLINK_NOFOLLOW) == 0 else {
                    throw VaultAgentSocketServerError.unavailable
                }
                var securedInfo = stat()
                guard fstatat(directoryDescriptor, "broker.sock", &securedInfo, AT_SYMLINK_NOFOLLOW) == 0,
                      (securedInfo.st_mode & S_IFMT) == S_IFSOCK,
                      securedInfo.st_uid == getuid(),
                      securedInfo.st_dev == boundInfo.st_dev,
                      securedInfo.st_ino == boundInfo.st_ino,
                      securedInfo.st_mode & 0o777 == 0o600 else {
                    throw VaultAgentSocketServerError.unavailable
                }
                listener = descriptor
                running = true
                let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
                source.setEventHandler { [weak self] in self?.acceptAvailableConnections() }
                source.setCancelHandler { [weak self] in
                    self?.listenerSourceCancellationCompleted(fileDescriptor: descriptor)
                }
                listenerSource = source
                lifecycleProbe.sourceCreated?(.listener, descriptor)
                source.resume()
            } catch {
                Darwin.close(descriptor)
                removeOwnedSocketIfUnchanged()
                boundDevice = nil
                boundInode = nil
                closeDirectoryDescriptor()
                throw error
            }
        }
    }

    func stop(completion: (() -> Void)? = nil) {
        onQueueNoThrow {
            if let completion { stopCompletions.append(completion) }
            guard running || listener >= 0 || !connections.isEmpty || !closingConnections.isEmpty else {
                finishStopIfPossible()
                return
            }
            stopping = true
            shutdownRetention = self
            running = false
            listenerSource?.setEventHandler {}
            listenerSource?.cancel()
            for connection in Array(connections.values) { close(connection) }
            removeOwnedSocketIfUnchanged()
            boundDevice = nil
            boundInode = nil
            finishStopIfPossible()
        }
    }
}

private extension VaultAgentSocketServer {
    private static func applicationSupportURL() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    private func resolveDirectoryURL() throws {
        guard activeDirectoryURL == nil else { return }
        do {
            activeDirectoryURL = try applicationSupportURLProvider()
                .appendingPathComponent("Pastera/Agent/v1")
        } catch {
            throw VaultAgentSocketServerError.unavailable
        }
    }

    private func validateSocketPathLength() throws {
        let address = sockaddr_un()
        guard socketURL.path.utf8.count + 1 <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw VaultAgentSocketServerError.pathTooLong
        }
    }

    private func ensurePrivateDirectory() throws -> VaultAgentDirectoryHandle {
        try openDirectoryPath(createMissing: true, securePrivateDirectories: true)
    }

    private func openDirectoryPath(
        createMissing: Bool,
        securePrivateDirectories: Bool
    ) throws -> VaultAgentDirectoryHandle {
        var currentDescriptor = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard currentDescriptor >= 0 else { throw VaultAgentSocketServerError.directoryConflict }
        var shouldClose = true
        defer { if shouldClose { Darwin.close(currentDescriptor) } }

        let standardizedPath = directoryURL.standardizedFileURL.path
        let noAliasPath = standardizedPath.hasPrefix("/var/") ? "/private\(standardizedPath)" : standardizedPath
        let components = Array(URL(fileURLWithPath: noAliasPath).pathComponents.dropFirst())
        for (index, component) in components.enumerated() {
            var next = openat(currentDescriptor, component, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            if next < 0, errno == ENOENT, createMissing {
                guard mkdirat(currentDescriptor, component, 0o700) == 0 || errno == EEXIST else {
                    throw VaultAgentSocketServerError.directoryConflict
                }
                next = openat(currentDescriptor, component, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            }
            guard next >= 0 else { throw VaultAgentSocketServerError.directoryConflict }
            var info = stat()
            let isPrivateAgentDirectory = index == components.count - 2 &&
                component == "Agent" && components.last == "v1"
            let requiresCurrentOwner = index == components.count - 1 || isPrivateAgentDirectory
            guard fstat(next, &info) == 0,
                  (info.st_mode & S_IFMT) == S_IFDIR,
                  !requiresCurrentOwner || info.st_uid == getuid() else {
                Darwin.close(next)
                throw VaultAgentSocketServerError.directoryConflict
            }
            if requiresCurrentOwner {
                if securePrivateDirectories, fchmod(next, 0o700) != 0 {
                    Darwin.close(next)
                    throw VaultAgentSocketServerError.directoryConflict
                }
                guard fstat(next, &info) == 0, info.st_mode & 0o777 == 0o700 else {
                    Darwin.close(next)
                    throw VaultAgentSocketServerError.directoryConflict
                }
            }
            Darwin.close(currentDescriptor)
            currentDescriptor = next
        }
        var finalInfo = stat()
        guard fstat(currentDescriptor, &finalInfo) == 0,
              (finalInfo.st_mode & S_IFMT) == S_IFDIR,
              finalInfo.st_uid == getuid() else {
            throw VaultAgentSocketServerError.directoryConflict
        }
        shouldClose = false
        return VaultAgentDirectoryHandle(
            fileDescriptor: currentDescriptor,
            device: UInt64(finalInfo.st_dev),
            inode: UInt64(finalInfo.st_ino)
        )
    }

    private func validateDirectoryIdentity() throws {
        let reopened = try openDirectoryPath(createMissing: false, securePrivateDirectories: false)
        defer { Darwin.close(reopened.fileDescriptor) }
        guard let directoryDevice,
              let directoryInode,
              reopened.device == directoryDevice,
              reopened.inode == directoryInode else {
            throw VaultAgentSocketServerError.directoryConflict
        }
    }

    private func resolveExistingSocket() throws {
        var before = stat()
        guard fstatat(directoryDescriptor, "broker.sock", &before, AT_SYMLINK_NOFOLLOW) == 0 else {
            if errno == ENOENT { return }
            throw VaultAgentSocketServerError.socketPathConflict
        }
        guard (before.st_mode & S_IFMT) == S_IFSOCK, before.st_uid == getuid() else {
            throw VaultAgentSocketServerError.socketPathConflict
        }

        let probe = socket(AF_UNIX, SOCK_STREAM, 0)
        guard probe >= 0 else { throw VaultAgentSocketServerError.socketPathConflict }
        defer { Darwin.close(probe) }
        try configure(probe)
        try validateDirectoryIdentity()
        var address = try makeAddress()
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(probe, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        let connectionError = result == 0 ? 0 : errno
        try validateDirectoryIdentity()
        if result == 0 || connectionError == EINPROGRESS || connectionError == EALREADY {
            throw VaultAgentSocketServerError.socketPathConflict
        }
        guard connectionError == ECONNREFUSED || connectionError == ENOENT else {
            throw VaultAgentSocketServerError.socketPathConflict
        }
        var after = stat()
        guard fstatat(directoryDescriptor, "broker.sock", &after, AT_SYMLINK_NOFOLLOW) == 0,
              (after.st_mode & S_IFMT) == S_IFSOCK,
              after.st_uid == getuid(),
              before.st_dev == after.st_dev,
              before.st_ino == after.st_ino,
              unlinkat(directoryDescriptor, "broker.sock", 0) == 0 else {
            throw VaultAgentSocketServerError.socketPathConflict
        }
    }

    private func configure(_ descriptor: Int32) throws {
        guard fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK) == 0,
              fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0 else {
            throw VaultAgentSocketServerError.unavailable
        }
        var enabled: Int32 = 1
        var lowWater: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size)) == 0,
              setsockopt(descriptor, SOL_SOCKET, SO_SNDLOWAT, &lowWater, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw VaultAgentSocketServerError.unavailable
        }
    }

    private func makeAddress() throws -> sockaddr_un {
        let path = Array(socketURL.path.utf8) + [0]
        var address = sockaddr_un()
        guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw VaultAgentSocketServerError.pathTooLong
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path) }
        return address
    }

    private func acceptAvailableConnections() {
        guard running, listener >= 0 else { return }
        while true {
            let descriptor = accept(listener, nil, nil)
            if descriptor < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                stop()
                return
            }
            guard connections.count + closingConnections.count < Self.maximumConnections else {
                Darwin.close(descriptor)
                continue
            }
            do {
                try configure(descriptor)
                let identity = try peerVerifier.verify(fileDescriptor: descriptor)
                let connection = Connection(fileDescriptor: descriptor, identity: identity)
                connections[connection.id] = connection
                let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
                source.setEventHandler { [weak self, weak connection] in
                    guard let connection else { return }
                    self?.readAvailable(from: connection)
                }
                source.setCancelHandler { [weak self, weak connection] in
                    guard let connection else { return }
                    self?.connectionSourceCancellationCompleted(.read, connection: connection)
                }
                connection.readSource = source
                lifecycleProbe.sourceCreated?(.read, descriptor)
                let timer = idleTimerFactory(queue)
                timer.setEventHandler { [weak self, weak connection] in
                    guard let connection else { return }
                    self?.close(connection)
                }
                timer.setCancelHandler { [weak self, weak connection] in
                    guard let connection else { return }
                    self?.connectionSourceCancellationCompleted(.idle, connection: connection)
                }
                connection.idleTimer = timer
                lifecycleProbe.sourceCreated?(.idle, descriptor)
                scheduleIdle(for: connection)
                source.resume()
                timer.resume()
            } catch {
                Darwin.close(descriptor)
            }
        }
    }

    private func readAvailable(from connection: Connection) {
        guard !connection.closed else { return }
        var bytes = [UInt8](repeating: 0, count: 8_192)
        while true {
            let count = Darwin.read(connection.fileDescriptor, &bytes, bytes.count)
            if count > 0 {
                connection.input.append(contentsOf: bytes.prefix(count))
                guard connection.input.count <= VaultAgentLimits.maximumFrameBytes else {
                    close(connection)
                    return
                }
                scheduleIdle(for: connection)
                parseFrames(connection)
                if connection.closed { return }
            } else if count == 0 {
                close(connection)
                return
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                return
            } else {
                close(connection)
                return
            }
        }
    }

    private func parseFrames(_ connection: Connection) {
        while connection.input.count >= 4 {
            let declared = connection.input.prefix(4).reduce(UInt32.zero) { ($0 << 8) | UInt32($1) }
            guard Int(declared) <= VaultAgentLimits.maximumFrameBytes - 4 else {
                close(connection)
                return
            }
            let completeLength = Int(declared) + 4
            guard connection.input.count >= completeLength else { return }
            let payloadStart = connection.input.index(connection.input.startIndex, offsetBy: 4)
            let payloadEnd = connection.input.index(connection.input.startIndex, offsetBy: completeLength)
            let payload = Data(connection.input[payloadStart..<payloadEnd])
            connection.input.removeFirst(completeLength)
            handle(payload, from: connection)
            if connection.closed { return }
        }
    }

    private func handle(_ payload: Data, from connection: Connection) {
        switch connection.phase {
        case .clientHello:
            do {
                let hello = try JSONDecoder().decode(VaultAgentClientHello.self, from: payload)
                let context = try VaultAgentServerHandshakeContext()
                let accepted = try context.accept(hello)
                connection.channel = accepted.channel
                connection.phase = .encrypted
                try enqueue(try JSONEncoder().encode(accepted.hello), for: connection)
            } catch {
                close(connection)
            }
        case .encrypted:
            guard connection.inFlightID == nil, let channel = connection.channel else {
                close(connection)
                return
            }
            do {
                let frame = try JSONDecoder().decode(VaultAgentEncryptedFrame.self, from: payload)
                let plaintext = try channel.open(frame)
                guard plaintext.count <= VaultAgentLimits.maximumFrameBytes else {
                    close(connection)
                    return
                }
                let requestID = UUID()
                connection.inFlightID = requestID
                let connectionID = connection.id
                handler.handle(identity: connection.identity, request: plaintext) { [weak self] result in
                    self?.queue.async {
                        self?.complete(result, connectionID: connectionID, requestID: requestID)
                    }
                }
            } catch {
                close(connection)
            }
        }
    }

    private func complete(_ result: Result<Data, Error>, connectionID: UUID, requestID: UUID) {
        guard let connection = connections[connectionID],
              !connection.closed,
              connection.inFlightID == requestID,
              let channel = connection.channel else { return }
        connection.inFlightID = nil
        do {
            let response = try result.get()
            guard response.count <= VaultAgentLimits.maximumResponseBytes else {
                close(connection)
                return
            }
            let encrypted = try channel.seal(response)
            try enqueue(try JSONEncoder().encode(encrypted), for: connection)
        } catch {
            close(connection)
        }
    }

    private func enqueue(_ payload: Data, for connection: Connection) throws {
        let framed = try VaultAgentFrameCodec.frame(payload: payload)
        guard connection.output.count - connection.outputOffset + framed.count <= VaultAgentLimits.maximumFrameBytes else {
            throw VaultAgentProtocolError.frameTooLarge
        }
        if connection.outputOffset > 0 {
            connection.output.removeFirst(connection.outputOffset)
            connection.outputOffset = 0
        }
        connection.output.append(framed)
        flush(connection)
    }

    private func flush(_ connection: Connection) {
        guard !connection.closed else { return }
        while connection.outputOffset < connection.output.count {
            let written = connection.output.withUnsafeBytes { buffer in
                Darwin.write(
                    connection.fileDescriptor,
                    buffer.baseAddress!.advanced(by: connection.outputOffset),
                    connection.output.count - connection.outputOffset
                )
            }
            if written > 0 {
                connection.outputOffset += written
                scheduleIdle(for: connection)
            } else if written < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                if connection.writeSourceLifecycle.noteWouldBlock() {
                    installWriteSource(for: connection)
                }
                return
            } else {
                close(connection)
                return
            }
        }
        connection.output.removeAll(keepingCapacity: false)
        connection.outputOffset = 0
        cancelWriteSourceAfterDrain(for: connection)
    }

    private func installWriteSource(for connection: Connection) {
        guard connection.writeSource == nil else { return }
        let source = DispatchSource.makeWriteSource(fileDescriptor: connection.fileDescriptor, queue: queue)
        source.setEventHandler { [weak self, weak connection] in
            guard let connection else { return }
            self?.flush(connection)
        }
        source.setCancelHandler { [weak self, weak connection] in
            guard let connection else { return }
            self?.connectionSourceCancellationCompleted(.write, connection: connection)
        }
        connection.writeSource = source
        connection.writeSourceLifecycle.didInstallSource()
        lifecycleProbe.sourceCreated?(.write, connection.fileDescriptor)
        source.resume()
    }

    private func cancelWriteSourceAfterDrain(for connection: Connection) {
        guard let source = connection.writeSource,
              connection.writeSourceLifecycle.beginDrainCancellation() else { return }
        source.setEventHandler {}
        source.cancel()
    }

    private func scheduleIdle(for connection: Connection) {
        guard !connection.closed, let timer = connection.idleTimer else { return }
        timer.schedule(deadline: .now() + idleTimeout, repeating: .never)
    }

    private func close(_ connection: Connection) {
        guard !connection.closed else { return }
        connection.closed = true
        connections.removeValue(forKey: connection.id)
        closingConnections[connection.id] = connection
        connection.readSource?.setEventHandler {}
        connection.readSource?.cancel()
        if connection.writeSourceLifecycle.beginClose(), let source = connection.writeSource {
            source.setEventHandler {}
            source.cancel()
        }
        connection.idleTimer?.setEventHandler {}
        connection.idleTimer?.cancel()
        finishConnectionCloseIfPossible(connection)
    }

    private func connectionSourceCancellationCompleted(
        _ kind: VaultAgentSocketSourceKind,
        connection: Connection
    ) {
        lifecycleProbe.sourceCancellationCompleted?(kind, connection.fileDescriptor)
        switch kind {
        case .read:
            connection.readSource = nil
        case .write:
            connection.writeSource = nil
            let hasPendingOutput = connection.outputOffset < connection.output.count
            if !connection.closed,
               connection.writeSourceLifecycle.cancellationCompleted(hasPendingOutput: hasPendingOutput) {
                installWriteSource(for: connection)
            } else if connection.closed {
                _ = connection.writeSourceLifecycle.cancellationCompleted(hasPendingOutput: false)
            }
        case .idle:
            connection.idleTimer = nil
        case .listener:
            return
        }
        finishConnectionCloseIfPossible(connection)
    }

    private func finishConnectionCloseIfPossible(_ connection: Connection) {
        guard connection.closed,
              connection.readSource == nil,
              connection.writeSource == nil,
              connection.idleTimer == nil else { return }
        Darwin.close(connection.fileDescriptor)
        lifecycleProbe.descriptorClosed?(connection.fileDescriptor)
        connection.input.removeAll(keepingCapacity: false)
        connection.output.removeAll(keepingCapacity: false)
        connection.channel = nil
        connection.inFlightID = nil
        closingConnections.removeValue(forKey: connection.id)
        finishStopIfPossible()
    }

    private func listenerSourceCancellationCompleted(fileDescriptor: Int32) {
        guard listener == fileDescriptor else { return }
        lifecycleProbe.sourceCancellationCompleted?(.listener, fileDescriptor)
        listenerSource = nil
        Darwin.close(fileDescriptor)
        lifecycleProbe.descriptorClosed?(fileDescriptor)
        listener = -1
        finishStopIfPossible()
    }

    private func finishStopIfPossible() {
        guard !running,
              listener < 0,
              connections.isEmpty,
              closingConnections.isEmpty else { return }
        removeOwnedSocketIfUnchanged()
        boundDevice = nil
        boundInode = nil
        closeDirectoryDescriptor()
        stopping = false
        let completions = stopCompletions
        stopCompletions.removeAll()
        shutdownRetention = nil
        completions.forEach { $0() }
    }

    private func removeOwnedSocketIfUnchanged() {
        guard directoryDescriptor >= 0, let boundDevice, let boundInode else { return }
        var info = stat()
        guard fstatat(directoryDescriptor, "broker.sock", &info, AT_SYMLINK_NOFOLLOW) == 0,
              (info.st_mode & S_IFMT) == S_IFSOCK,
              info.st_uid == getuid(),
              UInt64(info.st_dev) == boundDevice,
              UInt64(info.st_ino) == boundInode else { return }
        _ = unlinkat(directoryDescriptor, "broker.sock", 0)
    }

    private func closeDirectoryDescriptor() {
        guard directoryDescriptor >= 0 else { return }
        Darwin.close(directoryDescriptor)
        directoryDescriptor = -1
        directoryDevice = nil
        directoryInode = nil
    }

    private func onQueue<T>(_ body: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil { return try body() }
        return try queue.sync(execute: body)
    }

    private func onQueueNoThrow(_ body: () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) != nil { body() } else { queue.sync(execute: body) }
    }
}
