import AppKit
import Foundation
import LocalAuthentication
import PasteraAgentProtocol
import Testing
@testable import Pastera

// The suite keeps its UI, authorization transaction, and preference-runtime probes together.
// swiftlint:disable file_length

@MainActor
@Suite("Agent integration preferences", .serialized)
// swiftlint:disable:next type_body_length
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
                    installationHint: nil,
                    authorization: .authorized,
                    idleExpiresAt: start.addingTimeInterval(60),
                    hardExpiresAt: start.addingTimeInterval(120),
                    lastSensitiveUseAt: start
                ),
                .cli: .testValue(client: .cli, installed: false, authorization: .authorized)
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
        #expect(!row.showsSecondaryUninstall)
        let cli = try #require(controller.rowSnapshotForTesting(.cli))
        #expect(cli.primaryAction == .revoke)
        #expect(!cli.showsSecondaryUninstall)
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
        #expect(controller.permissionControlsFitForTesting(width: 444))
    }

    @Test("the real preference shell renders the Agent page at default and minimum sizes")
    func realPreferenceShellRendersAgentPage() throws {
        let runtime = AgentPreferenceRuntimeProbe(snapshot: .installedAll)
        VaultAgentPreferenceRuntimeProvider.install(runtime)
        defer { VaultAgentPreferenceRuntimeProvider.install(UnavailableVaultAgentPreferenceRuntime()) }
        let controller = CPYPreferencesWindowController(
            frameAutosaveName: "PasteraAgentVisual-\(UUID().uuidString)",
            reduceMotion: { true },
            deactivateApplication: {}
        )
        controller.showPreferencePaneForTesting(paneID: .agentIntegrations)
        let window = try #require(controller.window)
        let outputDirectory = ProcessInfo.processInfo.environment["PASTERA_AGENT_VISUAL_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }

        for size in [NSSize(width: 760, height: 600), NSSize(width: 680, height: 480)] {
            window.setFrame(NSRect(origin: .zero, size: size), display: false)
            let contentView = try #require(window.contentView)
            contentView.layoutSubtreeIfNeeded()
            let paneFrame = controller.selectedPaneFrameInContentViewForTesting
            #expect(paneFrame.minX >= contentView.bounds.minX - 1)
            #expect(paneFrame.maxX <= contentView.bounds.maxX + 1)
            #expect(controller.preferencePaneViewportWidthForTesting > 0)
            #expect(controller.preferencePaneViewportHeightForTesting > 0)
            if let outputDirectory {
                try FileManager.default.createDirectory(
                    at: outputDirectory,
                    withIntermediateDirectories: true
                )
                let url = outputDirectory.appendingPathComponent(
                    "agent-integrations-\(Int(size.width))x\(Int(size.height)).png"
                )
                try renderPNG(contentView, to: url)
            }
        }
    }

    @Test("partial installs update first and installed clients retain a secondary uninstall route")
    func updateAndSecondaryUninstallRouting() async throws {
        let runtime = AgentPreferenceRuntimeProbe(snapshot: .init(
            clients: [
                .codex: .testValue(client: .codex, installed: true, authorization: .revoked),
                .claude: .testValue(
                    client: .claude,
                    installed: false,
                    needsUpdate: true,
                    authorization: .authorized
                )
            ],
            claudePermission: .unavailable,
            audit: []
        ))
        let controller = CPYAgentIntegrationPreferenceViewController(runtime: runtime)
        controller.loadView()

        let codex = try #require(controller.rowSnapshotForTesting(.codex))
        let claude = try #require(controller.rowSnapshotForTesting(.claude))
        #expect(codex.primaryAction == .reauthorize)
        #expect(codex.primaryActionCount == 1)
        #expect(codex.showsSecondaryUninstall)
        #expect(claude.primaryAction == .update)
        #expect(!claude.showsSecondaryUninstall)

        controller.triggerSecondaryUninstallForTesting(.codex)
        controller.triggerPrimaryActionForTesting(.claude)
        try await waitUntil { runtime.actions.count == 2 }
        #expect(runtime.actions == [.uninstall(.codex), .install(.claude)])
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

    @Test("Claude metadata preview exposes the exact tools before copy and apply become available")
    func metadataPermissionRequiresExactPreview() async throws {
        let runtime = AgentPreferenceRuntimeProbe(snapshot: .installedClaude)
        let expectedSnippet = try VaultAgentPermissionSnippet.canonical(for: .metadataOnly)
        var copied = ""
        let controller = CPYAgentIntegrationPreferenceViewController(runtime: runtime)
        let copiedController = CPYAgentIntegrationPreferenceViewController(
            runtime: runtime,
            copyText: { copied = $0 }
        )
        copiedController.loadView()

        #expect(!copiedController.metadataApplyEnabledForTesting)
        #expect(!copiedController.copyPermissionEnabledForTesting)
        copiedController.previewClaudeMetadataForTesting()
        try await waitUntil { copiedController.metadataApplyEnabledForTesting }

        #expect(copiedController.permissionPreviewForTesting == [
            "mcp__pastera-vault__vault_get",
            "mcp__pastera-vault__vault_search",
            "mcp__pastera-vault__vault_status"
        ].joined(separator: ", "))
        #expect(copiedController.copyPermissionEnabledForTesting)
        copiedController.copyClaudePermissionForTesting()
        copiedController.applyClaudeMetadataPermissionForTesting()
        try await waitUntil { runtime.actions.count == 1 }

        #expect(copied == expectedSnippet.serialized)
        #expect(runtime.actions == [.applyClaudePermission(.metadataOnly)])
        #expect(runtime.snippetScopes == [.metadataOnly])

        let invalidRuntime = AgentPreferenceRuntimeProbe(snapshot: .installedClaude)
        invalidRuntime.snippetOverride = .init(
            allowedTools: expectedSnippet.allowedTools,
            serialized: "{}"
        )
        let invalidController = CPYAgentIntegrationPreferenceViewController(runtime: invalidRuntime)
        invalidController.loadView()
        invalidController.previewClaudeMetadataForTesting()
        try await waitUntil { !invalidController.permissionErrorForTesting.isEmpty }
        #expect(!invalidController.metadataApplyEnabledForTesting)
        #expect(!invalidController.copyPermissionEnabledForTesting)

        // Keep the original controller alive to prove previews are controller-local.
        controller.loadView()
        #expect(!controller.metadataApplyEnabledForTesting)
    }

    @Test("client and permission failures stay in their own visual regions")
    func failuresAreIsolated() async throws {
        let runtime = AgentPreferenceRuntimeProbe(snapshot: .installedAll)
        runtime.actionFailure = (.revoke(.codex), VaultAgentErrorCode.brokerUnavailable)
        runtime.snippetFailure = VaultAgentErrorCode.invalidRequest
        let controller = CPYAgentIntegrationPreferenceViewController(runtime: runtime)
        controller.loadView()

        controller.triggerPrimaryActionForTesting(.codex)
        try await waitUntil { !controller.clientErrorForTesting(.codex).isEmpty }
        #expect(controller.clientErrorForTesting(.claude).isEmpty)
        #expect(controller.permissionErrorForTesting.isEmpty)

        controller.previewClaudeMetadataForTesting()
        try await waitUntil { !controller.permissionErrorForTesting.isEmpty }
        #expect(!controller.clientErrorForTesting(.codex).isEmpty)
        #expect(controller.clientErrorForTesting(.claude).isEmpty)
    }

    @Test("missing and reauthorization rows disclose scopes expiry boundaries and unattended risk")
    func consentBoundariesAreVisibleBeforeAuthentication() throws {
        let runtime = AgentPreferenceRuntimeProbe(snapshot: .init(
            clients: [
                .codex: .testValue(client: .codex, installed: true, authorization: .missing),
                .cli: .testValue(client: .cli, installed: true, authorization: .identityChanged)
            ],
            claudePermission: .unavailable,
            audit: []
        ))
        let controller = CPYAgentIntegrationPreferenceViewController(runtime: runtime)
        controller.loadView()

        let codex = controller.clientDetailForTesting(.codex)
        let cli = controller.clientDetailForTesting(.cli)
        for detail in [codex, cli] {
            #expect(detail.contains("7"))
            #expect(detail.contains("30"))
            #expect(detail.contains(pasteraPreferenceString(
                "Unattended automation can expose secrets to client commands."
            )))
            #expect(!detail.localizedCaseInsensitiveContains("never"))
        }
        #expect(codex.contains(pasteraPreferenceString(
            "Metadata, paste, and controlled injection"
        )))
        #expect(cli.contains(pasteraPreferenceString(
            "Metadata, paste, copy, and controlled injection"
        )))
    }

    @Test("the system authorization reason binds identity scopes expiry and unattended risk")
    func systemAuthorizationReasonIsInformed() {
        let codex = SystemVaultAgentIdentityAuthenticator.authorizationReason(
            for: .preferenceTestValue(client: .codex)
        )
        let cli = SystemVaultAgentIdentityAuthenticator.authorizationReason(
            for: .preferenceTestValue(client: .cli)
        )

        for reason in [codex, cli] {
            #expect(reason.contains(pasteraPreferenceString("7 idle days · 30 days total")))
            #expect(reason.contains(pasteraPreferenceString(
                "Unattended automation can expose secrets to client commands."
            )))
        }
        #expect(codex.localizedCaseInsensitiveContains("Codex"))
        #expect(codex.contains(pasteraPreferenceString(
            "Metadata, paste, and controlled injection"
        )))
        #expect(cli.localizedCaseInsensitiveContains("Pastera CLI"))
        #expect(cli.contains(pasteraPreferenceString(
            "Metadata, paste, copy, and controlled injection"
        )))
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

    @Test("a failed grant save rolls back a newly prepared automation key")
    func grantSaveFailureRollsBackPrepare() async throws {
        let store = AgentGrantStoreProbe()
        let executor = VaultAgentSerialExecutor(
            queue: DispatchQueue(label: "test.agent-preference.rollback")
        )
        let policy = try VaultAgentAuthorizationPolicy(store: store, executor: executor)
        store.saveError = PasswordVaultError.keychainUnavailable
        let coordinator = VaultAgentAuthorizationCoordinator(
            executor: executor,
            policy: policy,
            authenticator: AgentIdentityAuthenticatorProbe(result: .success(())),
            defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
        )
        var prepareCount = 0
        var rollbackCount = 0

        let result = await authorize(
            coordinator,
            identity: .preferenceTestValue(client: .cli),
            prepare: { prepareCount += 1 },
            rollbackPrepare: { rollbackCount += 1 }
        )

        #expect(result == .failure(.automationUnlockUnavailable))
        #expect(prepareCount == 1)
        #expect(rollbackCount == 1)
        #expect(store.grants.isEmpty)
    }

    @Test("a failed additional grant save preserves automation unlock for another valid client")
    func grantSaveFailurePreservesAnotherClient() async throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let codexIdentity = VaultAgentPeerIdentity.preferenceTestValue(client: .codex)
        let store = AgentGrantStoreProbe(grants: [
            .codex: .testValue(identity: codexIdentity, authenticatedAt: now)
        ])
        let executor = VaultAgentSerialExecutor(
            queue: DispatchQueue(label: "test.agent-preference.rollback-isolation")
        )
        let policy = try VaultAgentAuthorizationPolicy(store: store, executor: executor)
        store.saveError = PasswordVaultError.keychainUnavailable
        let coordinator = VaultAgentAuthorizationCoordinator(
            executor: executor,
            policy: policy,
            authenticator: AgentIdentityAuthenticatorProbe(result: .success(())),
            defaults: try #require(UserDefaults(suiteName: UUID().uuidString)),
            now: { now }
        )
        var rollbackCount = 0

        let result = await authorize(
            coordinator,
            identity: .preferenceTestValue(client: .cli),
            prepare: {},
            rollbackPrepare: { rollbackCount += 1 }
        )

        #expect(result == .failure(.automationUnlockUnavailable))
        #expect(rollbackCount == 0)
        #expect(policy.validGrantCount(at: now) == 1)
        #expect(store.grants[.codex]?.identity == codexIdentity)
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

    @Test("an old authentication completion cannot consume a new pending authorization")
    func staleAuthenticationCannotConsumeNewPendingAuthorization() async throws {
        let store = AgentGrantStoreProbe()
        let executor = VaultAgentSerialExecutor(
            queue: DispatchQueue(label: "test.agent-preference.stale-authentication")
        )
        let policy = try VaultAgentAuthorizationPolicy(store: store, executor: executor)
        let authenticator = AgentIdentityAuthenticatorProbe(result: nil)
        let coordinator = VaultAgentAuthorizationCoordinator(
            executor: executor,
            policy: policy,
            authenticator: authenticator,
            defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
        )
        let identity = VaultAgentPeerIdentity.preferenceTestValue(client: .cli)
        var first: Result<VaultAgentGrant, VaultAgentErrorCode>?
        var second: Result<VaultAgentGrant, VaultAgentErrorCode>?

        coordinator.authorize(
            identity: identity,
            trigger: .automaticFirstRequest,
            completion: { first = $0 }
        )
        try await waitUntil { authenticator.callCount == 1 }
        let mutation = try coordinator.beginLifecycleMutation(for: .cli, kind: .uninstall).get()
        try await waitUntil { first == .failure(.authorizationRequired) }
        coordinator.abortLifecycleMutation(mutation)
        coordinator.authorize(
            identity: identity,
            trigger: .automaticFirstRequest,
            completion: { second = $0 }
        )
        try await waitUntil { authenticator.callCount == 2 }

        try authenticator.completeNext(.success(()))
        #expect(policy.grantSnapshot(for: .cli) == nil)
        #expect(second == nil)

        try authenticator.completeNext(.success(()))
        try await waitUntil { second?.isSuccess == true }
        #expect(policy.grantSnapshot(for: .cli)?.identity == identity)
    }

    @Test("lifecycle mutations are single-owner and stale tokens cannot release a newer owner")
    func lifecycleMutationOwnershipIsTokenBound() throws {
        let store = AgentGrantStoreProbe()
        let executor = VaultAgentSerialExecutor(
            queue: DispatchQueue(label: "test.agent-preference.lifecycle-owner")
        )
        let policy = try VaultAgentAuthorizationPolicy(store: store, executor: executor)
        let coordinator = VaultAgentAuthorizationCoordinator(executor: executor, policy: policy)

        let first = try coordinator.beginLifecycleMutation(for: .cli, kind: .install).get()
        #expect(
            coordinator.beginLifecycleMutation(for: .cli, kind: .uninstall) ==
                .failure(.vaultBusy)
        )
        coordinator.abortLifecycleMutation(first)

        let second = try coordinator.beginLifecycleMutation(for: .cli, kind: .uninstall).get()
        #expect(!coordinator.resolveLifecycleMutation(first, authorizationEligible: true))
        #expect(coordinator.isAuthorizationBlocked(for: .cli))
        #expect(coordinator.resolveLifecycleMutation(second, authorizationEligible: false))
        #expect(coordinator.isAuthorizationBlocked(for: .cli))
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

    @Test("automatic authorization prompts only for a missing grant")
    func automaticAuthorizationDecisionMatrix() async throws {
        for decision in AutomaticAuthorizationRuntimeHarness.DecisionFixture.allCases {
            let harness = try AutomaticAuthorizationRuntimeHarness(decision: decision)

            let code = await harness.call(.get(entryID: UUID()))

            if decision == .missing {
                try await waitUntil { harness.authenticator.callCount == 1 }
            }
            #expect(code != nil)
            #expect(harness.authenticator.callCount == (decision == .missing ? 1 : 0))
        }
    }

    @Test("only direct entry operations can trigger the first automatic authorization prompt")
    func automaticAuthorizationOperationMatrix() async throws {
        let directOperations: [VaultAgentOperation] = [
            .search(.init(query: "", folderID: nil, limit: 1, cursor: nil)),
            .get(entryID: UUID()),
            .paste(entryID: UUID(), field: .password),
            .copy(entryID: UUID(), field: .password),
            .prepareExec(entryID: UUID(), field: .password, mode: .stdin)
        ]
        for operation in directOperations {
            let harness = try AutomaticAuthorizationRuntimeHarness()
            _ = await harness.call(operation)
            try await waitUntil { harness.authenticator.callCount == 1 }
        }

        let internalOperations: [VaultAgentOperation] = [
            .redeemTicket(token: "invalid", mode: .stdin),
            .completeTicket(receiptID: UUID())
        ]
        for operation in internalOperations {
            let harness = try AutomaticAuthorizationRuntimeHarness()
            _ = await harness.call(operation)
            #expect(harness.authenticator.callCount == 0)
        }
    }

    @Test("runtime emits one redacted state notification for authorization and sensitive transitions")
    func runtimeStateNotificationsAreBounded() async throws {
        let expiredCenter = NotificationCenter()
        var expiredNotifications = 0
        let expiredToken = expiredCenter.addObserver(
            forName: .vaultAgentPreferenceStateDidChange,
            object: nil,
            queue: nil
        ) { _ in expiredNotifications += 1 }
        defer { expiredCenter.removeObserver(expiredToken) }
        let expired = try AutomaticAuthorizationRuntimeHarness(
            decision: .expired,
            notificationCenter: expiredCenter
        )
        _ = await expired.call(.get(entryID: UUID()))
        _ = await expired.call(.get(entryID: UUID()))
        #expect(expiredNotifications == 1)

        let missingCenter = NotificationCenter()
        var authorizationNotifications = 0
        let missingToken = missingCenter.addObserver(
            forName: .vaultAgentPreferenceStateDidChange,
            object: nil,
            queue: nil
        ) { _ in authorizationNotifications += 1 }
        defer { missingCenter.removeObserver(missingToken) }
        let missing = try AutomaticAuthorizationRuntimeHarness(notificationCenter: missingCenter)
        _ = await missing.call(.get(entryID: UUID()))
        try await waitUntil { missing.authenticator.callCount == 1 }
        missing.authenticator.completeAll(.success(()))
        try await waitUntil { authorizationNotifications == 1 }

        let sensitiveCenter = NotificationCenter()
        var sensitiveNotifications = 0
        let sensitiveToken = sensitiveCenter.addObserver(
            forName: .vaultAgentPreferenceStateDidChange,
            object: nil,
            queue: nil
        ) { _ in sensitiveNotifications += 1 }
        defer { sensitiveCenter.removeObserver(sensitiveToken) }
        let sensitive = try AutomaticAuthorizationRuntimeHarness(
            decision: .allowed,
            notificationCenter: sensitiveCenter
        )
        _ = await sensitive.call(.copy(entryID: UUID(), field: .password))
        sensitive.vault.reportInteractiveSensitiveSuccess()
        try await waitUntil { sensitiveNotifications == 2 }

        #expect(sensitiveNotifications == 2)
    }

    @Test("page refreshes when shown again and on redacted runtime state notifications")
    func pageRefreshesWithoutPolling() async throws {
        let center = NotificationCenter()
        let runtime = AgentPreferenceRuntimeProbe(snapshot: .allUnavailable)
        let controller = CPYAgentIntegrationPreferenceViewController(
            runtime: runtime,
            notificationCenter: center
        )
        controller.loadView()
        let initialLoads = runtime.loadCount

        controller.viewWillAppear()
        try await waitUntil { runtime.loadCount == initialLoads + 1 }
        center.post(name: .vaultAgentPreferenceStateDidChange, object: nil)
        try await waitUntil { runtime.loadCount == initialLoads + 2 }

        #expect(runtime.loadCount == initialLoads + 2)
    }

    @Test("hidden state notifications stay dirty and refresh exactly once when shown")
    func hiddenStateNotificationsCoalesceUntilShown() async throws {
        let center = NotificationCenter()
        let runtime = AgentPreferenceRuntimeProbe(snapshot: .allUnavailable)
        let controller = CPYAgentIntegrationPreferenceViewController(
            runtime: runtime,
            notificationCenter: center
        )
        controller.loadView()
        controller.viewDidDisappear()
        let hiddenLoads = runtime.loadCount

        for _ in 0..<20 {
            center.post(name: .vaultAgentPreferenceStateDidChange, object: nil)
        }
        #expect(runtime.loadCount == hiddenLoads)

        controller.viewWillAppear()
        try await waitUntil { runtime.loadCount == hiddenLoads + 1 }
        #expect(runtime.loadCount == hiddenLoads + 1)
    }

    @Test("visible notification bursts allow one snapshot load and one dirty follow-up")
    func visibleStateNotificationsCoalesceWhileLoading() throws {
        let center = NotificationCenter()
        let runtime = AgentPreferenceRuntimeProbe(snapshot: .allUnavailable)
        let controller = CPYAgentIntegrationPreferenceViewController(
            runtime: runtime,
            notificationCenter: center
        )
        controller.loadView()
        controller.viewWillAppear()
        runtime.defersSnapshotLoads = true
        let visibleLoads = runtime.loadCount

        for _ in 0..<20 {
            center.post(name: .vaultAgentPreferenceStateDidChange, object: nil)
        }
        #expect(runtime.loadCount == visibleLoads + 1)
        #expect(runtime.maximumConcurrentLoadCount == 1)

        try runtime.completeNextSnapshotLoad()
        #expect(runtime.loadCount == visibleLoads + 2)
        #expect(runtime.maximumConcurrentLoadCount == 1)
        #expect(runtime.pendingSnapshotLoadCount == 1)

        try runtime.completeNextSnapshotLoad()
        #expect(runtime.loadCount == visibleLoads + 2)
        #expect(runtime.maximumConcurrentLoadCount == 1)
    }

    @Test("CLI PATH guidance is visible and snapshot refresh failures are not silent")
    func cliPathHintAndRefreshFailureAreVisible() {
        let runtime = AgentPreferenceRuntimeProbe(snapshot: .init(
            clients: [
                .cli: .testValue(
                    client: .cli,
                    installed: true,
                    authorization: .missing,
                    installationHint: "Add /usr/local/bin to PATH"
                )
            ],
            claudePermission: .unavailable,
            audit: []
        ))
        let controller = CPYAgentIntegrationPreferenceViewController(runtime: runtime)
        controller.loadView()
        #expect(controller.clientDetailForTesting(.cli).contains("/usr/local/bin"))

        runtime.loadFailure = VaultAgentErrorCode.brokerUnavailable
        controller.viewWillAppear()
        #expect(!controller.pageErrorForTesting.isEmpty)
        #expect(controller.clientDetailForTesting(.cli).contains("/usr/local/bin"))
    }

    @Test("duplicate facade authorization calls merge in the coordinator and complete on main")
    func duplicateExplicitAuthorizationMerges() async throws {
        let harness = try DefaultPreferenceRuntimeHarness(authenticatorResult: nil)
        var results: [Result<VaultAgentPreferenceSnapshot, Error>] = []
        var mainFlags: [Bool] = []

        harness.runtime.perform(.authorize(.cli)) { result in
            results.append(result)
            mainFlags.append(Thread.isMainThread)
        }
        harness.runtime.perform(.authorize(.cli)) { result in
            results.append(result)
            mainFlags.append(Thread.isMainThread)
        }
        try await waitUntil { harness.authenticator.callCount == 1 }
        harness.authenticator.completeAll(.success(()))
        try await waitUntil { results.count == 2 }

        #expect(results.allSatisfy { $0.isSuccess })
        #expect(mainFlags == [true, true])
        #expect(harness.vault.enableCount == 1)
    }

    @Test("an authorization waiter cannot release another authorization or admit a conflicting revoke")
    func authorizationReservationIsolation() async throws {
        let resolver = SequencedIdentityResolverProbe(results: [
            .success(.preferenceTestValue(client: .cli)),
            .failure(VaultAgentErrorCode.authorizationRequired)
        ])
        let harness = try DefaultPreferenceRuntimeHarness(
            authenticatorResult: nil,
            identityResolver: resolver
        )
        var first: Result<VaultAgentPreferenceSnapshot, Error>?
        var waiter: Result<VaultAgentPreferenceSnapshot, Error>?
        harness.runtime.perform(.authorize(.cli)) { first = $0 }
        try await waitUntil { harness.authenticator.callCount == 1 }
        harness.runtime.perform(.authorize(.cli)) { waiter = $0 }
        try await waitUntil { waiter != nil }

        let conflict = await perform(harness.runtime, .revoke(.cli))
        #expect(conflict.errorCode == .vaultBusy)
        harness.authenticator.completeAll(.success(()))
        try await waitUntil { first != nil }

        let afterCompletion = await perform(harness.runtime, .revoke(.cli))
        #expect(afterCompletion.isSuccess)
    }

    @Test("default facade releases its gate and reports busy completions on main")
    func defaultRuntimeGateAndCompletionContract() async throws {
        let gate = VaultAgentIntegrationWorkGate(capacity: 1)
        let harness = try DefaultPreferenceRuntimeHarness(workGate: gate)
        #expect(gate.tryAcquire())

        let busy = await loadSnapshot(harness.runtime)
        #expect(busy.errorCode == .vaultBusy)
        #expect(busy.completedOnMain)
        gate.release()

        let success = await loadSnapshot(harness.runtime)
        #expect(success.result.isSuccess)
        #expect(success.completedOnMain)
        #expect(gate.activeCount == 0)
    }

    @Test("client lifecycle actions never mutate Claude permissions and last revoke cleans automation")
    func facadeActionAndGrantIsolation() async throws {
        let harness = try DefaultPreferenceRuntimeHarness(useProductionLifecycle: true)

        _ = await perform(harness.runtime, .install(.codex))
        _ = await perform(harness.runtime, .authorize(.codex))
        _ = await perform(harness.runtime, .authorize(.cli))
        #expect(harness.policy.validGrantCount(at: harness.now) == 2)
        _ = await perform(harness.runtime, .revoke(.codex))
        #expect(harness.policy.validGrantCount(at: harness.now) == 1)
        #expect(harness.vault.disableCount == 0)
        _ = await perform(harness.runtime, .uninstall(.codex))
        #expect(harness.integration.permissionMutationCount == 0)

        _ = await perform(harness.runtime, .revoke(.cli))
        #expect(harness.policy.validGrantCount(at: harness.now) == 0)
        #expect(harness.vault.disableCount == 1)
        #expect(harness.integration.permissionMutationCount == 0)
    }

    @Test("an authorized CLI must be revoked before uninstall can touch integration")
    func authorizedCLIRequiresRevokeBeforeUninstall() async throws {
        let harness = try DefaultPreferenceRuntimeHarness(useProductionLifecycle: true)

        #expect((await perform(harness.runtime, .install(.cli))).isSuccess)
        #expect((await perform(harness.runtime, .authorize(.cli))).isSuccess)
        let grantBeforeUpdate = try #require(harness.policy.grantSnapshot(for: .cli))
        #expect((await perform(harness.runtime, .install(.cli))).isSuccess)
        #expect(harness.policy.grantSnapshot(for: .cli) == grantBeforeUpdate)
        let rejected = await perform(harness.runtime, .uninstall(.cli))

        #expect(rejected.errorCode == .invalidRequest)
        #expect(harness.integration.cliUninstallCount == 0)
        #expect(harness.policy.validGrantCount(at: harness.now) == 1)
        #expect(harness.vault.disableCount == 0)

        #expect((await perform(harness.runtime, .revoke(.cli))).isSuccess)
        #expect(harness.policy.validGrantCount(at: harness.now) == 0)
        #expect(harness.vault.disableCount == 1)
        #expect((await perform(harness.runtime, .uninstall(.cli))).isSuccess)
        #expect(harness.integration.cliUninstallCount == 1)
        #expect(harness.vault.disableCount == 1)
        #expect(harness.integration.permissionMutationCount == 0)
        #expect(harness.coordinator.isAuthorizationBlocked(for: .cli))

        #expect((await perform(harness.runtime, .install(.cli))).isSuccess)
        #expect(!harness.coordinator.isAuthorizationBlocked(for: .cli))
    }

    @Test("an identity-changed client revokes the old grant before uninstall and reinstall")
    func identityChangedClientCanUninstall() async throws {
        let currentIdentity = VaultAgentPeerIdentity.preferenceChangedTestValue(client: .cli)
        let harness = try DefaultPreferenceRuntimeHarness(
            identityResolver: FixedIdentityResolverProbe(identity: currentIdentity)
        )
        #expect((await perform(harness.runtime, .install(.cli))).isSuccess)
        let oldIdentity = VaultAgentPeerIdentity.preferenceTestValue(client: .cli)
        try harness.policy.authorize(identity: oldIdentity, authenticatedAt: harness.now)

        let result = await perform(harness.runtime, .uninstall(.cli))

        #expect(result.isSuccess)
        #expect(harness.integration.cliUninstallCount == 1)
        #expect(harness.policy.grantSnapshot(for: .cli)?.identity == oldIdentity)
        #expect(harness.policy.grantSnapshot(for: .cli)?.revokedAt == harness.now)
        #expect(harness.coordinator.isAuthorizationBlocked(for: .cli))

        #expect((await perform(harness.runtime, .install(.cli))).isSuccess)
        #expect(!harness.coordinator.isAuthorizationBlocked(for: .cli))
        #expect(harness.policy.decision(for: oldIdentity, at: harness.now) == .revoked)
    }

    @Test("identity-change cleanup failures are surfaced after the old grant is revoked")
    func identityChangedCleanupFailureIsSurfaced() async throws {
        let lifecycle = PreferenceLifecycleProbe(error: .invalidRequest)
        let currentIdentity = VaultAgentPeerIdentity.preferenceChangedTestValue(client: .cli)
        let harness = try DefaultPreferenceRuntimeHarness(
            identityResolver: FixedIdentityResolverProbe(identity: currentIdentity),
            lifecycleReconciler: lifecycle
        )
        #expect((await perform(harness.runtime, .install(.cli))).isSuccess)
        let oldIdentity = VaultAgentPeerIdentity.preferenceTestValue(client: .cli)
        try harness.policy.authorize(identity: oldIdentity, authenticatedAt: harness.now)
        harness.integration.cliUninstallFailure = VaultAgentErrorCode.brokerUnavailable

        let result = await perform(harness.runtime, .uninstall(.cli))

        #expect(result.errorCode == .invalidRequest)
        #expect(lifecycle.callCount == 1)
        #expect(harness.policy.decision(for: oldIdentity, at: harness.now) == .revoked)
    }

    @Test("an uninstall failure preserves the revoked grant and lifecycle state")
    func uninstallFailurePreservesGrant() async throws {
        let harness = try DefaultPreferenceRuntimeHarness(useProductionLifecycle: true)
        #expect((await perform(harness.runtime, .install(.cli))).isSuccess)
        #expect((await perform(harness.runtime, .authorize(.cli))).isSuccess)
        #expect((await perform(harness.runtime, .revoke(.cli))).isSuccess)
        let grantBeforeFailure = try #require(harness.policy.grantSnapshot(for: .cli))
        let lifecycleCount = harness.vault.disableCount
        harness.integration.cliUninstallFailure = VaultAgentErrorCode.brokerUnavailable

        let failed = await perform(harness.runtime, .uninstall(.cli))

        #expect(failed.errorCode == .brokerUnavailable)
        #expect(harness.integration.cliUninstallCount == 1)
        #expect(harness.policy.grantSnapshot(for: .cli) == grantBeforeFailure)
        #expect(harness.vault.disableCount == lifecycleCount)
        #expect(harness.integration.permissionMutationCount == 0)
        #expect(!harness.coordinator.isAuthorizationBlocked(for: .cli))
    }

    @Test("post-commit uninstall failure keeps authorization suspended when readback is uninstalled")
    func postCommitUninstallFailureStaysSuspended() async throws {
        let harness = try DefaultPreferenceRuntimeHarness()
        #expect((await perform(harness.runtime, .install(.cli))).isSuccess)
        harness.integration.cliUninstallBehavior = .failAfterMutation

        let failed = await perform(harness.runtime, .uninstall(.cli))

        #expect(failed.errorCode == .brokerUnavailable)
        #expect(!harness.integration.cliIsInstalled)
        #expect(harness.coordinator.isAuthorizationBlocked(for: .cli))
    }

    @Test("unknown uninstall readback fails closed and keeps authorization suspended")
    func unknownUninstallReadbackStaysSuspended() async throws {
        let harness = try DefaultPreferenceRuntimeHarness()
        #expect((await perform(harness.runtime, .install(.cli))).isSuccess)
        harness.integration.cliUninstallBehavior = .failBeforeMutation
        harness.integration.cliStatusFailure = VaultAgentErrorCode.brokerUnavailable

        let failed = await perform(harness.runtime, .uninstall(.cli))

        #expect(failed.errorCode == .brokerUnavailable)
        #expect(harness.coordinator.isAuthorizationBlocked(for: .cli))
    }

    @Test("unknown install readback fails closed until a durable install succeeds")
    func unknownInstallReadbackStaysSuspended() async throws {
        let harness = try DefaultPreferenceRuntimeHarness()
        harness.integration.cliStatusFailure = VaultAgentErrorCode.brokerUnavailable

        let failed = await perform(harness.runtime, .install(.cli))

        #expect(failed.errorCode == .brokerUnavailable)
        #expect(harness.coordinator.isAuthorizationBlocked(for: .cli))

        harness.integration.cliStatusFailure = nil
        #expect((await perform(harness.runtime, .install(.cli))).isSuccess)
        #expect(!harness.coordinator.isAuthorizationBlocked(for: .cli))
    }

    @Test("pending automatic authorization is cancelled by uninstall and stale LA success commits nothing")
    func pendingAutomaticAuthorizationCannotSurviveUninstall() async throws {
        let harness = try DefaultPreferenceRuntimeHarness(
            authenticatorResult: nil,
            useProductionLifecycle: true
        )
        #expect((await perform(harness.runtime, .install(.cli))).isSuccess)
        #expect(await harness.callBroker(.get(entryID: UUID())) == .authorizationRequired)
        try await waitUntil { harness.authenticator.callCount == 1 }

        #expect((await perform(harness.runtime, .uninstall(.cli))).isSuccess)
        try harness.authenticator.completeNext(.success(()))

        #expect(harness.policy.grantSnapshot(for: .cli) == nil)
        #expect(!harness.vault.automationUnlockEnabled)
        #expect(harness.vault.enableCount == 0)
        #expect(harness.coordinator.isAuthorizationBlocked(for: .cli))
    }

    @Test("automatic authorization starting during uninstall is rejected by the same client suspension")
    func automaticAuthorizationCannotEnterUninstallWindow() async throws {
        let harness = try DefaultPreferenceRuntimeHarness(useProductionLifecycle: true)
        #expect((await perform(harness.runtime, .install(.cli))).isSuccess)
        harness.integration.holdsCLIUninstall = true
        let uninstall = Task { await perform(harness.runtime, .uninstall(.cli)) }
        try await waitUntil { harness.integration.cliUninstallStartedCount == 1 }

        #expect(await harness.callBroker(.get(entryID: UUID())) == .authorizationRequired)
        #expect(harness.coordinator.isAuthorizationBlocked(for: .cli))
        #expect(harness.authenticator.callCount == 0)
        harness.integration.continueCLIUninstall()
        #expect((await uninstall.value).isSuccess)

        #expect(await harness.callBroker(.get(entryID: UUID())) == .authorizationRequired)
        #expect(harness.authenticator.callCount == 0)
        #expect(harness.policy.grantSnapshot(for: .cli) == nil)
    }

    @Test("Broker host integration mutations use the shared authorization lifecycle gate")
    func brokerHostMutationsUseSharedLifecycleGate() async throws {
        let harness = try DefaultPreferenceRuntimeHarness(useProductionLifecycle: true)
        #expect(await harness.callBroker(.integrationInstall(host: .codex)) == nil)
        let identity = VaultAgentPeerIdentity.preferenceTestValue(client: .codex)
        try harness.policy.authorize(identity: identity, authenticatedAt: harness.now)

        #expect(await harness.callBroker(.integrationUninstall(host: .codex)) == .invalidRequest)
        #expect(harness.integration.hostUninstallCount(.codex) == 0)
        #expect(!harness.coordinator.isAuthorizationBlocked(for: .codex))

        try harness.policy.revoke(.codex, at: harness.now)
        #expect(await harness.callBroker(.integrationUninstall(host: .codex)) == nil)
        #expect(harness.integration.hostUninstallCount(.codex) == 1)
        #expect(harness.coordinator.isAuthorizationBlocked(for: .codex))
        #expect(await harness.callBroker(.integrationInstall(host: .codex)) == nil)
        #expect(!harness.coordinator.isAuthorizationBlocked(for: .codex))
    }
}

