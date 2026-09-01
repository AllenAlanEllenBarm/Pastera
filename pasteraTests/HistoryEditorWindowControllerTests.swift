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
    func successfulOptimizationRevealsCollapsedInitialOriginal() async {
        let fixture = makeFixture(outcomes: [
            .optimized(text: "Improved prompt", source: .openAICompatible)
        ])
        fixture.controller.show(historyID: fixture.historyID)

        await fixture.controller.runPromptOptimizationForTesting()

        guard let contentView = fixture.controller.window?.contentView else {
            Issue.record("History editor has no content view")
            return
        }
        let disclosure = findHistoryEditorButton(
            in: contentView,
            accessibilityLabels: ["Original comparison", "原文对照"]
        )
        #expect(disclosure != nil)
        #expect(disclosure?.isHidden == false)
        #expect(disclosure?.title.contains("Draft") == false)
        #expect(disclosure?.title.contains("5") == true)

        let originalView = findHistoryEditorTextView(
            in: contentView,
            accessibilityLabels: ["Original history text", "历史原文"]
        )
        #expect(originalView?.string == "Draft")
        #expect(originalView?.isEditable == false)
        #expect(originalView?.enclosingScrollView?.isHidden == true)
    }

    @Test
    func originalComparisonExpandsAndKeepsTheInitiallyLoadedText() async {
        let fixture = makeFixture(outcomes: [
            .optimized(text: "First improvement", source: .openAICompatible),
            .optimized(text: "Second improvement", source: .openAICompatible)
        ])
        fixture.controller.show(historyID: fixture.historyID)
        await fixture.controller.runPromptOptimizationForTesting()

        guard let contentView = fixture.controller.window?.contentView,
              let disclosure = findHistoryEditorButton(
                in: contentView,
                accessibilityLabels: ["Original comparison", "原文对照"]
              ),
              let action = disclosure.action else {
            Issue.record("Missing original comparison disclosure")
            return
        }
        #expect(NSApp.sendAction(action, to: disclosure.target, from: disclosure))
        let originalView = findHistoryEditorTextView(
            in: contentView,
            accessibilityLabels: ["Original history text", "历史原文"]
        )
        #expect(originalView?.enclosingScrollView?.isHidden == false)

        await fixture.controller.runPromptOptimizationForTesting()

        #expect(fixture.controller.draftForTesting == "Second improvement")
        #expect(originalView?.string == "Draft")
    }

    @Test
    func originalComparisonHidesWhenUndoReturnsToInitialText() async {
        let fixture = makeFixture(outcomes: [
            .optimized(text: "Improved", source: .appleFoundationModel)
        ])
        fixture.controller.show(historyID: fixture.historyID)
        await fixture.controller.runPromptOptimizationForTesting()
        fixture.controller.undoForTesting()

        guard let contentView = fixture.controller.window?.contentView else {
            Issue.record("History editor has no content view")
            return
        }
        let disclosure = findHistoryEditorButton(
            in: contentView,
            accessibilityLabels: ["Original comparison", "原文对照"]
        )
        #expect(fixture.controller.draftForTesting == "Draft")
        #expect(disclosure?.isHidden == true)
    }

    @Test
    func unchangedOptimizationDoesNotRevealOriginalComparison() async {
        let fixture = makeFixture(outcomes: [.unchanged(source: .appleFoundationModel)])
        fixture.controller.show(historyID: fixture.historyID)
        await fixture.controller.runPromptOptimizationForTesting()

        guard let contentView = fixture.controller.window?.contentView else {
            Issue.record("History editor has no content view")
            return
        }
        let disclosure = findHistoryEditorButton(
            in: contentView,
            accessibilityLabels: ["Original comparison", "原文对照"]
        )
        #expect(disclosure?.isHidden == true)
    }

    @Test
    func imageOCRUsesTheSameInitialOriginalComparison() async throws {
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 8, height: 8).fill()
        image.unlockFocus()
        let repository = EditorHistoryRepository(
            imageData: try #require(image.tiffRepresentation),
            ocrText: "Scanned draft"
        )
        let optimizer = RecordingEditorPromptOptimizationService(outcomes: [
            .optimized(text: "Improved scan", source: .openAICompatible)
        ])
        let controller = makeController(repository: repository, optimizer: optimizer)
        controller.show(historyID: repository.history.id)

        await controller.runPromptOptimizationForTesting()

        guard let contentView = controller.window?.contentView else {
            Issue.record("Image history editor has no content view")
            return
        }
        let disclosure = findHistoryEditorButton(
            in: contentView,
            accessibilityLabels: ["Original comparison", "原文对照"]
        )
        let originalView = findHistoryEditorTextView(
            in: contentView,
            accessibilityLabels: ["Original history text", "历史原文"]
        )
        #expect(disclosure?.isHidden == false)
        #expect(originalView?.string == "Scanned draft")
        #expect(controller.draftForTesting == "Improved scan")
    }

    @Test
    func originalComparisonRendersCollapsedAndExpandedInBothAppearances() async throws {
        let source = "请帮我把这个开发需求整理一下，说明目标、范围和验收标准。"
        let repository = EditorHistoryRepository(text: source)
        let optimizer = RecordingEditorPromptOptimizationService(outcomes: [
            .optimized(
                text: "请把这段需求整理成更清楚、可执行的开发任务。",
                source: .openAICompatible
            )
        ])
        let controller = makeController(repository: repository, optimizer: optimizer)
        controller.show(historyID: repository.history.id)
        await controller.runPromptOptimizationForTesting()

        let window = try #require(controller.window)
        let contentView = try #require(window.contentView)
        let disclosure = try #require(findHistoryEditorButton(
            in: contentView,
            accessibilityLabels: ["Original comparison", "原文对照"]
        ))
        window.setFrame(NSRect(x: 0, y: 0, width: 820, height: 560), display: false)

        try renderHistoryEditorStates(
            contentView,
            suffix: "collapsed",
            outputDirectoryPath: ProcessInfo.processInfo.environment["PASTERA_HISTORY_VISUAL_DIR"]
        )

        let action = try #require(disclosure.action)
        #expect(NSApp.sendAction(action, to: disclosure.target, from: disclosure))
        let originalView = try #require(findHistoryEditorTextView(
            in: contentView,
            accessibilityLabels: ["Original history text", "历史原文"]
        ))
        #expect(originalView.enclosingScrollView?.isHidden == false)
        try renderHistoryEditorStates(
            contentView,
            suffix: "expanded",
            outputDirectoryPath: ProcessInfo.processInfo.environment["PASTERA_HISTORY_VISUAL_DIR"]
        )
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
            .unchanged(source: .appleFoundationModel),
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
    func unchangedLocalFormattingDoesNotClaimThePromptNeedsNoAdjustment() async {
        let fixture = makeFixture(outcomes: [.unchanged(source: .localFormatter)])
        fixture.controller.show(historyID: fixture.historyID)

        await fixture.controller.runPromptOptimizationForTesting()

        #expect(fixture.controller.draftForTesting == "Draft")
        #expect(fixture.controller.statusForTesting.contains("错别字")
            || fixture.controller.statusForTesting.localizedCaseInsensitiveContains("typo"))
        #expect(!fixture.controller.statusForTesting.contains("无需调整"))
        #expect(!fixture.controller.statusForTesting.localizedCaseInsensitiveContains("does not need"))
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
        let controller = makeController(
            repository: repository,
            optimizer: optimizer,
            scripts: scripts,
            confirmation: confirmation
        )
        return HistoryEditorFixture(
            controller: controller,
            repository: repository,
            optimizer: optimizer as? RecordingEditorPromptOptimizationService
                ?? RecordingEditorPromptOptimizationService(outcomes: []),
            historyID: repository.history.id
        )
    }

    private func makeController(
        repository: EditorHistoryRepository,
        optimizer: any PromptOptimizationServicing,
        scripts: [ScriptTransform] = [],
        confirmation: Bool = false
    ) -> HistoryEditorWindowController {
        HistoryEditorWindowController(
            repository: repository,
            ocrIndexer: EditorOCRIndexer(),
            scriptCoordinator: EditorScriptCoordinator(scripts: scripts),
            promptOptimizationService: optimizer,
            onSaved: {},
            confirmationRunner: { _, _ in
                PasteraConfirmationResult(confirmed: confirmation, suppressionChecked: false)
            }
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

private func findHistoryEditorButton(
    in view: NSView,
    accessibilityLabels: Set<String>
) -> NSButton? {
    if let button = view as? NSButton,
       accessibilityLabels.contains(button.accessibilityLabel() ?? "") {
        return button
    }
    for subview in view.subviews {
        if let button = findHistoryEditorButton(in: subview, accessibilityLabels: accessibilityLabels) {
            return button
        }
    }
    return nil
}

private func findHistoryEditorTextView(
    in view: NSView,
    accessibilityLabels: Set<String>
) -> NSTextView? {
    if let textView = view as? NSTextView,
       accessibilityLabels.contains(textView.accessibilityLabel() ?? "") {
        return textView
    }
    for subview in view.subviews {
        if let textView = findHistoryEditorTextView(in: subview, accessibilityLabels: accessibilityLabels) {
            return textView
        }
    }
    return nil
}

@MainActor
private func renderHistoryEditorStates(
    _ view: NSView,
    suffix: String,
    outputDirectoryPath: String?
) throws {
    let appearances: [(String, NSAppearance.Name)] = [
        ("light", .aqua),
        ("dark", .darkAqua)
    ]
    for (name, appearanceName) in appearances {
        let appearance = try #require(NSAppearance(named: appearanceName))
        view.appearance = appearance
        view.wantsLayer = true
        let backgroundWhite: CGFloat = name == "light" ? 0.93 : 0.11
        view.layer?.backgroundColor = NSColor(
            calibratedWhite: backgroundWhite,
            alpha: 1
        ).cgColor
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let outputDirectoryPath else { continue }
        let outputDirectory = URL(fileURLWithPath: outputDirectoryPath, isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        let representation = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: representation)
        let data = try #require(representation.representation(using: .png, properties: [:]))
        let url = outputDirectory.appendingPathComponent(
            "pastera-history-original-\(suffix)-\(name).png"
        )
        try data.write(to: url, options: .atomic)
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
    private let ocrText: PasteboardHistoryOCRText?
    private(set) var updateCalls: [EditorHistoryUpdateCall] = []

    init(text: String) {
        let content = PasteboardContent(editorTestString: text)
        self.content = content
        ocrText = nil
        history = PasteboardHistory(
            id: PasteboardHistory.ID(rawValue: content.hash),
            title: text,
            pasteboardTypes: [.string],
            updateAt: 1,
            deviceID: nil
        )
    }

    init(imageData: Data, ocrText: String) {
        let content = PasteboardContent(assets: [PasteboardContent.Asset(type: .tiff, data: imageData)])
        self.content = content
        let historyID = PasteboardHistory.ID(rawValue: content.hash)
        self.ocrText = PasteboardHistoryOCRText(
            pasteboardHistoryID: historyID,
            sourceHash: content.hash,
            recognizedText: ocrText,
            updatedAt: 1
        )
        history = PasteboardHistory(
            id: historyID,
            title: ocrText,
            pasteboardTypes: [.tiff],
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
    func fetchOCRText(historyID: PasteboardHistory.ID) -> PasteboardHistoryOCRText? {
        historyID == history.id ? ocrText : nil
    }
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
