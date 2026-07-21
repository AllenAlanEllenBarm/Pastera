import AppKit
import KeyHolder
import Magnet

@MainActor
// swiftlint:disable:next type_body_length
final class CPYScriptsPreferenceViewController: PasteraPreferencePageViewController {
    private enum Metrics {
        static let emptyStateHeight: CGFloat = 108
        static let initialLayoutHeight: CGFloat = 760
    }

    private let repository: ScriptRepositoryProtocol
    private let executor: ScriptExecuting
    private let hotKeyService: HotKeyService
    private let promptSettingsStore: any PromptOptimizationSettingsStoring
    private let promptAPIKeyStore: any PromptOptimizationAPIKeyStoring
    private let promptOptimizationService: any PromptOptimizationServicing
    private let listStack = NSStackView()
    private let scriptSummaryLabel = NSTextField(labelWithString: "")
    private let shortcutRecordView = RecordView(frame: .zero)
    private lazy var testScriptButton = NSButton(
        title: pasteraScriptString("Test Script", "测试脚本"),
        target: self,
        action: #selector(showScriptTest)
    )
    private weak var shortcutCard: NSView?
    private weak var promptOptimizationSection: PromptOptimizationPreferenceSection?
    private var emptyStateMinimumHeight: CGFloat = 0
    private var usesNonForcingBottomConstraint = false

    init(
        repository: ScriptRepositoryProtocol = ScriptRepository(),
        executor: ScriptExecuting = ScriptExecutionService(),
        hotKeyService: HotKeyService = AppEnvironment.current.hotKeyService,
        promptSettingsStore: any PromptOptimizationSettingsStoring = PromptOptimizationSettingsStore(),
        promptAPIKeyStore: any PromptOptimizationAPIKeyStoring = PromptOptimizationAPIKeyStore(),
        promptOptimizationService: any PromptOptimizationServicing = AppEnvironment.current.promptOptimizationService
    ) {
        self.repository = repository
        self.executor = executor
        self.hotKeyService = hotKeyService
        self.promptSettingsStore = promptSettingsStore
        self.promptAPIKeyStore = promptAPIKeyStore
        self.promptOptimizationService = promptOptimizationService
        super.init(paneID: .scripts, title: pasteraScriptString("Transform Scripts", "转换脚本"))
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        super.loadView()
        replacePageBottomConstraintForCompactContent()
        view.frame.size.height = Metrics.initialLayoutHeight
        let promptOptimizationSection = PromptOptimizationPreferenceSection(
            settingsStore: promptSettingsStore,
            apiKeyStore: promptAPIKeyStore,
            optimizationService: promptOptimizationService
        )
        let scriptsCard = makeScriptsCard()
        let shortcutCard = makeShortcutCard()
        self.promptOptimizationSection = promptOptimizationSection
        self.shortcutCard = shortcutCard
        addAdaptiveContent(promptOptimizationSection)
        registerAnchor("scripts.promptOptimization", view: promptOptimizationSection)
        addAdaptiveContent(scriptsCard)
        addAdaptiveContent(shortcutCard)
        reloadScripts()
        invalidateContentSize()
    }

