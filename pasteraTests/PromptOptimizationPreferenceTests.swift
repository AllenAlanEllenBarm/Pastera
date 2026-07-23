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
    func closingWindowCancelsInFlightConnectionTest() async throws {
        let service = BlockingConnectionPromptService()
        let settingsStore = PreferenceSettingsStore()
        let apiKeyStore = PreferenceAPIKeyStore(hasAPIKey: false)
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
    let service: any PromptOptimizationServicing
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
