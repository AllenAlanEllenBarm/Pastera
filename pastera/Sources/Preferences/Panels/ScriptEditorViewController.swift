import AppKit

@MainActor
// swiftlint:disable:next type_body_length
final class ScriptEditorViewController: NSViewController, NSTextFieldDelegate, NSTextViewDelegate {
    private enum Metrics {
        static let minimumWidth: CGFloat = 560
        static let idealWidth: CGFloat = 760
        static let minimumHeight: CGFloat = 480
        static let idealHeight: CGFloat = 680
    }

    private let original: ScriptTransform?
    private let executor: ScriptExecuting
    private let onSave: (ScriptTransform) -> Void

    private let nameField = NSTextField(string: "")
    private let enabledButton = NSButton(
        checkboxWithTitle: pasteraScriptString("Enable Script", "启用脚本"),
        target: nil,
        action: nil
    )
    private let copyButton = NSButton(
        checkboxWithTitle: pasteraScriptString("Run on Copy", "复制时执行"),
        target: nil,
        action: nil
    )
    private let pasteButton = NSButton(
        checkboxWithTitle: pasteraScriptString("Run on Pastera Paste", "Pastera 粘贴时执行"),
        target: nil,
        action: nil
    )
    private let manualButton = NSButton(
        checkboxWithTitle: pasteraScriptString("Run Manually", "手动运行"),
        target: nil,
        action: nil
    )
    private let codeView = NSTextView()
    private let testInputView = NSTextView()
    private let resultIcon = NSImageView()
    private let resultLabel = NSTextField(wrappingLabelWithString: "")
    private let resultStack = NSStackView()
    private let saveButton = NSButton()
    private weak var sheetScaffold: PasteraPreferenceSheetScaffold?
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
        configureFields()

        let scaffold = PasteraPreferenceSheetScaffold(
            title: original == nil
                ? pasteraScriptString("New Script", "新建脚本")
                : pasteraScriptString("Edit Script", "编辑脚本"),
            subtitle: pasteraScriptString(
                "Configure when the script runs, then validate it before saving.",
                "设置执行时机，并在保存前完成一次运行验证"
            ),
            minimumSize: NSSize(width: Metrics.minimumWidth, height: Metrics.minimumHeight),
            idealSize: NSSize(width: Metrics.idealWidth, height: Metrics.idealHeight)
        )
        sheetScaffold = scaffold

        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 16
        content.addArrangedSubview(basicSection())
        content.addArrangedSubview(executionSection())
        content.addArrangedSubview(codeSection())
        content.addArrangedSubview(testSection())
        content.arrangedSubviews.forEach {
            $0.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        scaffold.addBodyView(content)

        let cancelButton = NSButton(
            title: pasteraScriptString("Cancel", "取消"),
            target: self,
            action: #selector(cancel)
        )
        cancelButton.bezelStyle = .rounded
        saveButton.title = pasteraScriptString("Save", "保存")
        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.bezelStyle = .rounded
        saveButton.bezelColor = .controlAccentColor
        saveButton.contentTintColor = .white
        saveButton.keyEquivalent = "\r"
        scaffold.setFooterActions(trailing: [cancelButton, saveButton])

        view = scaffold
        scaffold.layoutSubtreeIfNeeded()
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
        codeView.isAutomaticQuoteSubstitutionEnabled = false
        codeView.isAutomaticDashSubstitutionEnabled = false

        testInputView.font = .systemFont(ofSize: 13)
        testInputView.string = "Hello World"
        testInputView.setAccessibilityLabel(pasteraScriptString("Test Input", "测试输入"))

        updateTestResult(
            message: pasteraScriptString(
                "Run a test to validate the current draft.",
                "运行测试以验证当前脚本"
            ),
            symbolName: "info.circle",
            color: .secondaryLabelColor
        )
    }

