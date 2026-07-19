import Foundation
import LocalAuthentication
import PasteraAgentProtocol
import Security
import Testing
@testable import Pastera

@Suite("Vault agent authorization policy")
struct VaultAgentAuthorizationPolicyTests {
    @Test("sensitive success slides idle expiry but never crosses hard expiry")
    func sensitiveSuccessSlidesIdleExpiry() throws {
        let start = Date(timeIntervalSince1970: 10_000)
        let store = InMemoryVaultAgentGrantStore()
        let policy = try VaultAgentAuthorizationPolicy(store: store)
        let identity = VaultAgentPeerIdentity.testValue(client: .codex)
        try policy.authorize(identity: identity, authenticatedAt: start)

        let useTime = start.addingTimeInterval(6 * 24 * 60 * 60)
        try policy.recordSensitiveSuccess(for: identity, at: useTime)
        let grant = try #require(store.grants[.codex])

        #expect(grant.idleExpiresAt == useTime.addingTimeInterval(7 * 24 * 60 * 60))
        #expect(grant.hardExpiresAt == start.addingTimeInterval(30 * 24 * 60 * 60))
    }

    @Test("metadata and failed actions do not renew")
    func nonSensitiveActionsDoNotRenew() throws {
        let start = Date(timeIntervalSince1970: 20_000)
        let store = InMemoryVaultAgentGrantStore()
        let policy = try VaultAgentAuthorizationPolicy(store: store)
        let identity = VaultAgentPeerIdentity.testValue(client: .claude)
        try policy.authorize(identity: identity, authenticatedAt: start)
        let original = try #require(store.grants[.claude])

        _ = policy.decision(for: identity, at: start.addingTimeInterval(60))
        policy.recordFailure(for: identity, at: start.addingTimeInterval(120))

        #expect(store.grants[.claude] == original)
        #expect(store.grants[.codex] == nil)
    }

    @Test("idle and hard expiry boundaries are exclusive")
    func expiryBoundaries() throws {
        let start = Date(timeIntervalSince1970: 30_000)
        let store = InMemoryVaultAgentGrantStore()
        let policy = try VaultAgentAuthorizationPolicy(store: store)
        let identity = VaultAgentPeerIdentity.testValue(client: .cli)
        let grant = try policy.authorize(identity: identity, authenticatedAt: start)

        #expect(policy.decision(for: identity, at: grant.idleExpiresAt.addingTimeInterval(-1)) == .allowed(grant))
        #expect(policy.decision(for: identity, at: grant.idleExpiresAt) == .idleExpired)

        try policy.authorize(identity: identity, authenticatedAt: start)
        for day in [6, 12, 18, 24, 29] {
            try policy.recordSensitiveSuccess(
                for: identity,
                at: start.addingTimeInterval(TimeInterval(day * 24 * 60 * 60))
            )
        }
        let renewed = try #require(store.grants[.cli])
        #expect(renewed.idleExpiresAt == renewed.hardExpiresAt)
        #expect(policy.decision(for: identity, at: renewed.hardExpiresAt) == .hardExpired)
    }

