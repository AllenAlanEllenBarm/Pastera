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
        let policy = try VaultAgentAuthorizationPolicy(store: store, executor: .testValue())
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
        let policy = try VaultAgentAuthorizationPolicy(store: store, executor: .testValue())
        let identity = VaultAgentPeerIdentity.testValue(client: .claude)
        try policy.authorize(identity: identity, authenticatedAt: start)
        let original = try #require(store.grants[.claude])

        _ = policy.decision(for: identity, at: start.addingTimeInterval(60))
        policy.recordFailure(for: identity, at: start.addingTimeInterval(120))

        #expect(store.grants[.claude] == original)
        #expect(store.grants[.codex] == nil)
    }

    @Test("grant snapshot is a serialized read without exposing other clients")
    func grantSnapshotIsClientScoped() throws {
        let start = Date(timeIntervalSince1970: 25_000)
        let store = InMemoryVaultAgentGrantStore()
        let policy = try VaultAgentAuthorizationPolicy(store: store, executor: .testValue())
        let codex = VaultAgentPeerIdentity.testValue(client: .codex)
        let claude = VaultAgentPeerIdentity.testValue(client: .claude)
        let codexGrant = try policy.authorize(identity: codex, authenticatedAt: start)
        _ = try policy.authorize(identity: claude, authenticatedAt: start.addingTimeInterval(1))

        #expect(policy.grantSnapshot(for: .codex) == codexGrant)
        #expect(policy.grantSnapshot(for: .cli) == nil)
    }

    @Test("idle and hard expiry boundaries are exclusive")
    func expiryBoundaries() throws {
        let start = Date(timeIntervalSince1970: 30_000)
        let store = InMemoryVaultAgentGrantStore()
        let policy = try VaultAgentAuthorizationPolicy(store: store, executor: .testValue())
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
        let policy = try VaultAgentAuthorizationPolicy(store: store, executor: .testValue())
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
        let policy = try VaultAgentAuthorizationPolicy(store: store, executor: .testValue())
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
        let policy = try VaultAgentAuthorizationPolicy(store: store, executor: .testValue())
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
        let policy = try VaultAgentAuthorizationPolicy(store: store, executor: .testValue())
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
        let policy = try VaultAgentAuthorizationPolicy(store: store, executor: .testValue())
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
            try VaultAgentAuthorizationPolicy(store: store, executor: .testValue())
        }
    }

    @Test("invalid identity tuples never create grants")
    func invalidIdentityTuplesAreRejected() throws {
        let invalidIdentities = [
            VaultAgentPeerIdentity.withHost(client: .codex, helperRequirement: ""),
            VaultAgentPeerIdentity.withHost(client: .codex, helperPath: ""),
            VaultAgentPeerIdentity.withHost(client: .codex, helperCDHash: nil, helperIsAdHoc: true),
            VaultAgentPeerIdentity.withoutHost(client: .codex),
            VaultAgentPeerIdentity.withHost(client: .codex, hostRequirement: nil),
            VaultAgentPeerIdentity.withHost(client: .codex, hostRequirement: ""),
            VaultAgentPeerIdentity.withHost(client: .claude, hostPath: nil),
            VaultAgentPeerIdentity.withHost(client: .claude, hostPath: ""),
            VaultAgentPeerIdentity.withHost(client: .claude, hostIsAdHoc: nil),
            VaultAgentPeerIdentity.withHost(client: .claude, hostCDHash: nil, hostIsAdHoc: true),
            VaultAgentPeerIdentity.withHost(client: .cli),
            VaultAgentPeerIdentity.withHost(client: .cli, hostRequirement: nil)
        ]

        for identity in invalidIdentities {
            let store = InMemoryVaultAgentGrantStore()
            let policy = try VaultAgentAuthorizationPolicy(store: store, executor: .testValue())
            #expect(throws: VaultAgentErrorCode.authorizationRequired) {
                try policy.authorize(identity: identity, authenticatedAt: Date(timeIntervalSince1970: 80_000))
            }
            #expect(store.grants.isEmpty)
            #expect(!VaultAgentAuthorizationPolicy.identitiesMatch(identity, identity))
        }
    }

    @Test("host identity changes are rejected while CLI without host is legal")
    func hostIdentityIntegrity() throws {
        let start = Date(timeIntervalSince1970: 81_000)
        let store = InMemoryVaultAgentGrantStore()
        let policy = try VaultAgentAuthorizationPolicy(store: store, executor: .testValue())
        let formal = VaultAgentPeerIdentity.withHost(client: .codex)
        let grant = try policy.authorize(identity: formal, authenticatedAt: start)

        #expect(policy.decision(for: .withHost(client: .codex, hostRequirement: "identifier changed"), at: start) == .identityChanged)
        #expect(policy.decision(for: .withHost(client: .codex, hostPath: "/tmp/Host"), at: start) == .identityChanged)
        #expect(policy.decision(for: .withHost(client: .codex, hostIsAdHoc: true), at: start) == .identityChanged)
        #expect(policy.decision(for: .withHost(client: .codex, hostCDHash: Data([0x99])), at: start) == .allowed(grant))

        let adHoc = VaultAgentPeerIdentity.withHost(
            client: .claude,
            hostCDHash: Data([0x20]),
            hostIsAdHoc: true
        )
        try policy.authorize(identity: adHoc, authenticatedAt: start)
        #expect(policy.decision(for: .withHost(
            client: .claude,
            hostCDHash: Data([0x21]),
            hostIsAdHoc: true
        ), at: start) == .identityChanged)

        let cli = VaultAgentPeerIdentity.testValue(client: .cli)
        #expect(try policy.authorize(identity: cli, authenticatedAt: start).identity == cli)
    }
}

