import CryptoKit
import Darwin
import Foundation
import PasteraAgentProtocol
import Security

// The dispatcher keeps the complete V1 operation and error allowlists together for security review.
// swiftlint:disable file_length

protocol VaultAgentAuditLogging: AnyObject {
    // swiftlint:disable:next function_parameter_count
    func record(
        client: VaultAgentClientKind,
        action: VaultAgentAuditAction,
        entryID: UUID?,
        result: VaultAgentErrorCode?,
        latencyBucket: VaultAgentLatencyBucket,
        at date: Date
    )
}

extension VaultAgentAuditLogger: VaultAgentAuditLogging {}

protocol VaultAgentPasteTargetTracking: AnyObject {
    func resolve() throws -> PasteTargetContext
}

protocol VaultAgentSensitiveUseObserving: AnyObject {
    @discardableResult
    func addInteractiveSensitiveUseObserver(_ observer: @escaping () -> Void) -> UUID
    func removeInteractiveSensitiveUseObserver(_ identifier: UUID)
}

extension PasswordVaultUIController: VaultAgentSensitiveUseObserving {}

protocol VaultAgentIntegrationServicing {
    func status(host: VaultAgentHostKind?) throws -> VaultAgentIntegrationStatus
    func install(host: VaultAgentHostKind) throws -> VaultAgentIntegrationStatus
    func uninstall(host: VaultAgentHostKind) throws -> VaultAgentIntegrationStatus
}

struct UnavailableVaultAgentIntegrationService: VaultAgentIntegrationServicing {
    func status(host: VaultAgentHostKind?) -> VaultAgentIntegrationStatus {
        let hosts = (host.map { [$0] } ?? [.codex, .claude]).map {
            VaultAgentHostIntegrationStatus(
                host: $0,
                hostDetected: false,
                hostExecutablePath: nil,
                mcpInstalled: false,
                skillInstalled: false,
                installedVersion: nil,
                authorized: false,
                idleExpiresAt: nil,
                hardExpiresAt: nil
            )
        }
        return .init(hosts: hosts)
    }

    func install(host _: VaultAgentHostKind) throws -> VaultAgentIntegrationStatus {
        throw VaultAgentErrorCode.brokerUnavailable
    }

    func uninstall(host _: VaultAgentHostKind) throws -> VaultAgentIntegrationStatus {
        throw VaultAgentErrorCode.brokerUnavailable
    }
}

enum VaultAgentPreferenceAuthorizationState: String, Codable, Equatable {
    case missing
    case authorized
    case expired
    case revoked
    case identityChanged
    case unavailable
}

enum VaultAgentPreferencePrimaryAction: String, Equatable {
    case install
    case update
    case authorize
    case reauthorize
    case revoke
    case uninstall
}

struct VaultAgentPreferenceClientSnapshot: Equatable {
    let client: VaultAgentClientKind
    let hostDetected: Bool
    let installed: Bool
    let installationNeedsUpdate: Bool
    let hostPathSummary: String?
    let authorization: VaultAgentPreferenceAuthorizationState
    let idleExpiresAt: Date?
    let hardExpiresAt: Date?
    let lastSensitiveUseAt: Date?

    var primaryAction: VaultAgentPreferencePrimaryAction {
        if installed, client != .cli, !hostDetected { return .uninstall }
        if !installed { return .install }
        if installationNeedsUpdate { return .update }
        switch authorization {
        case .authorized: return .revoke
        case .missing: return .authorize
        case .expired, .revoked, .identityChanged: return .reauthorize
        case .unavailable: return .uninstall
        }
    }

    static func unavailable(client: VaultAgentClientKind) -> Self {
        .init(
            client: client,
            hostDetected: false,
            installed: false,
            installationNeedsUpdate: false,
            hostPathSummary: nil,
            authorization: .unavailable,
            idleExpiresAt: nil,
            hardExpiresAt: nil,
            lastSensitiveUseAt: nil
        )
    }
}

struct VaultAgentClaudePermissionSnapshot: Equatable {
    let policyDisposition: VaultAgentManagedPermissionDisposition
    let ownedRules: [String]

    var canApplyAutomatically: Bool { policyDisposition == .userRulesAllowed }
    var canRemoveOwnedRules: Bool { !ownedRules.isEmpty }

    static let unavailable = Self(policyDisposition: .unknown, ownedRules: [])
}

struct VaultAgentPreferenceAuditSummary: Codable, Equatable {
    let action: VaultAgentAuditAction
    let result: VaultAgentErrorCode?
    let timestamp: Date
}

struct VaultAgentPreferenceSnapshot: Equatable {
    let clients: [VaultAgentClientKind: VaultAgentPreferenceClientSnapshot]
    let claudePermission: VaultAgentClaudePermissionSnapshot
    let audit: [VaultAgentPreferenceAuditSummary]
}

enum VaultAgentPreferenceAction: Equatable {
    case install(VaultAgentClientKind)
    case authorize(VaultAgentClientKind)
    case revoke(VaultAgentClientKind)
    case uninstall(VaultAgentClientKind)
    case applyClaudePermission(VaultAgentHostPermissionScope)
    case removeClaudePermission
}

protocol VaultAgentPreferenceRuntimeServicing: AnyObject {
    func loadSnapshot(completion: @escaping (Result<VaultAgentPreferenceSnapshot, Error>) -> Void)
    func perform(
        _ action: VaultAgentPreferenceAction,
        completion: @escaping (Result<VaultAgentPreferenceSnapshot, Error>) -> Void
    )
    func claudePermissionSnippet(
        scope: VaultAgentHostPermissionScope,
        completion: @escaping (Result<VaultAgentPermissionSnippet, Error>) -> Void
    )
}

final class UnavailableVaultAgentPreferenceRuntime: VaultAgentPreferenceRuntimeServicing {
    private static let snapshot = VaultAgentPreferenceSnapshot(
        clients: Dictionary(uniqueKeysWithValues: VaultAgentClientKind.allCases.map {
            ($0, VaultAgentPreferenceClientSnapshot.unavailable(client: $0))
        }),
        claudePermission: .unavailable,
        audit: []
    )

    func loadSnapshot(completion: @escaping (Result<VaultAgentPreferenceSnapshot, Error>) -> Void) {
        DispatchQueue.main.async { completion(.success(Self.snapshot)) }
    }

    func perform(
        _: VaultAgentPreferenceAction,
        completion: @escaping (Result<VaultAgentPreferenceSnapshot, Error>) -> Void
    ) {
        DispatchQueue.main.async { completion(.failure(VaultAgentErrorCode.brokerUnavailable)) }
    }

    func claudePermissionSnippet(
        scope _: VaultAgentHostPermissionScope,
        completion: @escaping (Result<VaultAgentPermissionSnippet, Error>) -> Void
    ) {
        DispatchQueue.main.async { completion(.failure(VaultAgentErrorCode.brokerUnavailable)) }
    }
}

