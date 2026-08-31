import AppKit

@MainActor
final class ScriptTestViewController: NSViewController {
    private enum Metrics {
        static let minimumWidth: CGFloat = 560
        static let idealWidth: CGFloat = 620
        static let minimumHeight: CGFloat = 430
        static let idealHeight: CGFloat = 500
    }

    private let scripts: [ScriptTransform]
    private let executor: ScriptExecuting
    private let scriptPicker = NSPopUpButton()
    private let inputView = NSTextView()
    private let resultIcon = NSImageView()
    private let resultLabel = NSTextField(wrappingLabelWithString: "")
    private let resultStack = NSStackView()
    private lazy var runButton = NSButton(
        title: pasteraScriptString("Run Test", "运行测试"),
        target: self,
        action: #selector(runTest)
    )

    private(set) var testOutputForTesting: String?
    private(set) var testErrorForTesting: ScriptExecutionError?

    init(scripts: [ScriptTransform], executor: ScriptExecuting) {
        self.scripts = scripts
        self.executor = executor
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let scaffold = PasteraPreferenceSheetScaffold(
            title: pasteraScriptString("Test Script", "测试脚本"),
            subtitle: pasteraScriptString(
                "Preview the result without changing the clipboard.",
                "预览脚本结果，不会修改剪贴板"
            ),
            minimumSize: NSSize(width: Metrics.minimumWidth, height: Metrics.minimumHeight),
            idealSize: NSSize(width: Metrics.idealWidth, height: Metrics.idealHeight)
        )
        scaffold.addBodyView(makeContent())

        let doneButton = NSButton(
            title: pasteraScriptString("Done", "完成"),
            target: self,
            action: #selector(done)
        )
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\u{1b}"
        doneButton.setAccessibilityLabel(pasteraScriptString("Close Script Test", "关闭脚本测试"))
        scaffold.setFooterActions(trailing: [doneButton])

        view = scaffold
        scaffold.layoutSubtreeIfNeeded()
    }

    private func makeContent() -> NSView {
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10

        content.addArrangedSubview(makeFieldLabel(pasteraScriptString("Script", "选择脚本")))
        scriptPicker.addItems(withTitles: scripts.map(\.name))
        scriptPicker.setAccessibilityLabel(pasteraScriptString("Script to Test", "要测试的脚本"))
        content.addArrangedSubview(scriptPicker)
        scriptPicker.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true

        content.setCustomSpacing(18, after: scriptPicker)
        content.addArrangedSubview(makeFieldLabel(pasteraScriptString("Test Input", "测试输入")))
        let inputScroll = NSScrollView()
        inputScroll.hasVerticalScroller = true
        inputScroll.borderType = .bezelBorder
        inputScroll.documentView = inputView
        inputScroll.translatesAutoresizingMaskIntoConstraints = false
        inputScroll.heightAnchor.constraint(equalToConstant: 150).isActive = true
        inputView.font = .systemFont(ofSize: 13)
        inputView.string = "Hello World"
        inputView.isAutomaticQuoteSubstitutionEnabled = false
        inputView.setAccessibilityLabel(pasteraScriptString("Test Input", "测试输入"))
        content.addArrangedSubview(inputScroll)
        inputScroll.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true

        runButton.bezelStyle = .rounded
        runButton.bezelColor = .controlAccentColor
        runButton.contentTintColor = .white
        runButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)
        runButton.imagePosition = .imageLeading
        runButton.keyEquivalent = "\r"
        runButton.isEnabled = !scripts.isEmpty
        runButton.setAccessibilityLabel(pasteraScriptString("Run Script Test", "运行脚本测试"))
        let actionRow = NSStackView()
        actionRow.orientation = .horizontal
        actionRow.addArrangedSubview(NSView())
        actionRow.addArrangedSubview(runButton)
        content.addArrangedSubview(actionRow)
        actionRow.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true

        resultStack.orientation = .horizontal
        resultStack.alignment = .centerY
        resultStack.spacing = 8
        resultStack.edgeInsets = NSEdgeInsets(top: 9, left: 10, bottom: 9, right: 10)
        resultStack.wantsLayer = true
        resultStack.layer?.cornerRadius = 7
        resultStack.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.45).cgColor
        resultStack.identifier = NSUserInterfaceItemIdentifier("script.test.result")
        resultStack.setAccessibilityIdentifier("script.test.result")
        resultStack.translatesAutoresizingMaskIntoConstraints = false
        resultStack.heightAnchor.constraint(greaterThanOrEqualToConstant: 42).isActive = true
        resultIcon.translatesAutoresizingMaskIntoConstraints = false
        resultIcon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        resultIcon.heightAnchor.constraint(equalToConstant: 16).isActive = true
        resultLabel.maximumNumberOfLines = 5
        resultStack.addArrangedSubview(resultIcon)
        resultStack.addArrangedSubview(resultLabel)
        content.addArrangedSubview(resultStack)
        resultStack.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true

        showResult(
            scripts.isEmpty
                ? pasteraScriptString("Create a script before running a test.", "请先创建脚本再运行测试")
                : pasteraScriptString("Ready to run.", "已准备好运行"),
            symbol: scripts.isEmpty ? "exclamationmark.circle" : "info.circle",
            color: .secondaryLabelColor
        )
        return content
    }

    private func makeFieldLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        return label
    }

    @objc private func done() {
        dismissScriptSheet(self)
    }

    @objc private func runTest() {
        Task { await runSelectedScript(input: inputView.string) }
    }

    private func runSelectedScript(input: String) async {
        guard scripts.indices.contains(scriptPicker.indexOfSelectedItem) else { return }
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showResult(
                pasteraScriptString("Enter text to test the script.", "请输入用于测试脚本的文本"),
                symbol: "exclamationmark.circle.fill",
                color: .systemRed
            )
            return
        }

        runButton.isEnabled = false
        runButton.title = pasteraScriptString("Running…", "正在运行…")
        defer {
            runButton.isEnabled = true
            runButton.title = pasteraScriptString("Run Test", "运行测试")
        }
        let result = await executor.execute(
            scripts: [scripts[scriptPicker.indexOfSelectedItem]],
            input: ScriptExecutionInput(text: input, sourceAppBundleIdentifier: nil)
        )
        switch result {
        case let .success(output):
            testOutputForTesting = output
            testErrorForTesting = nil
            showResult(
                output.isEmpty
                    ? pasteraScriptString("Success: empty string", "运行成功：输出为空字符串")
                    : output,
                symbol: "checkmark.circle.fill",
                color: .systemGreen
            )
        case let .failure(error):
            testOutputForTesting = nil
            testErrorForTesting = error
            showResult(
                pasteraScriptString(
                    "Test failed: \(error.shortDescription)",
                    "测试失败：\(error.shortDescription)"
                ),
                symbol: "xmark.circle.fill",
                color: .systemRed
            )
        }
    }

    private func showResult(_ message: String, symbol: String, color: NSColor) {
        resultIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        resultIcon.contentTintColor = color
        resultLabel.stringValue = message
        resultLabel.textColor = color
        resultStack.isHidden = false
        resultStack.setAccessibilityLabel(message)
    }

    var usesSingleColumnLayoutForTesting: Bool {
        scriptPicker.superview != nil && inputView.enclosingScrollView?.superview != nil
    }

    func runSelectedScriptForTesting(input: String) async {
        await runSelectedScript(input: input)
    }

    var minimumSheetWidthForTesting: CGFloat { Metrics.minimumWidth }
}
