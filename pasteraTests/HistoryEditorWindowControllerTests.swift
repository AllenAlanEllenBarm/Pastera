import AppKit
import Combine
import Testing
@testable import Pastera

@MainActor
struct HistoryEditorWindowControllerTests {
    @Test
    func openingEditorDoesNotRunOptimizer() {
        let fixture = makeFixture(outcomes: [.unchanged(source: .localFormatter)])

        fixture.controller.show(historyID: fixture.historyID)

        #expect(fixture.optimizer.optimizeCalls.isEmpty)
        #expect(fixture.controller.draftForTesting == "Draft")
    }

    @Test
    func optimizedDraftIsUndoableAndNotSavedAutomatically() async {
        let fixture = makeFixture(outcomes: [
            .optimized(text: "Improved", source: .appleFoundationModel)
        ])
        fixture.controller.show(historyID: fixture.historyID)

        await fixture.controller.runPromptOptimizationForTesting()

        #expect(fixture.controller.draftForTesting == "Improved")
        #expect(fixture.repository.updateCalls.isEmpty)
        fixture.controller.undoForTesting()
        #expect(fixture.controller.draftForTesting == "Draft")
    }

    @Test
    func promptActionComesBeforeOptionalScriptSeparatorAndScripts() {
        let scriptID = UUID()
        let fixture = makeFixture(
            outcomes: [.unchanged(source: .localFormatter)],
            scripts: [makeScript(id: scriptID, name: "Uppercase")]
        )
        fixture.controller.show(historyID: fixture.historyID)

        #expect(fixture.controller.transformationActionsForTesting == [
            .promptOptimization,
            nil,
            .script(scriptID)
        ])
    }

    @Test
    func noScriptsDoesNotAddSeparatorOrHidePromptOptimization() {
        let fixture = makeFixture(outcomes: [.unchanged(source: .localFormatter)])
        fixture.controller.show(historyID: fixture.historyID)

        #expect(fixture.controller.transformationActionsForTesting == [.promptOptimization])
    }

    @Test
    func unchangedAndFailurePreserveDraft() async {
        let fixture = makeFixture(outcomes: [
            .unchanged(source: .localFormatter),
            .failed(.requestTimedOut)
        ])
        fixture.controller.show(historyID: fixture.historyID)

        await fixture.controller.runPromptOptimizationForTesting()
        #expect(fixture.controller.draftForTesting == "Draft")
        #expect(fixture.controller.statusForTesting.contains("无需调整")
            || fixture.controller.statusForTesting.contains("does not need"))

        await fixture.controller.runPromptOptimizationForTesting()
        #expect(fixture.controller.draftForTesting == "Draft")
        #expect(fixture.controller.statusForTesting.contains("超时")
            || fixture.controller.statusForTesting.contains("timed out"))
    }

    @Test
    func remoteConsentCancellationDoesNotRetryOrChangeDraft() async {
        let fixture = makeFixture(
            outcomes: [.consentRequired(origin: "https://models.example.com")],
            confirmation: false
        )
        fixture.controller.show(historyID: fixture.historyID)

        await fixture.controller.runPromptOptimizationForTesting()

        #expect(fixture.optimizer.optimizeCalls == ["Draft"])
        #expect(fixture.optimizer.confirmedOrigins.isEmpty)
        #expect(fixture.controller.draftForTesting == "Draft")
    }

    @Test
    func remoteConsentConfirmationRetriesOnlyOnce() async {
        let fixture = makeFixture(
            outcomes: [
                .consentRequired(origin: "https://models.example.com"),
                .optimized(text: "Remote improved", source: .openAICompatible)
            ],
            confirmation: true
        )
        fixture.controller.show(historyID: fixture.historyID)

        await fixture.controller.runPromptOptimizationForTesting()

        #expect(fixture.optimizer.optimizeCalls == ["Draft", "Draft"])
        #expect(fixture.optimizer.confirmedOrigins == ["https://models.example.com"])
        #expect(fixture.controller.draftForTesting == "Remote improved")
    }

    @Test
    func duplicateRunIsPreventedAndCancellationLeavesDraftUntouched() async {
        let optimizer = SlowPromptOptimizationService()
        let fixture = makeFixture(optimizer: optimizer)
        fixture.controller.show(historyID: fixture.historyID)

        fixture.controller.startSelectedTransformationForTesting()
        fixture.controller.startSelectedTransformationForTesting()
        await optimizer.waitUntilOptimizationStarts()
        #expect(optimizer.optimizeCallCount == 1)

        fixture.controller.cancelTransformationForTesting()
        for _ in 0..<10 where fixture.controller.isRunningForTesting {
            await Task.yield()
        }
        #expect(fixture.controller.draftForTesting == "Draft")
        #expect(!fixture.controller.isRunningForTesting)
    }

    @Test
    func optimizedDraftPersistsOnlyWhenSaved() async {
        let fixture = makeFixture(outcomes: [
            .optimized(text: "Saved improvement", source: .localFormatter)
        ])
        fixture.controller.show(historyID: fixture.historyID)
        await fixture.controller.runPromptOptimizationForTesting()

        #expect(fixture.repository.updateCalls.isEmpty)
        #expect(fixture.controller.saveDraftForTesting())
        #expect(fixture.repository.updateCalls.map(\.text) == ["Saved improvement"])
    }

    private func makeFixture(
        outcomes: [PromptOptimizationOutcome],
        scripts: [ScriptTransform] = [],
        confirmation: Bool = false
    ) -> HistoryEditorFixture {
        makeFixture(
            optimizer: RecordingEditorPromptOptimizationService(outcomes: outcomes),
            scripts: scripts,
            confirmation: confirmation
        )
    }

    private func makeFixture(
        optimizer: any PromptOptimizationServicing,
        scripts: [ScriptTransform] = [],
        confirmation: Bool = false
    ) -> HistoryEditorFixture {
        let repository = EditorHistoryRepository(text: "Draft")
        let controller = HistoryEditorWindowController(
            repository: repository,
            ocrIndexer: EditorOCRIndexer(),
            scriptCoordinator: EditorScriptCoordinator(scripts: scripts),
            promptOptimizationService: optimizer,
            onSaved: {},
            confirmationRunner: { _, _ in
                PasteraConfirmationResult(confirmed: confirmation, suppressionChecked: false)
            }
        )
        return HistoryEditorFixture(
            controller: controller,
            repository: repository,
            optimizer: optimizer as? RecordingEditorPromptOptimizationService
                ?? RecordingEditorPromptOptimizationService(outcomes: []),
            historyID: repository.history.id
        )
    }

    private func makeScript(id: UUID, name: String) -> ScriptTransform {
        ScriptTransform(
            id: id,
            name: name,
            code: "function transform(clip) { return clip.text; }",
            isEnabled: true,
            runOnCopy: false,
            runOnPaste: false,
            runManually: true,
            sortIndex: 0,
            createdAt: 1,
            updatedAt: 1
        )
    }
}

