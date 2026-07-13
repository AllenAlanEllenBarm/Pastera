import AppKit

@MainActor
final class ScriptTestViewController: NSViewController {
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
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        let header = makeHeader()
        let content = makeContent()
        root.addSubview(header)
        root.addSubview(content)
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: 620),
            root.heightAnchor.constraint(equalToConstant: 500),
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 82),
            content.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            content.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -24)
        ])
        view = root
    }

    private func makeHeader() -> NSView {
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: pasteraScriptString("Test Script", "测试脚本"))
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        let subtitle = NSTextField(labelWithString: pasteraScriptString(
            "Preview a script result without changing the clipboard.",
            "预览脚本结果，不会修改剪贴板"
        ))
        subtitle.textColor = .secondaryLabelColor
        let labels = NSStackView(views: [title, subtitle])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3
        labels.translatesAutoresizingMaskIntoConstraints = false
        let done = NSButton(title: pasteraScriptString("Done", "完成"), target: self, action: #selector(done))
        done.bezelStyle = .rounded
        done.translatesAutoresizingMaskIntoConstraints = false
        done.setAccessibilityLabel(pasteraScriptString("Close Script Test", "关闭脚本测试"))
        header.addSubview(labels)
        header.addSubview(done)
        NSLayoutConstraint.activate([
            labels.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 24),
            labels.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            done.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -24),
            done.centerYAnchor.constraint(equalTo: header.centerYAnchor)
        ])
        return header
    }

    private func makeContent() -> NSStackView {
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false

        let pickerLabel = makeFieldLabel(pasteraScriptString("Script", "选择脚本"))
        scriptPicker.addItems(withTitles: scripts.map(\.name))
        scriptPicker.setAccessibilityLabel(pasteraScriptString("Script to Test", "要测试的脚本"))
        content.addArrangedSubview(pickerLabel)
        content.addArrangedSubview(scriptPicker)
        scriptPicker.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true

        content.addArrangedSubview(makeFieldLabel(pasteraScriptString("Test Input", "测试输入")))
        let inputScroll = NSScrollView()
        inputScroll.hasVerticalScroller = true
        inputScroll.borderType = .bezelBorder
        inputScroll.documentView = inputView
        inputScroll.translatesAutoresizingMaskIntoConstraints = false
        inputScroll.heightAnchor.constraint(equalToConstant: 170).isActive = true
        inputView.font = .systemFont(ofSize: 13)
        inputView.string = "Hello World"
        inputView.setAccessibilityLabel(pasteraScriptString("Test Input", "测试输入"))
        content.addArrangedSubview(inputScroll)
        inputScroll.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true

        runButton.bezelStyle = .rounded
        runButton.bezelColor = .controlAccentColor
        runButton.contentTintColor = .white
        runButton.keyEquivalent = "\r"
        runButton.setAccessibilityLabel(pasteraScriptString("Run Script Test", "运行脚本测试"))
        let actionRow = NSStackView()
        actionRow.orientation = .horizontal
        actionRow.addArrangedSubview(NSView())
        actionRow.addArrangedSubview(runButton)
        content.addArrangedSubview(actionRow)
        actionRow.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true

        resultStack.orientation = .horizontal
        resultStack.alignment = .top
        resultStack.spacing = 8
        resultStack.isHidden = true
        resultIcon.translatesAutoresizingMaskIntoConstraints = false
        resultIcon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        resultIcon.heightAnchor.constraint(equalToConstant: 16).isActive = true
        resultLabel.maximumNumberOfLines = 4
        resultStack.addArrangedSubview(resultIcon)
        resultStack.addArrangedSubview(resultLabel)
        content.addArrangedSubview(resultStack)
        resultStack.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        return content
    }

    private func makeFieldLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    @objc private func done() { dismiss(self) }

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
                output.isEmpty ? pasteraScriptString("Success — empty string", "运行成功 — 输出为空字符串") : output,
                symbol: "checkmark.circle.fill",
                color: .systemGreen
            )
        case let .failure(error):
            testOutputForTesting = nil
            testErrorForTesting = error
            showResult(
                pasteraScriptString("Test failed: \(error)", "测试失败：\(error)"),
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
    }

    var usesSingleColumnLayoutForTesting: Bool {
        scriptPicker.superview != nil && inputView.enclosingScrollView?.superview != nil
    }

    func runSelectedScriptForTesting(input: String) async {
        await runSelectedScript(input: input)
    }
}