enum VaultAgentPreferenceRuntimeProvider {
    private static let lock = NSLock()
    private static var storedRuntime: VaultAgentPreferenceRuntimeServicing =
        UnavailableVaultAgentPreferenceRuntime()

    static var runtime: VaultAgentPreferenceRuntimeServicing {
        lock.withLock { storedRuntime }
    }

    static func install(_ runtime: VaultAgentPreferenceRuntimeServicing) {
        lock.withLock { storedRuntime = runtime }
    }
}

protocol VaultAgentPreferenceIntegrationServicing:
    VaultAgentIntegrationServicing,
    VaultAgentHostIdentityProviding,
    VaultAgentHostPermissionManaging {
    func cliStatus() throws -> VaultAgentCLIInstallationStatus
    func installCLI() throws -> VaultAgentCLIInstallationStatus
    func uninstallCLI() throws -> VaultAgentCLIInstallationStatus
    func permissionSnippet(
        for host: VaultAgentHostKind,
        scope: VaultAgentHostPermissionScope
    ) throws -> VaultAgentPermissionSnippet
}

extension VaultAgentIntegrationInstaller: VaultAgentPreferenceIntegrationServicing {}

protocol VaultAgentPreferenceVaultServicing: AnyObject {
    var agentVaultReady: Bool { get }

    func checkQuickUnlockAvailability(completion: @escaping (Bool) -> Void)
    func unlockWithQuickKey(completion: @escaping (Result<Void, PasswordVaultError>) -> Void)
    func enableAutomationUnlockForAgent() throws
}

extension PasswordVaultUIController: VaultAgentPreferenceVaultServicing {}

protocol VaultAgentPreferenceIdentityResolving {
    func resolveIdentity(for client: VaultAgentClientKind) throws -> VaultAgentPeerIdentity
}

final class VaultAgentStaticIdentityResolver: VaultAgentPreferenceIdentityResolving {
    private struct HelperMapping {
        let name: String
        let identifier: String
    }

    private struct FileSnapshot: Equatable {
        let device: UInt64
        let inode: UInt64
        let size: UInt64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
    }

    private let helpersURL: URL
    private let signatureInspector: VaultAgentCodeSigningInspecting
    private let hostIdentityProvider: VaultAgentHostIdentityProviding

    init(
        applicationURL: URL = Bundle.main.bundleURL,
        signatureInspector: VaultAgentCodeSigningInspecting = VaultAgentSystemCodeSigningInspector(),
        hostIdentityProvider: VaultAgentHostIdentityProviding
    ) {
        helpersURL = applicationURL.appendingPathComponent("Contents/Helpers", isDirectory: true)
        self.signatureInspector = signatureInspector
        self.hostIdentityProvider = hostIdentityProvider
    }

    func resolveIdentity(for client: VaultAgentClientKind) throws -> VaultAgentPeerIdentity {
        let mapping = helperMapping(for: client)
        let helperURL = helpersURL.appendingPathComponent(mapping.name, isDirectory: false)
        let before = try fileSnapshot(helperURL)
        let helperSignature = try signatureInspector.inspect(executableURL: helperURL)
        let after = try fileSnapshot(helperURL)
        let finalSignature = try signatureInspector.inspect(executableURL: helperURL)
        guard before == after,
              helperSignature == finalSignature,
              helperSignature.identifier == mapping.identifier,
              !helperSignature.designatedRequirement.isEmpty,
              !helperSignature.isAdHoc || helperSignature.cdHash != nil else {
            throw VaultAgentErrorCode.authorizationRequired
        }

        let host: (identity: VaultAgentInstalledHostIdentity, signature: VaultAgentCodeSignature)?
        switch client {
        case .codex, .claude:
            host = try validatedHost(for: client)
        case .cli:
            host = nil
        }
        return VaultAgentPeerIdentity(
            client: client,
            helperRequirement: helperSignature.designatedRequirement,
            helperCDHash: helperSignature.cdHash,
            helperIsAdHoc: helperSignature.isAdHoc,
            helperPath: helperURL.path,
            hostRequirement: host?.signature.designatedRequirement,
            hostCDHash: host?.signature.cdHash,
            hostIsAdHoc: host?.signature.isAdHoc,
            hostPath: host?.identity.canonicalPath
        )
    }

    private func validatedHost(
        for client: VaultAgentClientKind
    ) throws -> (identity: VaultAgentInstalledHostIdentity, signature: VaultAgentCodeSignature) {
        guard let installed = hostIdentityProvider.installedHostIdentity(for: client),
              installed.client == client else {
            throw VaultAgentErrorCode.authorizationRequired
        }
        let hostURL = URL(fileURLWithPath: installed.canonicalPath).standardizedFileURL
        guard hostURL.path == installed.canonicalPath else {
            throw VaultAgentErrorCode.authorizationRequired
        }
        let before = try fileSnapshot(hostURL)
        let signature = try signatureInspector.inspect(executableURL: hostURL)
        let after = try fileSnapshot(hostURL)
        let finalSignature = try signatureInspector.inspect(executableURL: hostURL)
        guard before == after,
              signature == finalSignature,
              signature.designatedRequirement == installed.designatedRequirement,
              signature.isAdHoc == installed.isAdHoc,
              !signature.isAdHoc || signature.cdHash == installed.cdHash else {
            throw VaultAgentErrorCode.authorizationRequired
        }
        return (installed, signature)
    }

    private func helperMapping(for client: VaultAgentClientKind) -> HelperMapping {
        switch client {
        case .codex: .init(name: "PasteraCodexMCP", identifier: "com.pastera-app.PasteraCodexMCP")
        case .claude: .init(name: "PasteraClaudeMCP", identifier: "com.pastera-app.PasteraClaudeMCP")
        case .cli: .init(name: "pastera", identifier: "com.pastera-app.pastera")
        }
    }

    private func fileSnapshot(_ url: URL) throws -> FileSnapshot {
        var info = stat()
        guard lstat(url.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG,
              info.st_mode & (S_IXUSR | S_IXGRP | S_IXOTH) != 0 else {
            throw VaultAgentErrorCode.authorizationRequired
        }
        return .init(
            device: UInt64(info.st_dev),
            inode: UInt64(info.st_ino),
            size: UInt64(info.st_size),
            modifiedSeconds: Int64(info.st_mtimespec.tv_sec),
            modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec)
        )
    }
}

protocol VaultAgentAuditSnapshotProviding: AnyObject {
    func records(at now: Date) -> [VaultAgentAuditRecord]
}

extension VaultAgentAuditLogger: VaultAgentAuditSnapshotProviding {}

protocol VaultAgentGrantLifecycleReconciling: AnyObject {
    func authorizationStateDidChange() throws
}

extension VaultAgentRuntime: VaultAgentGrantLifecycleReconciling {}

// The preference facade serializes bounded integration work away from AppKit's main thread.
final class DefaultVaultAgentPreferenceRuntime: VaultAgentPreferenceRuntimeServicing {
    private enum WorkKey: Hashable {
        case client(VaultAgentClientKind)
        case permission
    }