    @Test("formal signatures allow cdhash upgrades but reject identity changes")
    func formalIdentityMatching() throws {
        let start = Date(timeIntervalSince1970: 40_000)
        let store = InMemoryVaultAgentGrantStore()
        let policy = try VaultAgentAuthorizationPolicy(store: store)
        let original = VaultAgentPeerIdentity.testValue(client: .codex, helperCDHash: Data([0x01]))
        let grant = try policy.authorize(identity: original, authenticatedAt: start)

        let upgraded = VaultAgentPeerIdentity.testValue(
            client: .codex,
            helperCDHash: Data([0x02]),
            helperPath: "/Applications/../Applications/Pastera.app/Contents/MacOS/pastera-agent-helper"
        )
        #expect(policy.decision(for: upgraded, at: start) == .allowed(grant))
        #expect(policy.decision(
            for: .testValue(client: .codex, helperPath: "/tmp/pastera-agent-helper"),
            at: start
        ) == .identityChanged)
        #expect(policy.decision(
            for: .testValue(client: .codex, helperCDHash: Data([0x01]), helperIsAdHoc: true),
            at: start
        ) == .identityChanged)
    }

    @Test("ad hoc signatures require exact cdhash for helper and host")
    func adHocIdentityMatching() throws {
        let start = Date(timeIntervalSince1970: 50_000)
        let store = InMemoryVaultAgentGrantStore()
        let policy = try VaultAgentAuthorizationPolicy(store: store)
        let original = VaultAgentPeerIdentity.adHocWithHost(client: .claude, hash: Data([0x11]))
        let grant = try policy.authorize(identity: original, authenticatedAt: start)

        #expect(policy.decision(for: original, at: start) == .allowed(grant))
        #expect(policy.decision(
            for: .adHocWithHost(client: .claude, hash: Data([0x12])),
            at: start
        ) == .identityChanged)
        #expect(policy.decision(
            for: .adHocWithHost(client: .claude, hash: nil),
            at: start
        ) == .identityChanged)
    }

    @Test("revocation is a persistent tombstone and invalid grants are not counted")
    func revocationAndValidCount() throws {
        let start = Date(timeIntervalSince1970: 60_000)
        let store = InMemoryVaultAgentGrantStore()
        let policy = try VaultAgentAuthorizationPolicy(store: store)
        let codex = VaultAgentPeerIdentity.testValue(client: .codex)
        let claude = VaultAgentPeerIdentity.testValue(client: .claude)
        try policy.authorize(identity: codex, authenticatedAt: start)
        try policy.authorize(identity: claude, authenticatedAt: start)

        try policy.revoke(.codex, at: start.addingTimeInterval(1))
        #expect(store.grants[.codex]?.revokedAt == start.addingTimeInterval(1))
        #expect(policy.decision(for: codex, at: start.addingTimeInterval(2)) == .revoked)
        #expect(policy.validGrantCount(at: start.addingTimeInterval(2)) == 1)

        try policy.revokeAll(at: start.addingTimeInterval(3))
        #expect(policy.decision(for: claude, at: start.addingTimeInterval(4)) == .revoked)
        #expect(policy.validGrantCount(at: start.addingTimeInterval(4)) == 0)
    }

    @Test("interactive sensitive success renews every valid grant only")
    func interactiveSensitiveSuccess() throws {
        let start = Date(timeIntervalSince1970: 70_000)
        let store = InMemoryVaultAgentGrantStore()
        let policy = try VaultAgentAuthorizationPolicy(store: store)
        try policy.authorize(identity: .testValue(client: .codex), authenticatedAt: start)
        try policy.authorize(identity: .testValue(client: .claude), authenticatedAt: start)
        try policy.authorize(identity: .testValue(client: .cli), authenticatedAt: start.addingTimeInterval(-8 * 24 * 60 * 60))
        try policy.revoke(.claude, at: start)

        let useTime = start.addingTimeInterval(60)
        try policy.recordInteractiveSensitiveSuccess(at: useTime)

        #expect(store.grants[.codex]?.lastSensitiveUseAt == useTime)
        #expect(store.grants[.claude]?.lastSensitiveUseAt == nil)
        #expect(store.grants[.cli]?.lastSensitiveUseAt == nil)
    }

    @Test("failed persistence never advances in-memory authorization")
    func persistenceFailureIsAtomic() throws {
        let store = InMemoryVaultAgentGrantStore()
        let policy = try VaultAgentAuthorizationPolicy(store: store)
        let identity = VaultAgentPeerIdentity.testValue(client: .codex)
        store.saveError = VaultAgentErrorCode.automationUnlockUnavailable

        #expect(throws: VaultAgentErrorCode.automationUnlockUnavailable) {
            try policy.authorize(identity: identity, authenticatedAt: Date(timeIntervalSince1970: 80_000))
        }
        #expect(policy.decision(for: identity, at: Date(timeIntervalSince1970: 80_000)) == .missing)
        store.saveError = nil
        let grant = try policy.authorize(identity: identity, authenticatedAt: Date(timeIntervalSince1970: 80_000))
        store.saveError = VaultAgentErrorCode.automationUnlockUnavailable
        #expect(throws: VaultAgentErrorCode.automationUnlockUnavailable) {
            try policy.recordSensitiveSuccess(for: identity, at: Date(timeIntervalSince1970: 80_060))
        }
        #expect(policy.decision(for: identity, at: Date(timeIntervalSince1970: 80_060)) == .allowed(grant))
    }

    @Test("load failure is surfaced during policy initialization")
    func loadFailureIsSurfaced() {
        let store = InMemoryVaultAgentGrantStore()
        store.loadError = VaultAgentErrorCode.automationUnlockUnavailable

        #expect(throws: VaultAgentErrorCode.automationUnlockUnavailable) {
            try VaultAgentAuthorizationPolicy(store: store)
        }
    }
}

