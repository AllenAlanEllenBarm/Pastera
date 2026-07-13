import AppKit
import KeyHolder
import Magnet

@MainActor
final class CPYScriptsPreferenceViewController: PasteraPreferencePageViewController {
    private let repository: ScriptRepositoryProtocol
    private let executor: ScriptExecuting
    private let hotKeyService: HotKeyService
    private let listStack = NSStackView()
    private let shortcutRecordView = RecordView(frame: .zero)
    private let testScriptPicker = NSPopUpButton()
    private let testInputField = NSTextField(string: "Hello World")
    private let testResultLabel = NSTextField(wrappingLabelWithString: "")
    private var testScripts = [ScriptTransform]()

    private(set) var testOutputForTesting: String?
    private(set) var testErrorForTesting: ScriptExecutionError?

    init(
        repository: ScriptRepositoryProtocol = ScriptRepository(),
        executor: ScriptExecuting = ScriptExecutionService(),
        hotKeyService: HotKeyService = AppEnvironment.current.hotKeyService
    ) {
        self.repository = repository
        self.executor = executor
        self.hotKeyService = hotKeyService
        super.init(paneID: .scripts, title: pasteraScriptString("Transform Scripts", "转换脚本"))
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        super.loadView()
        let scriptsCard = makeScriptsCard()
        let testCard = makeTestCard()
        let shortcutCard = makeShortcutCard()
        contentStack.addArrangedSubview(scriptsCard)
        contentStack.addArrangedSubview(testCard)
        contentStack.addArrangedSubview(shortcutCard)
        scriptsCard.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        testCard.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        shortcutCard.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        reloadScripts()
    }

    private func makeScriptsCard() -> NSView {
        let card = makeCard()
        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        let icon = NSImageView(image: NSImage(systemSymbolName: "doc.text.fill", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .systemBlue
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 34).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 34).isActive = true
        let headerLabels = NSStackView()
        headerLabels.orientation = .vertical
        headerLabels.alignment = .leading
        let heading = NSTextField(labelWithString: pasteraScriptString("My Scripts", "转换脚本"))
        heading.font = .systemFont(ofSize: 16, weight: .semibold)
        let subtitle = NSTextField(labelWithString: pasteraScriptString(
            "Create scripts to transform plain-text clipboard content.",
            "创建脚本来自动转换剪贴板中的文本内容"
        ))
        subtitle.textColor = .secondaryLabelColor
        headerLabels.addArrangedSubview(heading)
        headerLabels.addArrangedSubview(subtitle)
        header.addArrangedSubview(icon)
        header.addArrangedSubview(headerLabels)
        card.addArrangedSubview(header)
        listStack.orientation = .vertical
        listStack.alignment = .centerX
        listStack.spacing = 12
        card.addArrangedSubview(listStack)
        listStack.widthAnchor.constraint(equalTo: card.widthAnchor, constant: -36).isActive = true
        registerAnchor("scripts.list", view: card)
        return card
    }

    private func makeShortcutCard() -> NSView {
        let card = makeCard()
        let heading = NSTextField(labelWithString: pasteraScriptString("Manual Run Shortcut", "全局快捷键"))
        heading.font = .systemFont(ofSize: 16, weight: .semibold)
        card.addArrangedSubview(heading)
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        let labels = NSStackView()
        labels.orientation = .vertical
        labels.alignment = .leading
        let title = NSTextField(labelWithString: pasteraScriptString("Transform Current Clipboard", "转换当前剪贴板"))
        title.font = .systemFont(ofSize: 14, weight: .medium)
        labels.addArrangedSubview(title)
        let help = NSTextField(wrappingLabelWithString: pasteraScriptString(
            "Runs enabled manual scripts and does not paste automatically.",
            "执行已启用的手动脚本，只更新剪贴板，不会自动粘贴"
        ))
        help.textColor = .secondaryLabelColor
        help.maximumNumberOfLines = 2
        labels.addArrangedSubview(help)
        shortcutRecordView.delegate = self
        shortcutRecordView.keyCombo = hotKeyService.scriptTransformKeyCombo
        shortcutRecordView.clearButtonMode = .whenRecorded
        shortcutRecordView.setAccessibilityLabel(pasteraScriptString("Manual Script Shortcut", "手动运行脚本快捷键"))
        shortcutRecordView.translatesAutoresizingMaskIntoConstraints = false
        shortcutRecordView.widthAnchor.constraint(equalToConstant: 150).isActive = true
        shortcutRecordView.heightAnchor.constraint(equalToConstant: 30).isActive = true
        row.addArrangedSubview(labels)
        row.addArrangedSubview(shortcutRecordView)
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        shortcutRecordView.setContentCompressionResistancePriority(.required, for: .horizontal)
        card.addArrangedSubview(row)
        registerAnchor("scripts.shortcut", view: card)
        return card
    }

