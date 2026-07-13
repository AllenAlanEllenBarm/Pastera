import AppKit

@MainActor
final class ScriptEditorViewController: NSViewController, NSTextFieldDelegate, NSTextViewDelegate {
    private let original: ScriptTransform?
    private let executor: ScriptExecuting
    private let onSave: (ScriptTransform) -> Void

    private let nameField = NSTextField(string: "")
    private let enabledButton = NSButton(checkboxWithTitle: pasteraScriptString("Enable Script", "启用脚本"), target: nil, action: nil)
    private let copyButton = NSButton(checkboxWithTitle: pasteraScriptString("Run on Copy", "复制时执行"), target: nil, action: nil)
    private let pasteButton = NSButton(checkboxWithTitle: pasteraScriptString("Run on Pastera Paste", "Pastera 粘贴时执行"), target: nil, action: nil)
    private let manualButton = NSButton(checkboxWithTitle: pasteraScriptString("Run Manually", "手动运行"), target: nil, action: nil)
    private let codeView = NSTextView()
    private let testInputField = NSTextField(string: "Hello World")
    private let resultLabel = NSTextField(wrappingLabelWithString: "")
    private let saveButton = NSButton()
    private let documentView = PasteraPreferenceFlippedView()
    private var validatedSignature: String?

    private(set) var testOutputForTesting: String?
    private(set) var testErrorForTesting: ScriptExecutionError?

