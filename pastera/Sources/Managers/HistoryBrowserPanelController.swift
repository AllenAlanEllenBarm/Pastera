//
//  HistoryBrowserPanelController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Codex on 2026/06/03.
//
//  Copyright © 2015-2026 Clipy Project.
//

import Cocoa
import Magnet

struct HistoryBrowserPanelBehavior {
    let isPinned: Bool

    var hidesOnDeactivate: Bool {
        !isPinned
    }

    var level: NSWindow.Level {
        isPinned ? .floating : .popUpMenu
    }

    var collectionBehavior: NSWindow.CollectionBehavior {
        isPinned ? [.ignoresCycle] : [.transient, .ignoresCycle]
    }
}

private final class HistoryBrowserPanel: NSPanel {
    var onCancel: (() -> Void)?
    var onKeyDown: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true {
            return
        }
        guard event.keyCode == 53 else {
            super.keyDown(with: event)
            return
        }
        onCancel?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKeyDown?(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class HistoryBrowserPanelController: NSObject, NSWindowDelegate {
    typealias StateUpdate = (inout HistoryMenuPaginationState) -> Void
    typealias RowBuilder = (PasteboardHistoryDetail, Int, @escaping () -> Void) -> HistoryMenuRowView

    private enum Metrics {
        static let width: CGFloat = HistoryBrowserLayout.width
        static let headerHeight: CGFloat = 64
        static let separatorHeight: CGFloat = 1
        static let bottomInset: CGFloat = 8
        static let emptyRowHeight: CGFloat = 36
        static let cornerRadius: CGFloat = PasteraDesignTokens.Metrics.panelCornerRadius
        static let horizontalOffset: CGFloat = 8
    }

    private let currentState: () -> HistoryMenuPaginationState
    private let updateState: (StateUpdate) -> Void
    private let fetchPage: () -> HistoryMenuPage
    private let makeRowView: RowBuilder
    private let selectHistory: (PasteboardHistory.ID, PasteTargetContext?) -> Void

    private let contentView = NSView()
    private let headerView = HistoryMenuHeaderView()
    private let separatorView = NSView()
    private var rowViews = [NSView]()
    private var panel: HistoryBrowserPanel?
    private var pasteTargetContext: PasteTargetContext?
    private var numberShortcutModifierFlags: NSEvent.ModifierFlags = []
    private var activationObserver: Any?
    private var isPinned = false
    var onClose: (() -> Void)?
    var onMainMenuNavigationKeyDown: ((NSEvent) -> Bool)?

    init(
        currentState: @escaping () -> HistoryMenuPaginationState,
        updateState: @escaping (StateUpdate) -> Void,
        fetchPage: @escaping () -> HistoryMenuPage,
        makeRowView: @escaping RowBuilder,
        selectHistory: @escaping (PasteboardHistory.ID, PasteTargetContext?) -> Void
    ) {
        self.currentState = currentState
        self.updateState = updateState
        self.fetchPage = fetchPage
        self.makeRowView = makeRowView
        self.selectHistory = selectHistory
        super.init()
        setupContent()
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    func show(
        at screenPoint: NSPoint,
        pasteTargetContext: PasteTargetContext? = nil,
        triggerKeyCombo: KeyCombo? = nil
    ) {
        self.pasteTargetContext = pasteTargetContext ?? PasteTargetContext.capture()
        numberShortcutModifierFlags = triggerKeyCombo.numberShortcutModifierFlags
        let panel = makePanelIfNeeded()
        reloadResults()
        if !isPinned || !panel.isVisible {
            position(panel, near: screenPoint)
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        headerView.focusDefaultHistoryBrowserItem()
    }

    func show(
        attachedTo anchorFrame: NSRect,
        pasteTargetContext: PasteTargetContext? = nil,
        triggerKeyCombo: KeyCombo? = nil
    ) {
        self.pasteTargetContext = pasteTargetContext ?? PasteTargetContext.capture()
        numberShortcutModifierFlags = triggerKeyCombo.numberShortcutModifierFlags
        let panel = makePanelIfNeeded()
        reloadResults()
        position(panel, attachedTo: anchorFrame)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        headerView.focusDefaultHistoryBrowserItem()
    }

    func close() {
        panel?.makeFirstResponder(nil)
        panel?.orderOut(nil)
        HistoryMenuRowView.hideImagePreview()
        onClose?()
    }

    var visibleFrame: NSRect? {
        guard panel?.isVisible == true else { return nil }
        return panel?.frame
    }

    func reloadResultsIfVisible() {
        guard panel?.isVisible == true else { return }
        reloadResults()
    }

    func refreshAppearanceIfVisible() {
        guard panel?.isVisible == true else { return }
        contentView.layer?.backgroundColor = CPYWindowAppearance.backgroundColor(for: panel?.effectiveAppearance).cgColor
    }

    private func setupContent() {
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = Metrics.cornerRadius
        contentView.layer?.masksToBounds = true

        headerView.usesMenuTrackingKeyMonitor = false
        headerView.onPanelShortcutKeyDown = { [weak self] event in
            self?.handleHistoryPanelShortcut(event) == true
        }
        headerView.onQueryChange = { [weak self] query in
            self?.updateAndReload { $0.updateQuery(query) }
        }
        headerView.onModeChange = { [weak self] mode in
            self?.updateAndReload { $0.updateMode(mode) }
        }
        headerView.onCaseSensitiveChange = { [weak self] caseSensitive in
            self?.updateAndReload { $0.updateCaseSensitive(caseSensitive) }
        }
        headerView.onTypeFilterChange = { [weak self] typeFilter in
            self?.updateAndReload { $0.updateTypeFilter(typeFilter) }
        }
        headerView.onPreviousPage = { [weak self] in
            self?.updateAndReload { $0.goToPreviousPage() }
        }
        headerView.onNextPage = { [weak self] in
            guard let self else { return }
            let page = self.fetchPage()
            self.updateAndReload { $0.goToNextPage(if: page.hasNextPage) }
        }
        separatorView.wantsLayer = true
        separatorView.layer?.backgroundColor = PasteraDesignTokens.colors().separator.cgColor

        contentView.addSubview(headerView)
        contentView.addSubview(separatorView)
    }

    private func makePanelIfNeeded() -> HistoryBrowserPanel {
        if let panel { return panel }

        let panel = HistoryBrowserPanel(
            contentRect: NSRect(x: 0, y: 0, width: Metrics.width, height: Metrics.headerHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.animationBehavior = .none
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.onCancel = { [weak self] in self?.close() }
        panel.onKeyDown = { [weak self] event in
            if self?.handleHistoryPanelShortcut(event) == true {
                return true
            }
            if self?.onMainMenuNavigationKeyDown?(event) == true {
                return true
            }
            return self?.confirmHistoryForNumberShortcut(event) ?? false
        }
        panel.delegate = self
        panel.contentView = contentView
        self.panel = panel
        applyPanelBehavior()
        installActivationObserverIfNeeded()
        return panel
    }

    func setPinned(_ pinned: Bool) {
        guard isPinned != pinned else { return }
        isPinned = pinned
        applyPanelBehavior()
    }

    private func applyPanelBehavior() {
        guard let panel else { return }
        let behavior = HistoryBrowserPanelBehavior(isPinned: isPinned)
        panel.level = behavior.level
        panel.collectionBehavior = behavior.collectionBehavior
        panel.hidesOnDeactivate = behavior.hidesOnDeactivate
    }

    private func installActivationObserverIfNeeded() {
        guard activationObserver == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.workspaceDidActivateApplication(notification)
        }
    }

    private func workspaceDidActivateApplication(_ notification: Notification) {
        guard isPinned, panel?.isVisible == true else { return }
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        guard application.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        pasteTargetContext = PasteTargetContext.capture(from: application)
    }

    private func updateAndReload(_ update: StateUpdate) {
        updateState(update)
        reloadResults()
    }

    private func reloadResults() {
        HistoryMenuRowView.hideImagePreview()
        contentView.layer?.backgroundColor = CPYWindowAppearance.backgroundColor().cgColor
        rowViews.forEach { $0.removeFromSuperview() }
        rowViews.removeAll()

        var page = fetchPage()
        if page.details.isEmpty && page.error == nil && currentState().pageIndex > 0 {
            updateState { $0.resetPage() }
            page = fetchPage()
        }

        headerView.configure(state: currentState(), hasNextPage: page.hasNextPage)

        if let error = page.error {
            addEmptyRow(title: error.historyMenuTitle)
        } else if page.details.isEmpty {
            let title = currentState().hasActiveSearchOptions ? String(localized: "No Results") : String(localized: "No History")
            addEmptyRow(title: title)
        } else {
            for (index, detail) in page.details.enumerated() {
                let rowView = makeRowView(detail, index) { [weak self] in
                    self?.confirmSelection(historyID: detail.history.id)
                }
                rowViews.append(rowView)
                contentView.addSubview(rowView)
            }
        }

        headerView.connectKeyboardNavigation(to: rowViews)
        layoutContent()
    }

    private func addEmptyRow(title: String) {
        let label = NSTextField(labelWithString: title)
        label.frame = NSRect(x: 16, y: 0, width: Metrics.width - 32, height: Metrics.emptyRowHeight)
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabelColor
        label.alignment = .left
        rowViews = [label]
        contentView.addSubview(label)
    }

    private func layoutContent() {
        let rowsHeight = rowViews.reduce(CGFloat(0)) { total, view in
            total + max(view.frame.height, Metrics.emptyRowHeight)
        }
        let height = Metrics.headerHeight + Metrics.separatorHeight + rowsHeight + Metrics.bottomInset
        let size = NSSize(width: Metrics.width, height: height)
        contentView.setFrameSize(size)
        panel?.setContentSize(size)

        headerView.frame = NSRect(
            x: 0,
            y: height - Metrics.headerHeight,
            width: Metrics.width,
            height: Metrics.headerHeight
        )
        separatorView.frame = NSRect(
            x: 10,
            y: height - Metrics.headerHeight - Metrics.separatorHeight,
            width: Metrics.width - 20,
            height: Metrics.separatorHeight
        )

        var currentY = height - Metrics.headerHeight - Metrics.separatorHeight
        for rowView in rowViews {
            let rowHeight = max(rowView.frame.height, Metrics.emptyRowHeight)
            currentY -= rowHeight
            rowView.frame = NSRect(x: 0, y: currentY, width: Metrics.width, height: rowHeight)
        }
    }

    private func position(_ panel: NSPanel, near screenPoint: NSPoint) {
        let screen = NSScreen.screens.first { NSMouseInRect(screenPoint, $0.frame, false) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            panel.setFrameOrigin(screenPoint)
            return
        }

        let size = panel.frame.size
        var origin = NSPoint(
            x: screenPoint.x + Metrics.horizontalOffset,
            y: screenPoint.y - size.height + Metrics.horizontalOffset
        )
        origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - size.width)
        origin.y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - size.height)
        panel.setFrameOrigin(origin)
    }

    private func position(_ panel: NSPanel, attachedTo anchorFrame: NSRect) {
        let screen = NSScreen.screens.first { $0.frame.intersects(anchorFrame) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            panel.setFrameOrigin(NSPoint(x: anchorFrame.maxX + Metrics.horizontalOffset, y: anchorFrame.minY))
            return
        }

        let size = panel.frame.size
        let rightOriginX = anchorFrame.maxX + Metrics.horizontalOffset
        let leftOriginX = anchorFrame.minX - size.width - Metrics.horizontalOffset
        let fitsRight = rightOriginX + size.width <= visibleFrame.maxX
        let originX = fitsRight ? rightOriginX : max(visibleFrame.minX, leftOriginX)
        let preferredY = anchorFrame.maxY - size.height
        let originY = min(max(preferredY, visibleFrame.minY), visibleFrame.maxY - size.height)
        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    private func confirmSelection(historyID: PasteboardHistory.ID) {
        let targetContext = pasteTargetContext
        close()
        selectHistory(historyID, targetContext)
    }

    private func handleHistoryPanelShortcut(_ event: NSEvent) -> Bool {
        guard !headerView.shouldPreserveSearchFieldEditingCommand(event) else {
            return false
        }
        guard let shortcut = HistoryPanelShortcut.matching(event, hotKeyService: AppEnvironment.current.hotKeyService) else {
            return false
        }

        switch shortcut {
        case .search:
            headerView.focusSearchFieldFromShortcut()
        case .previousPage:
            guard currentState().pageIndex > 0 else { return true }
            updateAndReload { $0.goToPreviousPage() }
        case .nextPage:
            let page = fetchPage()
            guard page.hasNextPage else { return true }
            updateAndReload { $0.goToNextPage(if: page.hasNextPage) }
        }
        return true
    }

    private func confirmHistoryForNumberShortcut(_ event: NSEvent) -> Bool {
        let startsAtZero = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsTitleStartWithZero)
        guard let rowIndex = HistoryMenuNumberShortcutMapper.rowIndex(
            for: event,
            startsAtZero: startsAtZero,
            rowCount: rowViews.count,
            allowedModifierFlags: numberShortcutModifierFlags
        ),
            let rowView = rowViews[rowIndex] as? HistoryMenuRowView else {
            return false
        }
        rowView.confirmFromKeyboard()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        HistoryMenuRowView.hideImagePreview()
    }
}

#if DEBUG
extension HistoryBrowserPanelController {
    var pasteTargetProcessIdentifierForTesting: pid_t? {
        pasteTargetContext?.processIdentifier
    }

    func confirmFirstHistoryForTesting() {
        guard let firstRow = rowViews.first as? HistoryMenuRowView else { return }
        firstRow.confirmForTesting()
    }

    func focusFirstHistoryForTesting() {
        guard let firstRow = rowViews.first as? HistoryMenuRowView else { return }
        panel?.makeFirstResponder(firstRow)
    }

    func handleNumberShortcutForTesting(_ event: NSEvent) -> Bool {
        confirmHistoryForNumberShortcut(event)
    }

    func handleHistoryPanelKeyDownForTesting(_ event: NSEvent) -> Bool {
        handleHistoryPanelShortcut(event)
    }

    func dispatchHistoryPanelKeyDownForTesting(_ event: NSEvent) -> Bool {
        panel?.onKeyDown?(event) ?? false
    }

    func dispatchHistoryHeaderMenuTrackingKeyDownForTesting(_ event: NSEvent) -> Bool {
        headerView.handleMenuTrackingKeyDown(event)
    }

    func dispatchFirstHistoryRowKeyDownForTesting(_ event: NSEvent) -> Bool {
        guard let firstRow = rowViews.first as? HistoryMenuRowView else { return false }
        firstRow.keyDown(with: event)
        return true
    }

    func dispatchSearchFieldKeyEquivalentForTesting(_ event: NSEvent) -> Bool {
        headerView.dispatchSearchFieldKeyEquivalentForTesting(event)
    }

    func focusSearchFieldForTesting() {
        headerView.focusSearchFieldFromShortcut()
    }

    var isSearchFieldFocusedForTesting: Bool {
        headerView.isSearchFieldFocusedForTesting
    }

    var contentBackgroundAlphaForTesting: CGFloat {
        CGFloat(contentView.layer?.backgroundColor?.alpha ?? 0)
    }
}
#endif

private extension Optional where Wrapped == KeyCombo {
    var numberShortcutModifierFlags: NSEvent.ModifierFlags {
        guard let keyCombo = self, !keyCombo.doubledModifiers else { return [] }
        return keyCombo.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask)
    }
}
