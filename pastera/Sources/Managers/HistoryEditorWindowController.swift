import AppKit
// swiftlint:disable file_length

enum HistoryTextTransformationAction: Equatable {
    case promptOptimization
    case script(UUID)
}

final class HistoryEditorWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    private enum Mode {
        case text
        case image
    }

    private let repository: any PasteboardHistoryRepositoryProtocol
    nonisolated(unsafe) private let ocrIndexer: any PasteboardHistoryOCRIndexing
    nonisolated(unsafe) private let scriptCoordinator: any ClipboardScriptCoordinating
    nonisolated(unsafe) private let promptOptimizationService: any PromptOptimizationServicing
    private let onSaved: () -> Void
    private let confirmationRunner: (PasteraConfirmationOptions, NSWindow?) -> PasteraConfirmationResult

    private let metadataLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let typeIconView = NSImageView()
    private let textView = NSTextView()
    private let imageView = NSImageView()
    private let imageScrollView = NSScrollView()
    private let scriptPopup = NSPopUpButton()
    private let runButton = NSButton()
    private let automationIconView = NSImageView()
    private let automationSurface = NSView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private let saveButton = NSButton()
    private var contentContainer = NSView()

    private var historyID: PasteboardHistory.ID?
    private var mode: Mode = .text
    private var originalText = ""
    private var operationID = UUID()
    private var isRunning = false
    private var transformationTask: Task<Void, Never>?
    private var loadingFeedbackWorkItem: DispatchWorkItem?

    init(
        repository: any PasteboardHistoryRepositoryProtocol,
        ocrIndexer: any PasteboardHistoryOCRIndexing,
        scriptCoordinator: any ClipboardScriptCoordinating,
        promptOptimizationService: any PromptOptimizationServicing,
        onSaved: @escaping () -> Void,
        confirmationRunner: @escaping (PasteraConfirmationOptions, NSWindow?) -> PasteraConfirmationResult = {
            PasteraConfirmationController.runModal(options: $0, sourceWindow: $1)
        }
    ) {
        self.repository = repository
        self.ocrIndexer = ocrIndexer
        self.scriptCoordinator = scriptCoordinator
        self.promptOptimizationService = promptOptimizationService
        self.onSaved = onSaved
        self.confirmationRunner = confirmationRunner
        super.init(window: nil)
        configureWindow()
    }

    required init?(coder: NSCoder) { nil }

    func show(historyID requestedID: PasteboardHistory.ID) {
        guard requestedID != historyID else {
            showWindow(nil)
            window?.makeKeyAndOrderFront(nil)
            return
        }
        guard confirmReplacingDirtyDraftIfNeeded() else { return }
        load(historyID: requestedID)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        confirmReplacingDirtyDraftIfNeeded()
    }

    func windowWillClose(_ notification: Notification) {
        cancelTransformation()
        operationID = UUID()
        isRunning = false
        historyID = nil
        originalText = ""
        textView.string = ""
        imageView.image = nil
        statusLabel.stringValue = ""
    }

    func textDidChange(_ notification: Notification) {
        if !isRunning {
            statusLabel.textColor = .secondaryLabelColor
            statusLabel.stringValue = mode == .image && !textView.string.isEmpty
                ? historyEditorString("OCR draft edited", "OCR 草稿已编辑")
                : ""
            configureRunButtonForSelectedTransformation()
        }
        updateControls()
    }

    private func configureWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = historyEditorString("History Detail", "历史详情")
        window.minSize = NSSize(width: 620, height: 420)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
    }

    private func load(historyID: PasteboardHistory.ID) {
        guard let history = repository.fetchHistory(id: historyID),
              let content = repository.fetchContent(id: historyID) else {
            showError(historyEditorString("Unable to load this history item.", "无法加载此历史条目。"))
            return
        }
        cancelTransformation()
        operationID = UUID()
        isRunning = false
        self.historyID = historyID
        statusLabel.stringValue = ""

        let imageSource = PasteboardHistoryOCRIndexer.imageSource(from: content)
        if let imageSource, let image = NSImage(data: imageSource.data) {
            mode = .image
            configureHeader(for: history, isImage: true)
            originalText = repository.fetchOCRText(historyID: historyID)?.recognizedText ?? ""
            textView.string = originalText
            imageView.image = image
            imageView.frame.size = image.size
            buildContent(showsImage: true)
            if originalText.isEmpty {
                recognize(content: content)
            }
        } else {
            mode = .text
            configureHeader(for: history, isImage: false)
            originalText = content.stringValue
            textView.string = originalText
            imageView.image = nil
            buildContent(showsImage: false)
        }
        reloadTransformations()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(textView)
        updateControls()
    }

}

