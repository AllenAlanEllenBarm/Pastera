//
//  MainMenuPanelController.swift
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

enum MainMenuPanelLayout {
    static let width: CGFloat = 168
    static let topInset: CGFloat = 4
    static let bottomInset: CGFloat = 4
    static let rowHeight: CGFloat = 30
    static let headerHeight: CGFloat = 38
    static let separatorHeight: CGFloat = 1
    static let separatorHorizontalInset: CGFloat = 10
    static let separatorVerticalInset: CGFloat = 4
    static let separatorAlpha: CGFloat = 0.22
    static let cornerRadius: CGFloat = 14
    static let screenPadding: CGFloat = 8
}

struct MainMenuPanelBehavior {
    let isPinned: Bool

    init(isPinned: Bool = true) {
        self.isPinned = isPinned
    }

    var hidesOnDeactivate: Bool { !isPinned }
    var level: NSWindow.Level { isPinned ? .floating : .popUpMenu }
    var collectionBehavior: NSWindow.CollectionBehavior {
        isPinned ? [.ignoresCycle] : [.transient, .ignoresCycle]
    }
    var isMovableByWindowBackground: Bool { isPinned }
}

enum MainMenuPanelItem {
    case separator
    case action(title: String, image: NSImage?, onSelect: () -> Void)
}

private final class MainMenuPanel: NSPanel {
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

final class MainMenuPanelController: NSObject, NSWindowDelegate {
    private let historyTitle: String
    private let historyImage: NSImage?
    private let itemsProvider: () -> [MainMenuPanelItem]
    private let onOpenHistory: () -> Void
    private let onPinnedChange: (Bool) -> Void

    private let contentView = NSView()
    private var panel: MainMenuPanel?
    private var isPinned = true

    init(
        historyTitle: String,
        historyImage: NSImage?,
        itemsProvider: @escaping () -> [MainMenuPanelItem],
        onOpenHistory: @escaping () -> Void,
        onPinnedChange: @escaping (Bool) -> Void
    ) {
        self.historyTitle = historyTitle
        self.historyImage = historyImage
        self.itemsProvider = itemsProvider
        self.onOpenHistory = onOpenHistory
        self.onPinnedChange = onPinnedChange
        super.init()
    }