extension VaultAgentAuthorizationPolicyTests {
    @Test("not found loads empty grants with the exact non-sync query")
    func notFoundLoadsEmpty() throws {
        let keychain = VaultAgentKeychainProbe()
        keychain.copyStatus = errSecItemNotFound
        let store = VaultAgentGrantStore(keychain: keychain)

        #expect(try store.load().isEmpty)
        let query = try #require(keychain.copyQuery)
        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String == "com.pastera-app.Pastera.agent-grants.v1")
        #expect(query[kSecAttrAccount as String] as? String == "grants")
        #expect(query[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(query[kSecReturnData as String] as? Bool == true)
        #expect(query[kSecMatchLimit as String] as? String == kSecMatchLimitOne as String)
    }

    @Test("save updates one object or adds a device-only item")
    func saveUsesAtomicObject() throws {
        let keychain = VaultAgentKeychainProbe()
        keychain.updateStatus = errSecItemNotFound
        keychain.addStatus = errSecSuccess
        let store = VaultAgentGrantStore(keychain: keychain)
        let grant = VaultAgentGrant.testValue(client: .codex)

        try store.save([.codex: grant])

        let update = try #require(keychain.updateQuery)
        #expect(update[kSecAttrService as String] as? String == "com.pastera-app.Pastera.agent-grants.v1")
        let add = try #require(keychain.addQuery)
        #expect(add[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        #expect(add[kSecAttrSynchronizable as String] as? Bool == false)
        let data = try #require(add[kSecValueData as String] as? Data)
        keychain.copyStatus = errSecSuccess
        keychain.copyData = data
        #expect(try store.load()[.codex] == grant)
    }

    @Test("Security and decoding failures map to the stable vault error")
    func failuresAreStable() {
        let keychain = VaultAgentKeychainProbe()
        let store = VaultAgentGrantStore(keychain: keychain)
        keychain.copyStatus = errSecInteractionNotAllowed
        #expect(throws: VaultAgentErrorCode.automationUnlockUnavailable) { try store.load() }

        keychain.copyStatus = errSecSuccess
        keychain.copyData = Data("not-json".utf8)
        #expect(throws: VaultAgentErrorCode.automationUnlockUnavailable) { try store.load() }

        keychain.updateStatus = errSecAuthFailed
        #expect(throws: VaultAgentErrorCode.automationUnlockUnavailable) { try store.save([:]) }
        keychain.updateStatus = errSecItemNotFound
        keychain.addStatus = errSecAuthFailed
        #expect(throws: VaultAgentErrorCode.automationUnlockUnavailable) { try store.save([:]) }
    }
}

extension VaultAgentAuthorizationPolicyTests {
    @Test("matching requests deduplicate while changed identities fail immediately")
    func requestDeduplicationAndIdentityIsolation() async throws {
        let harness = try CoordinatorHarness()
        let firstIdentity = VaultAgentPeerIdentity.testValue(client: .codex, helperCDHash: Data([0x01]))
        let upgradedIdentity = VaultAgentPeerIdentity.testValue(client: .codex, helperCDHash: Data([0x02]))
        async let first = harness.request(firstIdentity)
        async let upgraded = harness.request(upgradedIdentity)
        try await waitUntil { harness.authenticator.callCount == 1 }
        let changed = await harness.request(.testValue(client: .codex, helperPath: "/tmp/changed"))
        #expect(changed == .failure(.authorizationRequired))
        harness.authenticator.completeAll(.success(()))

        let (firstResult, upgradedResult) = await (first, upgraded)
        #expect(firstResult == upgradedResult)
        #expect(firstResult.isSuccess)
        #expect(harness.authenticator.callCount == 1)
    }