extension VaultAgentAuthorizationPolicyTests {
    @Test("not found loads empty grants with the exact non-sync query")
    func notFoundLoadsEmpty() throws {
        let keychain = VaultAgentKeychainProbe()
        keychain.copyStatus = errSecItemNotFound
        let store = VaultAgentGrantStore(keychain: keychain, usesDataProtectionKeychain: true)

        #expect(try store.load().isEmpty)
        let query = try #require(keychain.copyQuery)
        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String == "com.pastera-app.Pastera.agent-grants.v1")
        #expect(query[kSecAttrAccount as String] as? String == "grants")
        #expect(query[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
        #expect(query[kSecReturnData as String] as? Bool == true)
        #expect(query[kSecMatchLimit as String] as? String == kSecMatchLimitOne as String)
    }

    @Test("save updates one object or adds a device-only item")
    func saveUsesAtomicObject() throws {
        let keychain = VaultAgentKeychainProbe()
        keychain.updateStatus = errSecItemNotFound
        keychain.addStatus = errSecSuccess
        let store = VaultAgentGrantStore(keychain: keychain, usesDataProtectionKeychain: true)
        let grant = VaultAgentGrant.testValue(client: .codex)

        try store.save([.codex: grant])

        let update = try #require(keychain.updateQuery)
        #expect(update[kSecAttrService as String] as? String == "com.pastera-app.Pastera.agent-grants.v1")
        #expect(update[kSecUseDataProtectionKeychain as String] as? Bool == true)
        let add = try #require(keychain.addQuery)
        #expect(add[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        #expect(add[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(add[kSecUseDataProtectionKeychain as String] as? Bool == true)
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

    @Test("ad-hoc builds omit the unavailable Data Protection Keychain selector")
    func adHocBuildUsesLegacyKeychain() throws {
        let keychain = VaultAgentKeychainProbe()
        keychain.copyStatus = errSecItemNotFound
        let store = VaultAgentGrantStore(keychain: keychain, usesDataProtectionKeychain: false)

        #expect(try store.load().isEmpty)
        #expect(keychain.copyQuery?[kSecUseDataProtectionKeychain as String] == nil)
    }

    @Test("Data Protection Keychain requires an application access-group entitlement")
    func dataProtectionEligibility() {
        #expect(!VaultAgentKeychainBackend.isEligible(
            applicationIdentifier: nil,
            keychainAccessGroups: nil
        ))
        #expect(!VaultAgentKeychainBackend.isEligible(
            applicationIdentifier: "",
            keychainAccessGroups: [""]
        ))
        #expect(VaultAgentKeychainBackend.isEligible(
            applicationIdentifier: "BBCHAJ584H.com.pastera-app.Pastera",
            keychainAccessGroups: nil
        ))
        #expect(VaultAgentKeychainBackend.isEligible(
            applicationIdentifier: nil,
            keychainAccessGroups: ["BBCHAJ584H.com.pastera-app.Pastera"]
        ))
    }
}