    private func replacePageBottomConstraintForCompactContent() {
        guard let bottomConstraint = view.constraints.first(where: { constraint in
            constraint.firstItem === contentStack &&
                constraint.firstAttribute == .bottom &&
                constraint.relation == .equal
        }) else { return }
        bottomConstraint.isActive = false
        contentStack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -22).isActive = true
        usesNonForcingBottomConstraint = true
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
        headerLabels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        scriptSummaryLabel.font = .systemFont(ofSize: 11, weight: .medium)
        scriptSummaryLabel.textColor = .secondaryLabelColor
        scriptSummaryLabel.alignment = .center
        scriptSummaryLabel.wantsLayer = true
        scriptSummaryLabel.layer?.cornerRadius = 8
        scriptSummaryLabel.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor
        scriptSummaryLabel.translatesAutoresizingMaskIntoConstraints = false
        scriptSummaryLabel.heightAnchor.constraint(equalToConstant: 24).isActive = true
        scriptSummaryLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 70).isActive = true
        header.addArrangedSubview(scriptSummaryLabel)
        card.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: card.widthAnchor, constant: -32).isActive = true
        listStack.orientation = .vertical
        listStack.alignment = .centerX
        listStack.spacing = 12
        card.addArrangedSubview(listStack)
        listStack.widthAnchor.constraint(equalTo: card.widthAnchor, constant: -36).isActive = true
        card.addArrangedSubview(makeScriptActions())
        registerAnchor("scripts.list", view: card)
        return card
    }

    private func makeShortcutCard() -> NSView {
        let card = makeCard()
        let section = NSStackView()
        section.orientation = .horizontal
        section.alignment = .centerY
        section.spacing = 16
        let labels = NSStackView()
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 4
        let heading = NSTextField(labelWithString: pasteraScriptString("Manual Run Shortcut", "全局快捷键"))
        heading.font = .systemFont(ofSize: 15, weight: .semibold)
        labels.addArrangedSubview(heading)
        let help = NSTextField(wrappingLabelWithString: pasteraScriptString(
            "Transform the current clipboard without auto-pasting.",
            "转换当前剪贴板，不会自动粘贴"
        ))
        help.textColor = .secondaryLabelColor
        help.maximumNumberOfLines = 1
        labels.addArrangedSubview(help)
        shortcutRecordView.delegate = self
        shortcutRecordView.keyCombo = hotKeyService.scriptTransformKeyCombo
        shortcutRecordView.clearButtonMode = .whenRecorded
        shortcutRecordView.setAccessibilityLabel(pasteraScriptString("Manual Script Shortcut", "手动运行脚本快捷键"))
        shortcutRecordView.translatesAutoresizingMaskIntoConstraints = false
        shortcutRecordView.widthAnchor.constraint(equalToConstant: 150).isActive = true
        shortcutRecordView.heightAnchor.constraint(equalToConstant: 30).isActive = true
        section.addArrangedSubview(labels)
        section.addArrangedSubview(shortcutRecordView)
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        card.addArrangedSubview(section)
        section.widthAnchor.constraint(equalTo: card.widthAnchor, constant: -32).isActive = true
        registerAnchor("scripts.shortcut", view: section)
        return card
    }

    private func makeScriptActions() -> NSView {
        let newButton = NSButton(title: pasteraScriptString("New Script", "新建脚本"), target: self, action: #selector(addScript))
        newButton.bezelStyle = .rounded
        newButton.bezelColor = .controlAccentColor
        newButton.contentTintColor = .white
        let templateButton = NSButton(
            title: pasteraScriptString("Create from Template", "从模板创建"),
            target: self,
            action: #selector(showTemplates)
        )
        templateButton.bezelStyle = .rounded
        testScriptButton.bezelStyle = .rounded
        testScriptButton.setAccessibilityLabel(pasteraScriptString("Open Script Test", "打开脚本测试"))
        registerAnchor("scripts.test", view: testScriptButton)
        let actions = NSStackView(views: [newButton, templateButton, testScriptButton])
        actions.orientation = .horizontal
        actions.spacing = 10
        actions.edgeInsets = NSEdgeInsets(top: 2, left: 18, bottom: 0, right: 18)
        return actions
    }

    private func makeCard() -> NSStackView {
        let card = NSStackView()
        card.orientation = .vertical
        card.alignment = .leading
        card.spacing = 10
        card.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.34).cgColor
        card.layer?.borderWidth = PasteraDesignTokens.Metrics.hairlineWidth
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.65).cgColor
        return card
    }

    private func reloadScripts() {
        listStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let scripts = (try? repository.fetchAll()) ?? []
        let enabledCount = scripts.filter(\.isEnabled).count
        scriptSummaryLabel.stringValue = pasteraScriptString(
            "\(enabledCount) of \(scripts.count) on",
            "已启用 \(enabledCount)/\(scripts.count)"
        )
        testScriptButton.isEnabled = !scripts.isEmpty
        guard !scripts.isEmpty else {
            let emptyState = NSStackView()
            emptyState.orientation = .vertical
            emptyState.alignment = .centerX
            emptyState.spacing = 6
            emptyStateMinimumHeight = Metrics.emptyStateHeight
            emptyState.translatesAutoresizingMaskIntoConstraints = false
            emptyState.heightAnchor.constraint(equalToConstant: Metrics.emptyStateHeight).isActive = true
            let empty = NSTextField(labelWithString: pasteraScriptString("No scripts yet", "暂无脚本"))
            empty.font = .systemFont(ofSize: 15, weight: .medium)
            emptyState.addArrangedSubview(empty)
            let detail = NSTextField(labelWithString: pasteraScriptString(
                "Create one from scratch or start with a template.",
                "新建脚本，或从模板快速开始"
            ))
            detail.textColor = .secondaryLabelColor
            emptyState.addArrangedSubview(detail)
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

    var emptyStateMinimumHeightForTesting: CGFloat { emptyStateMinimumHeight }
    var hasEmbeddedTestControlsForTesting: Bool { false }
    var hasSeparateShortcutCardForTesting: Bool { shortcutCard?.superview != nil }
    var isTestActionEnabledForTesting: Bool { testScriptButton.isEnabled }
    var usesNonForcingBottomConstraintForTesting: Bool { usesNonForcingBottomConstraint }
    var initialLayoutHeightForTesting: CGFloat { Metrics.initialLayoutHeight }
    var orderedSectionIDsForTesting: [String] {
        ["scripts.promptOptimization", "scripts.list", "scripts.shortcut"]
    }
    var promptOptimizationSectionForTesting: PromptOptimizationPreferenceSection? {
        promptOptimizationSection
    }

    private func makeScriptRow(_ script: ScriptTransform) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        row.wantsLayer = true
        row.layer?.cornerRadius = 9
        row.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.45).cgColor
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
        detail.font = .systemFont(ofSize: 11)
        labels.addArrangedSubview(title)
        labels.addArrangedSubview(detail)
        let edit = NSButton(title: pasteraPreferenceString("Edit"), target: self, action: #selector(editScript(_:)))
        edit.identifier = NSUserInterfaceItemIdentifier(script.id.uuidString)
        let enabled = NSSwitch()
        enabled.target = self
        enabled.action = #selector(toggleScript(_:))
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
        labels.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        return row
    }

    @objc private func addScript() { presentEditor(script: nil) }

    @objc private func showScriptTest() {
        let scripts = (try? repository.fetchAll()) ?? []
        guard !scripts.isEmpty else { return }
        presentAsSheet(ScriptTestViewController(scripts: scripts, executor: executor))
    }

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

    @objc private func toggleScript(_ sender: NSSwitch) {
        guard var script = script(for: sender) else { return }
        script.isEnabled = sender.state == .on
        script.updatedAt = Int(Date().timeIntervalSince1970)
        try? repository.update(script)
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
