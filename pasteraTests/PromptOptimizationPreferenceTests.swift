import AppKit
import Testing
@testable import Pastera
// swiftlint:disable file_length

@MainActor
// swiftlint:disable:next type_body_length
struct PromptOptimizationPreferenceTests {
    @Test
    func profileDraftStagesAcrossSwitchesAndGeneratesUniqueNames() {
        let firstID = UUID(uuidString: "60000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "60000000-0000-0000-0000-000000000002")!
        var draft = PromptOptimizationRemoteProfileDraft(
            settings: .makeDefault(profileID: firstID)
        )
        draft.updateSelected(
            displayName: "openai",
            preset: .openAI,
            baseURL: "https://api.openai.com/v1",
            model: "gpt-5.6-luna",
            allowsInsecureHTTP: false
        )

        let addedID = draft.addProfile(preset: .openAI, id: secondID)
        #expect(draft.settings.remoteProfiles.map(\.displayName) == ["openai", "OpenAI 2"])
        draft.updateSelected(
            displayName: "Gateway",
            preset: .custom,
            baseURL: "https://aigateway.variflight.com/api",
            model: "aliyun/deepseek-v4-flash-0731",
            allowsInsecureHTTP: false
        )
        draft.selectProfile(id: firstID)

        #expect(addedID == secondID)
        #expect(draft.selectedProfile?.displayName == "openai")
        draft.selectProfile(id: secondID)
        #expect(draft.selectedProfile?.model == "aliyun/deepseek-v4-flash-0731")
        #expect(!draft.isPersisted(secondID))
        draft.markSaved()
        #expect(draft.isPersisted(secondID))
        draft.setProvider(.openAICompatible)

        let snapshot = draft.snapshot()

        #expect(snapshot.provider == .openAICompatible)
        #expect(snapshot.activeRemoteProfileID == secondID)
        draft.removeOrResetSelectedProfile()
        #expect(draft.selectedProfileID == firstID)
        #expect(draft.settings.remoteProfiles.count == 1)
    }

    @Test
    func lastProfileRemovalResetsItWithoutChangingItsID() {
        let id = UUID(uuidString: "60000000-0000-0000-0000-000000000003")!
        var draft = PromptOptimizationRemoteProfileDraft(settings: .makeDefault(profileID: id))
        draft.updateSelected(
            displayName: "Gateway",
            preset: .custom,
            baseURL: "https://aigateway.variflight.com/api",
            model: "aliyun/deepseek-v4-flash-0731",
            allowsInsecureHTTP: false
        )

        draft.removeOrResetSelectedProfile()

        #expect(draft.settings.remoteProfiles.count == 1)
        #expect(draft.selectedProfile?.id == id)
        #expect(draft.selectedProfile?.preset == .openAI)
        #expect(draft.selectedProfile?.model == "gpt-5.6-luna")
    }

    @Test
    func selectingProfilePreservesCustomFieldsUntilPresetDefaultsAreApplied() {
        let firstID = UUID(uuidString: "60000000-0000-0000-0000-000000000004")!
        let secondID = UUID(uuidString: "60000000-0000-0000-0000-000000000005")!
        var draft = PromptOptimizationRemoteProfileDraft(
            settings: .makeDefault(profileID: firstID)
        )

        draft.addProfile(preset: .ollama, id: secondID)
        draft.updateSelected(
            displayName: "Local Gateway",
            preset: .ollama,
            baseURL: "https://staged.example.invalid/api",
            model: "staged-model",
            allowsInsecureHTTP: false
        )
        draft.selectProfile(id: firstID)
        draft.selectProfile(id: secondID)

        #expect(draft.selectedProfile?.baseURL == "https://staged.example.invalid/api")
        #expect(draft.selectedProfile?.model == "staged-model")

        draft.applyPresetDefaults()

        #expect(draft.selectedProfile?.baseURL == "http://127.0.0.1:11434/v1")
        #expect(draft.selectedProfile?.model == "qwen2.5:7b-instruct")
    }

    @Test
    func automaticFreeHidesRemoteFieldsAndRemoteProviderRevealsThem() {
        let fixture = makeFixture()

        #expect(!fixture.section.showsRemoteFieldsForTesting)
        fixture.section.selectProviderForTesting(.openAICompatible)
        #expect(fixture.section.showsRemoteFieldsForTesting)
    }

    @Test
    func automaticFreeExplainsTypoLimitationWhenOnlyLocalFormattingIsAvailable() {
        let service = PreferencePromptService()
        service.availability = .unavailable(.deviceNotEligible)

        let fixture = makeFixture(service: service)
        let visibleText = allText(in: fixture.section).joined(separator: "\n")

        #expect(visibleText.contains("错别字")
            || visibleText.localizedCaseInsensitiveContains("typo"))
        #expect(visibleText.contains("本地")
            || visibleText.localizedCaseInsensitiveContains("local"))
    }

    @Test
    func presetSelectionPreservesCustomFieldsUntilDefaultsAreApplied() {
        let fixture = makeFixture()
        fixture.section.selectProviderForTesting(.openAICompatible)
        fixture.section.setProfileFieldsForTesting(
            name: "Gateway",
            baseURL: "https://aigateway.variflight.com/api",
            model: "aliyun/deepseek-v4-flash-0731"
        )

        fixture.section.selectPresetForTesting(.ollama)
        #expect(fixture.section.baseURLForTesting == "https://aigateway.variflight.com/api")
        #expect(fixture.section.modelForTesting == "aliyun/deepseek-v4-flash-0731")

        fixture.section.applyPresetDefaultsForTesting()

        #expect(fixture.section.baseURLForTesting == "http://127.0.0.1:11434/v1")
        #expect(fixture.section.modelForTesting == "qwen2.5:7b-instruct")
    }

    @Test
    func switchingProfilesPreservesDraftFieldsAndShowsTheSelectedKeyStatus() {
        let fixture = makeFixture()
        fixture.section.selectProviderForTesting(.openAICompatible)
        let firstID = fixture.section.activeProfileIDForTesting
        fixture.section.setProfileFieldsForTesting(
            name: "OpenAI Work",
            baseURL: "https://api.openai.com/v1",
            model: "gpt-5.6-luna"
        )
        let gatewayID = fixture.section.addProfileForTesting(preset: .custom)
        fixture.section.setProfileFieldsForTesting(
            name: "Gateway",
            baseURL: "https://aigateway.variflight.com/api",
            model: "aliyun/deepseek-v4-flash-0731"
        )
        fixture.apiKeyStore.values[firstID] = "first-fake-key"

        fixture.section.selectProfileForTesting(firstID)

        #expect(gatewayID != firstID)
        #expect(fixture.section.profileNameForTesting == "OpenAI Work")
        #expect(fixture.section.modelForTesting == "gpt-5.6-luna")
        #expect(fixture.section.activeProfileIDForTesting == firstID)
        #expect(fixture.apiKeyStore.loadedProfileIDs.last == firstID)
        #expect(fixture.section.credentialStatusForTesting.contains("saved")
            || fixture.section.credentialStatusForTesting.contains("保存"))
        #expect(!fixture.section.credentialStatusForTesting.contains("first-fake-key"))
    }

    @Test
    func savingCustomGatewayPersistsExactPathModelAndSelectedProfile() {
        let fixture = makeFixture()
        fixture.section.selectProviderForTesting(.openAICompatible)
        let gatewayID = fixture.section.addProfileForTesting(preset: .custom)
        fixture.section.setProfileFieldsForTesting(
            name: "Gateway",
            baseURL: "https://aigateway.variflight.com/api",
            model: "aliyun/deepseek-v4-flash-0731"
        )

        #expect(fixture.section.saveSettingsForTesting())

        #expect(fixture.settingsStore.settings.activeRemoteProfileID == gatewayID)
        #expect(fixture.settingsStore.settings.activeRemoteProfile?.baseURL
            == "https://aigateway.variflight.com/api")
        #expect(fixture.settingsStore.settings.activeRemoteProfile?.model
            == "aliyun/deepseek-v4-flash-0731")
    }

    @Test
    func failedKeyDeletionKeepsTheProfileVisible() {
        let fixture = makeFixture(hasAPIKey: true)
        fixture.section.selectProviderForTesting(.openAICompatible)
        let profileID = fixture.section.activeProfileIDForTesting
        fixture.apiKeyStore.deleteFailures.insert(profileID)

        fixture.section.deleteSelectedProfileForTesting(confirmed: true)

        #expect(fixture.settingsStore.settings.remoteProfiles.contains { $0.id == profileID })
        #expect(fixture.apiKeyStore.values[profileID] == "secret-value")
        #expect(fixture.section.statusForTesting.contains("Unable")
            || fixture.section.statusForTesting.contains("无法"))
    }

    @Test
    func unsavedProfileCannotUseStandaloneSaveKeyAction() {
        let fixture = makeFixture()
        fixture.section.selectProviderForTesting(.openAICompatible)
        let unsavedID = fixture.section.addProfileForTesting(preset: .custom)
        fixture.section.setAPIKeyForTesting("unsaved-fake-key")

        #expect(!fixture.section.saveAPIKeyEnabledForTesting)
        #expect(!fixture.section.saveAPIKeyForTesting())
        #expect(fixture.apiKeyStore.values[unsavedID] == nil)
        #expect(!fixture.section.statusForTesting.contains("unsaved-fake-key"))
    }

    @Test
    func credentialStatusUsesTheSelectedProfileUUID() {
        let fixture = makeFixture(hasAPIKey: true)
        fixture.section.selectProviderForTesting(.openAICompatible)
        let firstID = fixture.section.activeProfileIDForTesting
        let secondID = fixture.section.addProfileForTesting(preset: .custom)

        #expect(fixture.apiKeyStore.loadedProfileIDs.last == secondID)
        #expect(fixture.section.credentialStatusForTesting.contains("No key")
            || fixture.section.credentialStatusForTesting.contains("未保存"))

        fixture.section.selectProfileForTesting(firstID)

        #expect(fixture.apiKeyStore.loadedProfileIDs.last == firstID)
        #expect(fixture.section.credentialStatusForTesting.contains("saved")
            || fixture.section.credentialStatusForTesting.contains("保存"))
    }

    @Test
    func deletingOnlyProfileDeletesItsKeyThenResetsTheSameProfile() {
        let fixture = makeFixture(hasAPIKey: true)
        fixture.section.selectProviderForTesting(.openAICompatible)
        let profileID = fixture.section.activeProfileIDForTesting
        fixture.section.setProfileFieldsForTesting(
            name: "Gateway",
            baseURL: "https://aigateway.variflight.com/api",
            model: "aliyun/deepseek-v4-flash-0731"
        )

        fixture.section.deleteSelectedProfileForTesting(confirmed: true)

        #expect(fixture.apiKeyStore.values[profileID] == nil)
        #expect(fixture.settingsStore.settings.remoteProfiles.count == 1)
        #expect(fixture.settingsStore.settings.activeRemoteProfileID == profileID)
        #expect(fixture.settingsStore.settings.activeRemoteProfile?.preset == .openAI)
        #expect(fixture.settingsStore.settings.activeRemoteProfile?.model == "gpt-5.6-luna")
    }

    @Test
    func compatibleProviderRequiresModelBeforeSaving() {
        let fixture = makeFixture()
        fixture.section.selectProviderForTesting(.openAICompatible)
        fixture.section.setRemoteFieldsForTesting(
            baseURL: "https://api.example.com/v1",
            model: ""
        )

        #expect(!fixture.section.saveSettingsForTesting())
        #expect(fixture.section.modelValidationForTesting?.contains("Model") == true
            || fixture.section.modelValidationForTesting?.contains("模型") == true)
        #expect(fixture.settingsStore.savedSettings.isEmpty)
    }

    @Test
    func compatibleProviderRejectsUnapprovedNonLoopbackHTTP() {
        let fixture = makeFixture()
        fixture.section.selectProviderForTesting(.openAICompatible)
        fixture.section.setRemoteFieldsForTesting(baseURL: "http://model.internal/v1", model: "private-model")

        #expect(!fixture.section.saveSettingsForTesting())
        #expect(fixture.section.modelValidationForTesting != nil)
    }

    @Test
    func keyStatusNeverExposesSavedSecret() {
        let fixture = makeFixture(hasAPIKey: true)

        #expect(fixture.section.credentialStatusForTesting.contains("saved")
            || fixture.section.credentialStatusForTesting.contains("保存"))
        #expect(!fixture.section.credentialStatusForTesting.contains("secret-value"))
    }

    @Test
    func savingSettingsAlsoStoresANewAPIKeyWithoutReadingItBack() {
        let fixture = makeFixture()
        fixture.section.selectProviderForTesting(.openAICompatible)
        fixture.section.setRemoteFieldsForTesting(
            baseURL: "https://api.example.com/v1",
            model: "compatible-model"
        )
        fixture.section.setAPIKeyForTesting("new-secret")

        #expect(fixture.section.saveSettingsForTesting())
        #expect(
            fixture.apiKeyStore.apiKey(for: fixture.settingsStore.settings.activeRemoteProfileID)
                == "new-secret"
        )
        #expect(!fixture.section.credentialStatusForTesting.contains("new-secret"))
    }

    @Test
    func connectionTestUsesServiceAndReportsSuccess() async {
        let service = PreferencePromptService(testResult: .success(()))
        let fixture = makeFixture(service: service)
        fixture.section.selectProviderForTesting(.openAICompatible)
        fixture.section.setRemoteFieldsForTesting(
            baseURL: "https://api.example.com/v1",
            model: "compatible-model"
        )

        await fixture.section.testConnectionForTesting()

        #expect(service.testCalls == 1)
        #expect(fixture.section.statusForTesting.contains("successful")
            || fixture.section.statusForTesting.contains("成功"))
    }

    @Test
    func closingWindowCancelsInFlightConnectionTest() async throws {
        let service = BlockingConnectionPromptService()
        let settingsStore = PreferenceSettingsStore()
        let apiKeyStore = PreferenceAPIKeyStore(
            hasAPIKey: false,
            profileID: settingsStore.settings.activeRemoteProfileID
        )
        let promptPage = CPYPromptOptimizationPreferenceViewController(
            settingsStore: settingsStore,
            apiKeyStore: apiKeyStore,
            optimizationService: service
        )
        let controller = CPYPreferencesWindowController(
            catalog: .default,
            pageControllerProvider: { paneID in
                if paneID == .promptOptimization { return promptPage }
                return PasteraPreferencePageViewController(paneID: paneID, title: paneID.rawValue)
            },
            reduceMotion: { true },
            frameAutosaveName: "PromptOptimizationPreferenceTests.\(UUID().uuidString)",
            applicationWindows: { [] },
            deactivateApplication: {}
        )
        controller.showPreferencePaneForTesting(paneID: .promptOptimization)
        let section = try #require(promptPage.promptOptimizationSectionForTesting)
        section.selectProviderForTesting(.openAICompatible)
        section.setRemoteFieldsForTesting(
            baseURL: "https://api.example.com/v1",
            model: "compatible-model"
        )
        let window = try #require(controller.window)
        defer {
            service.completeConnectionTest()
            controller.close()
        }

        let testButton = try #require(findButton(
            in: section,
            titles: ["Test Connection", "测试连接"]
        ))
        testButton.performClick(nil)
        await service.waitUntilConnectionTestStarts()
        #expect(!testButton.isEnabled)

        window.close()

        #expect(section.window === window)
        #expect(await service.waitUntilConnectionTestIsCancelled())
        #expect(testButton.isEnabled)
    }

    @Test
    func promptOptimizationPaneOwnsConfiguration() throws {
        let fixture = makeFixture()
        let page = CPYPromptOptimizationPreferenceViewController(
            settingsStore: fixture.settingsStore,
            apiKeyStore: fixture.apiKeyStore,
            optimizationService: fixture.service
        )
        _ = page.view

        #expect(page.paneID == .promptOptimization)
        #expect(page.revealSetting(
            anchorID: "promptOptimization.configuration",
            animated: false
        ))
        #expect(page.promptOptimizationSectionForTesting != nil)
    }

    @Test
    func promptOptimizationPaneRelayoutsAfterRevealingRemoteProviderFields() throws {
        let fixture = makeFixture()
        let page = CPYPromptOptimizationPreferenceViewController(
            settingsStore: fixture.settingsStore,
            apiKeyStore: fixture.apiKeyStore,
            optimizationService: fixture.service
        )
        _ = page.view
        let freeHeight = page.view.frame.height

        let section = try #require(page.promptOptimizationSectionForTesting)
        section.selectProviderForTesting(.openAICompatible)

        #expect(page.view.frame.height > freeHeight)
        #expect(page.view.frame.height >= page.view.fittingSize.height - 1)
    }

    private func makeFixture(
        hasAPIKey: Bool = false,
        service: any PromptOptimizationServicing = PreferencePromptService()
    ) -> PreferenceFixture {
        let store = PreferenceSettingsStore()
        let keyStore = PreferenceAPIKeyStore(
            hasAPIKey: hasAPIKey,
            profileID: store.settings.activeRemoteProfileID
        )
        let section = PromptOptimizationPreferenceSection(
            settingsStore: store,
            apiKeyStore: keyStore,
            optimizationService: service
        )
        return PreferenceFixture(
            section: section,
            settingsStore: store,
            apiKeyStore: keyStore,
            service: service
        )
    }
}