extension VaultAgentAuthorizationPolicyTests {
    @Test("installed policy revocation updates live and durable grants without building a fallback")
    func installedPolicyRevocationUsesLivePolicy() throws {
        let now = Date(timeIntervalSince1970: 102_000)
        let store = InMemoryVaultAgentGrantStore()
        let executor = VaultAgentSerialExecutor.testValue()
        let policy = try VaultAgentAuthorizationPolicy(store: store, executor: executor)
        let identity = VaultAgentPeerIdentity.testValue(client: .codex)
        _ = try policy.authorize(identity: identity, authenticatedAt: now)
        var fallbackBuildCount = 0
        let resetCoordinator = VaultAgentAuthorizationResetCoordinator(
            executor: executor,
            storeFactory: {
                fallbackBuildCount += 1
                return store
            },
            now: { now.addingTimeInterval(1) }
        )
        try resetCoordinator.install(policy)

        try resetCoordinator.revokeAll()

        #expect(policy.decision(for: identity, at: now.addingTimeInterval(1)) == .revoked)
        #expect(store.grants[.codex]?.revokedAt == now.addingTimeInterval(1))
        #expect(fallbackBuildCount == 0)
    }

    @Test("uninstalled policy revocation rebuilds from durable grants on the shared executor")
    func uninstalledPolicyRevocationUsesDurableFallback() throws {
        let now = Date(timeIntervalSince1970: 103_000)
        let store = InMemoryVaultAgentGrantStore()
        let executor = VaultAgentSerialExecutor.testValue()
        let policy = try VaultAgentAuthorizationPolicy(store: store, executor: executor)
        let identity = VaultAgentPeerIdentity.testValue(client: .claude)
        _ = try policy.authorize(identity: identity, authenticatedAt: now)
        var fallbackBuildCount = 0
        let resetCoordinator = VaultAgentAuthorizationResetCoordinator(
            executor: executor,
            storeFactory: {
                fallbackBuildCount += 1
                return store
            },
            now: { now.addingTimeInterval(2) }
        )
        try resetCoordinator.install(policy)
        resetCoordinator.uninstall(policy)

        try executor.sync { try resetCoordinator.revokeAll() }

        let laterPolicy = try VaultAgentAuthorizationPolicy(store: store, executor: executor)
        #expect(laterPolicy.decision(for: identity, at: now.addingTimeInterval(2)) == .revoked)
        #expect(store.grants[.claude]?.revokedAt == now.addingTimeInterval(2))
        #expect(fallbackBuildCount == 1)
    }