private final class AgentPreferenceRuntimeProbe: VaultAgentPreferenceRuntimeServicing {
    var snapshot: VaultAgentPreferenceSnapshot
    var loadFailure: Error?
    var actionFailure: (action: VaultAgentPreferenceAction, error: Error)?
    var snippetFailure: Error?
    var snippetOverride: VaultAgentPermissionSnippet?
    var defersSnapshotLoads = false
    private(set) var actions: [VaultAgentPreferenceAction] = []
    private(set) var snippetScopes: [VaultAgentHostPermissionScope] = []
    private(set) var loadCount = 0
    private(set) var maximumConcurrentLoadCount = 0
    private var activeLoadCount = 0
    private var pendingSnapshotLoads = [
        (Result<VaultAgentPreferenceSnapshot, Error>) -> Void
    ]()

    var pendingSnapshotLoadCount: Int { pendingSnapshotLoads.count }

    init(snapshot: VaultAgentPreferenceSnapshot) {
        self.snapshot = snapshot
    }

    func loadSnapshot(completion: @escaping (Result<VaultAgentPreferenceSnapshot, Error>) -> Void) {
        loadCount += 1
        activeLoadCount += 1
        maximumConcurrentLoadCount = max(maximumConcurrentLoadCount, activeLoadCount)
        if defersSnapshotLoads {
            pendingSnapshotLoads.append(completion)
            return
        }
        completeSnapshotLoad(completion)
    }