    private let integration: VaultAgentPreferenceIntegrationServicing
    private let authorizationPolicy: VaultAgentAuthorizationPolicy
    private let authorizationCoordinator: VaultAgentAuthorizationCoordinator
    private let vault: VaultAgentPreferenceVaultServicing
    private let identityResolver: VaultAgentPreferenceIdentityResolving
    private let lifecycleReconciler: VaultAgentGrantLifecycleReconciling
    private weak var auditSource: VaultAgentAuditSnapshotProviding?
    private let worker: DispatchQueue
    private let workGate: VaultAgentIntegrationWorkGate
    private let now: () -> Date
    private let inFlightLock = NSLock()
    private var inFlight = Set<WorkKey>()

    init(
        integration: VaultAgentPreferenceIntegrationServicing,
        authorizationPolicy: VaultAgentAuthorizationPolicy,
        authorizationCoordinator: VaultAgentAuthorizationCoordinator,
        vault: VaultAgentPreferenceVaultServicing,
        identityResolver: VaultAgentPreferenceIdentityResolving,
        lifecycleReconciler: VaultAgentGrantLifecycleReconciling,
        auditSource: VaultAgentAuditSnapshotProviding? = nil,
        worker: DispatchQueue,
        workGate: VaultAgentIntegrationWorkGate,
        now: @escaping () -> Date = Date.init
    ) {
        self.integration = integration
        self.authorizationPolicy = authorizationPolicy
        self.authorizationCoordinator = authorizationCoordinator
        self.vault = vault
        self.identityResolver = identityResolver
        self.lifecycleReconciler = lifecycleReconciler
        self.auditSource = auditSource
        self.worker = worker
        self.workGate = workGate
        self.now = now
    }

    func loadSnapshot(completion: @escaping (Result<VaultAgentPreferenceSnapshot, Error>) -> Void) {
        performBounded({ try self.makeSnapshot() }, completion: completion)
    }

    func perform(
        _ action: VaultAgentPreferenceAction,
        completion: @escaping (Result<VaultAgentPreferenceSnapshot, Error>) -> Void
    ) {
        let key = workKey(for: action)
        guard begin(key) else {
            deliver(.failure(VaultAgentErrorCode.vaultBusy), completion: completion)
            return
        }
        if case let .authorize(client) = action {
            authorize(client, key: key, completion: completion)
            return
        }
        performBounded(
            {
                try self.performSynchronous(action)
                return try self.makeSnapshot()
            },
            completion: { result in
                self.end(key)
                completion(result)
            }
        )
    }

    func claudePermissionSnippet(
        scope: VaultAgentHostPermissionScope,
        completion: @escaping (Result<VaultAgentPermissionSnippet, Error>) -> Void
    ) {
        performBounded({
            try self.integration.permissionSnippet(for: .claude, scope: scope)
        }, completion: completion)
    }

    private func authorize(
        _ client: VaultAgentClientKind,
        key: WorkKey,
        completion: @escaping (Result<VaultAgentPreferenceSnapshot, Error>) -> Void
    ) {
        performBounded(
            { try self.identityResolver.resolveIdentity(for: client) },
            completion: { result in
                switch result {
                case let .success(identity):
                    self.authenticate(identity, key: key, completion: completion)
                case let .failure(error):
                    self.end(key)
                    completion(.failure(error))
                }
            }
        )
    }

    private func authenticate(
        _ identity: VaultAgentPeerIdentity,
        key: WorkKey,
        completion: @escaping (Result<VaultAgentPreferenceSnapshot, Error>) -> Void
    ) {
        if vault.agentVaultReady {
            requestAuthorization(
                identity,
                authentication: nil,
                key: key,
                completion: completion
            )
            return
        }
        vault.checkQuickUnlockAvailability { available in
            guard available else {
                self.end(key)
                completion(.failure(PasswordVaultError.vaultLocked))
                return
            }
            self.requestAuthorization(
                identity,
                authentication: { callback in
                    self.vault.unlockWithQuickKey { result in
                        callback(result.mapError { $0 as Error })
                    }
                },
                key: key,
                completion: completion
            )
        }
    }

    private func requestAuthorization(
        _ identity: VaultAgentPeerIdentity,
        authentication: VaultAgentAuthorizationCoordinator.AuthenticationAction?,
        key: WorkKey,
        completion: @escaping (Result<VaultAgentPreferenceSnapshot, Error>) -> Void
    ) {
        authorizationCoordinator.authorize(
            identity: identity,
            trigger: .explicitPreferencesAction,
            authentication: authentication,
            prepare: { try self.vault.enableAutomationUnlockForAgent() },
            completion: { result in
                switch result {
                case .success:
                    self.refreshAfterAction(key: key, completion: completion)
                case let .failure(error):
                    self.end(key)
                    completion(.failure(error))
                }
            }
        )
    }

    private func refreshAfterAction(
        key: WorkKey,
        completion: @escaping (Result<VaultAgentPreferenceSnapshot, Error>) -> Void
    ) {
        performBounded(
            { try self.makeSnapshot() },
            completion: { result in
                self.end(key)
                completion(result)
            }
        )
    }

    private func performSynchronous(_ action: VaultAgentPreferenceAction) throws {
        switch action {
        case let .install(client):
            switch client {
            case .codex: _ = try integration.install(host: .codex)
            case .claude: _ = try integration.install(host: .claude)
            case .cli: _ = try integration.installCLI()
            }
        case .authorize:
            preconditionFailure("Authorization is asynchronous")
        case let .revoke(client):
            try authorizationPolicy.revoke(client, at: now())
            try lifecycleReconciler.authorizationStateDidChange()
        case let .uninstall(client):
            switch client {
            case .codex: _ = try integration.uninstall(host: .codex)
            case .claude: _ = try integration.uninstall(host: .claude)
            case .cli: _ = try integration.uninstallCLI()
            }
        case let .applyClaudePermission(scope):
            _ = try integration.applyClaudePermissionScope(scope)
        case .removeClaudePermission:
            _ = try integration.removeOwnedClaudePermissionRules()
        }
    }

    private func makeSnapshot() throws -> VaultAgentPreferenceSnapshot {
        let hostStatus = try integration.status(host: nil)
        let statuses = Dictionary(uniqueKeysWithValues: hostStatus.hosts.map { ($0.host, $0) })
        let cliStatus = try integration.cliStatus()
        var clients = [VaultAgentClientKind: VaultAgentPreferenceClientSnapshot]()
        clients[.codex] = clientSnapshot(.codex, hostStatus: statuses[.codex], cliStatus: nil)
        clients[.claude] = clientSnapshot(.claude, hostStatus: statuses[.claude], cliStatus: nil)
        clients[.cli] = clientSnapshot(.cli, hostStatus: nil, cliStatus: cliStatus)

        let permission = (try? integration.claudePermissionStatus()).map {
            VaultAgentClaudePermissionSnapshot(
                policyDisposition: $0.policyDisposition,
                ownedRules: $0.ownedRules
            )
        } ?? .unavailable
        let audit = (auditSource?.records(at: now()) ?? []).suffix(20).reversed().map {
            VaultAgentPreferenceAuditSummary(
                action: $0.action,
                result: $0.result,
                timestamp: $0.timestamp
            )
        }
        return .init(clients: clients, claudePermission: permission, audit: audit)
    }