    @Test("fallback persistence failure is propagated")
    func fallbackRevocationFailureIsPropagated() throws {
        let now = Date(timeIntervalSince1970: 104_000)
        let store = InMemoryVaultAgentGrantStore()
        store.grants[.cli] = VaultAgentGrant.testValue(client: .cli)
        store.saveError = VaultAgentErrorCode.automationUnlockUnavailable
        let resetCoordinator = VaultAgentAuthorizationResetCoordinator(
            executor: .testValue(),
            storeFactory: { store },
            now: { now }
        )

        #expect(throws: VaultAgentErrorCode.automationUnlockUnavailable) {
            try resetCoordinator.revokeAll()
        }
        #expect(store.grants[.cli]?.revokedAt == nil)
    }

    @Test("application runtime registers reset policy before socket traffic and unregisters on stop")
    func applicationRuntimeOwnsResetPolicyLifecycle() async throws {
        let now = Date(timeIntervalSince1970: 105_000)
        let store = InMemoryVaultAgentGrantStore()
        let executor = VaultAgentSerialExecutor.testValue()
        let policy = try VaultAgentAuthorizationPolicy(store: store, executor: executor)
        var fallbackBuildCount = 0
        let events = AgentResetEventRecorder()
        let resetCoordinator = VaultAgentAuthorizationResetCoordinator(
            executor: executor,
            storeFactory: {
                fallbackBuildCount += 1
                return store
            },
            now: { now }
        )
        let runtime = VaultAgentApplicationRuntime(
            startupSeed: { events.append("seed") },
            preferenceRuntime: UnavailableVaultAgentPreferenceRuntime(),
            socketStart: {
                events.append("socketStart")
                try resetCoordinator.revokeAll()
            },
            socketStop: { events.append("socketStop") },
            trackerStart: { events.append("trackerStart") },
            trackerStop: { events.append("trackerStop") },
            removeTickets: { events.append("removeTickets") },
            authorizationResetCoordinator: resetCoordinator,
            authorizationPolicy: policy,
            worker: DispatchQueue(label: "VaultAgentAuthorizationResetCoordinatorTests.runtime")
        )

        runtime.start()
        try await waitUntil { events.values.contains("socketStart") }
        #expect(Array(events.values.prefix(3)) == ["seed", "trackerStart", "socketStart"])
        #expect(fallbackBuildCount == 0)

        runtime.stop()
        try resetCoordinator.revokeAll()

        #expect(fallbackBuildCount == 1)
    }

    @Test("runtime reloads a stale policy after fallback revocation before socket traffic")
    func runtimeReloadsRevocationBeforeSocketStart() async throws {
        let now = Date(timeIntervalSince1970: 105_500)
        let identity = VaultAgentPeerIdentity.testValue(client: .codex)
        let store = InMemoryVaultAgentGrantStore()
        store.grants[.codex] = VaultAgentGrant.testValue(client: .codex)
        let executor = VaultAgentSerialExecutor.testValue()
        let policy = try VaultAgentAuthorizationPolicy(store: store, executor: executor)
        var fallbackBuildCount = 0
        let events = AgentResetEventRecorder()
        let resetCoordinator = VaultAgentAuthorizationResetCoordinator(
            executor: executor,
            storeFactory: {
                fallbackBuildCount += 1
                return store
            },
            now: { now }
        )

        try resetCoordinator.revokeAll()
        #expect(policy.decision(for: identity, at: now) != .revoked)

        let runtime = VaultAgentApplicationRuntime(
            startupSeed: { events.append("seed") },
            preferenceRuntime: UnavailableVaultAgentPreferenceRuntime(),
            socketStart: {
                switch policy.decision(for: identity, at: now) {
                case .revoked: events.append("socketSawRevoked")
                default: events.append("socketSawStaleGrant")
                }
                try resetCoordinator.revokeAll()
            },
            socketStop: { events.append("socketStop") },
            trackerStart: { events.append("trackerStart") },
            trackerStop: { events.append("trackerStop") },
            removeTickets: { events.append("removeTickets") },
            authorizationResetCoordinator: resetCoordinator,
            authorizationPolicy: policy,
            worker: DispatchQueue(label: "VaultAgentAuthorizationResetCoordinatorTests.stale-runtime")
        )

        runtime.start()
        try await waitUntil {
            events.values.contains("socketSawRevoked") || events.values.contains("socketSawStaleGrant")
        }
        defer { runtime.stop() }

        #expect(Array(events.values.prefix(3)) == ["seed", "trackerStart", "socketSawRevoked"])
        #expect(fallbackBuildCount == 1)
        #expect(store.grants[.codex]?.revokedAt == now)
    }

    @Test("runtime installs a reloaded policy before seed can persist stale grants")
    func runtimeInstallsReloadedPolicyBeforeStaleSeed() async throws {
        let now = Date(timeIntervalSince1970: 105_750)
        let codexIdentity = VaultAgentPeerIdentity.testValue(client: .codex)
        let claudeIdentity = VaultAgentPeerIdentity.testValue(client: .claude)
        let store = InMemoryVaultAgentGrantStore()
        store.grants = [
            .codex: VaultAgentGrant.testValue(client: .codex),
            .claude: VaultAgentGrant.testValue(client: .claude)
        ]
        let executor = VaultAgentSerialExecutor.testValue()
        let policy = try VaultAgentAuthorizationPolicy(store: store, executor: executor)
        var fallbackBuildCount = 0
        let resetCoordinator = VaultAgentAuthorizationResetCoordinator(
            executor: executor,
            storeFactory: {
                fallbackBuildCount += 1
                return store
            },
            now: { now }
        )

        try resetCoordinator.revokeAll()
        #expect(policy.decision(for: codexIdentity, at: now) != .revoked)
        #expect(policy.decision(for: claudeIdentity, at: now) != .revoked)

        let events = AgentResetEventRecorder()
        let runtime = VaultAgentApplicationRuntime(
            startupSeed: {
                try policy.revoke(.codex, at: now.addingTimeInterval(1))
                events.append("seed")
            },
            preferenceRuntime: UnavailableVaultAgentPreferenceRuntime(),
            socketStart: {
                events.append(policy.decision(for: codexIdentity, at: now) == .revoked
                    ? "socketSawCodexRevoked"
                    : "socketSawCodexAllowed")
                events.append(policy.decision(for: claudeIdentity, at: now) == .revoked
                    ? "socketSawClaudeRevoked"
                    : "socketSawClaudeAllowed")
                events.append(store.grants[.claude]?.revokedAt == now
                    ? "durableClaudeRevoked"
                    : "durableClaudeResurrected")
            },
            socketStop: { events.append("socketStop") },
            trackerStart: { events.append("trackerStart") },
            trackerStop: { events.append("trackerStop") },
            removeTickets: { events.append("removeTickets") },
            authorizationResetCoordinator: resetCoordinator,
            authorizationPolicy: policy,
            worker: DispatchQueue(label: "VaultAgentAuthorizationResetCoordinatorTests.seed-race")
        )

        runtime.start()
        try await waitUntil {
            events.values.contains("durableClaudeRevoked")
                || events.values.contains("durableClaudeResurrected")
        }
        defer { runtime.stop() }

        #expect(Array(events.values.prefix(5)) == [
            "seed",
            "trackerStart",
            "socketSawCodexRevoked",
            "socketSawClaudeRevoked",
            "durableClaudeRevoked"
        ])
        #expect(fallbackBuildCount == 1)
    }

    @Test("stopping during seed defers policy uninstall until preparation exits")
    func stopDuringSeedDefersPolicyUninstall() async throws {
        let now = Date(timeIntervalSince1970: 105_875)
        let store = InMemoryVaultAgentGrantStore()
        store.grants[.codex] = VaultAgentGrant.testValue(client: .codex)
        let executor = VaultAgentSerialExecutor.testValue()
        let policy = try VaultAgentAuthorizationPolicy(store: store, executor: executor)
        let events = AgentResetEventRecorder()
        var fallbackBuildCount = 0
        let resetCoordinator = VaultAgentAuthorizationResetCoordinator(
            executor: executor,
            storeFactory: {
                fallbackBuildCount += 1
                events.append("fallbackBuilt")
                return store
            },
            now: { now }
        )
        let seedStarted = DispatchSemaphore(value: 0)
        let releaseSeed = DispatchSemaphore(value: 0)
        let runtime = VaultAgentApplicationRuntime(
            startupSeed: {
                seedStarted.signal()
                releaseSeed.wait()
                events.append("seedFinished")
            },
            preferenceRuntime: UnavailableVaultAgentPreferenceRuntime(),
            socketStart: { events.append("socketStart") },
            socketStop: { events.append("socketStop") },
            trackerStart: { events.append("trackerStart") },
            trackerStop: { events.append("trackerStop") },
            removeTickets: { events.append("removeTickets") },
            authorizationResetCoordinator: resetCoordinator,
            authorizationPolicy: policy,
            worker: DispatchQueue(label: "VaultAgentAuthorizationResetCoordinatorTests.stop-during-seed")
        )

        runtime.start()
        #expect(seedStarted.wait(timeout: .now() + 1) == .success)
        runtime.stop()
        try resetCoordinator.revokeAll()
        #expect(!events.values.contains("fallbackBuilt"))

        releaseSeed.signal()
        try await waitUntil {
            if events.values.contains("fallbackBuilt") { return true }
            try? resetCoordinator.revokeAll()
            return events.values.contains("fallbackBuilt")
        }

        #expect(fallbackBuildCount == 1)
        #expect(!events.values.contains("trackerStart"))
        #expect(!events.values.contains("socketStart"))
    }

    @Test("runtime reload failure prevents tracker and socket startup")
    func runtimeReloadFailureFailsClosed() async throws {
        let store = InMemoryVaultAgentGrantStore()
        let executor = VaultAgentSerialExecutor.testValue()
        let policy = try VaultAgentAuthorizationPolicy(store: store, executor: executor)
        store.loadError = VaultAgentErrorCode.automationUnlockUnavailable
        let resetCoordinator = VaultAgentAuthorizationResetCoordinator(
            executor: executor,
            storeFactory: { store }
        )
        let events = AgentResetEventRecorder()
        let runtime = VaultAgentApplicationRuntime(
            startupSeed: { events.append("seed") },
            preferenceRuntime: UnavailableVaultAgentPreferenceRuntime(),
            socketStart: { events.append("socketStart") },
            socketStop: { events.append("socketStop") },
            trackerStart: { events.append("trackerStart") },
            trackerStop: { events.append("trackerStop") },
            removeTickets: { events.append("removeTickets") },
            authorizationResetCoordinator: resetCoordinator,
            authorizationPolicy: policy,
            worker: DispatchQueue(label: "VaultAgentAuthorizationResetCoordinatorTests.reload-failure")
        )

        runtime.start()
        try await waitUntil {
            events.values.contains("socketStart") || events.values.contains("removeTickets")
        }

        #expect(!events.values.contains("trackerStart"))
        #expect(!events.values.contains("socketStart"))
        #expect(events.values.contains("removeTickets"))
    }

    @Test("socket startup failure unregisters the policy for durable fallback")
    func socketStartupFailureUninstallsPolicy() async throws {
        let store = InMemoryVaultAgentGrantStore()
        let executor = VaultAgentSerialExecutor.testValue()
        let policy = try VaultAgentAuthorizationPolicy(store: store, executor: executor)
        var fallbackBuildCount = 0
        let events = AgentResetEventRecorder()
        let resetCoordinator = VaultAgentAuthorizationResetCoordinator(
            executor: executor,
            storeFactory: {
                fallbackBuildCount += 1
                events.append("fallbackBuilt")
                return store
            }
        )
        let runtime = VaultAgentApplicationRuntime(
            startupSeed: { events.append("seed") },
            preferenceRuntime: UnavailableVaultAgentPreferenceRuntime(),
            socketStart: {
                events.append("socketStart")
                throw VaultAgentErrorCode.invalidRequest
            },
            socketStop: { events.append("socketStop") },
            trackerStart: { events.append("trackerStart") },
            trackerStop: { events.append("trackerStop") },
            removeTickets: { events.append("removeTickets") },
            authorizationResetCoordinator: resetCoordinator,
            authorizationPolicy: policy,
            worker: DispatchQueue(label: "VaultAgentAuthorizationResetCoordinatorTests.socket-failure")
        )

        runtime.start()
        try await waitUntil { events.values.contains("socketStart") }
        try await waitUntil {
            try? resetCoordinator.revokeAll()
            return events.values.contains("fallbackBuilt")
        }

        #expect(fallbackBuildCount == 1)
    }

    @Test("fallback policy load failure is propagated before any save")
    func fallbackLoadFailureIsPropagated() {
        let store = InMemoryVaultAgentGrantStore()
        store.loadError = VaultAgentErrorCode.automationUnlockUnavailable
        let resetCoordinator = VaultAgentAuthorizationResetCoordinator(
            executor: .testValue(),
            storeFactory: { store }
        )

        #expect(throws: VaultAgentErrorCode.automationUnlockUnavailable) {
            try resetCoordinator.revokeAll()
        }
        #expect(store.saveCallCount == 0)
    }

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

    @Test("invalid identity is rejected before authentication")
    func invalidIdentitySkipsAuthentication() async throws {
        let harness = try CoordinatorHarness()
        harness.authenticator.automaticResult = .success(())

        #expect(await harness.request(.withoutHost(client: .codex)) == .failure(.authorizationRequired))
        #expect(harness.authenticator.callCount == 0)
        #expect(harness.policy.validGrantCount(at: harness.now()) == 0)
    }

    @Test("in-flight authentication retains coordinator and completes exactly once")
    func inFlightAuthenticationRetainsCoordinator() async throws {
        let store = InMemoryVaultAgentGrantStore()
        let executor = VaultAgentSerialExecutor.testValue()
        let policy = try VaultAgentAuthorizationPolicy(store: store, executor: executor)
        let authenticator = VaultAgentAuthenticatorProbe()
        let suiteName = "VaultAgentAuthorizationLifecycleTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let identity = VaultAgentPeerIdentity.testValue(client: .codex)
        let results = AuthorizationResultProbe()
        var coordinator: VaultAgentAuthorizationCoordinator? = VaultAgentAuthorizationCoordinator(
            executor: executor,
            policy: policy,
            authenticator: authenticator,
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 100_000) }
        )

        coordinator?.authorize(identity: identity, trigger: .automaticFirstRequest) {
            results.append($0, isMainThread: Thread.isMainThread)
        }
        try await waitUntil { authenticator.callCount == 1 }
        coordinator = nil
        authenticator.completeAll(.success(()))
        try await waitUntil { results.count == 1 }
        authenticator.completeAll(.success(()))
        try await Task.sleep(for: .milliseconds(20))

        #expect(results.count == 1)
        #expect(results.allOnMainThread)
        #expect(results.first?.isSuccess == true)
        #expect(store.grants[.codex]?.identity == identity)
    }

    @Test("policy store access uses injected serial executor and supports reentry")
    func policyUsesInjectedExecutor() throws {
        let queue = DispatchQueue(label: "test.pastera.password-vault.store.probe")
        let key = DispatchSpecificKey<String>()
        queue.setSpecific(key: key, value: "vault-store")
        let executor = VaultAgentSerialExecutor(queue: queue)
        let store = ExecutorProbeGrantStore(key: key)
        let policy = try VaultAgentAuthorizationPolicy(store: store, executor: executor)
        let identity = VaultAgentPeerIdentity.testValue(client: .cli)

        _ = try executor.sync {
            try policy.authorize(identity: identity, authenticatedAt: Date(timeIntervalSince1970: 101_000))
        }

        #expect(store.events == [
            .init(operation: "load", queueValue: "vault-store", isMainThread: false),
            .init(operation: "save", queueValue: "vault-store", isMainThread: false)
        ])
    }
}