@MainActor
private struct PreferenceFixture {
    let section: PromptOptimizationPreferenceSection
    let settingsStore: PreferenceSettingsStore
    let apiKeyStore: PreferenceAPIKeyStore
    let service: any PromptOptimizationServicing
}

private final class PreferenceSettingsStore: PromptOptimizationSettingsStoring {
    var settings = PromptOptimizationSettings.defaultValue
    var pendingLegacyCredentialProfileID: UUID?
    private(set) var savedSettings: [PromptOptimizationSettings] = []

    func load() -> PromptOptimizationSettings { settings }
    func save(_ settings: PromptOptimizationSettings) {
        self.settings = settings
        savedSettings.append(settings)
    }
    func confirmRemoteOrigin(_ origin: String) {
        settings.confirmedOrigins.insert(origin)
    }

    func completeLegacyCredentialMigration(for profileID: UUID) {
        guard pendingLegacyCredentialProfileID == profileID else { return }
        pendingLegacyCredentialProfileID = nil
    }
}

private final class PreferenceAPIKeyStore: PromptOptimizationAPIKeyStoring {
    var values: [UUID: String] = [:]
    private(set) var loadedProfileIDs: [UUID] = []
    var deleteFailures: Set<UUID> = []

    init(hasAPIKey: Bool, profileID: UUID) {
        if hasAPIKey {
            values[profileID] = "secret-value"
        }
    }