    func completeNextSnapshotLoad() throws {
        guard !pendingSnapshotLoads.isEmpty else { throw VaultAgentErrorCode.invalidRequest }
        completeSnapshotLoad(pendingSnapshotLoads.removeFirst())
    }

    private func completeSnapshotLoad(
        _ completion: @escaping (Result<VaultAgentPreferenceSnapshot, Error>) -> Void
    ) {
        activeLoadCount -= 1
        if let loadFailure {
            completion(.failure(loadFailure))
        } else {
            completion(.success(snapshot))
        }
    }

    func perform(
        _ action: VaultAgentPreferenceAction,
        completion: @escaping (Result<VaultAgentPreferenceSnapshot, Error>) -> Void
    ) {
        actions.append(action)
        if let failure = actionFailure, failure.action == action {
            completion(.failure(failure.error))
            return
        }
        completion(.success(snapshot))
    }

    func claudePermissionSnippet(
        scope: VaultAgentHostPermissionScope,
        completion: @escaping (Result<VaultAgentPermissionSnippet, Error>) -> Void
    ) {
        snippetScopes.append(scope)
        if let snippetFailure {
            completion(.failure(snippetFailure))
            return
        }
        if let snippetOverride {
            completion(.success(snippetOverride))
            return
        }
        completion(Result { try VaultAgentPermissionSnippet.canonical(for: scope) })
    }
}