    private func clientSnapshot(
        _ client: VaultAgentClientKind,
        hostStatus: VaultAgentHostIntegrationStatus?,
        cliStatus: VaultAgentCLIInstallationStatus?
    ) -> VaultAgentPreferenceClientSnapshot {
        let installed: Bool
        let needsUpdate: Bool
        let detected: Bool
        let path: String?
        if let hostStatus {
            installed = hostStatus.mcpInstalled && hostStatus.skillInstalled
            needsUpdate = hostStatus.mcpInstalled != hostStatus.skillInstalled ||
                (installed && hostStatus.installedVersion == nil)
            detected = hostStatus.hostDetected
            path = hostStatus.hostExecutablePath
        } else if let cliStatus {
            installed = cliStatus.installed
            needsUpdate = false
            detected = true
            path = cliStatus.executablePath
        } else {
            installed = false
            needsUpdate = false
            detected = false
            path = nil
        }

        let grant = authorizationPolicy.grantSnapshot(for: client)
        let authorization: VaultAgentPreferenceAuthorizationState
        if let identity = try? identityResolver.resolveIdentity(for: client) {
            switch authorizationPolicy.decision(for: identity, at: now()) {
            case .allowed: authorization = .authorized
            case .missing: authorization = .missing
            case .identityChanged: authorization = .identityChanged
            case .idleExpired, .hardExpired: authorization = .expired
            case .revoked: authorization = .revoked
            }
        } else {
            authorization = .unavailable
        }
        return .init(
            client: client,
            hostDetected: detected,
            installed: installed,
            installationNeedsUpdate: needsUpdate,
            hostPathSummary: path.map(Self.pathSummary),
            authorization: authorization,
            idleExpiresAt: grant?.idleExpiresAt,
            hardExpiresAt: grant?.hardExpiresAt,
            lastSensitiveUseAt: grant?.lastSensitiveUseAt
        )
    }

    private func performBounded<T>(
        _ operation: @escaping () throws -> T,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        guard workGate.tryAcquire() else {
            deliver(.failure(VaultAgentErrorCode.vaultBusy), completion: completion)
            return
        }
        worker.async {
            let result: Result<T, Error>
            do { result = .success(try operation()) } catch { result = .failure(error) }
            self.workGate.release()
            self.deliver(result, completion: completion)
        }
    }

    private func workKey(for action: VaultAgentPreferenceAction) -> WorkKey {
        switch action {
        case let .install(client), let .authorize(client), let .revoke(client), let .uninstall(client):
            .client(client)
        case .applyClaudePermission, .removeClaudePermission:
            .permission
        }
    }

    private func begin(_ key: WorkKey) -> Bool {
        inFlightLock.withLock { inFlight.insert(key).inserted }
    }

    private func end(_ key: WorkKey) {
        inFlightLock.withLock { _ = inFlight.remove(key) }
    }

    private func deliver<T>(
        _ result: Result<T, Error>,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        DispatchQueue.main.async { completion(result) }
    }

    private static func pathSummary(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent().lastPathComponent
        return parent.isEmpty ? url.lastPathComponent : "\(parent)/\(url.lastPathComponent)"
    }
}

enum VaultAgentPasteTargetError: Error {
    case unavailable
}

final class VaultAgentIntegrationWorkGate {
    let capacity: Int

    private let lock = NSLock()
    private var storedActiveCount = 0

    init(capacity: Int = VaultAgentSocketServer.maximumConnections) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    var activeCount: Int {
        lock.withLock { storedActiveCount }
    }

    func tryAcquire() -> Bool {
        lock.withLock {
            guard storedActiveCount < capacity else { return false }
            storedActiveCount += 1
            return true
        }
    }

    func release() {
        lock.withLock {
            precondition(storedActiveCount > 0)
            storedActiveCount -= 1
        }
    }
}

final class VaultAgentRuntime: VaultAgentSocketRequestHandling {
    private let executor: VaultAgentSerialExecutor
    private let authorizationPolicy: VaultAgentAuthorizationPolicy
    private let authorizationCoordinator: VaultAgentAuthorizationCoordinator?
    private let automaticAuthorizationPrepare: VaultAgentAuthorizationCoordinator.PrepareAction?
    private let vault: PasswordVaultAgentAccess
    private let pasteTargetTracker: VaultAgentPasteTargetTracking
    private let integrationService: VaultAgentIntegrationServicing
    private let integrationWorker: DispatchQueue
    private let integrationWorkGate: VaultAgentIntegrationWorkGate
    private let rateLimiter: VaultAgentRateLimiter
    private let ticketStore: VaultAgentTicketStore
    private let auditLogger: VaultAgentAuditLogging
    private let now: () -> Date
    private let cursorKey: Data
    private weak var interactiveSensitiveUseSource: VaultAgentSensitiveUseObserving?
    private var interactiveSensitiveUseObserverID: UUID?
    private var lastValidGrantCount: Int?

    init(
        executor: VaultAgentSerialExecutor,
        authorizationPolicy: VaultAgentAuthorizationPolicy,
        authorizationCoordinator: VaultAgentAuthorizationCoordinator? = nil,
        automaticAuthorizationPrepare: VaultAgentAuthorizationCoordinator.PrepareAction? = nil,
        vault: PasswordVaultAgentAccess,
        pasteTargetTracker: VaultAgentPasteTargetTracking,
        integrationService: VaultAgentIntegrationServicing = UnavailableVaultAgentIntegrationService(),
        integrationWorker: DispatchQueue = DispatchQueue(
            label: "com.pastera.agent.integration-worker",
            qos: .utility
        ),
        integrationWorkGate: VaultAgentIntegrationWorkGate = VaultAgentIntegrationWorkGate(),
        rateLimiter: VaultAgentRateLimiter = VaultAgentRateLimiter(),
        ticketStore: VaultAgentTicketStore,
        auditLogger: VaultAgentAuditLogging,
        now: @escaping () -> Date = Date.init,
        cursorKey: Data
    ) throws {
        guard cursorKey.count == 32 else { throw VaultAgentErrorCode.brokerUnavailable }
        guard authorizationCoordinator == nil || automaticAuthorizationPrepare != nil else {
            throw VaultAgentErrorCode.automationUnlockUnavailable
        }
        self.executor = executor
        self.authorizationPolicy = authorizationPolicy
        self.authorizationCoordinator = authorizationCoordinator
        self.automaticAuthorizationPrepare = automaticAuthorizationPrepare
        self.vault = vault
        self.pasteTargetTracker = pasteTargetTracker
        self.integrationService = integrationService
        self.integrationWorker = integrationWorker
        self.integrationWorkGate = integrationWorkGate
        self.rateLimiter = rateLimiter
        self.ticketStore = ticketStore
        self.auditLogger = auditLogger
        self.now = now
        self.cursorKey = cursorKey
        if let source = vault as? VaultAgentSensitiveUseObserving {
            interactiveSensitiveUseSource = source
            interactiveSensitiveUseObserverID = source.addInteractiveSensitiveUseObserver { [weak self] in
                self?.interactiveSensitiveUseDidSucceed()
            }
        }
    }

