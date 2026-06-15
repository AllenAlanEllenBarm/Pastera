//
//  CPYShortcutsPreferenceViewController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/02/26.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import KeyHolder
import Magnet

class CPYShortcutsPreferenceViewController: NSViewController {

    // MARK: - Properties
    private enum Metrics {
        static let width: CGFloat = 520
        static let rowHeight: CGFloat = 32
        static let rowSpacing: CGFloat = 10
        static let sectionHeight: CGFloat = 18
        static let sectionSpacing: CGFloat = 14
        static let labelWidth: CGFloat = 120
        static let controlX: CGFloat = 140
        static let controlWidth: CGFloat = 320
        static let recordHeight: CGFloat = 28
        static let contentHeight: CGFloat = sectionHeight + 8
            + (rowHeight + rowSpacing) * 3
            + sectionSpacing
            + sectionHeight + 8
            + (rowHeight + rowSpacing) * 3
            - rowSpacing
    }

    private let mainShortcutRecordView = RecordView(frame: .zero)
    private let historyShortcutRecordView = RecordView(frame: .zero)
    private let historySearchShortcutRecordView = RecordView(frame: .zero)
    private let historyPreviousPageShortcutRecordView = RecordView(frame: .zero)
    private let historyNextPageShortcutRecordView = RecordView(frame: .zero)
    private let snippetShortcutRecordView = RecordView(frame: .zero)

    // MARK: - Initialize
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: Metrics.width, height: Metrics.contentHeight))
        buildShortcutForm()
        shortcutRecordViews.forEach { $0.delegate = self }
        prepareHotKeys()
    }

}

// MARK: - Shortcut
private extension CPYShortcutsPreferenceViewController {
    var shortcutRecordViews: [RecordView] {
        [
            mainShortcutRecordView,
            historyShortcutRecordView,
            historySearchShortcutRecordView,
            historyPreviousPageShortcutRecordView,
            historyNextPageShortcutRecordView,
            snippetShortcutRecordView
        ]
    }

    func buildShortcutForm() {
        var nextMaxY = view.bounds.maxY
        addSectionTitle("Menu Shortcuts", nextMaxY: &nextMaxY)
        addShortcutRow(label: "Main", recordView: mainShortcutRecordView, nextMaxY: &nextMaxY)
        addShortcutRow(label: "History", recordView: historyShortcutRecordView, nextMaxY: &nextMaxY)
        addShortcutRow(label: "Snippets", recordView: snippetShortcutRecordView, nextMaxY: &nextMaxY)

        nextMaxY -= Metrics.sectionSpacing
        addSectionTitle("History Panel Shortcuts", nextMaxY: &nextMaxY)
        addShortcutRow(label: "Search", recordView: historySearchShortcutRecordView, nextMaxY: &nextMaxY)
        addShortcutRow(label: "Previous Page", recordView: historyPreviousPageShortcutRecordView, nextMaxY: &nextMaxY)
        addShortcutRow(label: "Next Page", recordView: historyNextPageShortcutRecordView, nextMaxY: &nextMaxY)
    }

    func addSectionTitle(_ localizationKey: String, nextMaxY: inout CGFloat) {
        let title = NSTextField(labelWithString: String(localized: String.LocalizationValue(localizationKey)))
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        title.alignment = .left
        title.frame = NSRect(
            x: 0,
            y: nextMaxY - Metrics.sectionHeight,
            width: Metrics.width,
            height: Metrics.sectionHeight
        )
        view.addSubview(title)
        nextMaxY -= Metrics.sectionHeight + 8
    }

    func addShortcutRow(label localizationKey: String, recordView: RecordView, nextMaxY: inout CGFloat) {
        let row = NSView(frame: NSRect(
            x: 0,
            y: nextMaxY - Metrics.rowHeight,
            width: Metrics.width,
            height: Metrics.rowHeight
        ))
        let label = NSTextField(labelWithString: localizedRowLabel(localizationKey))
        label.font = .systemFont(ofSize: 12.5, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .left
        label.frame = NSRect(
            x: 0,
            y: (Metrics.rowHeight - 18) / 2,
            width: Metrics.labelWidth,
            height: 18
        )
        recordView.frame = NSRect(
            x: Metrics.controlX,
            y: (Metrics.rowHeight - Metrics.recordHeight) / 2,
            width: Metrics.controlWidth,
            height: Metrics.recordHeight
        )
        row.addSubview(label)
        row.addSubview(recordView)
        view.addSubview(row)
        nextMaxY -= Metrics.rowHeight + Metrics.rowSpacing
    }

    func localizedRowLabel(_ localizationKey: String) -> String {
        let text = String(localized: String.LocalizationValue(localizationKey))
        let usesFullWidthColon = text.range(of: "\\p{Han}", options: .regularExpression) != nil
        return text + (usesFullWidthColon ? "：" : ":")
    }

    func prepareHotKeys() {
        mainShortcutRecordView.keyCombo = AppEnvironment.current.hotKeyService.mainKeyCombo
        historyShortcutRecordView.keyCombo = AppEnvironment.current.hotKeyService.historyKeyCombo
        historySearchShortcutRecordView.keyCombo = AppEnvironment.current.hotKeyService.historyPanelKeyCombo(for: .search)
        historyPreviousPageShortcutRecordView.keyCombo = AppEnvironment.current.hotKeyService.historyPanelKeyCombo(for: .previousPage)
        historyNextPageShortcutRecordView.keyCombo = AppEnvironment.current.hotKeyService.historyPanelKeyCombo(for: .nextPage)
        snippetShortcutRecordView.keyCombo = AppEnvironment.current.hotKeyService.snippetKeyCombo
    }
}

// MARK: - RecordView Delegate
extension CPYShortcutsPreferenceViewController: RecordViewDelegate {
    func recordViewShouldBeginRecording(_ recordView: RecordView) -> Bool {
        return true
    }

    func recordView(_ recordView: RecordView, canRecordKeyCombo keyCombo: KeyCombo) -> Bool {
        return true
    }

    func recordView(_ recordView: RecordView, didChangeKeyCombo keyCombo: KeyCombo?) {
        switch recordView {
        case mainShortcutRecordView:
            AppEnvironment.current.hotKeyService.change(with: .main, keyCombo: keyCombo)
        case historyShortcutRecordView:
            AppEnvironment.current.hotKeyService.change(with: .history, keyCombo: keyCombo)
        case historySearchShortcutRecordView:
            AppEnvironment.current.hotKeyService.changeHistoryPanelKeyCombo(.search, keyCombo: keyCombo)
        case historyPreviousPageShortcutRecordView:
            AppEnvironment.current.hotKeyService.changeHistoryPanelKeyCombo(.previousPage, keyCombo: keyCombo)
        case historyNextPageShortcutRecordView:
            AppEnvironment.current.hotKeyService.changeHistoryPanelKeyCombo(.nextPage, keyCombo: keyCombo)
        case snippetShortcutRecordView:
            AppEnvironment.current.hotKeyService.change(with: .snippet, keyCombo: keyCombo)
        default: break
        }
    }

    func recordViewDidEndRecording(_ recordView: RecordView) {}
}