    @Test("Codex Claude and CLI keep independent pending authentication")
    func clientsHaveIndependentPendingState() async throws {
        let harness = try CoordinatorHarness()
        async let codex = harness.request(.testValue(client: .codex))
        async let claude = harness.request(.testValue(client: .claude))
        async let cli = harness.request(.testValue(client: .cli))
        try await waitUntil { harness.authenticator.callCount == 3 }
        harness.authenticator.completeAll(.success(()))

        _ = await (codex, claude, cli)
        #expect(harness.policy.validGrantCount(at: harness.now()) == 3)
    }

    @Test(
        "automatic cancellation cools down while preferences can retry",
        arguments: [LAError.Code.userCancel, .systemCancel, .appCancel]
    )
    func cancellationCooldown(code: LAError.Code) async throws {
        let harness = try CoordinatorHarness()
        harness.authenticator.automaticResult = .failure(LAError(code))
        let identity = VaultAgentPeerIdentity.testValue(client: .claude)

        #expect(await harness.request(identity) == .failure(.authorizationRequired))
        #expect(harness.authenticator.callCount == 1)
        #expect(harness.defaults.object(forKey: harness.cooldownKey(.claude)) as? Date == harness.now().addingTimeInterval(24 * 60 * 60))

        #expect(await harness.request(identity) == .failure(.authorizationRequired))
        #expect(harness.authenticator.callCount == 1)

        harness.authenticator.automaticResult = .success(())
        #expect(await harness.request(identity, trigger: .explicitPreferencesAction).isSuccess)
        #expect(harness.authenticator.callCount == 2)
        #expect(harness.defaults.object(forKey: harness.cooldownKey(.claude)) == nil)
    }

    @Test("authentication or persistence failure creates no grant")
    func failuresCreateNoGrant() async throws {
        let harness = try CoordinatorHarness()
        let identity = VaultAgentPeerIdentity.testValue(client: .cli)
        harness.authenticator.automaticResult = .failure(LAError(.authenticationFailed))
        #expect(await harness.request(identity) == .failure(.authorizationRequired))
        #expect(harness.policy.decision(for: identity, at: harness.now()) == .missing)

        harness.authenticator.automaticResult = .success(())
        harness.store.saveError = VaultAgentErrorCode.automationUnlockUnavailable
        let cooldown = harness.now().addingTimeInterval(60)
        harness.defaults.set(cooldown, forKey: harness.cooldownKey(.cli))
        #expect(await harness.request(
            identity,
            trigger: .explicitPreferencesAction
        ) == .failure(.automationUnlockUnavailable))
        #expect(harness.policy.decision(for: identity, at: harness.now()) == .missing)
        #expect(harness.defaults.object(forKey: harness.cooldownKey(.cli)) as? Date == cooldown)
    }

    @Test("completion is delivered on the main queue")
    func completionUsesMainQueue() async throws {
        let harness = try CoordinatorHarness()
        harness.authenticator.automaticResult = .success(())

        let isMain = await withCheckedContinuation { continuation in
            harness.coordinator.authorize(
                identity: .testValue(client: .codex),
                trigger: .automaticFirstRequest
            ) { _ in continuation.resume(returning: Thread.isMainThread) }
        }
        #expect(isMain)
    }
}

private final class InMemoryVaultAgentGrantStore: VaultAgentGrantStoring {
    var grants: [VaultAgentClientKind: VaultAgentGrant] = [:]
    var loadError: Error?
    var saveError: Error?

    func load() throws -> [VaultAgentClientKind: VaultAgentGrant] {
        if let loadError { throw loadError }
        return grants
    }

    func save(_ grants: [VaultAgentClientKind: VaultAgentGrant]) throws {
        if let saveError { throw saveError }
        self.grants = grants
    }
}

private extension VaultAgentPeerIdentity {
    static func testValue(
        client: VaultAgentClientKind,
        helperCDHash: Data? = Data([0x01]),
        helperIsAdHoc: Bool = false,
        helperPath: String = "/Applications/Pastera.app/Contents/MacOS/pastera-agent-helper"
    ) -> VaultAgentPeerIdentity {
        VaultAgentPeerIdentity(
            client: client,
            helperRequirement: "identifier com.pastera.agent-helper",
            helperCDHash: helperCDHash,
            helperIsAdHoc: helperIsAdHoc,
            helperPath: helperPath,
            hostRequirement: nil,
            hostCDHash: nil,
            hostIsAdHoc: nil,
            hostPath: nil
        )
    }