    convenience init(
        executor: VaultAgentSerialExecutor,
        authorizationPolicy: VaultAgentAuthorizationPolicy,
        authorizationCoordinator: VaultAgentAuthorizationCoordinator? = nil,
        automaticAuthorizationPrepare: VaultAgentAuthorizationCoordinator.PrepareAction? = nil,
        vault: PasswordVaultAgentAccess,
        pasteTargetTracker: VaultAgentPasteTargetTracking,
        integrationService: VaultAgentIntegrationServicing = UnavailableVaultAgentIntegrationService(),
        integrationWorker: DispatchQueue = DispatchQueue(
            label: "com.pastera.agent.integration-worker",
            qos: .utility
        ),
        integrationWorkGate: VaultAgentIntegrationWorkGate = VaultAgentIntegrationWorkGate(),
        rateLimiter: VaultAgentRateLimiter = VaultAgentRateLimiter(),
        auditLogger: VaultAgentAuditLogging,
        applicationURL: URL = Bundle.main.bundleURL,
        now: @escaping () -> Date = Date.init
    ) throws {
        let ticketStore = VaultAgentTicketStore(commandBuilder: { client, mode, token in
            Self.helperCommand(
                applicationURL: applicationURL,
                client: client,
                mode: mode,
                token: token
            )
        })
        try self.init(
            executor: executor,
            authorizationPolicy: authorizationPolicy,
            authorizationCoordinator: authorizationCoordinator,
            automaticAuthorizationPrepare: automaticAuthorizationPrepare,
            vault: vault,
            pasteTargetTracker: pasteTargetTracker,
            integrationService: integrationService,
            integrationWorker: integrationWorker,
            integrationWorkGate: integrationWorkGate,
            rateLimiter: rateLimiter,
            ticketStore: ticketStore,
            auditLogger: auditLogger,
            now: now,
            cursorKey: Self.secureRandomCursorKey()
        )
    }

    deinit {
        if let identifier = interactiveSensitiveUseObserverID {
            interactiveSensitiveUseSource?.removeInteractiveSensitiveUseObserver(identifier)
        }
    }

    func authorizationStateDidChange() throws {
        try reconcileGrantLifecycle(at: now())
    }

    static func secureRandomCursorKey() throws -> Data {
        var bytes = Data(count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            guard let address = buffer.baseAddress else { return errSecAllocate }
            return SecRandomCopyBytes(kSecRandomDefault, buffer.count, address)
        }
        guard status == errSecSuccess else { throw VaultAgentErrorCode.brokerUnavailable }
        return bytes
    }

    static func helperCommand(
        applicationURL: URL,
        client: VaultAgentClientKind,
        mode: VaultAgentInjectionMode,
        token: String
    ) -> [String] {
        let helperName: String
        switch client {
        case .codex: helperName = "PasteraCodexMCP"
        case .claude: helperName = "PasteraClaudeMCP"
        case .cli: helperName = "pastera"
        }
        let helper = applicationURL
            .appendingPathComponent("Contents/Helpers", isDirectory: true)
            .appendingPathComponent(helperName, isDirectory: false)
            .path
        switch mode {
        case .stdin:
            return [helper, "exec", "--ticket", token, "--stdin", "--"]
        case .fileDescriptor:
            return [helper, "exec", "--ticket", token, "--fd", "3", "--"]
        }
    }

    func handle(
        identity: VaultAgentPeerIdentity,
        request: Data,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        let envelope: VaultAgentRequestEnvelope
        do {
            guard request.count <= VaultAgentLimits.maximumFrameBytes else {
                throw VaultAgentProtocolError.limitExceeded
            }
            envelope = try JSONDecoder().decode(VaultAgentRequestEnvelope.self, from: request)
        } catch {
            completion(.success(Self.encodeFallbackFailure(.invalidRequest)))
            return
        }

        let action = Self.auditAction(for: envelope.operation)
        let startedAt = now()
        let entryID = Self.entryID(for: envelope.operation)
        let completionGate = VaultAgentRuntimeCompletionGate()
        let finish: (VaultAgentResponseBody) -> Void = { [weak self] body in
            guard completionGate.claim() else { return }
            guard let self else {
                completion(.success(Self.finalize(
                    envelope: envelope,
                    proposedBody: .failure(Self.failure(.brokerUnavailable))
                ).data))
                return
            }
            let finalized = Self.finalize(envelope: envelope, proposedBody: body)
            let finishedAt = self.now()
            self.auditLogger.record(
                client: identity.client,
                action: action,
                entryID: entryID,
                result: finalized.body.failureCode,
                latencyBucket: Self.latencyBucket(finishedAt.timeIntervalSince(startedAt)),
                at: finishedAt
            )
            completion(.success(finalized.data))
        }

        do {
            try reconcileGrantLifecycle(at: startedAt)
        } catch {
            finish(.failure(Self.failure(.brokerUnavailable)))
            return
        }

        guard envelope.protocolVersion == VaultAgentLimits.protocolVersion else {
            finish(.failure(Self.failure(.protocolMismatch)))
            return
        }
        dispatch(envelope.operation, identity: identity, finish: finish)
    }
}

private extension VaultAgentRuntime {
    private func reconcileGrantLifecycle(at date: Date) throws {
        try executor.sync {
            let currentCount = authorizationPolicy.validGrantCount(at: date)
            if currentCount == 0, lastValidGrantCount != 0 {
                do {
                    try vault.disableAutomationUnlockForAgent()
                    ticketStore.removeAll()
                } catch {
                    ticketStore.removeAll()
                    throw error
                }
            }
            lastValidGrantCount = currentCount
        }
    }

    private func interactiveSensitiveUseDidSucceed() {
        executor.sync {
            do {
                let date = now()
                try authorizationPolicy.recordInteractiveSensitiveSuccess(at: date)
                try reconcileGrantLifecycle(at: date)
            } catch {
                // The interactive action already succeeded; persistence is best-effort here.
            }
        }
    }