    func containsAPIKey(for profileID: UUID) -> Bool {
        loadedProfileIDs.append(profileID)
        return values[profileID] != nil
    }

    func save(_ apiKey: String, for profileID: UUID) throws {
        values[profileID] = apiKey
    }

    func load(for profileID: UUID) throws -> String? {
        loadedProfileIDs.append(profileID)
        return values[profileID]
    }

    func delete(for profileID: UUID) throws {
        guard !deleteFailures.contains(profileID) else {
            throw PromptOptimizationError.keychainUnavailable
        }
        values[profileID] = nil
    }

    func migrateLegacyAPIKeyIfNeeded(to profileID: UUID) throws {}

    func apiKey(for profileID: UUID) -> String? {
        values[profileID]
    }
}

private final class PreferencePromptService: PromptOptimizationServicing {
    var availability: PromptOptimizationAvailability = .available
    var testResult: Result<Void, PromptOptimizationError>
    private(set) var testCalls = 0
    private(set) var confirmedOrigins: [String] = []

    init(testResult: Result<Void, PromptOptimizationError> = .success(())) {
        self.testResult = testResult
    }

    func optimize(_ text: String) async -> PromptOptimizationOutcome {
        .unchanged(source: .localFormatter)
    }

    func confirmRemoteOrigin(_ origin: String) {
        confirmedOrigins.append(origin)
    }