@MainActor
private struct HistoryEditorFixture {
    let controller: HistoryEditorWindowController
    let repository: EditorHistoryRepository
    let optimizer: RecordingEditorPromptOptimizationService
    let historyID: PasteboardHistory.ID
}

private final class RecordingEditorPromptOptimizationService: PromptOptimizationServicing {
    var availability: PromptOptimizationAvailability = .available
    private var outcomes: [PromptOptimizationOutcome]
    private(set) var optimizeCalls: [String] = []
    private(set) var confirmedOrigins: [String] = []

    init(outcomes: [PromptOptimizationOutcome]) {
        self.outcomes = outcomes
    }

    func optimize(_ text: String) async -> PromptOptimizationOutcome {
        optimizeCalls.append(text)
        return outcomes.isEmpty ? .unchanged(source: .localFormatter) : outcomes.removeFirst()
    }

    func confirmRemoteOrigin(_ origin: String) {
        confirmedOrigins.append(origin)
    }

    func testRemoteConnection() async -> Result<Void, PromptOptimizationError> { .success(()) }
}

private final class SlowPromptOptimizationService: PromptOptimizationServicing {
    var availability: PromptOptimizationAvailability = .available
    private let lock = NSLock()
    private let optimizationStarts: AsyncStream<Void>
    private let optimizationStartsContinuation: AsyncStream<Void>.Continuation
    private var storedOptimizeCallCount = 0

    init() {
        let stream = AsyncStream<Void>.makeStream()
        optimizationStarts = stream.stream
        optimizationStartsContinuation = stream.continuation
    }