    // swiftlint:disable:next function_body_length
    private func dispatch(
        _ operation: VaultAgentOperation,
        identity: VaultAgentPeerIdentity,
        finish: @escaping (VaultAgentResponseBody) -> Void
    ) {
        switch operation {
        case .status:
            status(identity: identity, finish: finish)
        case let .integrationStatus(host):
            guard identity.client == .cli else {
                finish(.failure(Self.failure(.invalidRequest)))
                return
            }
            performIntegration(finish: finish) {
                self.resultBody {
                    .integrationStatus(try self.integrationService.status(host: host))
                }
            }
        case let .integrationInstall(host):
            guard identity.client == .cli else {
                finish(.failure(Self.failure(.invalidRequest)))
                return
            }
            performIntegration(finish: finish) {
                self.resultBody {
                    .integrationStatus(try self.integrationService.install(host: host))
                }
            }
        case let .integrationUninstall(host):
            guard identity.client == .cli else {
                finish(.failure(Self.failure(.invalidRequest)))
                return
            }
            performIntegration(finish: finish) {
                self.resultBody {
                    .integrationStatus(try self.integrationService.uninstall(host: host))
                }
            }
        case let .search(request):
            withReady(identity: identity, category: .metadata, finish: finish) {
                self.vault.agentMetadata { result in
                    finish(self.metadataBody(result) { folders, entries in
                        try self.search(request, folders: folders, entries: entries)
                    })
                }
            }
        case let .get(entryID):
            withReady(identity: identity, category: .metadata, finish: finish) {
                self.vault.agentMetadata { result in
                    finish(self.metadataBody(result) { folders, entries in
                        guard let entry = entries.first(where: { $0.id == entryID }) else {
                            throw PasswordVaultError.entryNotFound
                        }
                        return .entry(Self.map(entry, folders: folders))
                    })
                }
            }
        case let .paste(entryID, field):
            withReady(identity: identity, category: .directSecret, finish: finish) {
                let target: PasteTargetContext
                do { target = try self.pasteTargetTracker.resolve() } catch {
                    finish(.failure(Self.failure(.targetUnavailable)))
                    return
                }
                self.vault.agentPaste(entryID: entryID, field: field, target: target) { result in
                    switch result {
                    case .success:
                        finish(self.renewalBody(identity: identity))
                    case let .failure(error):
                        finish(.failure(Self.failure(for: error)))
                    }
                }
            }
        case let .copy(entryID, field):
            guard identity.client == .cli else {
                finish(.failure(Self.failure(.invalidRequest)))
                return
            }
            withReady(identity: identity, category: .directSecret, finish: finish) {
                self.vault.agentCopy(entryID: entryID, field: field) { result in
                    switch result {
                    case .success:
                        finish(self.renewalBody(identity: identity))
                    case let .failure(error):
                        finish(.failure(Self.failure(for: error)))
                    }
                }
            }
        case let .prepareExec(entryID, field, mode):
            withReady(identity: identity, category: .ticket, finish: finish) {
                self.vault.agentMetadata { result in
                    finish(self.metadataBody(result) { _, entries in
                        guard entries.contains(where: { $0.id == entryID }) else {
                            throw PasswordVaultError.entryNotFound
                        }
                        return .ticket(try self.ticketStore.issue(
                            client: identity.client,
                            entryID: entryID,
                            field: field,
                            mode: mode,
                            now: self.now()
                        ))
                    })
                }
            }
        case let .redeemTicket(token, mode):
            withReady(identity: identity, category: .ticket, finish: finish) {
                let redemption: (receiptID: UUID, binding: VaultAgentTicketBinding)
                do {
                    redemption = try self.ticketStore.redeem(
                        token: token,
                        client: identity.client,
                        mode: mode,
                        now: self.now()
                    )
                } catch {
                    finish(.failure(Self.failure(for: error)))
                    return
                }
                self.vault.agentSecret(
                    entryID: redemption.binding.entryID,
                    field: redemption.binding.field
                ) { result in
                    switch result {
                    case let .success(bytes):
                        finish(.success(.secretDelivery(.init(
                            receiptID: redemption.receiptID,
                            bytes: bytes
                        ))))
                    case let .failure(error):
                        finish(.failure(Self.failure(for: error)))
                    }
                }
            }
        case let .completeTicket(receiptID):
            withReady(identity: identity, category: .ticket, finish: finish) {
                do {
                    _ = try self.ticketStore.complete(
                        receiptID: receiptID,
                        client: identity.client,
                        now: self.now()
                    )
                    finish(self.renewalBody(identity: identity))
                } catch {
                    finish(.failure(Self.failure(for: error)))
                }
            }
        }
    }

    private func withReady(
        identity: VaultAgentPeerIdentity,
        category: VaultAgentRateLimitCategory,
        finish: @escaping (VaultAgentResponseBody) -> Void,
        operation: @escaping () -> Void
    ) {
        let decision = authorizationPolicy.decision(for: identity, at: now())
        if let code = Self.authorizationFailure(decision) {
            if vault.agentVaultReady,
               decision == .missing || decision == .identityChanged {
                authorizationCoordinator?.authorize(
                    identity: identity,
                    trigger: .automaticFirstRequest,
                    prepare: automaticAuthorizationPrepare
                ) { _ in }
            }
            finish(.failure(Self.failure(code)))
            return
        }
        do {
            try rateLimiter.check(client: identity.client, category: category, at: now())
        } catch {
            finish(.failure(Self.failure(for: error)))
            return
        }
        vault.ensureReadyForAgent { result in
            switch result {
            case .success: operation()
            case let .failure(error): finish(.failure(Self.failure(for: error)))
            }
        }
    }

    private func status(
        identity: VaultAgentPeerIdentity,
        finish: @escaping (VaultAgentResponseBody) -> Void
    ) {
        if identity.client == .cli {
            finish(statusBody(identity: identity, installed: true))
            return
        }
        performIntegration(finish: finish) {
            let host: VaultAgentHostKind = identity.client == .codex ? .codex : .claude
            let integration = try? self.integrationService.status(host: host)
            let installed = integration?.hosts.first.map {
                $0.mcpInstalled && $0.skillInstalled
            } ?? false
            return self.statusBody(identity: identity, installed: installed)
        }
    }

    private func statusBody(
        identity: VaultAgentPeerIdentity,
        installed: Bool
    ) -> VaultAgentResponseBody {
        let date = now()
        let decision = authorizationPolicy.decision(for: identity, at: date)
        let grant = authorizationPolicy.grantSnapshot(for: identity.client)
        let authorized: Bool
        if case .allowed = decision { authorized = true } else { authorized = false }
        return .success(.status(.init(
            client: identity.client,
            installed: installed,
            authorized: authorized,
            vaultReady: vault.agentVaultReady,
            idleExpiresAt: grant?.idleExpiresAt,
            hardExpiresAt: grant?.hardExpiresAt,
            protocolVersion: VaultAgentLimits.protocolVersion
        )))
    }

    private func performIntegration(
        finish: @escaping (VaultAgentResponseBody) -> Void,
        operation: @escaping () -> VaultAgentResponseBody
    ) {
        guard integrationWorkGate.tryAcquire() else {
            finish(.failure(Self.failure(.vaultBusy)))
            return
        }
        integrationWorker.async {
            defer { self.integrationWorkGate.release() }
            finish(operation())
        }
    }

