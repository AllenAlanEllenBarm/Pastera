//
//  CPYShortcutsPreferenceViewController.swift
//
//  Pastera
//

import AppKit
import KeyHolder
import Magnet

final class CPYShortcutsPreferenceViewController: PasteraPreferencePageViewController {
    private enum Metrics {
        static let recordWidth: CGFloat = 240
        static let recordHeight: CGFloat = 24
        static let rowMinimumHeight: CGFloat = 38
        static let titleContentSpacing: CGFloat = 4
        static let restoredStatusDuration: TimeInterval = 1.5
    }

    private var mainShortcutRecordView = RecordView(frame: .zero)
    private var historyShortcutRecordView = RecordView(frame: .zero)
    private var snippetShortcutRecordView = RecordView(frame: .zero)
    private var passwordVaultShortcutRecordView = RecordView(frame: .zero)
    private var historySearchShortcutRecordView = RecordView(frame: .zero)
    private var historyPreviousPageShortcutRecordView = RecordView(frame: .zero)
    private var historyNextPageShortcutRecordView = RecordView(frame: .zero)
    private var restoredStatusView = PasteraPreferenceStatusView(
        text: pasteraPreferenceString("Restored Defaults"),
        style: .success
    )

    private var restoreStatusDismissWorkItem: DispatchWorkItem?
    private var restoreStatusGeneration = 0

    init() {
        super.init(paneID: .shortcuts, title: pasteraPreferenceString("Shortcuts"))
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        restoreStatusDismissWorkItem?.cancel()
    }

    override func loadView() {
        resetViewState()
        super.loadView()
        if let titleView = contentStack.arrangedSubviews.first {
            contentStack.setCustomSpacing(Metrics.titleContentSpacing, after: titleView)
        }
        configureRecordViews()
        buildMenuGroup()
        buildHistoryPanelGroup()
        configureRestoredStatus()
        refreshRecordViews()
    }

    private func resetViewState() {
        restoreStatusDismissWorkItem?.cancel()
        restoreStatusDismissWorkItem = nil
        restoreStatusGeneration += 1
        shortcutRecordViews.forEach { $0.delegate = nil }
        removeExistingContent()

        mainShortcutRecordView = RecordView(frame: .zero)
        historyShortcutRecordView = RecordView(frame: .zero)
        snippetShortcutRecordView = RecordView(frame: .zero)
        passwordVaultShortcutRecordView = RecordView(frame: .zero)
        historySearchShortcutRecordView = RecordView(frame: .zero)
        historyPreviousPageShortcutRecordView = RecordView(frame: .zero)
        historyNextPageShortcutRecordView = RecordView(frame: .zero)
        restoredStatusView = PasteraPreferenceStatusView(
            text: pasteraPreferenceString("Restored Defaults"),
            style: .success
        )
    }

    private func removeExistingContent() {
        contentStack.arrangedSubviews.forEach { arrangedSubview in
            NSLayoutConstraint.deactivate(contentStack.constraints.filter {
                $0.firstItem === arrangedSubview || $0.secondItem === arrangedSubview
            })
            contentStack.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }
        if let container = contentStack.superview {
            NSLayoutConstraint.deactivate(container.constraints.filter {
                $0.firstItem === contentStack || $0.secondItem === contentStack
            })
        }
        contentStack.removeFromSuperview()
    }

    private var shortcutRecordViews: [RecordView] {
        [
            mainShortcutRecordView,
            historyShortcutRecordView,
            snippetShortcutRecordView,
            passwordVaultShortcutRecordView,
            historySearchShortcutRecordView,
            historyPreviousPageShortcutRecordView,
            historyNextPageShortcutRecordView
        ]
    }

