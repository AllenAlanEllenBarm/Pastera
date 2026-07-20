import AppKit
import Foundation
import LocalAuthentication
import PasteraAgentProtocol
import Testing
@testable import Pastera

@MainActor
@Suite("Agent integration preferences", .serialized)
struct AgentIntegrationPreferenceTests {
    @Test("agent integrations are searchable and expose independent client rows")
    func agentIntegrationPageIsRegistered() throws {
        let page = try #require(
            PasteraPreferenceCatalog.default.pages.first { $0.paneID == .agentIntegrations }
        )

        #expect(page.title == pasteraPreferenceString("Agent Integrations"))
        #expect(Set(page.searchItems.map(\.id)).isSuperset(of: [
            "agents.codex", "agents.claude", "agents.cli", "agents.authorization"
        ]))
    }

    @Test("authorized row shows authorization boundaries and exactly one primary action")
    func authorizedRowShowsBoundaries() throws {
        let start = Date(timeIntervalSince1970: 100_000)
        let runtime = AgentPreferenceRuntimeProbe(snapshot: .init(
            clients: [
                .codex: .init(
                    client: .codex,
                    hostDetected: true,
                    installed: true,
                    installationNeedsUpdate: false,
                    hostPathSummary: "/Applications/Codex.app",
                    authorization: .authorized,
                    idleExpiresAt: start.addingTimeInterval(60),
                    hardExpiresAt: start.addingTimeInterval(120),
                    lastSensitiveUseAt: start
                )
            ],
            claudePermission: .unavailable,
            audit: []
        ))
        let controller = CPYAgentIntegrationPreferenceViewController(runtime: runtime)

        controller.loadView()
        let row = try #require(controller.rowSnapshotForTesting(.codex))

        #expect(row.showsIdleExpiry)
        #expect(row.showsHardExpiry)
        #expect(row.showsLastSensitiveUse)
        #expect(row.primaryAction == .revoke)
        #expect(row.primaryActionCount == 1)
    }

    @Test("three clients share one compact group and fit the minimum pane width")
    func compactSharedGroupFitsMinimumWidth() throws {
        let runtime = AgentPreferenceRuntimeProbe(snapshot: .allUnavailable)
        let controller = CPYAgentIntegrationPreferenceViewController(runtime: runtime)

        controller.loadView()
        controller.view.frame = NSRect(x: 0, y: 0, width: 444, height: 600)
        controller.view.layoutSubtreeIfNeeded()

        #expect(controller.clientRowCountForTesting == 3)
        #expect(controller.clientGroupCountForTesting == 1)
        #expect(controller.maximumClientRowWidthForTesting <= 444)
        #expect(controller.primaryActionCenterYOffsetsForTesting.allSatisfy { abs($0) <= 2 })
    }

    @Test("Codex exposes host-managed approval text but no broad permission control")
    func codexHasNoBroadPermissionControl() {
        let controller = CPYAgentIntegrationPreferenceViewController(
            runtime: AgentPreferenceRuntimeProbe(snapshot: .allUnavailable)
        )

        controller.loadView()

        #expect(controller.codexApprovalManagedByHostForTesting)
        #expect(!controller.codexHasPermissionControlForTesting)
    }

    @Test("Claude sensitive permission requires confirmation and cancellation writes nothing")
    func sensitivePermissionRequiresConfirmation() async throws {
        let runtime = AgentPreferenceRuntimeProbe(snapshot: .allUnavailable)
        var confirmationCount = 0
        let controller = CPYAgentIntegrationPreferenceViewController(
            runtime: runtime,
            confirmSensitivePermission: {
                confirmationCount += 1
                return false
            }
        )
        controller.loadView()

        controller.applyClaudePermissionForTesting(.allCurrentPasteraTools)
        try await waitUntil { confirmationCount == 1 }

        #expect(runtime.actions.isEmpty)
        #expect(runtime.snippetScopes == [.allCurrentPasteraTools])
    }

    @Test("Claude metadata permission routes an exact three-tool scope")
    func metadataPermissionRoutesExactScope() async throws {
        let runtime = AgentPreferenceRuntimeProbe(snapshot: .allUnavailable)
        let controller = CPYAgentIntegrationPreferenceViewController(runtime: runtime)
        controller.loadView()

        controller.applyClaudePermissionForTesting(.metadataOnly)
        try await waitUntil { runtime.actions.count == 1 }

        #expect(runtime.actions == [.applyClaudePermission(.metadataOnly)])
        #expect(runtime.snippetScopes == [.metadataOnly])
    }

    @Test("audit summaries contain only action result and time")
    func auditSummaryIsRedacted() {
        let summary = VaultAgentPreferenceAuditSummary(
            action: .paste,
            result: .authorizationRequired,
            timestamp: Date(timeIntervalSince1970: 123)
        )
        let encoded = String(data: try! JSONEncoder().encode(summary), encoding: .utf8) ?? ""

        #expect(encoded.contains("paste"))
        #expect(!encoded.contains("entry"))
        #expect(!encoded.contains("query"))
        #expect(!encoded.contains("hash"))
        #expect(!encoded.contains("digest"))
    }

    @Test("coordinator runs prepare after one authentication and before writing the grant")
    func coordinatorRunsPrepareBeforeGrant() async throws {
        let store = AgentGrantStoreProbe()
        let executor = VaultAgentSerialExecutor(
            queue: DispatchQueue(label: "test.agent-preference.prepare")
        )
        let policy = try VaultAgentAuthorizationPolicy(store: store, executor: executor)
        let authenticator = AgentIdentityAuthenticatorProbe(result: .success(()))
        let coordinator = VaultAgentAuthorizationCoordinator(
            executor: executor,
            policy: policy,
            authenticator: authenticator,
            defaults: try #require(UserDefaults(suiteName: UUID().uuidString)),
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        let identity = VaultAgentPeerIdentity.preferenceTestValue(client: .cli)
        var prepareCount = 0

        let first = Task { await authorize(coordinator, identity: identity) { prepareCount += 1 } }
        let second = Task { await authorize(coordinator, identity: identity) { prepareCount += 1 } }
        let results = await [first.value, second.value]

        #expect(authenticator.callCount == 1)
        #expect(prepareCount == 1)
        #expect(results.allSatisfy { $0.isSuccess })
        #expect(store.grants[.cli]?.identity == identity)
    }

    @Test("prepare failure creates no grant")
    func prepareFailureCreatesNoGrant() async throws {
        let store = AgentGrantStoreProbe()
        let executor = VaultAgentSerialExecutor(
            queue: DispatchQueue(label: "test.agent-preference.prepare-failure")
        )
        let policy = try VaultAgentAuthorizationPolicy(store: store, executor: executor)
        let coordinator = VaultAgentAuthorizationCoordinator(
            executor: executor,
            policy: policy,
            authenticator: AgentIdentityAuthenticatorProbe(result: .success(())),
            defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
        )
        let identity = VaultAgentPeerIdentity.preferenceTestValue(client: .cli)

        let result = await authorize(coordinator, identity: identity) {
            throw PasswordVaultError.keychainUnavailable
        }

        #expect(result == .failure(.automationUnlockUnavailable))
        #expect(store.grants[.cli] == nil)
    }

    @Test("quick-key authentication bypasses the default local authentication action")
    func quickKeyAuthenticationBypassesDefaultAuthenticator() async throws {
        let store = AgentGrantStoreProbe()
        let executor = VaultAgentSerialExecutor(
            queue: DispatchQueue(label: "test.agent-preference.quick-key")
        )
        let policy = try VaultAgentAuthorizationPolicy(store: store, executor: executor)
        let defaultAuthenticator = AgentIdentityAuthenticatorProbe(
            result: .failure(LAError(.authenticationFailed))
        )
        let coordinator = VaultAgentAuthorizationCoordinator(
            executor: executor,
            policy: policy,
            authenticator: defaultAuthenticator,
            defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
        )
        let identity = VaultAgentPeerIdentity.preferenceTestValue(client: .cli)
        var quickKeyCount = 0

        let result = await withCheckedContinuation { continuation in
            coordinator.authorize(
                identity: identity,
                trigger: .explicitPreferencesAction,
                authentication: { callback in
                    quickKeyCount += 1
                    callback(.success(()))
                },
                prepare: {},
                completion: { continuation.resume(returning: $0) }
            )
        }

        #expect(result.isSuccess)
        #expect(quickKeyCount == 1)
        #expect(defaultAuthenticator.callCount == 0)
    }

    @Test("automatic first request is merged while status never prompts")
    func automaticFirstRequestIsMergedAndStatusDoesNotPrompt() async throws {
        let harness = try AutomaticAuthorizationRuntimeHarness()

        let first = await harness.call(.get(entryID: UUID()))
        let second = await harness.call(.get(entryID: UUID()))
        let status = await harness.call(.status)

        #expect(first == .authorizationRequired)
        #expect(second == .authorizationRequired)
        #expect(status == nil)
        #expect(harness.authenticator.callCount == 1)
        #expect(harness.vault.ensureReadyCount == 0)
    }
}