    private func search(
        _ request: VaultAgentSearchRequest,
        folders: [PasswordVaultFolder],
        entries: [PasswordVaultEntry]
    ) throws -> VaultAgentResponsePayload {
        let folderNames = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0.name) })
        let rawQuery = request.query ?? ""
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let revision = try Self.metadataRevision(folders: folders, entries: entries)
        let offset: Int
        if let cursor = request.cursor {
            offset = try decodeCursor(
                cursor,
                query: rawQuery,
                folderID: request.folderID,
                revision: revision
            )
        } else {
            offset = 0
        }
        let results = entries.lazy
            .filter { request.folderID == nil || $0.folderID == request.folderID }
            .filter {
                query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
                    || $0.website.localizedCaseInsensitiveContains(query)
                    || $0.username.localizedCaseInsensitiveContains(query)
            }
            .sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            .map {
                VaultAgentEntryMetadata(
                    id: $0.id,
                    folderID: $0.folderID,
                    folderName: folderNames[$0.folderID] ?? "",
                    title: $0.title,
                    website: $0.website,
                    username: $0.username,
                    updatedAt: $0.updatedAt
                )
            }
        guard offset >= 0, offset <= results.count else {
            throw VaultAgentProtocolError.invalidValue
        }
        let available = Array(results.dropFirst(offset).prefix(request.limit))
        if available.isEmpty {
            return .search(.init(entries: [], nextCursor: nil))
        }
        for count in stride(from: available.count, through: 1, by: -1) {
            let nextOffset = offset + count
            let nextCursor = nextOffset < results.count
                ? try encodeCursor(
                    query: rawQuery,
                    folderID: request.folderID,
                    offset: nextOffset,
                    revision: revision
                )
                : nil
            let payload = VaultAgentResponsePayload.search(.init(
                entries: Array(available.prefix(count)),
                nextCursor: nextCursor
            ))
            if Self.fitsMaximumResponse(payload) { return payload }
        }
        throw VaultAgentProtocolError.limitExceeded
    }

    private func encodeCursor(
        query: String,
        folderID: UUID?,
        offset: Int,
        revision: Data
    ) throws -> String {
        guard offset >= 0 else { throw VaultAgentProtocolError.invalidValue }
        let payload = VaultAgentCursorPayload(
            version: 1,
            queryDigest: Data(SHA256.hash(data: Data(query.utf8))),
            folderID: folderID,
            offset: offset,
            revision: revision
        )
        let payloadData = try Self.cursorEncoder.encode(payload)
        let signature = Data(HMAC<SHA256>.authenticationCode(
            for: payloadData,
            using: SymmetricKey(data: cursorKey)
        ))
        let container = try Self.cursorEncoder.encode(VaultAgentCursorContainer(
            payload: payloadData,
            signature: signature
        ))
        let token = container.vaultAgentBase64URL
        guard token.lengthOfBytes(using: .utf8) <= VaultAgentLimits.maximumCursorBytes else {
            throw VaultAgentProtocolError.limitExceeded
        }
        return token
    }

    private func decodeCursor(
        _ token: String,
        query: String,
        folderID: UUID?,
        revision: Data
    ) throws -> Int {
        guard let encoded = Data(vaultAgentBase64URL: token),
              let container = try? Self.cursorDecoder.decode(VaultAgentCursorContainer.self, from: encoded),
              container.signature.count == 32,
              HMAC<SHA256>.isValidAuthenticationCode(
                container.signature,
                authenticating: container.payload,
                using: SymmetricKey(data: cursorKey)
              ),
              let payload = try? Self.cursorDecoder.decode(VaultAgentCursorPayload.self, from: container.payload),
              payload.version == 1,
              payload.queryDigest == Data(SHA256.hash(data: Data(query.utf8))),
              payload.folderID == folderID,
              payload.revision == revision,
              payload.offset >= 0 else {
            throw VaultAgentProtocolError.invalidValue
        }
        return payload.offset
    }

    private static func metadataRevision(
        folders: [PasswordVaultFolder],
        entries: [PasswordVaultEntry]
    ) throws -> Data {
        let snapshot = VaultAgentMetadataRevision(
            folders: folders.sorted { $0.id.uuidString < $1.id.uuidString }.map {
                .init(id: $0.id, name: $0.name, updatedAt: $0.updatedAt)
            },
            entries: entries.sorted { $0.id.uuidString < $1.id.uuidString }.map {
                .init(
                    id: $0.id,
                    folderID: $0.folderID,
                    title: $0.title,
                    website: $0.website,
                    username: $0.username,
                    updatedAt: $0.updatedAt
                )
            }
        )
        return Data(SHA256.hash(data: try cursorEncoder.encode(snapshot)))
    }

    private static func fitsMaximumResponse(_ payload: VaultAgentResponsePayload) -> Bool {
        let maximumSequenceDigits = UInt64.max
        let placeholder = VaultAgentResponseEnvelope(
            protocolVersion: VaultAgentLimits.protocolVersion,
            connectionID: UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!,
            sequence: maximumSequenceDigits,
            requestID: UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!,
            body: .success(payload)
        )
        guard let encoded = try? JSONEncoder().encode(placeholder) else { return false }
        return encoded.count <= VaultAgentLimits.maximumResponseBytes
    }

    private static var cursorEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    private static var cursorDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    private func metadataBody(
        _ result: Result<([PasswordVaultFolder], [PasswordVaultEntry]), PasswordVaultError>,
        transform: ([PasswordVaultFolder], [PasswordVaultEntry]) throws -> VaultAgentResponsePayload
    ) -> VaultAgentResponseBody {
        do {
            let metadata = try result.get()
            return .success(try transform(metadata.0, metadata.1))
        } catch {
            return .failure(Self.failure(for: error))
        }
    }

    private func renewalBody(identity: VaultAgentPeerIdentity) -> VaultAgentResponseBody {
        do {
            try authorizationPolicy.recordSensitiveSuccess(for: identity, at: now())
            return .success(.empty)
        } catch {
            return .failure(Self.failure(.brokerUnavailable))
        }
    }

    private func resultBody(
        _ operation: () throws -> VaultAgentResponsePayload
    ) -> VaultAgentResponseBody {
        do { return .success(try operation()) } catch { return .failure(Self.failure(for: error)) }
    }

    private static func map(
        _ entry: PasswordVaultEntry,
        folders: [PasswordVaultFolder]
    ) -> VaultAgentEntryMetadata {
        .init(
            id: entry.id,
            folderID: entry.folderID,
            folderName: folders.first(where: { $0.id == entry.folderID })?.name ?? "",
            title: entry.title,
            website: entry.website,
            username: entry.username,
            updatedAt: entry.updatedAt
        )
    }

    private static func authorizationFailure(_ decision: VaultAgentGrantDecision) -> VaultAgentErrorCode? {
        switch decision {
        case .allowed: nil
        case .missing, .identityChanged: .authorizationRequired
        case .idleExpired, .hardExpired: .grantExpired
        case .revoked: .grantRevoked
        }
    }

    private static func failure(for error: Error) -> VaultAgentFailure {
        if let error = error as? VaultAgentRateLimitError {
            return .init(
                code: .rateLimited,
                message: message(for: .rateLimited),
                retryable: true,
                retryAfterMilliseconds: min(60_000, max(1, error.retryAfterMilliseconds))
            )
        }
        if let error = error as? VaultAgentTicketError {
            switch error {
            case .expired: return failure(.ticketExpired)
            case .used: return failure(.ticketUsed)
            case .capacityExceeded: return failure(.vaultBusy)
            case .bindingMismatch, .randomnessUnavailable, .invalidCommand:
                return failure(.brokerUnavailable)
            }
        }
        if let error = error as? PasswordVaultError {
            switch error {
            case .databaseNotConfigured: return failure(.vaultNotConfigured)
            case .entryNotFound: return failure(.entryNotFound)
            case .keychainUnavailable, .vaultLocked, .wrongMasterPassword:
                return failure(.automationUnlockUnavailable)
            default: return failure(.brokerUnavailable)
            }
        }
        if let error = error as? VaultAgentErrorCode { return failure(error) }
        if error is VaultAgentProtocolError { return failure(.invalidRequest) }
        if error is VaultAgentPasteTargetError { return failure(.targetUnavailable) }
        return failure(.brokerUnavailable)
    }

    private static func failure(_ code: VaultAgentErrorCode) -> VaultAgentFailure {
        .init(
            code: code,
            message: message(for: code),
            retryable: code == .vaultBusy || code == .rateLimited,
            retryAfterMilliseconds: nil
        )
    }

    private static func message(for code: VaultAgentErrorCode) -> String {
        switch code {
        case .authorizationRequired: "Authorization required."
        case .grantExpired: "Authorization expired."
        case .grantRevoked: "Authorization revoked."
        case .vaultNotConfigured: "Vault is not configured."
        case .automationUnlockUnavailable: "Automation unlock is unavailable."
        case .brokerUnavailable: "Broker is unavailable."
        case .vaultBusy: "Vault is busy."
        case .rateLimited: "Rate limit exceeded."
        case .entryNotFound: "Entry was not found."
        case .targetUnavailable: "Paste target is unavailable."
        case .ticketExpired: "Ticket expired."
        case .ticketUsed: "Ticket was already used."
        case .protocolMismatch: "Protocol version mismatch."
        case .invalidRequest: "Request is invalid."
        }
    }

    private static func finalize(
        envelope: VaultAgentRequestEnvelope,
        proposedBody: VaultAgentResponseBody
    ) -> (data: Data, body: VaultAgentResponseBody) {
        if let data = validatedEncoding(envelope: envelope, body: proposedBody) {
            return (data, proposedBody)
        }
        let failureBody = VaultAgentResponseBody.failure(failure(.brokerUnavailable))
        if let data = validatedEncoding(envelope: envelope, body: failureBody) {
            return (data, failureBody)
        }
        return (encodeFallbackFailure(.brokerUnavailable), failureBody)
    }

    private static func validatedEncoding(
        envelope: VaultAgentRequestEnvelope,
        body: VaultAgentResponseBody
    ) -> Data? {
        let response = VaultAgentResponseEnvelope(
            protocolVersion: VaultAgentLimits.protocolVersion,
            connectionID: envelope.connectionID,
            sequence: envelope.sequence,
            requestID: envelope.requestID,
            body: body
        )
        guard let data = try? JSONEncoder().encode(response),
              data.count <= VaultAgentLimits.maximumResponseBytes,
              (try? JSONDecoder().decode(VaultAgentResponseEnvelope.self, from: data)) != nil else {
            return nil
        }
        return data
    }

    private static func encodeFallbackFailure(_ code: VaultAgentErrorCode) -> Data {
        let response = VaultAgentResponseEnvelope(
            protocolVersion: VaultAgentLimits.protocolVersion,
            connectionID: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
            sequence: 0,
            requestID: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
            body: .failure(failure(code))
        )
        return (try? JSONEncoder().encode(response)) ?? Data()
    }

    private static func auditAction(for operation: VaultAgentOperation) -> VaultAgentAuditAction {
        switch operation {
        case .status: .status
        case .search: .search
        case .get: .get
        case .paste: .paste
        case .copy: .copy
        case .prepareExec: .prepareExec
        case .redeemTicket: .redeemTicket
        case .completeTicket: .completeTicket
        case .integrationStatus: .integrationStatus
        case .integrationInstall: .integrationInstall
        case .integrationUninstall: .integrationUninstall
        }
    }

    private static func entryID(for operation: VaultAgentOperation) -> UUID? {
        switch operation {
        case let .get(entryID), let .paste(entryID, _), let .copy(entryID, _),
             let .prepareExec(entryID, _, _): entryID
        default: nil
        }
    }

    private static func latencyBucket(_ interval: TimeInterval) -> VaultAgentLatencyBucket {
        switch interval {
        case ..<0.01: .under10ms
        case ..<0.05: .under50ms
        case ..<0.2: .under200ms
        case ..<1: .under1s
        default: .atLeast1s
        }
    }
}