    init(
        script: ScriptTransform?,
        executor: ScriptExecuting = ScriptExecutionService(),
        onSave: @escaping (ScriptTransform) -> Void
    ) {
        self.original = script
        self.executor = executor
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        let header = makeHeader()
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        content.edgeInsets = NSEdgeInsets(top: 18, left: 22, bottom: 22, right: 22)
        content.translatesAutoresizingMaskIntoConstraints = true
        content.autoresizingMask = [.width]
        documentView.frame = NSRect(x: 0, y: 0, width: 760, height: 1_200)
        content.frame = NSRect(x: 0, y: 0, width: 760, height: 1_200)
        documentView.addSubview(content)
        scrollView.documentView = documentView

        configureFields()
        content.addArrangedSubview(card(title: pasteraScriptString("Basic Information", "基本信息"), content: nameField))
        content.addArrangedSubview(executionCard())
        content.addArrangedSubview(codeCard())
        content.addArrangedSubview(testCard())

        root.addSubview(header)
        root.addSubview(scrollView)
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: 760),
            root.heightAnchor.constraint(equalToConstant: 680),
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 78),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        view = root
        content.layoutSubtreeIfNeeded()
        let contentHeight = max(1, content.fittingSize.height)
        content.frame.size = NSSize(width: 760, height: contentHeight)
        documentView.frame.size = NSSize(width: 760, height: contentHeight)
        updateSaveState()
    }

    private func configureFields() {
        nameField.placeholderString = pasteraScriptString("Script Name", "脚本名称")
        nameField.stringValue = original?.name ?? ""
        nameField.delegate = self
        enabledButton.state = original?.isEnabled == false ? .off : .on
        copyButton.state = original?.runOnCopy == true ? .on : .off
        pasteButton.state = original?.runOnPaste == true ? .on : .off
        manualButton.state = original?.runManually == true || original == nil ? .on : .off
        [enabledButton, copyButton, pasteButton, manualButton].forEach {
            $0.target = self
            $0.action = #selector(draftChanged)
        }
        codeView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        codeView.string = original?.code ?? "function transform(clip) {\n    return clip.text;\n}"
        codeView.delegate = self
        resultLabel.textColor = .secondaryLabelColor
    }

    private func makeHeader() -> NSView {
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: original == nil ? pasteraScriptString("New Script", "新建脚本") : pasteraScriptString("Edit Script", "编辑脚本"))
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        let cancel = NSButton(title: pasteraScriptString("Cancel", "取消"), target: self, action: #selector(cancel))
        cancel.bezelStyle = .rounded
        saveButton.title = pasteraScriptString("Save", "保存")
        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        let actions = NSStackView(views: [cancel, saveButton])
        actions.spacing = 8
        actions.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(title)
        header.addSubview(actions)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 22),
            title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            actions.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -22),
            actions.centerYAnchor.constraint(equalTo: header.centerYAnchor)
        ])
        return header
    }

    private func executionCard() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.addArrangedSubview(enabledButton)
        let timing = NSTextField(labelWithString: pasteraScriptString("Execution Timing", "执行时机"))
        timing.font = .systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(timing)
        let triggers = NSStackView(views: [copyButton, pasteButton, manualButton])
        triggers.distribution = .fillEqually
        triggers.spacing = 12
        stack.addArrangedSubview(triggers)
        let help = NSTextField(wrappingLabelWithString: pasteraScriptString("Pastera Paste only affects paste actions started from Pastera. It does not intercept system Command-V.", "只转换从 Pastera 发起的粘贴，不会拦截系统 Command-V。"))
        help.textColor = .secondaryLabelColor
        stack.addArrangedSubview(help)
        return card(title: pasteraScriptString("Execution Configuration", "执行配置"), content: stack)
    }

    private func codeCard() -> NSView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = codeView
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 210).isActive = true
        return card(title: pasteraScriptString("Script Code — implement transform(clip)", "脚本代码 — 必须实现 transform(clip)"), content: scroll)
    }

    private func testCard() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.addArrangedSubview(testInputField)
        let run = NSButton(title: pasteraScriptString("Run Test", "运行测试"), target: self, action: #selector(runTest))
        run.bezelStyle = .rounded
        stack.addArrangedSubview(run)
        stack.addArrangedSubview(resultLabel)
        return card(title: pasteraScriptString("Test Script", "测试脚本"), content: stack)
    }

    private func card(title: String, content: NSView) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 16, right: 16)
        stack.wantsLayer = true
        stack.layer?.cornerRadius = 12
        stack.layer?.borderWidth = 1
        stack.layer?.borderColor = NSColor.separatorColor.cgColor
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        stack.addArrangedSubview(label)
        content.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(content)
        content.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        return stack
    }

    private var draftSignature: String {
        [nameField.stringValue, codeView.string, String(copyButton.state.rawValue), String(pasteButton.state.rawValue), String(manualButton.state.rawValue)].joined(separator: "|")
    }

    private var hasRequiredFields: Bool {
        !nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (copyButton.state == .on || pasteButton.state == .on || manualButton.state == .on)
            && codeView.string.contains("function transform")
    }

    private func makeDraft() -> ScriptTransform {
        let now = Int(Date().timeIntervalSince1970)
        return ScriptTransform(
            id: original?.id ?? UUID(),
            name: nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            code: codeView.string,
            isEnabled: enabledButton.state == .on,
            runOnCopy: copyButton.state == .on,
            runOnPaste: pasteButton.state == .on,
            runManually: manualButton.state == .on,
            sortIndex: original?.sortIndex ?? now,
            createdAt: original?.createdAt ?? now,
            updatedAt: now
        )
    }

    private func updateSaveState() {
        saveButton.isEnabled = canSaveForTesting
    }

    @objc private func draftChanged() {
        validatedSignature = nil
        updateSaveState()
    }

    func controlTextDidChange(_ notification: Notification) { draftChanged() }
    func textDidChange(_ notification: Notification) { draftChanged() }

    @objc private func runTest() {
        let input = testInputField.stringValue
        Task { await validate(input: input) }
    }

    private func validate(input: String) async {
        guard hasRequiredFields else {
            validatedSignature = nil
            resultLabel.stringValue = pasteraPreferenceString("Enter a name, choose a trigger, and define transform(clip).")
            updateSaveState()
            return
        }
        let signature = draftSignature
        let result = await executor.execute(
            scripts: [makeDraft()],
            input: ScriptExecutionInput(text: input, sourceAppBundleIdentifier: nil)
        )
        switch result {
        case let .success(output):
            validatedSignature = signature
            testOutputForTesting = output
            testErrorForTesting = nil
            resultLabel.stringValue = output.isEmpty ? pasteraPreferenceString("Success — empty string") : output
            resultLabel.textColor = .systemGreen
        case let .failure(error):
            validatedSignature = nil
            testOutputForTesting = nil
            testErrorForTesting = error
            resultLabel.stringValue = pasteraPreferenceString("Script test failed: \(error)")
            resultLabel.textColor = .systemRed
        }
        updateSaveState()
    }

    @objc private func cancel() { dismiss(self) }

    @objc private func save() {
        guard canSaveForTesting else { NSSound.beep(); return }
        onSave(makeDraft())
        dismiss(self)
    }

    var canSaveForTesting: Bool {
        hasRequiredFields && validatedSignature == draftSignature
    }

    func setNameForTesting(_ name: String) {
        nameField.stringValue = name
        draftChanged()
    }

    func setTriggerForTesting(_ trigger: ScriptTrigger, enabled: Bool) {
        let button: NSButton
        switch trigger {
        case .copy: button = copyButton
        case .paste: button = pasteButton
        case .manual: button = manualButton
        }
        button.state = enabled ? .on : .off
        draftChanged()
    }

    func setCodeForTesting(_ code: String) {
        codeView.string = code
        draftChanged()
    }

    func validateForTesting(input: String) async {
        await validate(input: input)
    }
}