private final class AgentGrantStoreProbe: VaultAgentGrantStoring {
    var grants: [VaultAgentClientKind: VaultAgentGrant] = [:]
    var saveError: Error?

    init(grants: [VaultAgentClientKind: VaultAgentGrant] = [:]) {
        self.grants = grants
    }

    func load() -> [VaultAgentClientKind: VaultAgentGrant] { grants }
    func save(_ grants: [VaultAgentClientKind: VaultAgentGrant]) throws {
        if let saveError { throw saveError }
        self.grants = grants
    }
}

private final class AgentIdentityAuthenticatorProbe: VaultAgentIdentityAuthenticating {
    private let lock = NSLock()
    private let result: Result<Void, Error>?
    private var completions: [(Result<Void, Error>) -> Void] = []
    private var storedIdentities: [VaultAgentPeerIdentity] = []

    var callCount: Int { lock.withLock { completions.count } }
    var identities: [VaultAgentPeerIdentity] { lock.withLock { storedIdentities } }

    init(result: Result<Void, Error>?) {
        self.result = result
    }

    func authenticate(completion: @escaping (Result<Void, Error>) -> Void) {
        lock.withLock { completions.append(completion) }
        if let result { DispatchQueue.global().async { completion(result) } }
    }

    func authenticate(
        identity: VaultAgentPeerIdentity,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        lock.withLock { storedIdentities.append(identity) }
        authenticate(completion: completion)
    }

