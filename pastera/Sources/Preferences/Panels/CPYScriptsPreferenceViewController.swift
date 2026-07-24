import AppKit
import KeyHolder
import Magnet

@MainActor
// swiftlint:disable:next type_body_length
final class CPYScriptsPreferenceViewController: PasteraPreferencePageViewController {
    private enum Metrics {
        static let emptyStateHeight: CGFloat = 108
        static let rowHeight: CGFloat = 54
    }

    private let repository: ScriptRepositoryProtocol
    private let executor: ScriptExecuting
    private let hotKeyService: HotKeyService
    private let listContainer = NSView()
    private let listStack = NSStackView()
    private let scriptSummaryLabel = NSTextField(labelWithString: "")
    private let shortcutRecordView = RecordView(frame: .zero)
    private lazy var testScriptButton = NSButton(
        title: pasteraScriptString("Test Script", "测试脚本"),
        target: self,
        action: #selector(showScriptTest)
    )
    private var emptyStateFillConstraint: NSLayoutConstraint?
    private var emptyStateMinimumHeight: CGFloat = 0
    override var fillsAvailableHeight: Bool { true }

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
        addAdaptiveContent(makeScriptsWorkspace(), fillsHeight: true)
        reloadScripts()
        invalidateContentSize()
    }

    private func makeScriptsWorkspace() -> PasteraPreferenceGroupView {
        let group = PasteraPreferenceGroupView(
            title: pasteraScriptString("My Scripts", "我的脚本"),
            symbolName: "curlybraces",
            accentColor: .systemBlue
        )
        group.identifier = NSUserInterfaceItemIdentifier("scripts.workspace")
        group.setAccessibilityIdentifier("scripts.workspace")
        scriptSummaryLabel.font = .systemFont(ofSize: 11, weight: .medium)
        scriptSummaryLabel.textColor = .secondaryLabelColor
        group.setHeaderAccessory(scriptSummaryLabel)

        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 0
        listStack.translatesAutoresizingMaskIntoConstraints = false
        listContainer.addSubview(listStack)
        listContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        NSLayoutConstraint.activate([
            listStack.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            listStack.topAnchor.constraint(equalTo: listContainer.topAnchor),
            listStack.bottomAnchor.constraint(lessThanOrEqualTo: listContainer.bottomAnchor)
        ])
        group.addContent(listContainer)
        group.addContent(makeScriptActions())
        group.addRow(makeShortcutRow())
        registerAnchor("scripts.list", view: listContainer)
        return group
    }

    private func makeShortcutRow() -> PasteraPreferenceSettingRowView {
        shortcutRecordView.delegate = self
        shortcutRecordView.keyCombo = hotKeyService.scriptTransformKeyCombo
        shortcutRecordView.clearButtonMode = .whenRecorded
        shortcutRecordView.setAccessibilityLabel(pasteraScriptString("Manual Script Shortcut", "手动运行脚本快捷键"))
        shortcutRecordView.translatesAutoresizingMaskIntoConstraints = false
        shortcutRecordView.widthAnchor.constraint(equalToConstant: 150).isActive = true
        shortcutRecordView.heightAnchor.constraint(equalToConstant: 30).isActive = true
        let row = PasteraPreferenceSettingRowView(
            title: pasteraScriptString("Global Shortcut", "全局快捷键"),
            subtitle: pasteraScriptString(
                "Transform the current clipboard without pasting it automatically.",
                "转换当前剪贴板，但不会自动粘贴"
            ),
            control: shortcutRecordView,
            minimumHeight: 58
        )
        registerAnchor("scripts.shortcut", view: row)
        return row
    }

    private func makeScriptActions() -> NSView {
        let newButton = NSButton(title: pasteraScriptString("New Script", "新建脚本"), target: self, action: #selector(addScript))
        newButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        newButton.imagePosition = .imageLeading
        newButton.identifier = NSUserInterfaceItemIdentifier("scripts.action.primary")
        let templateButton = NSButton(
            title: pasteraScriptString("Create from Template", "从模板创建"),
            target: self,
            action: #selector(showTemplates)
        )
        templateButton.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)
        templateButton.imagePosition = .imageLeading
        templateButton.identifier = NSUserInterfaceItemIdentifier("scripts.action.secondary.templates")
        testScriptButton.image = NSImage(systemSymbolName: "play", accessibilityDescription: nil)
        testScriptButton.imagePosition = .imageLeading
        testScriptButton.identifier = NSUserInterfaceItemIdentifier("scripts.action.secondary.test")
        testScriptButton.setAccessibilityLabel(pasteraScriptString("Open Script Test", "打开脚本测试"))
        registerAnchor("scripts.test", view: testScriptButton)
        return PasteraPreferenceActionBarView(
            primaryAction: newButton,
            secondaryActions: [templateButton, testScriptButton]
        )
    }

    private func reloadScripts() {
        emptyStateFillConstraint?.isActive = false
        emptyStateFillConstraint = nil
        listStack.arrangedSubviews.forEach {
            listStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let scripts = (try? repository.fetchAll()) ?? []
        let enabledCount = scripts.filter(\.isEnabled).count
        scriptSummaryLabel.stringValue = pasteraScriptString(
            "\(enabledCount) of \(scripts.count) on",
            "已启用 \(enabledCount)/\(scripts.count)"
        )
        testScriptButton.isEnabled = !scripts.isEmpty
        guard !scripts.isEmpty else {
            emptyStateMinimumHeight = Metrics.emptyStateHeight
            let emptyState = PasteraPreferenceEmptyStateView(
                symbolName: "curlybraces",
                title: pasteraScriptString("No scripts yet", "暂无脚本"),
                message: pasteraScriptString(
                    "Create one from scratch or choose a template.",
                    "可以新建脚本，或从模板快速开始"
                ),
                minimumHeight: Metrics.emptyStateHeight
            )
            listStack.addArrangedSubview(emptyState)
            emptyState.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
            let fillConstraint = emptyState.heightAnchor.constraint(equalTo: listContainer.heightAnchor)
            fillConstraint.priority = .defaultHigh
            fillConstraint.isActive = true
            emptyStateFillConstraint = fillConstraint
            invalidateContentSize()
            return
        }
        emptyStateMinimumHeight = 0
        for (index, script) in scripts.enumerated() {
            let row = makeScriptRow(script, index: index, count: scripts.count)
            listStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
            guard index < scripts.count - 1 else { continue }
            let separator = NSBox()
            separator.boxType = .separator
            listStack.addArrangedSubview(separator)
            separator.widthAnchor.constraint(equalTo: listStack.widthAnchor, constant: -28).isActive = true
        }
        invalidateContentSize()
    }

    var emptyStateMinimumHeightForTesting: CGFloat { emptyStateMinimumHeight }
    var hasEmbeddedTestControlsForTesting: Bool { false }
    var isTestActionEnabledForTesting: Bool { testScriptButton.isEnabled }
    var orderedSectionIDsForTesting: [String] {
        ["scripts.list", "scripts.shortcut"]
    }

    private func makeScriptRow(_ script: ScriptTransform, index: Int, count: Int) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 7, left: 14, bottom: 7, right: 12)
        row.wantsLayer = true
        row.identifier = NSUserInterfaceItemIdentifier("scripts.row.\(script.id.uuidString)")
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.rowHeight).isActive = true

        let labels = NSStackView()
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        let title = NSTextField(labelWithString: script.name)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        let triggers = [script.runOnCopy ? pasteraPreferenceString("Copy") : nil,
                        script.runOnPaste ? pasteraPreferenceString("Pastera Paste") : nil,
                        script.runManually ? pasteraPreferenceString("Manual") : nil]
            .compactMap { $0 }.joined(separator: " · ")
        let detail = NSTextField(labelWithString: triggers.isEmpty
            ? pasteraScriptString("No trigger selected", "未选择执行时机")
            : triggers
        )
        detail.textColor = .secondaryLabelColor
        detail.font = .systemFont(ofSize: 11.5)
        labels.addArrangedSubview(title)
        labels.addArrangedSubview(detail)

        let moveUp = makeInlineButton(
            symbolName: "chevron.up",
            accessibilityLabel: pasteraScriptString("Move \(script.name) Up", "上移 \(script.name)"),
            identifier: "scripts.row.move-up.\(script.id.uuidString)",
            action: #selector(moveScriptUp(_:))
        )
        moveUp.isEnabled = index > 0
        let moveDown = makeInlineButton(
            symbolName: "chevron.down",
            accessibilityLabel: pasteraScriptString("Move \(script.name) Down", "下移 \(script.name)"),
            identifier: "scripts.row.move-down.\(script.id.uuidString)",
            action: #selector(moveScriptDown(_:))
        )
        moveDown.isEnabled = index < count - 1
        let edit = makeInlineButton(
            symbolName: "pencil",
            accessibilityLabel: pasteraScriptString("Edit \(script.name)", "编辑 \(script.name)"),
            identifier: "scripts.row.edit.\(script.id.uuidString)",
            action: #selector(editScript(_:))
        )
        let enabled = NSSwitch()
        enabled.target = self
        enabled.action = #selector(toggleScript(_:))
        enabled.state = script.isEnabled ? .on : .off
        enabled.identifier = NSUserInterfaceItemIdentifier("scripts.row.enable.\(script.id.uuidString)")
        enabled.setAccessibilityLabel(pasteraScriptString("Enable \(script.name)", "启用 \(script.name)"))
        let delete = makeInlineButton(
            symbolName: "trash",
            accessibilityLabel: pasteraScriptString("Delete \(script.name)", "删除 \(script.name)"),
            identifier: "scripts.row.delete.\(script.id.uuidString)",
            action: #selector(deleteScript(_:))
        )

        row.addArrangedSubview(labels)
        row.addArrangedSubview(moveUp)
        row.addArrangedSubview(moveDown)
        row.addArrangedSubview(edit)
        row.addArrangedSubview(enabled)
        row.addArrangedSubview(delete)
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return row
    }

    private func makeInlineButton(
        symbolName: String,
        accessibilityLabel: String,
        identifier: String,
        action: Selector
    ) -> NSButton {
        let button = NSButton(
            image: NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) ?? NSImage(),
            target: self,
            action: action
        )
        button.title = ""
        button.bezelStyle = .inline
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.setAccessibilityLabel(accessibilityLabel)
        button.toolTip = accessibilityLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 22).isActive = true
        button.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return button
    }

    @objc private func addScript() { presentEditor(script: nil) }

    @objc private func showScriptTest() {
        let scripts = (try? repository.fetchAll()) ?? []
        guard !scripts.isEmpty else { return }
        presentScriptSheet(ScriptTestViewController(scripts: scripts, executor: executor))
    }

    @objc private func showTemplates() {
        var selectedTemplate: ScriptTemplate?
        let market = ScriptTemplateMarketViewController { template in
            selectedTemplate = template
        }
        presentScriptSheet(market) { [weak self] in
            guard let selectedTemplate else { return }
            self?.presentEditor(script: selectedTemplate.makeDraft())
        }
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
        presentScriptSheet(editor)
    }

    private func presentScriptSheet(
        _ controller: NSViewController,
        completion: (() -> Void)? = nil
    ) {
        guard let parentWindow = view.window else { return }
        let sheetWindow = NSWindow(contentViewController: controller)
        parentWindow.beginSheet(sheetWindow) { _ in completion?() }
    }

    @objc private func toggleScript(_ sender: NSSwitch) {
        guard var script = script(for: sender) else { return }
        script.isEnabled = sender.state == .on
        script.updatedAt = Int(Date().timeIntervalSince1970)
        try? repository.update(script)
        reloadScripts()
    }

    @objc private func moveScriptUp(_ sender: NSButton) {
        moveScript(sender, offset: -1)
    }

    @objc private func moveScriptDown(_ sender: NSButton) {
        moveScript(sender, offset: 1)
    }

    private func moveScript(_ sender: NSButton, offset: Int) {
        guard let selected = script(for: sender),
              var scripts = try? repository.fetchAll(),
              let sourceIndex = scripts.firstIndex(where: { $0.id == selected.id }) else { return }
        let destinationIndex = sourceIndex + offset
        guard scripts.indices.contains(destinationIndex) else { return }
        scripts.swapAt(sourceIndex, destinationIndex)
        try? repository.replaceOrder(ids: scripts.map(\.id))
        reloadScripts()
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

    private func script(for sender: NSControl) -> ScriptTransform? {
        guard let rawID = sender.identifier?.rawValue,
              let idString = rawID.split(separator: ".").last,
              let id = UUID(uuidString: String(idString)) else { return nil }
        return try? repository.fetchAll().first(where: { $0.id == id })
    }
}

@MainActor
func dismissScriptSheet(_ controller: NSViewController) {
    guard let sheetWindow = controller.view.window,
          let parentWindow = sheetWindow.sheetParent else { return }
    parentWindow.endSheet(sheetWindow)
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