    private func basicSection() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.addArrangedSubview(makeFieldLabel(pasteraScriptString("Name", "名称")))
        stack.addArrangedSubview(nameField)
        nameField.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return makeSection(
            id: "script.editor.section.basic",
            title: pasteraScriptString("Basic Information", "基本信息"),
            content: stack
        )
    }

    private func executionSection() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.addArrangedSubview(enabledButton)
        stack.addArrangedSubview(makeFieldLabel(pasteraScriptString("Execution Timing", "执行时机")))

        let triggers = NSStackView(views: [copyButton, pasteButton, manualButton])
        triggers.orientation = .horizontal
        triggers.alignment = .centerY
        triggers.distribution = .fillProportionally
        triggers.spacing = 18
        stack.addArrangedSubview(triggers)

        let help = NSTextField(wrappingLabelWithString: pasteraScriptString(
            "Pastera Paste only affects paste actions started from Pastera. It does not intercept system Command-V.",
            "Pastera 粘贴只处理由 Pastera 发起的粘贴，不会拦截系统 Command-V。"
        ))
        help.font = .systemFont(ofSize: 11.5)
        help.textColor = .secondaryLabelColor
        stack.addArrangedSubview(help)
        help.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return makeSection(
            id: "script.editor.section.execution",
            title: pasteraScriptString("Execution Configuration", "执行配置"),
            content: stack
        )
    }

    private func codeSection() -> NSView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = codeView
        scrollView.identifier = NSUserInterfaceItemIdentifier("script.editor.code-scroll")
        scrollView.setAccessibilityIdentifier("script.editor.code-scroll")
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(equalToConstant: 158).isActive = true
        return makeSection(
            id: "script.editor.section.code",
            title: pasteraScriptString("Script Code", "脚本代码"),
            subtitle: pasteraScriptString(
                "Implement function transform(clip).",
                "必须实现 function transform(clip)。"
            ),
            content: scrollView
        )
    }

    private func testSection() -> NSView {
        let inputScroll = NSScrollView()
        inputScroll.hasVerticalScroller = true
        inputScroll.borderType = .bezelBorder
        inputScroll.documentView = testInputView
        inputScroll.translatesAutoresizingMaskIntoConstraints = false
        inputScroll.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let runButton = NSButton(
            title: pasteraScriptString("Run Test", "运行测试"),
            target: self,
            action: #selector(runTest)
        )
        runButton.bezelStyle = .rounded
        runButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)
        runButton.imagePosition = .imageLeading

        let inputHeader = NSStackView()
        inputHeader.orientation = .horizontal
        inputHeader.alignment = .centerY
        inputHeader.addArrangedSubview(makeFieldLabel(pasteraScriptString("Test Input", "测试输入")))
        inputHeader.addArrangedSubview(NSView())
        inputHeader.addArrangedSubview(runButton)

        resultStack.orientation = .horizontal
        resultStack.alignment = .centerY
        resultStack.spacing = 8
        resultStack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        resultStack.wantsLayer = true
        resultStack.layer?.cornerRadius = 7
        resultStack.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.45).cgColor
        resultStack.identifier = NSUserInterfaceItemIdentifier("script.editor.test-result")
        resultStack.setAccessibilityIdentifier("script.editor.test-result")
        resultStack.translatesAutoresizingMaskIntoConstraints = false
        resultStack.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        resultIcon.translatesAutoresizingMaskIntoConstraints = false
        resultIcon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        resultIcon.heightAnchor.constraint(equalToConstant: 16).isActive = true
        resultLabel.maximumNumberOfLines = 4
        resultStack.addArrangedSubview(resultIcon)
        resultStack.addArrangedSubview(resultLabel)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.addArrangedSubview(inputHeader)
        stack.addArrangedSubview(inputScroll)
        stack.addArrangedSubview(resultStack)
        [inputHeader, inputScroll, resultStack].forEach {
            $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return makeSection(
            id: "script.editor.section.test",
            title: pasteraScriptString("Validate Before Saving", "保存前验证"),
            subtitle: pasteraScriptString(
                "Testing does not modify the clipboard.",
                "测试不会修改剪贴板"
            ),
            content: stack
        )
    }

    private func makeSection(
        id: String,
        title: String,
        subtitle: String? = nil,
        content: NSView
    ) -> NSView {
        let section = NSStackView()
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 10
        section.identifier = NSUserInterfaceItemIdentifier(id)
        section.setAccessibilityIdentifier(id)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        section.addArrangedSubview(titleLabel)
        if let subtitle {
            let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
            subtitleLabel.font = .systemFont(ofSize: 11.5)
            subtitleLabel.textColor = .secondaryLabelColor
            section.addArrangedSubview(subtitleLabel)
            subtitleLabel.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        section.addArrangedSubview(content)
        content.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        return section
    }

    private func makeFieldLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        return label
    }

    private var draftSignature: String {
        [
            nameField.stringValue,
            codeView.string,
            String(copyButton.state.rawValue),
            String(pasteButton.state.rawValue),
            String(manualButton.state.rawValue)
        ].joined(separator: "|")
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
        testOutputForTesting = nil
        testErrorForTesting = nil
        updateTestResult(
            message: pasteraScriptString(
                "Draft changed. Run the test again before saving.",
                "脚本已修改，请重新运行测试后再保存"
            ),
            symbolName: "arrow.clockwise.circle",
            color: .secondaryLabelColor
        )
        updateSaveState()
    }

    func controlTextDidChange(_ notification: Notification) { draftChanged() }
    func textDidChange(_ notification: Notification) { draftChanged() }

    @objc private func runTest() {
        Task { await validate(input: testInputView.string) }
    }

    private func validate(input: String) async {
        guard hasRequiredFields else {
            validatedSignature = nil
            updateTestResult(
                message: pasteraScriptString(
                    "Enter a name, choose a trigger, and define transform(clip).",
                    "请填写名称、选择执行时机，并定义 transform(clip)"
                ),
                symbolName: "exclamationmark.circle.fill",
                color: .systemRed
            )
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
            updateTestResult(
                message: output.isEmpty
                    ? pasteraScriptString("Success: empty string", "运行成功：输出为空字符串")
                    : output,
                symbolName: "checkmark.circle.fill",
                color: .systemGreen
            )
        case let .failure(error):
            validatedSignature = nil
            testOutputForTesting = nil
            testErrorForTesting = error
            updateTestResult(
                message: pasteraScriptString("Script test failed: \(error)", "脚本测试失败：\(error)"),
                symbolName: "xmark.circle.fill",
                color: .systemRed
            )
        }
        updateSaveState()
    }

    private func updateTestResult(message: String, symbolName: String, color: NSColor) {
        resultIcon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        resultIcon.contentTintColor = color
        resultLabel.stringValue = message
        resultLabel.textColor = color
        resultStack.isHidden = false
        resultStack.setAccessibilityLabel(message)
    }

    @objc private func cancel() { dismissScriptSheet(self) }

    @objc private func save() {
        guard canSaveForTesting else {
            NSSound.beep()
            return
        }
        onSave(makeDraft())
        dismissScriptSheet(self)
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

    var minimumSheetWidthForTesting: CGFloat { Metrics.minimumWidth }
    var usesFlexibleDocumentWidthForTesting: Bool {
        sheetScaffold?.documentView.autoresizingMask.contains(.width) == true
    }
}