    private func makeTestCard() -> NSView {
        let card = makeCard()
        let heading = NSTextField(labelWithString: pasteraScriptString("Test Script", "测试脚本"))
        heading.font = .systemFont(ofSize: 16, weight: .semibold)
        card.addArrangedSubview(heading)
        let help = NSTextField(labelWithString: pasteraScriptString(
            "Choose a saved script and preview its output without changing the clipboard.",
            "选择已保存的脚本并预览输出，不会修改剪贴板"
        ))
        help.textColor = .secondaryLabelColor
        card.addArrangedSubview(help)

        let pickerLabel = NSTextField(labelWithString: pasteraScriptString("Script", "脚本"))
        pickerLabel.font = .systemFont(ofSize: 13, weight: .medium)
        card.addArrangedSubview(pickerLabel)
        testScriptPicker.translatesAutoresizingMaskIntoConstraints = false
        testScriptPicker.widthAnchor.constraint(equalToConstant: 280).isActive = true
        card.addArrangedSubview(testScriptPicker)

        let inputLabel = NSTextField(labelWithString: pasteraScriptString("Test Input", "测试输入"))
        inputLabel.font = .systemFont(ofSize: 13, weight: .medium)
        card.addArrangedSubview(inputLabel)
        testInputField.placeholderString = pasteraScriptString("Enter sample text", "输入示例文本")
        testInputField.translatesAutoresizingMaskIntoConstraints = false
        card.addArrangedSubview(testInputField)
        testInputField.widthAnchor.constraint(equalTo: card.widthAnchor, constant: -44).isActive = true

        let runButton = NSButton(
            title: pasteraScriptString("Run Test", "运行测试"),
            target: self,
            action: #selector(runSelectedScriptTest)
        )
        runButton.bezelStyle = .rounded
        runButton.bezelColor = .controlAccentColor
        runButton.contentTintColor = .white
        card.addArrangedSubview(runButton)
        testResultLabel.textColor = .secondaryLabelColor
        testResultLabel.maximumNumberOfLines = 4
        card.addArrangedSubview(testResultLabel)
        registerAnchor("scripts.test", view: card)
        return card
    }