private final class VaultAgentRuntimeCompletionGate {
    private let lock = NSLock()
    private var completed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return false }
        completed = true
        return true
    }
}

private extension VaultAgentResponseBody {
    var failureCode: VaultAgentErrorCode? {
        guard case let .failure(failure) = self else { return nil }
        return failure.code
    }
}

private struct VaultAgentCursorPayload: Codable {
    let version: Int
    let queryDigest: Data
    let folderID: UUID?
    let offset: Int
    let revision: Data
}

private struct VaultAgentCursorContainer: Codable {
    let payload: Data
    let signature: Data
}

private struct VaultAgentMetadataRevision: Codable {
    struct Folder: Codable {
        let id: UUID
        let name: String
        let updatedAt: Date
    }

    struct Entry: Codable {
        let id: UUID
        let folderID: UUID
        let title: String
        let website: String
        let username: String
        let updatedAt: Date
    }

    let folders: [Folder]
    let entries: [Entry]
}

private extension Data {
    var vaultAgentBase64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(vaultAgentBase64URL value: String) {
        guard value.lengthOfBytes(using: .utf8) <= VaultAgentLimits.maximumCursorBytes else { return nil }
        guard !value.isEmpty,
              value.utf8.allSatisfy({ byte in
                  switch byte {
                  case 45, 48...57, 65...90, 95, 97...122:
                      return true
                  default:
                      return false
                  }
              }) else {
            return nil
        }
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.utf8.count % 4
        if remainder != 0 { base64.append(String(repeating: "=", count: 4 - remainder)) }
        guard let decoded = Data(base64Encoded: base64),
              decoded.vaultAgentBase64URL == value else {
            return nil
        }
        self = decoded
    }
}