private extension HistoryEditorWindowController {
    func buildContent(showsImage: Bool) {
        guard let window else { return }
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        metadataLabel.font = .systemFont(ofSize: 12)
        metadataLabel.textColor = .secondaryLabelColor
        metadataLabel.lineBreakMode = .byTruncatingTail
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .labelColor

        contentContainer.removeFromSuperview()
        contentContainer = showsImage ? makeImageEditor() : makeTextEditor()
        let header = makeHeader()
        let footer = makeFooter()
        [header, contentContainer, footer].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview($0)
        }
        window.contentView = root
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            header.heightAnchor.constraint(equalToConstant: 42),
            contentContainer.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            contentContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            contentContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            footer.topAnchor.constraint(equalTo: contentContainer.bottomAnchor, constant: 10),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            footer.heightAnchor.constraint(equalToConstant: 38)
        ])
    }

    private func makeHeader() -> NSView {
        let iconBackground = NSView()
        iconBackground.wantsLayer = true
        iconBackground.layer?.cornerRadius = 9
        iconBackground.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        typeIconView.contentTintColor = .controlAccentColor
        typeIconView.imageScaling = .scaleProportionallyDown
        typeIconView.translatesAutoresizingMaskIntoConstraints = false
        iconBackground.addSubview(typeIconView)
        NSLayoutConstraint.activate([
            iconBackground.widthAnchor.constraint(equalToConstant: 38),
            iconBackground.heightAnchor.constraint(equalToConstant: 38),
            typeIconView.widthAnchor.constraint(equalToConstant: 18),
            typeIconView.heightAnchor.constraint(equalToConstant: 18),
            typeIconView.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            typeIconView.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor)
        ])

        let labels = NSStackView(views: [titleLabel, metadataLabel])
        labels.orientation = .vertical
        labels.spacing = 3
        labels.alignment = .leading
        let header = NSStackView(views: [iconBackground, labels])
        header.orientation = .horizontal
        header.spacing = 12
        header.alignment = .centerY
        return header
    }

    private func makeTextEditor() -> NSView {
        makeEditorSurface(containing: makeTextScrollView())
    }

    private func makeImageEditor() -> NSView {
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        imageScrollView.hasVerticalScroller = true
        imageScrollView.hasHorizontalScroller = true
        imageScrollView.allowsMagnification = true
        imageScrollView.minMagnification = 0.25
        imageScrollView.maxMagnification = 4
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageScrollView.documentView = imageView

        let textScrollView = makeTextScrollView()
        let imagePane = makeImagePreviewPane()
        let textPane = makeEditorPane(
            title: historyEditorString("OCR Text", "OCR 文本"),
            content: textScrollView
        )
        splitView.addArrangedSubview(imagePane)
        splitView.addArrangedSubview(textPane)
        imagePane.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        textPane.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        let balancedColumns = imagePane.widthAnchor.constraint(equalTo: textPane.widthAnchor)
        balancedColumns.priority = .defaultHigh
        balancedColumns.isActive = true
        return makeEditorSurface(containing: splitView)
    }

    private func makeImagePreviewPane() -> NSView {
        let fitButton = NSButton(
            image: NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: nil)!,
            target: self,
            action: #selector(fitImageToWindow)
        )
        fitButton.toolTip = historyEditorString("Fit to window", "适应窗口")
        fitButton.setAccessibilityLabel(fitButton.toolTip!)
        let zoomOutButton = NSButton(
            image: NSImage(systemSymbolName: "minus", accessibilityDescription: nil)!,
            target: self,
            action: #selector(zoomImageOut)
        )
        zoomOutButton.toolTip = historyEditorString("Zoom out", "缩小")
        zoomOutButton.setAccessibilityLabel(zoomOutButton.toolTip!)
        let zoomInButton = NSButton(
            image: NSImage(systemSymbolName: "plus", accessibilityDescription: nil)!,
            target: self,
            action: #selector(zoomImageIn)
        )
        zoomInButton.toolTip = historyEditorString("Zoom in", "放大")
        zoomInButton.setAccessibilityLabel(zoomInButton.toolTip!)
        [fitButton, zoomOutButton, zoomInButton].forEach {
            $0.bezelStyle = .inline
            $0.isBordered = false
            $0.contentTintColor = .secondaryLabelColor
            $0.widthAnchor.constraint(equalToConstant: 26).isActive = true
        }
        let controls = NSStackView(views: [fitButton, zoomOutButton, zoomInButton])
        controls.orientation = .horizontal
        controls.spacing = 2
        return makeEditorPane(
            title: historyEditorString("Preview", "图片预览"),
            controls: controls,
            content: imageScrollView
        )
    }

    private func makeEditorPane(title: String, controls: NSView? = nil, content: NSView) -> NSView {
        let pane = NSView()
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        let header = NSStackView(views: controls.map { [titleLabel, $0] } ?? [titleLabel])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.distribution = .fill
        header.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(header)
        pane.addSubview(content)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: pane.topAnchor),
            header.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -8),
            header.heightAnchor.constraint(equalToConstant: 34),
            content.topAnchor.constraint(equalTo: header.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: pane.bottomAnchor)
        ])
        return pane
    }

    @objc private func fitImageToWindow() {
        guard let image = imageView.image else { return }
        let viewport = imageScrollView.contentSize
        guard image.size.width > 0, image.size.height > 0, viewport.width > 0, viewport.height > 0 else { return }
        let magnification = min(viewport.width / image.size.width, viewport.height / image.size.height)
        imageScrollView.setMagnification(
            min(imageScrollView.maxMagnification, max(imageScrollView.minMagnification, magnification)),
            centeredAt: NSPoint(x: image.size.width / 2, y: image.size.height / 2)
        )
    }

    @objc private func zoomImageOut() {
        imageScrollView.magnification = max(imageScrollView.minMagnification, imageScrollView.magnification - 0.25)
    }

    @objc private func zoomImageIn() {
        imageScrollView.magnification = min(imageScrollView.maxMagnification, imageScrollView.magnification + 0.25)
    }

    private func makeEditorSurface(containing content: NSView) -> NSView {
        let surface = NSView()
        surface.wantsLayer = true
        surface.layer?.cornerRadius = 10
        surface.layer?.borderWidth = 1
        surface.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        surface.layer?.masksToBounds = true
        content.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: surface.topAnchor),
            content.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: surface.bottomAnchor)
        ])
        return surface
    }

    private func makeTextScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.delegate = self
        textView.setAccessibilityLabel(historyEditorString("History text", "历史文本"))
        scrollView.documentView = textView
        return scrollView
    }

    private func makeFooter() -> NSView {
        let footer = NSView()
        scriptPopup.setAccessibilityLabel(historyEditorString("Text transformation", "文本转换"))
        scriptPopup.target = self
        scriptPopup.action = #selector(transformationSelectionChanged(_:))

        configureRunButtonForSelectedTransformation()
        runButton.imagePosition = .imageOnly
        runButton.bezelStyle = .circular
        runButton.bezelColor = .controlAccentColor
        runButton.target = self
        runButton.action = #selector(runSelectedTransformation)
        runButton.keyEquivalent = "\r"
        runButton.keyEquivalentModifierMask = [.command]

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        let cancelButton = NSButton(
            title: historyEditorString("Cancel", "取消"),
            target: self,
            action: #selector(cancel)
        )
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"

        saveButton.title = historyEditorString("Save", "保存")
        saveButton.bezelStyle = .rounded
        saveButton.bezelColor = .controlAccentColor
        saveButton.keyEquivalent = "s"
        saveButton.keyEquivalentModifierMask = [.command]
        saveButton.target = self
        saveButton.action = #selector(save)

        countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        countLabel.textColor = .tertiaryLabelColor
        countLabel.alignment = .right

        automationIconView.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)
        automationIconView.contentTintColor = .secondaryLabelColor
        automationIconView.setAccessibilityLabel(historyEditorString("Automation", "自动化"))

        let automationStack = NSStackView(views: [automationIconView, scriptPopup, runButton])
        automationStack.orientation = .horizontal
        automationStack.spacing = 7
        automationStack.alignment = .centerY
        automationStack.translatesAutoresizingMaskIntoConstraints = false

        automationSurface.wantsLayer = true
        automationSurface.layer?.backgroundColor = NSColor.clear.cgColor
        automationSurface.layer?.borderWidth = 0
        automationSurface.addSubview(automationStack)
        NSLayoutConstraint.activate([
            automationStack.leadingAnchor.constraint(equalTo: automationSurface.leadingAnchor, constant: 10),
            automationStack.trailingAnchor.constraint(equalTo: automationSurface.trailingAnchor, constant: -5),
            automationStack.centerYAnchor.constraint(equalTo: automationSurface.centerYAnchor),
            automationIconView.widthAnchor.constraint(equalToConstant: 16),
            automationIconView.heightAnchor.constraint(equalToConstant: 16),
            automationSurface.heightAnchor.constraint(equalToConstant: 34)
        ])

        let stack = NSStackView(views: [automationSurface, statusLabel, countLabel, cancelButton, saveButton])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.distribution = .fill
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        stack.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            automationSurface.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
            automationSurface.widthAnchor.constraint(lessThanOrEqualToConstant: 390),
            scriptPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 170),
            runButton.widthAnchor.constraint(equalToConstant: 30),
            runButton.heightAnchor.constraint(equalToConstant: 30)
        ])
        return footer
    }

    private func reloadTransformations() {
        scriptPopup.removeAllItems()
        scriptPopup.addItem(withTitle: promptOptimizationService.availability.displayName)
        scriptPopup.lastItem?.representedObject = HistoryTextTransformationAction.promptOptimization

        let scripts = scriptCoordinator.availableHistoryScripts()
        if !scripts.isEmpty {
            scriptPopup.menu?.addItem(.separator())
            scripts.forEach { script in
                scriptPopup.addItem(withTitle: script.name)
                scriptPopup.lastItem?.representedObject = HistoryTextTransformationAction.script(script.id)
            }
        }
        scriptPopup.selectItem(at: 0)
        configureRunButtonForSelectedTransformation()
    }

    private func recognize(content: PasteboardContent) {
        guard let historyID else { return }
        cancelTransformation()
        let requestID = UUID()
        operationID = requestID
        isRunning = true
        configureRunButton(
            symbol: "hourglass",
            label: historyEditorString("Running script", "正在运行脚本")
        )
        statusLabel.stringValue = historyEditorString("Recognizing text...", "正在识别文字...")
        updateControls()
        Task { [weak self] in
            guard let self else { return }
            let result = await recognizeText(historyID: historyID, content: content)
            guard operationID == requestID, self.historyID == historyID else { return }
            isRunning = false
            switch result {
            case let .success(text):
                if textView.string == originalText {
                    originalText = text
                    textView.string = text
                }
                statusLabel.stringValue = text.isEmpty
                    ? historyEditorString("No text found in this image.", "未在图片中识别到文字。")
                    : historyEditorString("OCR complete", "OCR 已完成")
            case .failure:
                statusLabel.stringValue = historyEditorString("Unable to recognize this image.", "无法识别此图片。")
                statusLabel.textColor = .systemRed
            }
            updateControls()
        }
    }

    @objc private func transformationSelectionChanged(_ sender: NSPopUpButton) {
        configureRunButtonForSelectedTransformation()
        updateControls()
    }

    @objc private func runSelectedTransformation() {
        guard !isRunning,
              !textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let action = selectedTransformation else { return }
        switch action {
        case .promptOptimization:
            runPromptOptimization()
        case let .script(scriptID):
            runScript(scriptID: scriptID)
        }
    }

    private func runScript(scriptID: UUID) {
        let input = textView.string
        let requestID = UUID()
        operationID = requestID
        isRunning = true
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = historyEditorString("Running script...", "正在执行脚本...")
        updateControls()
        transformationTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await transformHistoryText(
                input,
                using: scriptID,
                sourceAppBundleIdentifier: nil
            )
            guard operationID == requestID else { return }
            transformationTask = nil
            isRunning = false
            switch outcome {
            case let .transformed(output):
                replaceDraft(
                    with: output,
                    undoText: input,
                    actionName: historyEditorString("Run Script", "运行脚本")
                )
                configureRunButton(
                    symbol: "arrow.clockwise",
                    label: historyEditorString("Run again", "再次运行")
                )
                statusLabel.stringValue = historyEditorString("Script complete", "脚本执行完成")
            case .unchanged:
                configureRunButton(
                    symbol: "arrow.clockwise",
                    label: historyEditorString("Run again", "再次运行")
                )
                statusLabel.stringValue = historyEditorString("The script made no changes.", "脚本未产生变化。")
            case .failed:
                configureRunButton(
                    symbol: "exclamationmark.arrow.triangle.2.circlepath",
                    label: historyEditorString("Retry script", "重试脚本")
                )
                statusLabel.textColor = .systemRed
                statusLabel.stringValue = historyEditorString("Script execution failed.", "脚本执行失败。")
            }
            updateControls()
        }
    }

    private func runPromptOptimization() {
        let input = textView.string
        let requestID = UUID()
        operationID = requestID
        isRunning = true
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = ""
        schedulePromptLoadingFeedback(for: requestID)
        updateControls()
        transformationTask = Task { [weak self] in
            guard let self else { return }
            await executePromptOptimization(
                input: input,
                requestID: requestID,
                allowsConsentRetry: true
            )
        }
    }

    private func executePromptOptimization(
        input: String,
        requestID: UUID,
        allowsConsentRetry: Bool
    ) async {
        let outcome = await optimizePrompt(input)
        guard operationID == requestID, !Task.isCancelled else { return }

        switch outcome {
        case let .optimized(output, source):
            finishPromptOptimization(requestID: requestID)
            replaceDraft(
                with: output,
                undoText: input,
                actionName: historyEditorString("Improve Prompt", "美化提示词")
            )
            configureRunButton(
                symbol: "arrow.clockwise",
                label: historyEditorString("Improve again", "再次美化")
            )
            if source == .localFormatter {
                setStatus(
                    historyEditorString(
                        "Improved with local formatting. You can undo this change.",
                        "已使用本地整理，可撤销。"
                    ),
                    announces: true
                )
            } else {
                setStatus(
                    historyEditorString(
                        "Prompt improved. You can undo this change.",
                        "提示词已优化，可撤销。"
                    ),
                    announces: true
                )
            }
        case .unchanged:
            finishPromptOptimization(requestID: requestID)
            configureRunButton(
                symbol: "arrow.clockwise",
                label: historyEditorString("Check again", "再次检查")
            )
            setStatus(
                historyEditorString(
                    "This prompt does not need adjustment.",
                    "当前提示词无需调整。"
                ),
                announces: true
            )
        case let .consentRequired(origin):
            guard allowsConsentRetry else {
                finishPromptOptimization(requestID: requestID)
                showPromptOptimizationFailure(.originNotConfirmed(origin: origin))
                return
            }
            let result = confirmationRunner(
                PasteraConfirmationOptions(
                    title: historyEditorString(
                        "Send prompt to \(origin)?",
                        "将提示词发送到 \(origin)？"
                    ),
                    message: historyEditorString(
                        "The current draft will be sent to this provider for optimization.",
                        "当前草稿将发送到此服务以进行提示词优化。"
                    ),
                    confirmTitle: historyEditorString("Continue", "继续"),
                    cancelTitle: historyEditorString("Cancel", "取消"),
                    symbolName: "network"
                ),
                window
            )
            guard operationID == requestID, !Task.isCancelled else { return }
            guard result.confirmed else {
                finishPromptOptimization(requestID: requestID)
                setStatus(
                    historyEditorString(
                        "Remote optimization cancelled. The draft was not changed.",
                        "已取消远端优化，原文未更改。"
                    ),
                    announces: true
                )
                return
            }
            promptOptimizationService.confirmRemoteOrigin(origin)
            await executePromptOptimization(
                input: input,
                requestID: requestID,
                allowsConsentRetry: false
            )
        case let .failed(error):
            finishPromptOptimization(requestID: requestID)
            if error == .cancelled {
                setStatus(
                    historyEditorString(
                        "Prompt optimization cancelled.",
                        "已取消提示词优化。"
                    ),
                    announces: true
                )
            } else {
                showPromptOptimizationFailure(error)
            }
        }
    }

    private func finishPromptOptimization(requestID: UUID) {
        guard operationID == requestID else { return }
        loadingFeedbackWorkItem?.cancel()
        loadingFeedbackWorkItem = nil
        transformationTask = nil
        isRunning = false
        updateControls()
    }

    private func schedulePromptLoadingFeedback(for requestID: UUID) {
        loadingFeedbackWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.operationID == requestID, self.isRunning else { return }
            self.configureRunButton(
                symbol: "hourglass",
                label: historyEditorString("Improving prompt", "正在美化提示词")
            )
            self.statusLabel.stringValue = historyEditorString(
                "Improving prompt...",
                "正在美化提示词..."
            )
        }
        loadingFeedbackWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private func showPromptOptimizationFailure(_ error: PromptOptimizationError) {
        configureRunButton(
            symbol: "exclamationmark.arrow.triangle.2.circlepath",
            label: historyEditorString("Retry prompt optimization", "重试提示词美化")
        )
        statusLabel.textColor = .systemRed
        setStatus(
            promptOptimizationFailureMessage(for: error),
            announces: true
        )
    }

    private func replaceDraft(with text: String, undoText: String, actionName: String) {
        textView.undoManager?.registerUndo(withTarget: self) { target in
            target.replaceDraft(with: undoText, undoText: text, actionName: actionName)
        }
        textView.undoManager?.setActionName(actionName)
        textView.string = text
        updateControls()
    }

    private func cancelTransformation() {
        loadingFeedbackWorkItem?.cancel()
        loadingFeedbackWorkItem = nil
        transformationTask?.cancel()
        transformationTask = nil
        operationID = UUID()
        isRunning = false
    }

    nonisolated private func recognizeText(
        historyID: PasteboardHistory.ID,
        content: PasteboardContent
    ) async -> Result<String, PasteboardHistoryOCRRecognitionError> {
        await ocrIndexer.recognizeText(historyID: historyID, content: content)
    }

    nonisolated private func transformHistoryText(
        _ text: String,
        using scriptID: UUID,
        sourceAppBundleIdentifier: String?
    ) async -> ScriptTransformOutcome {
        await scriptCoordinator.transformHistoryText(
            text,
            using: scriptID,
            sourceAppBundleIdentifier: sourceAppBundleIdentifier
        )
    }

    nonisolated private func optimizePrompt(_ text: String) async -> PromptOptimizationOutcome {
        await promptOptimizationService.optimize(text)
    }

    private func configureRunButton(symbol: String, label: String) {
        runButton.title = ""
        runButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        runButton.toolTip = label
        runButton.setAccessibilityLabel(label)
    }

    private func configureRunButtonForSelectedTransformation() {
        switch selectedTransformation {
        case .promptOptimization:
            configureRunButton(
                symbol: "wand.and.stars",
                label: historyEditorString("Improve Prompt", "美化提示词")
            )
        case .script:
            configureRunButton(
                symbol: "play.fill",
                label: historyEditorString("Run script", "运行脚本")
            )
        case nil:
            configureRunButton(
                symbol: "wand.and.stars",
                label: historyEditorString("Improve Prompt", "美化提示词")
            )
        }
    }

    private var selectedTransformation: HistoryTextTransformationAction? {
        scriptPopup.selectedItem?.representedObject as? HistoryTextTransformationAction
    }

    @objc private func save() {
        guard saveDraft() else { return }
        originalText = textView.string
        onSaved()
        window?.close()
    }

    @objc private func cancel() {
        window?.performClose(nil)
    }

    private func saveDraft() -> Bool {
        guard let historyID else { return false }
        let text = textView.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showError(historyEditorString("History text cannot be empty.", "历史文本不能为空。"))
            return false
        }
        let now = Int(Date().timeIntervalSince1970)
        let didSave: Bool
        switch mode {
        case .text:
            didSave = repository.updateTextHistory(id: historyID, text: text, updateAt: now)
        case .image:
            didSave = repository.createDerivedTextHistory(text: text, updateAt: now) != nil
        }
        if !didSave {
            showError(historyEditorString("Unable to save this history item.", "无法保存此历史条目。"))
        }
        return didSave
    }

    private func confirmReplacingDirtyDraftIfNeeded() -> Bool {
        guard textView.string != originalText else { return true }
        let alert = NSAlert()
        alert.messageText = historyEditorString("Save changes?", "要保存更改吗？")
        alert.informativeText = historyEditorString(
            "Your edited history text has not been saved.",
            "编辑后的历史文本尚未保存。"
        )
        alert.addButton(withTitle: historyEditorString("Save", "保存"))
        alert.addButton(withTitle: historyEditorString("Discard", "放弃"))
        alert.addButton(withTitle: historyEditorString("Cancel", "取消"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            guard saveDraft() else { return false }
            originalText = textView.string
            onSaved()
            return true
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    private func updateControls() {
        let hasText = !textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasTransformation = selectedTransformation != nil
        scriptPopup.isEnabled = !isRunning && hasTransformation
        runButton.isEnabled = !isRunning && hasText && hasTransformation
        runButton.bezelColor = runButton.isEnabled ? .controlAccentColor : nil
        runButton.contentTintColor = runButton.isEnabled ? .white : .tertiaryLabelColor
        automationIconView.contentTintColor = hasTransformation ? .controlAccentColor : .tertiaryLabelColor
        saveButton.isEnabled = !isRunning && hasText
        countLabel.stringValue = historyEditorString(
            "\(textView.string.count) characters",
            "\(textView.string.count) 个字符"
        )
    }

    private func configureHeader(for history: PasteboardHistory, isImage: Bool) {
        titleLabel.stringValue = isImage
            ? historyEditorString("Image OCR", "图片 OCR")
            : historyEditorString("Text History", "文本历史")
        typeIconView.image = NSImage(
            systemSymbolName: isImage ? "text.viewfinder" : "doc.text",
            accessibilityDescription: titleLabel.stringValue
        )
        metadataLabel.stringValue = metadataText(for: history)
    }

    private func metadataText(for history: PasteboardHistory) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(history.updateAt))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "\(formatter.string(from: date))  ·  "
            + historyEditorString("Source app not recorded", "未记录来源应用")
    }

    private func showError(_ message: String) {
        statusLabel.textColor = .systemRed
        statusLabel.stringValue = message
        updateControls()
    }

    private func setStatus(_ message: String, announces: Bool) {
        statusLabel.stringValue = message
        updateControls()
        guard announces else { return }
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
    }

    private func promptOptimizationFailureMessage(for error: PromptOptimizationError) -> String {
        switch error {
        case .missingModel, .invalidEndpoint, .insecureEndpoint,
             .unavailable(.remoteNotConfigured):
            return historyEditorString(
                "Configure the model provider in Settings. The draft was not changed.",
                "请先在设置中配置模型服务，原文未更改。"
            )
        case .missingAPIKey, .unauthorized, .keychainUnavailable:
            return historyEditorString(
                "Check the provider credential in Settings. The draft was not changed.",
                "请检查设置中的服务凭据，原文未更改。"
            )
        case .rateLimited:
            return historyEditorString(
                "The provider is rate limited. Try again later; the draft was not changed.",
                "服务请求过于频繁，请稍后重试；原文未更改。"
            )
        case .requestTimedOut:
            return historyEditorString(
                "The provider timed out. The draft was not changed.",
                "服务响应超时，原文未更改。"
            )
        case .inputTooLong:
            return historyEditorString(
                "This prompt is too long to optimize. The draft was not changed.",
                "提示词过长，无法优化；原文未更改。"
            )
        case .cancelled:
            return historyEditorString("Prompt optimization cancelled.", "已取消提示词优化。")
        case .emptyInput, .outputTooLong, .originNotConfirmed, .requestFailed,
             .invalidResponse, .serverRejected, .unavailable:
            return historyEditorString(
                "Unable to improve the prompt. The draft was not changed.",
                "无法优化，原文未更改。"
            )
        }
    }
}