private final class AgentResetEventRecorder {
    private let lock = NSLock()
    private var storage = [String]()

    var values: [String] { lock.withLock { storage } }

    func append(_ value: String) {
        lock.withLock { storage.append(value) }
    }
}

private final class InMemoryVaultAgentGrantStore: VaultAgentGrantStoring {
    var grants: [VaultAgentClientKind: VaultAgentGrant] = [:]
    var loadError: Error?
    var saveError: Error?
    private(set) var saveCallCount = 0

    func load() throws -> [VaultAgentClientKind: VaultAgentGrant] {
        if let loadError { throw loadError }
        return grants
    }

    func save(_ grants: [VaultAgentClientKind: VaultAgentGrant]) throws {
        saveCallCount += 1
        if let saveError { throw saveError }
        self.grants = grants
    }
}

private final class ExecutorProbeGrantStore: VaultAgentGrantStoring {
    struct Event: Equatable {
        let operation: String
        let queueValue: String?
        let isMainThread: Bool
    }

    private let key: DispatchSpecificKey<String>
    private(set) var events: [Event] = []
    private var grants: [VaultAgentClientKind: VaultAgentGrant] = [:]

    init(key: DispatchSpecificKey<String>) {
        self.key = key
    }

    func load() -> [VaultAgentClientKind: VaultAgentGrant] {
        record("load")
        return grants
    }