    static func adHocWithHost(client: VaultAgentClientKind, hash: Data?) -> VaultAgentPeerIdentity {
        VaultAgentPeerIdentity(
            client: client,
            helperRequirement: "identifier com.pastera.agent-helper",
            helperCDHash: hash,
            helperIsAdHoc: true,
            helperPath: "/Applications/Pastera.app/Contents/MacOS/pastera-agent-helper",
            hostRequirement: "identifier com.example.host",
            hostCDHash: hash,
            hostIsAdHoc: true,
            hostPath: "/Applications/Host.app/Contents/MacOS/Host"
        )
    }
}

private extension VaultAgentGrant {
    static func testValue(client: VaultAgentClientKind) -> VaultAgentGrant {
        let start = Date(timeIntervalSince1970: 90_000)
        return VaultAgentGrant(
            identity: .testValue(client: client),
            authenticatedAt: start,
            idleExpiresAt: start.addingTimeInterval(VaultAgentAuthorizationPolicy.idleLifetime),
            hardExpiresAt: start.addingTimeInterval(VaultAgentAuthorizationPolicy.hardLifetime),
            lastSensitiveUseAt: nil,
            revokedAt: nil
        )
    }
}

private final class VaultAgentKeychainProbe: VaultAgentKeychainAccessing {
    var copyStatus = errSecSuccess
    var copyData: Data?
    var updateStatus = errSecSuccess
    var addStatus = errSecSuccess
    var copyQuery: [String: Any]?
    var updateQuery: [String: Any]?
    var updateAttributes: [String: Any]?
    var addQuery: [String: Any]?

    func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?) {
        copyQuery = query
        return (copyStatus, copyData)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        updateQuery = query
        updateAttributes = attributes
        return updateStatus
    }

    func add(_ query: [String: Any]) -> OSStatus {
        addQuery = query
        return addStatus
    }
}

private final class VaultAgentAuthenticatorProbe: VaultAgentIdentityAuthenticating {
    private let lock = NSLock()
    private var completions: [(Result<Void, Error>) -> Void] = []
    var automaticResult: Result<Void, Error>?

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return completions.count
    }

    func authenticate(completion: @escaping (Result<Void, Error>) -> Void) {
        lock.lock()
        completions.append(completion)
        let result = automaticResult
        lock.unlock()
        if let result { completion(result) }
    }

    func completeAll(_ result: Result<Void, Error>) {
        lock.lock()
        let current = completions
        lock.unlock()
        current.forEach { $0(result) }
    }
}

private final class CoordinatorHarness {
    let store = InMemoryVaultAgentGrantStore()
    let policy: VaultAgentAuthorizationPolicy
    let authenticator = VaultAgentAuthenticatorProbe()
    let defaults: UserDefaults
    let defaultsSuiteName: String
    let now = { Date(timeIntervalSince1970: 100_000) }
    let coordinator: VaultAgentAuthorizationCoordinator

    init() throws {
        policy = try VaultAgentAuthorizationPolicy(store: store)
        defaultsSuiteName = "VaultAgentAuthorizationTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: defaultsSuiteName))
        coordinator = VaultAgentAuthorizationCoordinator(
            policy: policy,
            authenticator: authenticator,
            defaults: defaults,
            now: now
        )
    }

    deinit { defaults.removePersistentDomain(forName: defaultsSuiteName) }

    func request(
        _ identity: VaultAgentPeerIdentity,
        trigger: VaultAgentAuthorizationCoordinator.Trigger = .automaticFirstRequest
    ) async -> Result<VaultAgentGrant, VaultAgentErrorCode> {
        await withCheckedContinuation { continuation in
            coordinator.authorize(identity: identity, trigger: trigger) {
                continuation.resume(returning: $0)
            }
        }
    }

    func cooldownKey(_ client: VaultAgentClientKind) -> String {
        "Pastera.Agent.AuthorizationCooldownUntil.v1.\(client.rawValue)"
    }
}

private extension Result where Success == VaultAgentGrant, Failure == VaultAgentErrorCode {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

private func waitUntil(
    _ condition: @escaping () -> Bool
) async throws {
    for _ in 0..<1_000 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(1))
    }
    throw VaultAgentErrorCode.brokerUnavailable
}
