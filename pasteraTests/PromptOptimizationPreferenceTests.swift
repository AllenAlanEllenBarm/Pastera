import AppKit
import Testing
@testable import Pastera

@MainActor
struct PromptOptimizationPreferenceTests {
    @Test
    func automaticFreeHidesRemoteFieldsAndRemoteProviderRevealsThem() {
        let fixture = makeFixture()

        #expect(!fixture.section.showsRemoteFieldsForTesting)
        fixture.section.selectProviderForTesting(.openAICompatible)
        #expect(fixture.section.showsRemoteFieldsForTesting)
    }

    @Test
    func providerPresetFillsKnownBaseURLAndCustomPreservesIt() {
        let fixture = makeFixture()
        fixture.section.selectProviderForTesting(.openAICompatible)

        fixture.section.selectPresetForTesting(.ollama)
        #expect(fixture.section.baseURLForTesting == "http://127.0.0.1:11434/v1")

        fixture.section.selectPresetForTesting(.custom)
        #expect(fixture.section.baseURLForTesting == "http://127.0.0.1:11434/v1")
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
        #expect(fixture.apiKeyStore.savedValue == "new-secret")
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
    func scriptsPanePlacesPromptOptimizationBeforeScriptManagement() {
        let fixture = makeFixture()
        let page = CPYScriptsPreferenceViewController(
            repository: PreferenceScriptRepository(),
            executor: ScriptExecutionService(),
            hotKeyService: HotKeyService(),
            promptSettingsStore: fixture.settingsStore,
            promptAPIKeyStore: fixture.apiKeyStore,
            promptOptimizationService: fixture.service
        )
        _ = page.view

        #expect(page.orderedSectionIDsForTesting.prefix(3) == [
            "scripts.promptOptimization", "scripts.list", "scripts.shortcut"
        ])
        #expect(page.promptOptimizationSectionForTesting != nil)
    }

    @Test
    func scriptsPaneRelayoutsAfterRevealingRemoteProviderFields() throws {
        let fixture = makeFixture()
        let page = CPYScriptsPreferenceViewController(
            repository: PreferenceScriptRepository(),
            executor: ScriptExecutionService(),
            hotKeyService: HotKeyService(),
            promptSettingsStore: fixture.settingsStore,
            promptAPIKeyStore: fixture.apiKeyStore,
            promptOptimizationService: fixture.service
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
        service: PreferencePromptService = PreferencePromptService()
    ) -> PreferenceFixture {
        let store = PreferenceSettingsStore()
        let keyStore = PreferenceAPIKeyStore(hasAPIKey: hasAPIKey)
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
    let service: PreferencePromptService
}

private final class PreferenceSettingsStore: PromptOptimizationSettingsStoring {
    var settings = PromptOptimizationSettings.defaultValue
    private(set) var savedSettings: [PromptOptimizationSettings] = []

    func load() -> PromptOptimizationSettings { settings }
    func save(_ settings: PromptOptimizationSettings) {
        self.settings = settings
        savedSettings.append(settings)
    }
    func confirmRemoteOrigin(_ origin: String) {
        settings.confirmedOrigins.insert(origin)
    }
}

private final class PreferenceAPIKeyStore: PromptOptimizationAPIKeyStoring {
    var containsAPIKey: Bool
    private(set) var savedValue: String?

    init(hasAPIKey: Bool) {
        self.containsAPIKey = hasAPIKey
        self.savedValue = hasAPIKey ? "secret-value" : nil
    }

    func save(_ apiKey: String) throws {
        savedValue = apiKey
        containsAPIKey = true
    }

    func load() throws -> String? { savedValue }

    func delete() throws {
        savedValue = nil
        containsAPIKey = false
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

private final class PreferenceScriptRepository: ScriptRepositoryProtocol {
    func fetchAll() throws -> [ScriptTransform] { [] }
    func fetchEnabled(for trigger: ScriptTrigger) throws -> [ScriptTransform] { [] }
    func insert(_ script: ScriptTransform) throws {}
    func update(_ script: ScriptTransform) throws {}
    func delete(id: UUID) throws {}
    func replaceOrder(ids: [UUID]) throws {}
}