private extension PromptOptimizationAvailability {
    var displayName: String {
        switch self {
        case .available:
            return historyEditorString("Improve Prompt — Ready", "美化提示词 — 已就绪")
        case .unavailable(.remoteNotConfigured):
            return historyEditorString("Improve Prompt — Configure in Settings", "美化提示词 — 请前往设置配置")
        case .unavailable:
            return historyEditorString("Improve Prompt — Local fallback", "美化提示词 — 本地兼容模式")
        }
    }
}

#if DEBUG
extension HistoryEditorWindowController {
    var draftForTesting: String { textView.string }
    var statusForTesting: String { statusLabel.stringValue }
    var isRunningForTesting: Bool { isRunning }
    var transformationActionsForTesting: [HistoryTextTransformationAction?] {
        scriptPopup.itemArray.map { item in
            item.isSeparatorItem
                ? nil
                : item.representedObject as? HistoryTextTransformationAction
        }
    }

    func runPromptOptimizationForTesting() async {
        scriptPopup.selectItem(at: 0)
        runPromptOptimization()
        let task = transformationTask
        await task?.value
    }

    func selectTransformationForTesting(_ action: HistoryTextTransformationAction) {
        guard let index = scriptPopup.itemArray.firstIndex(where: {
            ($0.representedObject as? HistoryTextTransformationAction) == action
        }) else { return }
        scriptPopup.selectItem(at: index)
        configureRunButtonForSelectedTransformation()
        updateControls()
    }

    func runSelectedTransformationForTesting() async {
        runSelectedTransformation()
        let task = transformationTask
        await task?.value
    }

    func startSelectedTransformationForTesting() {
        runSelectedTransformation()
    }

    func undoForTesting() {
        textView.undoManager?.undo()
    }

    @discardableResult
    func saveDraftForTesting() -> Bool {
        saveDraft()
    }

    func cancelTransformationForTesting() {
        cancelTransformation()
        updateControls()
    }
}
#endif

private func historyEditorString(_ english: String, _ chinese: String) -> String {
    Locale.preferredLanguages.first?.hasPrefix("zh") == true ? chinese : english
}