private final class AgentPreferenceRuntimeProbe: VaultAgentPreferenceRuntimeServicing {
    var snapshot: VaultAgentPreferenceSnapshot
    private(set) var actions: [VaultAgentPreferenceAction] = []
    private(set) var snippetScopes: [VaultAgentHostPermissionScope] = []

    init(snapshot: VaultAgentPreferenceSnapshot) {
        self.snapshot = snapshot
    }

    func loadSnapshot(completion: @escaping (Result<VaultAgentPreferenceSnapshot, Error>) -> Void) {
        completion(.success(snapshot))
    }

    func perform(
        _ action: VaultAgentPreferenceAction,
        completion: @escaping (Result<VaultAgentPreferenceSnapshot, Error>) -> Void
    ) {
        actions.append(action)
        completion(.success(snapshot))
    }

    func claudePermissionSnippet(
        scope: VaultAgentHostPermissionScope,
        completion: @escaping (Result<VaultAgentPermissionSnippet, Error>) -> Void
    ) {
        snippetScopes.append(scope)
        let tools = scope == .metadataOnly
            ? ["vault_status", "vault_search", "vault_get"]
            : ["vault_status", "vault_search", "vault_get", "vault_paste", "vault_prepare_exec"]
        completion(.success(.init(allowedTools: tools, serialized: "{}")))
    }
}