    private func makeCard() -> NSStackView {
        let card = NSStackView()
        card.orientation = .vertical
        card.alignment = .leading
        card.spacing = 14
        card.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 22, right: 22)
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.cgColor
        return card
    }

    private func reloadScripts() {
        listStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let scripts = (try? repository.fetchAll()) ?? []
        reloadTestScripts(scripts)
        guard !scripts.isEmpty else {
            let emptyState = NSStackView()
            emptyState.orientation = .vertical
            emptyState.alignment = .centerX
            emptyState.spacing = 14
            emptyState.translatesAutoresizingMaskIntoConstraints = false
            emptyState.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
            let empty = NSTextField(labelWithString: pasteraScriptString("No scripts yet", "暂无脚本"))
            empty.font = .systemFont(ofSize: 18, weight: .semibold)
            emptyState.addArrangedSubview(empty)
            let newButton = NSButton(title: pasteraScriptString("New Script", "新建脚本"), target: self, action: #selector(addScript))
            newButton.bezelStyle = .rounded
            newButton.bezelColor = .controlAccentColor
            newButton.contentTintColor = .white
            newButton.font = .systemFont(ofSize: 14, weight: .semibold)
            let templateButton = NSButton(
                title: pasteraScriptString("Create from Template", "从模板创建"),
                target: self,
                action: #selector(showTemplates)
            )
            templateButton.bezelStyle = .rounded
            let actions = NSStackView(views: [newButton, templateButton])
            actions.spacing = 10
            emptyState.addArrangedSubview(actions)
            listStack.addArrangedSubview(emptyState)
            return
        }
        listStack.alignment = .leading
        scripts.forEach {
            let row = makeScriptRow($0)
            listStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
        }
    }

    private func reloadTestScripts(_ scripts: [ScriptTransform]) {
        let selectedID = testScripts.indices.contains(testScriptPicker.indexOfSelectedItem)
            ? testScripts[testScriptPicker.indexOfSelectedItem].id
            : nil
        testScripts = scripts
        testScriptPicker.removeAllItems()
        testScriptPicker.addItems(withTitles: scripts.map(\.name))
        if let selectedID, let index = scripts.firstIndex(where: { $0.id == selectedID }) {
            testScriptPicker.selectItem(at: index)
        }
        testScriptPicker.isEnabled = !scripts.isEmpty
        if scripts.isEmpty {
            testScriptPicker.addItem(withTitle: pasteraScriptString("No saved scripts", "暂无已保存脚本"))
            testResultLabel.stringValue = pasteraScriptString(
                "Create and save a script before running a test.",
                "请先创建并保存一个脚本，再运行测试"
            )
        }
    }

    @objc private func runSelectedScriptTest() {
        Task { await runSelectedScriptTest(input: testInputField.stringValue) }
    }

    private func runSelectedScriptTest(input: String) async {
        guard testScripts.indices.contains(testScriptPicker.indexOfSelectedItem) else {
            testOutputForTesting = nil
            testErrorForTesting = nil
            return
        }
        testResultLabel.stringValue = pasteraScriptString("Running…", "正在运行…")
        let result = await executor.execute(
            scripts: [testScripts[testScriptPicker.indexOfSelectedItem]],
            input: ScriptExecutionInput(text: input, sourceAppBundleIdentifier: nil)
        )
        switch result {
        case let .success(output):
            testOutputForTesting = output
            testErrorForTesting = nil
            testResultLabel.stringValue = output.isEmpty
                ? pasteraScriptString("Success — empty string", "运行成功 — 输出为空字符串")
                : output
            testResultLabel.textColor = .systemGreen
        case let .failure(error):
            testOutputForTesting = nil
            testErrorForTesting = error
            testResultLabel.stringValue = pasteraScriptString("Test failed: \(error)", "测试失败：\(error)")
            testResultLabel.textColor = .systemRed
        }
    }

    var hasTestCardForTesting: Bool { testResultLabel.superview != nil }

    func runSelectedScriptTestForTesting(input: String) async {
        await runSelectedScriptTest(input: input)
    }

    private func makeScriptRow(_ script: ScriptTransform) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        row.wantsLayer = true
        row.layer?.cornerRadius = 9
        row.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        let labels = NSStackView()
        labels.orientation = .vertical
        labels.alignment = .leading
        let title = NSTextField(labelWithString: script.name)
        title.font = .systemFont(ofSize: 14, weight: .medium)
        let triggers = [script.runOnCopy ? pasteraPreferenceString("Copy") : nil,
                        script.runOnPaste ? pasteraPreferenceString("Pastera Paste") : nil,
                        script.runManually ? pasteraPreferenceString("Manual") : nil]
            .compactMap { $0 }.joined(separator: " · ")
        let detail = NSTextField(labelWithString: triggers)
        detail.textColor = .secondaryLabelColor
        labels.addArrangedSubview(title)
        labels.addArrangedSubview(detail)
        let edit = NSButton(title: pasteraPreferenceString("Edit"), target: self, action: #selector(editScript(_:)))
        edit.identifier = NSUserInterfaceItemIdentifier(script.id.uuidString)
        let enabled = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleScript(_:)))
        enabled.state = script.isEnabled ? .on : .off
        enabled.identifier = edit.identifier
        enabled.setAccessibilityLabel(pasteraPreferenceString("Enable \(script.name)"))
        let delete = NSButton(image: NSImage(systemSymbolName: "trash", accessibilityDescription: nil) ?? NSImage(), target: self, action: #selector(deleteScript(_:)))
        delete.bezelStyle = .inline
        delete.identifier = edit.identifier
        delete.setAccessibilityLabel(pasteraPreferenceString("Delete \(script.name)"))
        row.addArrangedSubview(labels)
        row.addArrangedSubview(edit)
        row.addArrangedSubview(enabled)
        row.addArrangedSubview(delete)
        labels.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true
        return row
    }

    @objc private func addScript() { presentEditor(script: nil) }

    @objc private func showTemplates() {
        var market: ScriptTemplateMarketViewController!
        market = ScriptTemplateMarketViewController { [weak self] template in
            guard let self else { return }
            self.dismiss(market)
            DispatchQueue.main.async { self.presentEditor(script: template.makeDraft()) }
        }
        presentAsSheet(market)
    }

    @objc private func editScript(_ sender: NSButton) {
        guard let script = script(for: sender) else { return }
        presentEditor(script: script)
    }

    private func presentEditor(script: ScriptTransform?) {
        let editor = ScriptEditorViewController(script: script, executor: executor) { [weak self] saved in
            guard let self else { return }
            if script == nil || (try? self.repository.fetchAll().contains(where: { $0.id == saved.id })) == false {
                try? self.repository.insert(saved)
            } else {
                try? self.repository.update(saved)
            }
            self.reloadScripts()
        }
        presentAsSheet(editor)
    }

    @objc private func toggleScript(_ sender: NSButton) {
        guard var script = script(for: sender) else { return }
        script.isEnabled = sender.state == .on
        script.updatedAt = Int(Date().timeIntervalSince1970)
        try? repository.update(script)
    }

    @objc private func deleteScript(_ sender: NSButton) {
        guard let script = script(for: sender) else { return }
        let alert = NSAlert()
        alert.messageText = pasteraPreferenceString("Delete Script?")
        alert.informativeText = pasteraPreferenceString("This permanently deletes \(script.name).")
        alert.addButton(withTitle: pasteraPreferenceString("Delete"))
        alert.addButton(withTitle: pasteraPreferenceString("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try? repository.delete(id: script.id)
        reloadScripts()
    }

    private func script(for sender: NSButton) -> ScriptTransform? {
        guard let rawID = sender.identifier?.rawValue,
              let id = UUID(uuidString: rawID) else { return nil }
        return try? repository.fetchAll().first(where: { $0.id == id })
    }
}

func pasteraScriptString(_ english: String, _ simplifiedChinese: String) -> String {
    guard Locale.preferredLanguages.first?.hasPrefix("zh") == true else {
        return pasteraPreferenceString(english)
    }
    return simplifiedChinese
}

extension CPYScriptsPreferenceViewController: RecordViewDelegate {
    func recordViewShouldBeginRecording(_ recordView: RecordView) -> Bool { true }
    func recordView(_ recordView: RecordView, canRecordKeyCombo keyCombo: KeyCombo) -> Bool { true }
    func recordView(_ recordView: RecordView, didChangeKeyCombo keyCombo: KeyCombo?) {
        hotKeyService.changeScriptTransformKeyCombo(keyCombo)
    }
    func recordViewDidEndRecording(_ recordView: RecordView) {}
}