    private func configureRecordViews() {
        let records: [(RecordView, String, String)] = [
            (mainShortcutRecordView, "shortcuts.main", pasteraPreferenceString("Main")),
            (historyShortcutRecordView, "shortcuts.history", pasteraPreferenceString("History")),
            (snippetShortcutRecordView, "shortcuts.snippet", pasteraPreferenceString("Snippets")),
            (passwordVaultShortcutRecordView, "shortcuts.passwordVault", pasteraPreferenceString("Password Vault")),
            (historySearchShortcutRecordView, "shortcuts.historyPanel.search", pasteraPreferenceString("Search")),
            (
                historyPreviousPageShortcutRecordView,
                "shortcuts.historyPanel.previousPage",
                pasteraPreferenceString("Previous Page")
            ),
            (historyNextPageShortcutRecordView, "shortcuts.historyPanel.nextPage", pasteraPreferenceString("Next Page"))
        ]
        records.forEach { recordView, identifier, accessibilityLabel in
            recordView.delegate = self
            recordView.clearButtonMode = .whenRecorded
            recordView.cornerRadius = PasteraDesignTokens.Metrics.compactRowCornerRadius
            recordView.borderWidth = PasteraDesignTokens.Metrics.hairlineWidth
            recordView.setAccessibilityIdentifier(identifier)
            recordView.setAccessibilityLabel(accessibilityLabel)
            recordView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                recordView.widthAnchor.constraint(equalToConstant: Metrics.recordWidth),
                recordView.heightAnchor.constraint(equalToConstant: Metrics.recordHeight)
            ])
        }
    }

    private func buildMenuGroup() {
        let group = PasteraPreferenceGroupView(
            title: pasteraPreferenceString("Menu Shortcuts"),
            symbolName: "command",
            accentColor: .systemOrange
        )
        lockNaturalHeight(of: group)
        group.addRow(makeShortcutRow(title: pasteraPreferenceString("Main"), recordView: mainShortcutRecordView))
        group.addRow(makeShortcutRow(title: pasteraPreferenceString("History"), recordView: historyShortcutRecordView))
        group.addRow(makeShortcutRow(title: pasteraPreferenceString("Snippets"), recordView: snippetShortcutRecordView))
        group.addRow(makeShortcutRow(title: pasteraPreferenceString("Password Vault"), recordView: passwordVaultShortcutRecordView))
        addResetAction(
            to: group,
            identifier: "shortcuts.menu.reset",
            action: #selector(resetMenuShortcuts(_:))
        )
        addGroup(group, anchorID: "shortcuts.menu")
    }

    private func buildHistoryPanelGroup() {
        let group = PasteraPreferenceGroupView(
            title: pasteraPreferenceString("History Panel Shortcuts"),
            symbolName: "clock.arrow.circlepath",
            accentColor: .systemTeal
        )
        lockNaturalHeight(of: group)
        group.addRow(makeShortcutRow(title: pasteraPreferenceString("Search"), recordView: historySearchShortcutRecordView))
        group.addRow(makeShortcutRow(
            title: pasteraPreferenceString("Previous Page"),
            recordView: historyPreviousPageShortcutRecordView
        ))
        group.addRow(makeShortcutRow(
            title: pasteraPreferenceString("Next Page"),
            recordView: historyNextPageShortcutRecordView
        ))
        addResetAction(
            to: group,
            identifier: "shortcuts.historyPanel.reset",
            action: #selector(resetHistoryPanelShortcuts(_:))
        )
        addGroup(group, anchorID: "shortcuts.historyPanel")
    }

    private func makeShortcutRow(title: String, recordView: RecordView) -> PasteraPreferenceSettingRowView {
        PasteraPreferenceSettingRowView(
            title: title,
            control: recordView,
            minimumHeight: Metrics.rowMinimumHeight
        )
    }

    private func lockNaturalHeight(of group: PasteraPreferenceGroupView) {
        group.setContentHuggingPriority(.required, for: .vertical)
        group.setContentCompressionResistancePriority(.required, for: .vertical)
    }

    private func addResetAction(to group: PasteraPreferenceGroupView, identifier: String, action: Selector) {
        let button = NSButton(title: pasteraPreferenceString("Reset to Defaults"), target: self, action: action)
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.setAccessibilityIdentifier(identifier)

        group.setHeaderAccessory(button)
    }

    private func configureRestoredStatus() {
        restoredStatusView.isHidden = true
        restoredStatusView.setAccessibilityIdentifier("shortcuts.restoredStatus")
        contentStack.addArrangedSubview(restoredStatusView)
    }

    @objc private func resetMenuShortcuts(_ sender: Any?) {
        AppEnvironment.current.hotKeyService.resetMenuShortcutsToDefaults()
        didRestoreDefaults()
    }

    @objc private func resetHistoryPanelShortcuts(_ sender: Any?) {
        AppEnvironment.current.hotKeyService.resetHistoryPanelShortcutsToDefaults()
        didRestoreDefaults()
    }

    private func didRestoreDefaults() {
        refreshRecordViews()
        showRestoredStatus()
    }

    private func refreshRecordViews() {
        let service = AppEnvironment.current.hotKeyService
        mainShortcutRecordView.keyCombo = service.mainKeyCombo
        historyShortcutRecordView.keyCombo = service.historyKeyCombo
        snippetShortcutRecordView.keyCombo = service.snippetKeyCombo
        passwordVaultShortcutRecordView.keyCombo = service.passwordVaultKeyCombo
        historySearchShortcutRecordView.keyCombo = service.historyPanelKeyCombo(for: .search)
        historyPreviousPageShortcutRecordView.keyCombo = service.historyPanelKeyCombo(for: .previousPage)
        historyNextPageShortcutRecordView.keyCombo = service.historyPanelKeyCombo(for: .nextPage)
    }

    private func showRestoredStatus() {
        restoreStatusDismissWorkItem?.cancel()
        restoreStatusGeneration += 1
        let generation = restoreStatusGeneration
        restoredStatusView.isHidden = false
        invalidateContentSize()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.restoreStatusGeneration == generation else { return }
            self.restoredStatusView.isHidden = true
            self.invalidateContentSize()
            self.restoreStatusDismissWorkItem = nil
        }
        restoreStatusDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Metrics.restoredStatusDuration,
            execute: workItem
        )
    }
}