    func save(_ grants: [VaultAgentClientKind: VaultAgentGrant]) {
        record("save")
        self.grants = grants
    }

    private func record(_ operation: String) {
        events.append(.init(
            operation: operation,
            queueValue: DispatchQueue.getSpecific(key: key),
            isMainThread: Thread.isMainThread
        ))
    }
}

private extension VaultAgentPeerIdentity {
    static func testValue(
        client: VaultAgentClientKind,
        helperCDHash: Data? = Data([0x01]),
        helperIsAdHoc: Bool = false,
        helperPath: String = "/Applications/Pastera.app/Contents/MacOS/pastera-agent-helper"
    ) -> VaultAgentPeerIdentity {
        if client != .cli {
            return withHost(
                client: client,
                helperCDHash: helperCDHash,
                helperIsAdHoc: helperIsAdHoc,
                helperPath: helperPath
            )
        }
        return withoutHost(
            client: client,
            helperCDHash: helperCDHash,
            helperIsAdHoc: helperIsAdHoc,
            helperPath: helperPath
        )
    }

    static func withoutHost(
        client: VaultAgentClientKind,
        helperRequirement: String = "identifier com.pastera.agent-helper",
        helperCDHash: Data? = Data([0x01]),
        helperIsAdHoc: Bool = false,
        helperPath: String = "/Applications/Pastera.app/Contents/MacOS/pastera-agent-helper"
    ) -> VaultAgentPeerIdentity {
        VaultAgentPeerIdentity(
            client: client,
            helperRequirement: helperRequirement,
            helperCDHash: helperCDHash,
            helperIsAdHoc: helperIsAdHoc,
            helperPath: helperPath,
            hostRequirement: nil,
            hostCDHash: nil,
            hostIsAdHoc: nil,
            hostPath: nil
        )
    }