    func show(at screenPoint: NSPoint, pinned: Bool = true) {
        isPinned = pinned
        let panel = makePanelIfNeeded()
        reloadContent()
        applyBehavior(to: panel)
        if !panel.isVisible || !pinned {
            position(panel, near: screenPoint)
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func show(anchoredTo menuFrame: NSRect, pinned: Bool = true) {
        isPinned = pinned
        let panel = makePanelIfNeeded()
        reloadContent()
        applyBehavior(to: panel)
        position(panel, anchoredTo: menuFrame)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func show(attachedToStatusItemFrame statusItemFrame: NSRect, pinned: Bool = false) {
        isPinned = pinned
        let panel = makePanelIfNeeded()
        reloadContent()
        applyBehavior(to: panel)
        position(panel, attachedToStatusItemFrame: statusItemFrame)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    var isVisibleForTesting: Bool {
        panel?.isVisible == true
    }

    var visibleFrame: NSRect? {
        guard panel?.isVisible == true else { return nil }
        return panel?.frame
    }

    func openHistoryFromPinnedMenu() {
        onOpenHistory()
    }

    private func makePanelIfNeeded() -> MainMenuPanel {
        if let panel { return panel }

        let panel = MainMenuPanel(
            contentRect: NSRect(x: 0, y: 0, width: MainMenuPanelLayout.width, height: MainMenuPanelLayout.headerHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.onCancel = { [weak self] in self?.onPinnedChange(false) }
        panel.delegate = self
        panel.contentView = contentView
        applyBehavior(to: panel)
        self.panel = panel
        return panel
    }

    private func applyBehavior(to panel: MainMenuPanel) {
        let behavior = MainMenuPanelBehavior(isPinned: isPinned)
        panel.level = behavior.level
        panel.collectionBehavior = behavior.collectionBehavior
        panel.hidesOnDeactivate = behavior.hidesOnDeactivate
        panel.isMovableByWindowBackground = behavior.isMovableByWindowBackground
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !isPinned else { return }
        panel?.orderOut(nil)
    }

    private func reloadContent() {
        contentView.subviews.forEach { $0.removeFromSuperview() }
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = MainMenuPanelLayout.cornerRadius
        contentView.layer?.masksToBounds = true
        contentView.layer?.backgroundColor = CPYWindowAppearance.backgroundColor().cgColor

        let items = itemsProvider()
        let height = preferredHeight(for: items)
        contentView.frame = NSRect(x: 0, y: 0, width: MainMenuPanelLayout.width, height: height)
        panel?.setContentSize(NSSize(width: MainMenuPanelLayout.width, height: height))

        var currentY = height - MainMenuPanelLayout.topInset - MainMenuPanelLayout.headerHeight
        let headerView = MainMenuHeaderItemView(title: historyTitle, image: historyImage, isPinned: isPinned)
        headerView.allowsWindowDrag = isPinned
        headerView.frame = NSRect(x: 0, y: currentY, width: MainMenuPanelLayout.width, height: MainMenuPanelLayout.headerHeight)
        headerView.onOpen = { [weak self] in self?.openHistoryFromPinnedMenu() }
        headerView.onPinnedChange = { [weak self] pinned, _ in self?.updatePinnedState(pinned) }
        contentView.addSubview(headerView)

        currentY -= MainMenuPanelLayout.separatorVerticalInset + MainMenuPanelLayout.separatorHeight
        addSeparator(at: currentY)
        currentY -= MainMenuPanelLayout.separatorVerticalInset

        for item in items {
            switch item {
            case .separator:
                currentY -= MainMenuPanelLayout.separatorVerticalInset
                addSeparator(at: currentY)
                currentY -= MainMenuPanelLayout.separatorVerticalInset
            case let .action(title, image, onSelect):
                currentY -= MainMenuPanelLayout.rowHeight
                let rowView = MainMenuPanelRowView(title: title, image: image, onConfirm: onSelect)
                rowView.frame = NSRect(
                    x: 0,
                    y: currentY,
                    width: MainMenuPanelLayout.width,
                    height: MainMenuPanelLayout.rowHeight
                )
                contentView.addSubview(rowView)
            }
        }
    }

    private func preferredHeight(for items: [MainMenuPanelItem]) -> CGFloat {
        let rowHeights = items.reduce(CGFloat(0)) { total, item in
            switch item {
            case .separator:
                return total + MainMenuPanelLayout.separatorHeight + MainMenuPanelLayout.separatorVerticalInset * 2
            case .action:
                return total + MainMenuPanelLayout.rowHeight
            }
        }
        return MainMenuPanelLayout.topInset
            + MainMenuPanelLayout.headerHeight
            + MainMenuPanelLayout.separatorHeight
            + MainMenuPanelLayout.separatorVerticalInset * 2
            + rowHeights
            + MainMenuPanelLayout.bottomInset
    }

    private func addSeparator(at verticalPosition: CGFloat) {
        let separator = NSView(frame: NSRect(
            x: MainMenuPanelLayout.separatorHorizontalInset,
            y: verticalPosition,
            width: MainMenuPanelLayout.width - MainMenuPanelLayout.separatorHorizontalInset * 2,
            height: MainMenuPanelLayout.separatorHeight
        ))
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.separatorColor
            .withAlphaComponent(MainMenuPanelLayout.separatorAlpha)
            .cgColor
        contentView.addSubview(separator)
    }

    private func position(_ panel: NSPanel, near screenPoint: NSPoint) {
        let visibleFrame = NSScreen.screens
            .first { $0.frame.contains(screenPoint) }?
            .visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        let originX = min(
            max(screenPoint.x - MainMenuPanelLayout.width / 2, visibleFrame.minX + MainMenuPanelLayout.screenPadding),
            visibleFrame.maxX - MainMenuPanelLayout.width - MainMenuPanelLayout.screenPadding
        )
        let originY = min(
            max(screenPoint.y - panel.frame.height, visibleFrame.minY + MainMenuPanelLayout.screenPadding),
            visibleFrame.maxY - panel.frame.height - MainMenuPanelLayout.screenPadding
        )
        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    private func position(_ panel: NSPanel, anchoredTo menuFrame: NSRect) {
        panel.setFrameTopLeftPoint(NSPoint(x: menuFrame.minX, y: menuFrame.maxY))
    }

    private func position(_ panel: NSPanel, attachedToStatusItemFrame statusItemFrame: NSRect) {
        let visibleFrame = NSScreen.screens
            .first { $0.frame.intersects(statusItemFrame) }?
            .visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let originX = min(
            max(statusItemFrame.midX - panel.frame.width / 2, visibleFrame.minX + MainMenuPanelLayout.screenPadding),
            visibleFrame.maxX - panel.frame.width - MainMenuPanelLayout.screenPadding
        )
        let topY = statusItemFrame.minY
        panel.setFrameTopLeftPoint(NSPoint(x: originX, y: topY))
    }

    private func updatePinnedState(_ pinned: Bool) {
        guard let panel else {
            isPinned = pinned
            onPinnedChange(pinned)
            return
        }

        let topLeftPoint = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        isPinned = pinned
        onPinnedChange(pinned)

        guard pinned else { return }
        reloadContent()
        applyBehavior(to: panel)
        panel.setFrameTopLeftPoint(topLeftPoint)
        panel.makeKeyAndOrderFront(nil)
    }
}

private final class MainMenuPanelRowView: NSControl {
    private enum Metrics {
        static let horizontalInset: CGFloat = 32
        static let iconSize: CGFloat = 17
        static let iconSpacing: CGFloat = 8
    }

    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let onConfirm: () -> Void
    private var trackingArea: NSTrackingArea?
    private var isMouseInside = false
    private var didDragWindow = false

    init(title: String, image: NSImage?, onConfirm: @escaping () -> Void) {
        self.onConfirm = onConfirm
        super.init(frame: NSRect(x: 0, y: 0, width: MainMenuPanelLayout.width, height: MainMenuPanelLayout.rowHeight))
        setup(title: title, image: image)
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        replaceHistoryMenuTrackingArea(&trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        isMouseInside = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
        updateAppearance()
    }

    override func mouseDragged(with event: NSEvent) {
        didDragWindow = true
        window?.performDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard !didDragWindow else {
            didDragWindow = false
            return
        }
        onConfirm()
    }

    private func setup(title: String, image: NSImage?) {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        imageView.image = image
        imageView.imageScaling = .scaleProportionallyDown
        imageView.isHidden = image == nil

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 15)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        [imageView, titleLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalInset),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: image == nil ? 0 : Metrics.iconSize),
            imageView.heightAnchor.constraint(equalToConstant: image == nil ? 0 : Metrics.iconSize),

            titleLabel.leadingAnchor.constraint(
                equalTo: image == nil ? leadingAnchor : imageView.trailingAnchor,
                constant: image == nil ? Metrics.horizontalInset : Metrics.iconSpacing
            ),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalInset),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateAppearance()
    }

    private func updateAppearance() {
        layer?.backgroundColor = isMouseInside
            ? NSColor.selectedContentBackgroundColor.cgColor
            : NSColor.clear.cgColor
        titleLabel.textColor = isMouseInside ? .selectedMenuItemTextColor : .labelColor
    }
}