    func completeAll(_ result: Result<Void, Error>) {
        lock.withLock { completions }.forEach { $0(result) }
    }

    func completeNext(_ result: Result<Void, Error>) throws {
        let completion = try lock.withLock {
            guard !completions.isEmpty else { throw VaultAgentErrorCode.invalidRequest }
            return completions.removeFirst()
        }
        completion(result)
    }
}

private final class AutomaticAuthorizationRuntimeHarness {
    enum DecisionFixture: CaseIterable {
        case missing
        case identityChanged
        case expired
        case revoked
        case allowed

        static let allCases: [Self] = [.missing, .identityChanged, .expired, .revoked]
    }

    let authenticator = AgentIdentityAuthenticatorProbe(result: nil)
    let vault = AutomaticAuthorizationVaultProbe()
    private let runtime: VaultAgentRuntime
    private let identity: VaultAgentPeerIdentity

    init(
        decision: DecisionFixture = .missing,
        notificationCenter: NotificationCenter = .default
    ) throws {
        let currentIdentity = VaultAgentPeerIdentity.preferenceTestValue(client: .cli)
        identity = currentIdentity
        let executor = VaultAgentSerialExecutor(
            queue: DispatchQueue(label: "test.agent-preference.automatic")
        )
        let now = Date(timeIntervalSince1970: 100_000)
        let store = AgentGrantStoreProbe(grants: Self.grants(
            for: decision,
            currentIdentity: currentIdentity,
            now: now
        ))
        let policy = try VaultAgentAuthorizationPolicy(
            store: store,
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
            now: { now },
            preferenceNotificationCenter: notificationCenter,
            cursorKey: Data(repeating: 1, count: 32)
        )
    }

