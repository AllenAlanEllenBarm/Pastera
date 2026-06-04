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

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 53 else {
            super.keyDown(with: event)
            return
        }
        onCancel?()
    }
}

final class HistoryBrowserPanelController: NSObject, NSWindowDelegate {
    typealias StateUpdate = (inout HistoryMenuPaginationState) -> Void
    typealias RowBuilder = (PasteboardHistoryDetail, Int, @escaping () -> Void) -> HistoryMenuRowView

    private enum Metrics {
        static let width: CGFloat = HistoryBrowserLayout.width
        static let headerHeight: CGFloat = 58
        static let separatorHeight: CGFloat = 1
        static let bottomInset: CGFloat = 6
        static let emptyRowHeight: CGFloat = 36
        static let cornerRadius: CGFloat = 14
        static let horizontalOffset: CGFloat = 8
    }

    private let currentState: () -> HistoryMenuPaginationState
    private let updateState: (StateUpdate) -> Void
    private let fetchPage: () -> HistoryMenuPage
    private let makeRowView: RowBuilder
    private let selectHistory: (PasteboardHistory.ID, NSRunningApplication?) -> Void

    private let contentView = NSView()
    private let headerView = HistoryMenuHeaderView()
    private let separatorView = NSView()
    private var rowViews = [NSView]()
    private var panel: HistoryBrowserPanel?
    private var sourceApplication: NSRunningApplication?
    private var activationObserver: Any?
    private var isPinned = false

    init(
        currentState: @escaping () -> HistoryMenuPaginationState,
        updateState: @escaping (StateUpdate) -> Void,
        fetchPage: @escaping () -> HistoryMenuPage,
        makeRowView: @escaping RowBuilder,
        selectHistory: @escaping (PasteboardHistory.ID, NSRunningApplication?) -> Void
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

    func show(at screenPoint: NSPoint) {
        sourceApplication = NSWorkspace.shared.frontmostApplication.flatMap { application in
            application.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : application
        }
        let panel = makePanelIfNeeded()
        reloadResults()
        if !isPinned || !panel.isVisible {
            position(panel, near: screenPoint)
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        headerView.focusDefaultHistoryBrowserItem()
    }

    func show(attachedTo anchorFrame: NSRect) {
        sourceApplication = NSWorkspace.shared.frontmostApplication.flatMap { application in
            application.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : application
        }
        let panel = makePanelIfNeeded()
        reloadResults()
        position(panel, attachedTo: anchorFrame)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        headerView.focusDefaultHistoryBrowserItem()
    }

    func close() {
        panel?.orderOut(nil)
        HistoryMenuRowView.hideImagePreview()
    }

    var visibleFrame: NSRect? {
        guard panel?.isVisible == true else { return nil }
        return panel?.frame
    }

    private func setupContent() {
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = Metrics.cornerRadius
        contentView.layer?.masksToBounds = true

        headerView.usesMenuTrackingKeyMonitor = false
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
        separatorView.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor

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
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.onCancel = { [weak self] in self?.close() }
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
        sourceApplication = application
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
            x: 9,
            y: height - Metrics.headerHeight - Metrics.separatorHeight,
            width: Metrics.width - 18,
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
        let application = sourceApplication
        close()
        selectHistory(historyID, application)
    }

    func windowWillClose(_ notification: Notification) {
        HistoryMenuRowView.hideImagePreview()
    }
}