    func testRemoteConnection() async -> Result<Void, PromptOptimizationError> {
        testCalls += 1
        return testResult
    }
}

private final class BlockingConnectionPromptService: PromptOptimizationServicing {
    var availability: PromptOptimizationAvailability = .available
    private let lock = NSLock()
    private let completionStream: AsyncStream<Void>
    private let completionContinuation: AsyncStream<Void>.Continuation
    private var started = false
    private var cancellationObserved = false

    init() {
        let stream = AsyncStream<Void>.makeStream()
        completionStream = stream.stream
        completionContinuation = stream.continuation
    }

    var didStartConnectionTest: Bool {
        lock.withLock { started }
    }

    var didObserveCancellation: Bool {
        lock.withLock { cancellationObserved }
    }

    func optimize(_ text: String) async -> PromptOptimizationOutcome {
        .unchanged(source: .localFormatter)
    }

    func confirmRemoteOrigin(_ origin: String) {}

    func testRemoteConnection() async -> Result<Void, PromptOptimizationError> {
        lock.withLock { started = true }
        return await withTaskCancellationHandler {
            for await _ in completionStream {
                return Task.isCancelled ? .failure(.cancelled) : .success(())
            }
            return .failure(.cancelled)
        } onCancel: { [weak self] in
            guard let self else { return }
            self.lock.withLock { self.cancellationObserved = true }
            self.completionContinuation.yield(())
        }
    }

    func waitUntilConnectionTestStarts() async {
        for _ in 0..<100 {
            if didStartConnectionTest { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("connection test did not start")
    }

    func waitUntilConnectionTestIsCancelled() async -> Bool {
        for _ in 0..<100 {
            if didObserveCancellation { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    func completeConnectionTest() {
        completionContinuation.yield(())
    }
}

private func findButton(in view: NSView, titles: Set<String>) -> NSButton? {
    if let button = view as? NSButton, titles.contains(button.title) {
        return button
    }
    for subview in view.subviews {
        if let button = findButton(in: subview, titles: titles) {
            return button
        }
    }
    return nil
}

private func allText(in view: NSView) -> [String] {
    var result = (view as? NSTextField).map { [$0.stringValue] } ?? []
    for subview in view.subviews {
        result.append(contentsOf: allText(in: subview))
    }
    return result
}