private final class AgentGrantStoreProbe: VaultAgentGrantStoring {
    var grants: [VaultAgentClientKind: VaultAgentGrant] = [:]

    func load() -> [VaultAgentClientKind: VaultAgentGrant] { grants }
    func save(_ grants: [VaultAgentClientKind: VaultAgentGrant]) { self.grants = grants }
}

private final class AgentIdentityAuthenticatorProbe: VaultAgentIdentityAuthenticating {
    private let result: Result<Void, Error>?
    private var completions: [(Result<Void, Error>) -> Void] = []
    private(set) var callCount = 0

    init(result: Result<Void, Error>?) {
        self.result = result
    }

    func authenticate(completion: @escaping (Result<Void, Error>) -> Void) {
        callCount += 1
        completions.append(completion)
        if let result { DispatchQueue.global().async { completion(result) } }
    }
}

private final class AutomaticAuthorizationRuntimeHarness {
    let authenticator = AgentIdentityAuthenticatorProbe(result: nil)
    let vault = AutomaticAuthorizationVaultProbe()
    private let runtime: VaultAgentRuntime
    private let identity = VaultAgentPeerIdentity.preferenceTestValue(client: .cli)

    init() throws {
        let executor = VaultAgentSerialExecutor(
            queue: DispatchQueue(label: "test.agent-preference.automatic")
        )
        let policy = try VaultAgentAuthorizationPolicy(
            store: AgentGrantStoreProbe(),
            executor: executor
        )
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let coordinator = VaultAgentAuthorizationCoordinator(
            executor: executor,
            policy: policy,
            authenticator: authenticator,
            defaults: defaults
        )
        runtime = try VaultAgentRuntime(
            executor: executor,
            authorizationPolicy: policy,
            authorizationCoordinator: coordinator,
            automaticAuthorizationPrepare: {},
            vault: vault,
            pasteTargetTracker: AutomaticAuthorizationTargetProbe(),
            ticketStore: VaultAgentTicketStore(commandBuilder: { _, _, _ in ["/usr/bin/false"] }),
            auditLogger: AutomaticAuthorizationAuditProbe(),
            cursorKey: Data(repeating: 1, count: 32)
        )
    }