    static func withHost(
        client: VaultAgentClientKind,
        helperRequirement: String = "identifier com.pastera.agent-helper",
        helperCDHash: Data? = Data([0x01]),
        helperIsAdHoc: Bool = false,
        helperPath: String = "/Applications/Pastera.app/Contents/MacOS/pastera-agent-helper",
        hostRequirement: String? = "identifier com.example.host",
        hostCDHash: Data? = Data([0x10]),
        hostIsAdHoc: Bool? = false,
        hostPath: String? = "/Applications/Host.app/Contents/MacOS/Host"
    ) -> VaultAgentPeerIdentity {
        VaultAgentPeerIdentity(
            client: client,
            helperRequirement: helperRequirement,
            helperCDHash: helperCDHash,
            helperIsAdHoc: helperIsAdHoc,
            helperPath: helperPath,
            hostRequirement: hostRequirement,
            hostCDHash: hostCDHash,
            hostIsAdHoc: hostIsAdHoc,
            hostPath: hostPath
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
    let executor = VaultAgentSerialExecutor.testValue()

    init() throws {
        policy = try VaultAgentAuthorizationPolicy(store: store, executor: executor)
        defaultsSuiteName = "VaultAgentAuthorizationTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: defaultsSuiteName))
        coordinator = VaultAgentAuthorizationCoordinator(
            executor: executor,
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

private extension VaultAgentSerialExecutor {
    static func testValue() -> VaultAgentSerialExecutor {
        VaultAgentSerialExecutor(queue: DispatchQueue(label: "test.pastera.password-vault.store"))
    }
}

private final class AuthorizationResultProbe {
    private let lock = NSLock()
    private var values: [Result<VaultAgentGrant, VaultAgentErrorCode>] = []
    private var mainThreadValues: [Bool] = []

    var count: Int {
        lock.withLock { values.count }
    }

    var first: Result<VaultAgentGrant, VaultAgentErrorCode>? {
        lock.withLock { values.first }
    }

    var allOnMainThread: Bool {
        lock.withLock { mainThreadValues.allSatisfy { $0 } }
    }

    func append(_ value: Result<VaultAgentGrant, VaultAgentErrorCode>, isMainThread: Bool) {
        lock.withLock {
            values.append(value)
            mainThreadValues.append(isMainThread)
        }
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
// swiftlint:disable:this file_length