    var optimizeCallCount: Int {
        lock.withLock { storedOptimizeCallCount }
    }

    func optimize(_ text: String) async -> PromptOptimizationOutcome {
        lock.withLock { storedOptimizeCallCount += 1 }
        optimizationStartsContinuation.yield(())
        do {
            try await Task.sleep(for: .seconds(5))
            return .unchanged(source: .localFormatter)
        } catch {
            return .failed(.cancelled)
        }
    }

    func waitUntilOptimizationStarts() async {
        for await _ in optimizationStarts { return }
    }

    func confirmRemoteOrigin(_ origin: String) {}
    func testRemoteConnection() async -> Result<Void, PromptOptimizationError> { .success(()) }
}

private struct EditorHistoryUpdateCall {
    let id: PasteboardHistory.ID
    let text: String
    let updateAt: Int
}

private final class EditorHistoryRepository: PasteboardHistoryRepositoryProtocol {
    let history: PasteboardHistory
    private let content: PasteboardContent
    private(set) var updateCalls: [EditorHistoryUpdateCall] = []

    init(text: String) {
        let content = PasteboardContent(editorTestString: text)
        self.content = content
        history = PasteboardHistory(
            id: PasteboardHistory.ID(rawValue: content.hash),
            title: text,
            pasteboardTypes: [.string],
            updateAt: 1,
            deviceID: nil
        )
    }

    func observeHistories() -> AnyPublisher<[PasteboardHistory], Never> {
        Just([history]).eraseToAnyPublisher()
    }
    func hasHistories() -> Bool { true }
    func fetchHistoryDetails(
        ascending: Bool,
        includesThumbnailAsset: Bool,
        limit: Int,
        offset: Int
    ) -> [PasteboardHistoryDetail] { [] }
    func searchHistoryDetails(
        query: HistorySearchQuery,
        includesThumbnailAsset: Bool,
        limit: Int,
        offset: Int
    ) throws -> [PasteboardHistoryDetail] { [] }
    func fetchHistory(id: PasteboardHistory.ID) -> PasteboardHistory? { id == history.id ? history : nil }
    func fetchContent(id: PasteboardHistory.ID) -> PasteboardContent? { id == history.id ? content : nil }
    func save(id: PasteboardHistory.ID, content: PasteboardContent, updateAt: Int) {}
    func updateTextHistory(id: PasteboardHistory.ID, text: String, updateAt: Int) -> Bool {
        updateCalls.append(EditorHistoryUpdateCall(id: id, text: text, updateAt: updateAt))
        return true
    }
    func deleteHistory(id: PasteboardHistory.ID) {}
    func deleteAll() {}
    func deleteOverflowingHistories(maxHistorySize: Int) {}
    func pruneHistories(settings: HistoryRetentionSettings) {}
}

private struct EditorOCRIndexer: PasteboardHistoryOCRIndexing {
    func enqueueIndexing(historyID: PasteboardHistory.ID) {}
    func backfillMissingImageOCR(limit: Int) {}
    func recognizeText(
        historyID: PasteboardHistory.ID,
        content: PasteboardContent
    ) async -> Result<String, PasteboardHistoryOCRRecognitionError> {
        .failure(.unsupportedImageSource)
    }
}

private final class EditorScriptCoordinator: ClipboardScriptCoordinating {
    let scripts: [ScriptTransform]

    init(scripts: [ScriptTransform]) { self.scripts = scripts }
    func hasEnabledScripts(for trigger: ScriptTrigger) -> Bool { false }
    func availableHistoryScripts() -> [ScriptTransform] { scripts }
    func transform(
        text: String,
        sourceAppBundleIdentifier: String?,
        trigger: ScriptTrigger
    ) async -> ScriptTransformOutcome { .unchanged }
    func transformHistoryText(
        _ text: String,
        using scriptID: UUID,
        sourceAppBundleIdentifier: String?
    ) async -> ScriptTransformOutcome { .unchanged }
    func writeHistoryTransformResult(_ text: String) {}
    func runManualTransform() async {}
    func consumeSuppression(changeCount: Int) -> Bool { false }
}

private extension PasteboardContent {
    init(editorTestString: String) {
        self.init(assets: [Asset(type: .string, data: Data(editorTestString.utf8))])
    }
}