    private static func grants(
        for fixture: DecisionFixture,
        currentIdentity: VaultAgentPeerIdentity,
        now: Date
    ) -> [VaultAgentClientKind: VaultAgentGrant] {
        switch fixture {
        case .missing:
            return [:]
        case .identityChanged:
            var changed = VaultAgentPeerIdentity.preferenceTestValue(client: .cli)
            changed = .init(
                client: changed.client,
                helperRequirement: "identifier previous.helper",
                helperCDHash: changed.helperCDHash,
                helperIsAdHoc: changed.helperIsAdHoc,
                helperPath: changed.helperPath,
                hostRequirement: changed.hostRequirement,
                hostCDHash: changed.hostCDHash,
                hostIsAdHoc: changed.hostIsAdHoc,
                hostPath: changed.hostPath
            )
            return [.cli: .testValue(identity: changed, authenticatedAt: now)]
        case .expired:
            return [.cli: .init(
                identity: currentIdentity,
                authenticatedAt: now.addingTimeInterval(-100),
                idleExpiresAt: now,
                hardExpiresAt: now.addingTimeInterval(100),
                lastSensitiveUseAt: nil,
                revokedAt: nil
            )]
        case .revoked:
            return [.cli: .init(
                identity: currentIdentity,
                authenticatedAt: now.addingTimeInterval(-100),
                idleExpiresAt: now.addingTimeInterval(100),
                hardExpiresAt: now.addingTimeInterval(200),
                lastSensitiveUseAt: nil,
                revokedAt: now.addingTimeInterval(-1)
            )]
        case .allowed:
            return [.cli: .testValue(identity: currentIdentity, authenticatedAt: now)]
        }
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

private final class AutomaticAuthorizationVaultProbe:
    PasswordVaultAgentAccess,
    VaultAgentSensitiveUseObserving {
    var agentVaultReady = true
    private(set) var ensureReadyCount = 0
    private var sensitiveObservers = [UUID: () -> Void]()

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

    func addInteractiveSensitiveUseObserver(_ observer: @escaping () -> Void) -> UUID {
        let identifier = UUID()
        sensitiveObservers[identifier] = observer
        return identifier
    }

    func removeInteractiveSensitiveUseObserver(_ identifier: UUID) {
        sensitiveObservers.removeValue(forKey: identifier)
    }

    func reportInteractiveSensitiveSuccess() {
        sensitiveObservers.values.forEach { $0() }
    }
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

private final class DefaultPreferenceRuntimeHarness {
    let now = Date(timeIntervalSince1970: 400_000)
    let integration = PreferenceIntegrationProbe()
    let vault = PreferenceVaultProbe()
    let authenticator: AgentIdentityAuthenticatorProbe
    let policy: VaultAgentAuthorizationPolicy
    let coordinator: VaultAgentAuthorizationCoordinator
    let lifecycleGate: VaultAgentIntegrationLifecycleGate
    let runtime: DefaultVaultAgentPreferenceRuntime
    private var productionLifecycle: VaultAgentRuntime?

    init(
        authenticatorResult: Result<Void, Error>? = .success(()),
        workGate: VaultAgentIntegrationWorkGate = VaultAgentIntegrationWorkGate(capacity: 4),
        useProductionLifecycle: Bool = false,
        identityResolver: VaultAgentPreferenceIdentityResolving = PreferenceIdentityResolverProbe(),
        lifecycleReconciler: VaultAgentGrantLifecycleReconciling? = nil
    ) throws {
        let executor = VaultAgentSerialExecutor(
            queue: DispatchQueue(label: "test.agent-preference.default-runtime.store")
        )
        let store = AgentGrantStoreProbe()
        policy = try VaultAgentAuthorizationPolicy(store: store, executor: executor)
        authenticator = AgentIdentityAuthenticatorProbe(result: authenticatorResult)
        coordinator = VaultAgentAuthorizationCoordinator(
            executor: executor,
            policy: policy,
            authenticator: authenticator,
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            now: { [now] in now }
        )
        lifecycleGate = VaultAgentIntegrationLifecycleGate(
            authorizationCoordinator: coordinator,
            authorizationPolicy: policy,
            now: { [now] in now }
        )
        let lifecycle: VaultAgentGrantLifecycleReconciling
        if useProductionLifecycle {
            let runtime = try VaultAgentRuntime(
                executor: executor,
                authorizationPolicy: policy,
                authorizationCoordinator: coordinator,
                automaticAuthorizationPrepare: { [vault] in
                    try vault.enableAutomationUnlockForAgent()
                },
                vault: vault,
                pasteTargetTracker: AutomaticAuthorizationTargetProbe(),
                integrationService: integration,
                integrationLifecycleGate: lifecycleGate,
                ticketStore: VaultAgentTicketStore(commandBuilder: { _, _, _ in ["/usr/bin/false"] }),
                auditLogger: AutomaticAuthorizationAuditProbe(),
                now: { [now] in now },
                cursorKey: Data(repeating: 2, count: 32)
            )
            productionLifecycle = runtime
            lifecycle = runtime
        } else {
            lifecycle = lifecycleReconciler ?? PreferenceLifecycleProbe()
        }
        runtime = DefaultVaultAgentPreferenceRuntime(
            integration: integration,
            authorizationPolicy: policy,
            authorizationCoordinator: coordinator,
            vault: vault,
            identityResolver: identityResolver,
            lifecycleReconciler: lifecycle,
            integrationLifecycleGate: lifecycleGate,
            worker: DispatchQueue(label: "test.agent-preference.default-runtime.worker"),
            workGate: workGate,
            now: { [now] in now }
        )
    }

    func callBroker(_ operation: VaultAgentOperation) async -> VaultAgentErrorCode? {
        guard let productionLifecycle else { return .brokerUnavailable }
        let request = VaultAgentRequestEnvelope(
            protocolVersion: VaultAgentLimits.protocolVersion,
            connectionID: UUID(),
            sequence: 1,
            requestID: UUID(),
            operation: operation
        )
        let data = try! JSONEncoder().encode(request)
        let responseData = await withCheckedContinuation { continuation in
            productionLifecycle.handle(
                identity: .preferenceTestValue(client: .cli),
                request: data
            ) { result in
                continuation.resume(returning: try! result.get())
            }
        }
        let response = try! JSONDecoder().decode(VaultAgentResponseEnvelope.self, from: responseData)
        guard case let .failure(failure) = response.body else { return nil }
        return failure.code
    }
}

private final class PreferenceIntegrationProbe: VaultAgentPreferenceIntegrationServicing {
    enum CLIUninstallBehavior {
        case succeeds
        case failBeforeMutation
        case failAfterMutation
    }

    private let lock = NSLock()
    private var installedHosts = Set<VaultAgentHostKind>()
    private var cliInstalled = false
    private var permissionMutations = 0
    private var cliUninstallAttempts = 0
    private var storedCLIUninstallFailure: Error?
    private var storedCLIUninstallBehavior = CLIUninstallBehavior.succeeds
    private var storedCLIStatusFailure: Error?
    private var storedHoldsCLIUninstall = false
    private var cliUninstallStarted = 0
    private var hostUninstallAttempts = [VaultAgentHostKind: Int]()
    private let cliUninstallContinuation = DispatchSemaphore(value: 0)

    var permissionMutationCount: Int { lock.withLock { permissionMutations } }
    var cliUninstallCount: Int { lock.withLock { cliUninstallAttempts } }
    var cliUninstallFailure: Error? {
        get { lock.withLock { storedCLIUninstallFailure } }
        set { lock.withLock { storedCLIUninstallFailure = newValue } }
    }
    var cliUninstallBehavior: CLIUninstallBehavior {
        get { lock.withLock { storedCLIUninstallBehavior } }
        set { lock.withLock { storedCLIUninstallBehavior = newValue } }
    }
    var cliStatusFailure: Error? {
        get { lock.withLock { storedCLIStatusFailure } }
        set { lock.withLock { storedCLIStatusFailure = newValue } }
    }
    var holdsCLIUninstall: Bool {
        get { lock.withLock { storedHoldsCLIUninstall } }
        set { lock.withLock { storedHoldsCLIUninstall = newValue } }
    }
    var cliUninstallStartedCount: Int { lock.withLock { cliUninstallStarted } }
    var cliIsInstalled: Bool { lock.withLock { cliInstalled } }

    func hostUninstallCount(_ host: VaultAgentHostKind) -> Int {
        lock.withLock { hostUninstallAttempts[host, default: 0] }
    }

    func continueCLIUninstall() {
        cliUninstallContinuation.signal()
    }

    func status(host: VaultAgentHostKind?) -> VaultAgentIntegrationStatus {
        lock.withLock {
            let hosts = host.map { [$0] } ?? [.codex, .claude]
            return .init(hosts: hosts.map { current in
                let installed = installedHosts.contains(current)
                return .init(
                    host: current,
                    hostDetected: true,
                    hostExecutablePath: "/Applications/\(current.rawValue).app/Contents/MacOS/host",
                    mcpInstalled: installed,
                    skillInstalled: installed,
                    installedVersion: installed ? "1" : nil,
                    authorized: false,
                    idleExpiresAt: nil,
                    hardExpiresAt: nil
                )
            })
        }
    }

    func install(host: VaultAgentHostKind) -> VaultAgentIntegrationStatus {
        lock.withLock { _ = installedHosts.insert(host) }
        return status(host: host)
    }

    func uninstall(host: VaultAgentHostKind) -> VaultAgentIntegrationStatus {
        lock.withLock {
            hostUninstallAttempts[host, default: 0] += 1
            _ = installedHosts.remove(host)
        }
        return status(host: host)
    }

    func cliStatus() throws -> VaultAgentCLIInstallationStatus {
        try lock.withLock {
            if let storedCLIStatusFailure { throw storedCLIStatusFailure }
            return VaultAgentCLIInstallationStatus(
                installed: cliInstalled,
                executablePath: "/usr/local/bin/pastera",
                pathHint: nil
            )
        }
    }

    func installCLI() throws -> VaultAgentCLIInstallationStatus {
        lock.withLock { cliInstalled = true }
        return try cliStatus()
    }

    func uninstallCLI() throws -> VaultAgentCLIInstallationStatus {
        let state = try lock.withLock { () -> (CLIUninstallBehavior, Bool) in
            cliUninstallAttempts += 1
            if let storedCLIUninstallFailure { throw storedCLIUninstallFailure }
            if storedCLIUninstallBehavior == .failBeforeMutation {
                throw VaultAgentErrorCode.brokerUnavailable
            }
            cliUninstallStarted += 1
            return (storedCLIUninstallBehavior, storedHoldsCLIUninstall)
        }
        if state.1, cliUninstallContinuation.wait(timeout: .now() + 2) == .timedOut {
            throw VaultAgentErrorCode.brokerUnavailable
        }
        try lock.withLock {
            cliInstalled = false
            if state.0 == .failAfterMutation { throw VaultAgentErrorCode.brokerUnavailable }
        }
        return try cliStatus()
    }

    func permissionSnippet(
        for _: VaultAgentHostKind,
        scope: VaultAgentHostPermissionScope
    ) throws -> VaultAgentPermissionSnippet {
        try VaultAgentPermissionSnippet.canonical(for: scope)
    }

    func claudePermissionStatus() -> VaultAgentClaudePermissionStatus {
        .init(policyDisposition: .userRulesAllowed, ownedRules: [])
    }

    func applyClaudePermissionScope(
        _: VaultAgentHostPermissionScope
    ) -> VaultAgentPermissionChange {
        lock.withLock { permissionMutations += 1 }
        return .init(addedRules: [], removedRules: [], unchanged: false)
    }

    func removeOwnedClaudePermissionRules() -> VaultAgentPermissionChange {
        lock.withLock { permissionMutations += 1 }
        return .init(addedRules: [], removedRules: [], unchanged: false)
    }

    func installedHostIdentity(for client: VaultAgentClientKind) -> VaultAgentInstalledHostIdentity? {
        guard client != .cli else { return nil }
        return .init(
            client: client,
            canonicalPath: "/Applications/host",
            designatedRequirement: "identifier host",
            cdHash: nil,
            isAdHoc: false
        )
    }
}

private final class PreferenceVaultProbe: PasswordVaultAgentAccess, VaultAgentPreferenceVaultServicing {
    var agentVaultReady = true
    private(set) var enableCount = 0
    private(set) var disableCount = 0
    var automationUnlockEnabled: Bool { enableCount > disableCount }

    func checkQuickUnlockAvailability(completion: @escaping (Bool) -> Void) { completion(true) }
    func unlockWithQuickKey(completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        completion(.success(()))
    }
    func enableAutomationUnlockForAgent() throws { enableCount += 1 }
    func disableAutomationUnlockForAgent() throws { disableCount += 1 }
    func ensureReadyForAgent(completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
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
}

private struct PreferenceIdentityResolverProbe: VaultAgentPreferenceIdentityResolving {
    func resolveIdentity(for client: VaultAgentClientKind) -> VaultAgentPeerIdentity {
        .preferenceTestValue(client: client)
    }
}

private struct FixedIdentityResolverProbe: VaultAgentPreferenceIdentityResolving {
    let identity: VaultAgentPeerIdentity

    func resolveIdentity(for _: VaultAgentClientKind) -> VaultAgentPeerIdentity { identity }
}

private final class SequencedIdentityResolverProbe: VaultAgentPreferenceIdentityResolving {
    private let lock = NSLock()
    private var results: [Result<VaultAgentPeerIdentity, Error>]

    init(results: [Result<VaultAgentPeerIdentity, Error>]) {
        self.results = results
    }

    func resolveIdentity(for _: VaultAgentClientKind) throws -> VaultAgentPeerIdentity {
        try lock.withLock {
            guard !results.isEmpty else { throw VaultAgentErrorCode.authorizationRequired }
            return try results.removeFirst().get()
        }
    }
}

private final class PreferenceLifecycleProbe: VaultAgentGrantLifecycleReconciling {
    private(set) var callCount = 0
    let error: VaultAgentErrorCode?

    init(error: VaultAgentErrorCode? = nil) {
        self.error = error
    }

    func authorizationStateDidChange() throws {
        callCount += 1
        if let error { throw error }
    }
}

private extension VaultAgentPreferenceSnapshot {
    static let allUnavailable = VaultAgentPreferenceSnapshot(
        clients: Dictionary(uniqueKeysWithValues: VaultAgentClientKind.allCases.map {
            ($0, VaultAgentPreferenceClientSnapshot.unavailable(client: $0))
        }),
        claudePermission: .unavailable,
        audit: []
    )

    static let installedClaude = VaultAgentPreferenceSnapshot(
        clients: [
            .codex: .unavailable(client: .codex),
            .claude: .testValue(client: .claude, installed: true, authorization: .missing),
            .cli: .unavailable(client: .cli)
        ],
        claudePermission: .init(policyDisposition: .userRulesAllowed, ownedRules: []),
        audit: []
    )

    static let installedAll = VaultAgentPreferenceSnapshot(
        clients: Dictionary(uniqueKeysWithValues: VaultAgentClientKind.allCases.map {
            ($0, VaultAgentPreferenceClientSnapshot.testValue(
                client: $0,
                installed: true,
                authorization: .authorized
            ))
        }),
        claudePermission: .init(policyDisposition: .userRulesAllowed, ownedRules: []),
        audit: []
    )
}

private extension VaultAgentPreferenceClientSnapshot {
    static func testValue(
        client: VaultAgentClientKind,
        installed: Bool,
        needsUpdate: Bool = false,
        authorization: VaultAgentPreferenceAuthorizationState,
        installationHint: String? = nil
    ) -> Self {
        .init(
            client: client,
            hostDetected: true,
            installed: installed,
            installationNeedsUpdate: needsUpdate,
            hostPathSummary: "Applications/Host",
            installationHint: installationHint,
            authorization: authorization,
            idleExpiresAt: authorization == .authorized ? Date(timeIntervalSince1970: 2_000) : nil,
            hardExpiresAt: authorization == .authorized ? Date(timeIntervalSince1970: 3_000) : nil,
            lastSensitiveUseAt: nil
        )
    }
}

private extension VaultAgentGrant {
    static func testValue(identity: VaultAgentPeerIdentity, authenticatedAt: Date) -> Self {
        .init(
            identity: identity,
            authenticatedAt: authenticatedAt,
            idleExpiresAt: authenticatedAt.addingTimeInterval(VaultAgentAuthorizationPolicy.idleLifetime),
            hardExpiresAt: authenticatedAt.addingTimeInterval(VaultAgentAuthorizationPolicy.hardLifetime),
            lastSensitiveUseAt: nil,
            revokedAt: nil
        )
    }
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

    static func preferenceChangedTestValue(client: VaultAgentClientKind) -> VaultAgentPeerIdentity {
        VaultAgentPeerIdentity(
            client: client,
            helperRequirement: "identifier com.pastera.agent.helper.changed",
            helperCDHash: Data([9]),
            helperIsAdHoc: false,
            helperPath: "/Applications/Pastera.app/Contents/Helpers/helper",
            hostRequirement: client == .cli ? nil : "identifier com.example.host.changed",
            hostCDHash: client == .cli ? nil : Data([8]),
            hostIsAdHoc: client == .cli ? nil : false,
            hostPath: client == .cli ? nil : "/Applications/Host.app/Contents/MacOS/Host"
        )
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

private extension Result where Failure == Error {
    var errorCode: VaultAgentErrorCode? {
        guard case let .failure(error) = self else { return nil }
        return error as? VaultAgentErrorCode
    }
}

private func authorize(
    _ coordinator: VaultAgentAuthorizationCoordinator,
    identity: VaultAgentPeerIdentity,
    prepare: @escaping () throws -> Void,
    rollbackPrepare: (() throws -> Void)? = nil
) async -> Result<VaultAgentGrant, VaultAgentErrorCode> {
    await withCheckedContinuation { continuation in
        coordinator.authorize(
            identity: identity,
            trigger: .explicitPreferencesAction,
            prepare: prepare,
            rollbackPrepare: rollbackPrepare
        ) { continuation.resume(returning: $0) }
    }
}

private struct SnapshotResult {
    let result: Result<VaultAgentPreferenceSnapshot, Error>
    let completedOnMain: Bool

    var errorCode: VaultAgentErrorCode? { result.errorCode }
}

@MainActor
private func loadSnapshot(_ runtime: VaultAgentPreferenceRuntimeServicing) async -> SnapshotResult {
    await withCheckedContinuation { continuation in
        runtime.loadSnapshot { result in
            continuation.resume(returning: .init(
                result: result,
                completedOnMain: Thread.isMainThread
            ))
        }
    }
}

@MainActor
private func perform(
    _ runtime: VaultAgentPreferenceRuntimeServicing,
    _ action: VaultAgentPreferenceAction
) async -> Result<VaultAgentPreferenceSnapshot, Error> {
    await withCheckedContinuation { continuation in
        runtime.perform(action) { continuation.resume(returning: $0) }
    }
}

@MainActor
private func renderPNG(_ view: NSView, to url: URL) throws {
    view.layoutSubtreeIfNeeded()
    let representation = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: representation)
    let data = try #require(representation.representation(using: .png, properties: [:]))
    try data.write(to: url, options: .atomic)
}

@MainActor
private func waitUntil(_ condition: @escaping () -> Bool) async throws {
    for _ in 0..<1_000 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(1))
    }
    throw VaultAgentErrorCode.brokerUnavailable
}