extension CPYShortcutsPreferenceViewController: RecordViewDelegate {
    func recordViewShouldBeginRecording(_ recordView: RecordView) -> Bool {
        true
    }

    func recordView(_ recordView: RecordView, canRecordKeyCombo keyCombo: KeyCombo) -> Bool {
        true
    }

    func recordView(_ recordView: RecordView, didChangeKeyCombo keyCombo: KeyCombo?) {
        switch recordView {
        case mainShortcutRecordView:
            AppEnvironment.current.hotKeyService.change(with: .main, keyCombo: keyCombo)
        case historyShortcutRecordView:
            AppEnvironment.current.hotKeyService.change(with: .history, keyCombo: keyCombo)
        case snippetShortcutRecordView:
            AppEnvironment.current.hotKeyService.change(with: .snippet, keyCombo: keyCombo)
        case passwordVaultShortcutRecordView:
            AppEnvironment.current.hotKeyService.change(with: .passwordVault, keyCombo: keyCombo)
        case historySearchShortcutRecordView:
            AppEnvironment.current.hotKeyService.changeHistoryPanelKeyCombo(.search, keyCombo: keyCombo)
        case historyPreviousPageShortcutRecordView:
            AppEnvironment.current.hotKeyService.changeHistoryPanelKeyCombo(.previousPage, keyCombo: keyCombo)
        case historyNextPageShortcutRecordView:
            AppEnvironment.current.hotKeyService.changeHistoryPanelKeyCombo(.nextPage, keyCombo: keyCombo)
        default:
            break
        }
    }

    func recordViewDidEndRecording(_ recordView: RecordView) {}
}

#if DEBUG
extension CPYShortcutsPreferenceViewController {
    var shortcutRowMinimumHeightForTesting: CGFloat { Metrics.rowMinimumHeight }
    var shortcutRecordHeightForTesting: CGFloat { Metrics.recordHeight }

    var restoreStatusDismissWorkItemForTesting: DispatchWorkItem? {
        restoreStatusDismissWorkItem
    }
}
#endif