    func call(_ operation: VaultAgentOperation) async -> VaultAgentErrorCode? {
        let request = VaultAgentRequestEnvelope(
            protocolVersion: VaultAgentLimits.protocolVersion,
            connectionID: UUID(),
            sequence: 1,
            requestID: UUID(),
            operation: operation
        )
        let data = try! JSONEncoder().encode(request)
        let responseData = await withCheckedContinuation { continuation in
            runtime.handle(identity: identity, request: data) { result in
                continuation.resume(returning: try! result.get())
            }
        }
        let response = try! JSONDecoder().decode(VaultAgentResponseEnvelope.self, from: responseData)
        guard case let .failure(failure) = response.body else { return nil }
        return failure.code
    }
}

private final class AutomaticAuthorizationVaultProbe: PasswordVaultAgentAccess {
    var agentVaultReady = true
    private(set) var ensureReadyCount = 0

    func ensureReadyForAgent(completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        ensureReadyCount += 1
        completion(.success(()))
    }

    func agentMetadata(
        completion: @escaping (Result<([PasswordVaultFolder], [PasswordVaultEntry]), PasswordVaultError>) -> Void
    ) { completion(.success(([], []))) }

    func agentPaste(
        entryID _: UUID,
        field _: VaultAgentSecretField,
        target _: PasteTargetContext,
        completion: @escaping (Result<Void, PasswordVaultError>) -> Void
    ) { completion(.success(())) }

    func agentCopy(
        entryID _: UUID,
        field _: VaultAgentSecretField,
        completion: @escaping (Result<Void, PasswordVaultError>) -> Void
    ) { completion(.success(())) }

    func agentSecret(
        entryID _: UUID,
        field _: VaultAgentSecretField,
        completion: @escaping (Result<Data, PasswordVaultError>) -> Void
    ) { completion(.success(Data())) }

    func disableAutomationUnlockForAgent() throws {}
}

private final class AutomaticAuthorizationTargetProbe: VaultAgentPasteTargetTracking {
    func resolve() throws -> PasteTargetContext {
        throw VaultAgentPasteTargetError.unavailable
    }
}

private final class AutomaticAuthorizationAuditProbe: VaultAgentAuditLogging {
    // swiftlint:disable:next function_parameter_count
    func record(
        client _: VaultAgentClientKind,
        action _: VaultAgentAuditAction,
        entryID _: UUID?,
        result _: VaultAgentErrorCode?,
        latencyBucket _: VaultAgentLatencyBucket,
        at _: Date
    ) {}
}

private extension VaultAgentPreferenceSnapshot {
    static let allUnavailable = VaultAgentPreferenceSnapshot(
        clients: Dictionary(uniqueKeysWithValues: VaultAgentClientKind.allCases.map {
            ($0, VaultAgentPreferenceClientSnapshot.unavailable(client: $0))
        }),
        claudePermission: .unavailable,
        audit: []
    )
}

private extension VaultAgentPeerIdentity {
    static func preferenceTestValue(client: VaultAgentClientKind) -> VaultAgentPeerIdentity {
        VaultAgentPeerIdentity(
            client: client,
            helperRequirement: "identifier com.pastera.agent.helper",
            helperCDHash: Data([1]),
            helperIsAdHoc: false,
            helperPath: "/Applications/Pastera.app/Contents/Helpers/helper",
            hostRequirement: client == .cli ? nil : "identifier com.example.host",
            hostCDHash: client == .cli ? nil : Data([2]),
            hostIsAdHoc: client == .cli ? nil : false,
            hostPath: client == .cli ? nil : "/Applications/Host.app/Contents/MacOS/Host"
        )
    }
}

private extension Result where Success == VaultAgentGrant, Failure == VaultAgentErrorCode {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

private func authorize(
    _ coordinator: VaultAgentAuthorizationCoordinator,
    identity: VaultAgentPeerIdentity,
    prepare: @escaping () throws -> Void
) async -> Result<VaultAgentGrant, VaultAgentErrorCode> {
    await withCheckedContinuation { continuation in
        coordinator.authorize(
            identity: identity,
            trigger: .explicitPreferencesAction,
            prepare: prepare
        ) { continuation.resume(returning: $0) }
    }
}

private func waitUntil(_ condition: @escaping () -> Bool) async throws {
    for _ in 0..<1_000 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(1))
    }
    throw VaultAgentErrorCode.brokerUnavailable
}
