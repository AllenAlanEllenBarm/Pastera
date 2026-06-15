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
    static let topInset: CGFloat = 6
    static let bottomInset: CGFloat = 6
    static let rowHeight: CGFloat = 26
    static let snippetFolderRowHeight: CGFloat = 26
    static let headerHeight: CGFloat = 32
    static let separatorHeight: CGFloat = 1
    static let separatorHorizontalInset: CGFloat = 10
    static let separatorVerticalInset: CGFloat = 5
    static let separatorAlpha: CGFloat = 0.16
    static let pinButtonSize: CGFloat = 18
    static let pinTrailingInset: CGFloat = 10
    static let cornerRadius: CGFloat = PasteraDesignTokens.Metrics.panelCornerRadius
    static let screenPadding: CGFloat = 8
    static let folderHoverOpenDelay: TimeInterval = 0.45
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
    case snippetFolder(title: String, image: NSImage?, shortcutText: String? = nil, onOpen: (NSRect?) -> Void)
    case action(title: String, image: NSImage?, shortcutText: String? = nil, onSelect: () -> Void)
}

private final class MainMenuPanel: NSPanel {
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
}

final class MainMenuPanelController: NSObject, NSWindowDelegate {
    private struct KeyboardEntry {
        let title: String
        let setSelected: (Bool) -> Void
        let openChildPanel: (() -> Void)?
        let confirm: () -> Void
    }

    private let historyTitle: String
    private let historyImage: NSImage?
    private let historyShortcutText: String?
    private let snippetTitle: String
    private let snippetImage: NSImage?
    private let itemsProvider: () -> [MainMenuPanelItem]
    private let onOpenHistory: () -> Void
    private let onOpenSnippets: () -> Void
    private let onPinnedChange: (Bool) -> Void
    private let onCloseChildPanels: () -> Void

    private let contentView = NSView()
    private var panel: MainMenuPanel?
    private var keyboardEntries = [KeyboardEntry]()
    private var selectedKeyboardEntryIndex: Int?
    private var isPinned = true
    private var keepsVisibleWhileChildPanelOpen = false
    private var pasteTargetContext: PasteTargetContext?

    init(
        historyTitle: String,
        historyImage: NSImage?,
        historyShortcutText: String? = nil,
        snippetTitle: String,
        snippetImage: NSImage?,
        itemsProvider: @escaping () -> [MainMenuPanelItem],
        onOpenHistory: @escaping () -> Void,
        onOpenSnippets: @escaping () -> Void,
        onPinnedChange: @escaping (Bool) -> Void,
        onCloseChildPanels: @escaping () -> Void = {}
    ) {
        self.historyTitle = historyTitle
        self.historyImage = historyImage
        self.historyShortcutText = historyShortcutText
        self.snippetTitle = snippetTitle
        self.snippetImage = snippetImage
        self.itemsProvider = itemsProvider
        self.onOpenHistory = onOpenHistory
        self.onOpenSnippets = onOpenSnippets
        self.onPinnedChange = onPinnedChange
        self.onCloseChildPanels = onCloseChildPanels
        super.init()
    }

    func show(at screenPoint: NSPoint, pinned: Bool = true, pasteTargetContext: PasteTargetContext? = nil) {
        isPinned = pinned
        self.pasteTargetContext = pasteTargetContext ?? PasteTargetContext.capture()
        let panel = makePanelIfNeeded()
        reloadContent()
        applyBehavior(to: panel)
        if !panel.isVisible || !pinned {
            position(panel, near: screenPoint)
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func show(anchoredTo menuFrame: NSRect, pinned: Bool = true, pasteTargetContext: PasteTargetContext? = nil) {
        isPinned = pinned
        self.pasteTargetContext = pasteTargetContext ?? self.pasteTargetContext ?? PasteTargetContext.capture()
        let panel = makePanelIfNeeded()
        reloadContent()
        applyBehavior(to: panel)
        position(panel, anchoredTo: menuFrame)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func show(attachedToStatusItemFrame statusItemFrame: NSRect, pinned: Bool = false, pasteTargetContext: PasteTargetContext? = nil) {
        isPinned = pinned
        self.pasteTargetContext = pasteTargetContext ?? PasteTargetContext.capture()
        let panel = makePanelIfNeeded()
        reloadContent()
        applyBehavior(to: panel)
        position(panel, attachedToStatusItemFrame: statusItemFrame)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        keepsVisibleWhileChildPanelOpen = false
        panel?.orderOut(nil)
    }

    var isVisibleForTesting: Bool {
        panel?.isVisible == true
    }

    var visibleFrame: NSRect? {
        guard panel?.isVisible == true else { return nil }
        return panel?.frame
    }

    func reloadContentIfVisible() {
        guard let panel, panel.isVisible else { return }
        let topLeftPoint = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        reloadContent()
        panel.setFrameTopLeftPoint(topLeftPoint)
    }

    func refreshAppearanceIfVisible() {
        guard panel?.isVisible == true else { return }
        contentView.layer?.backgroundColor = CPYWindowAppearance.backgroundColor(for: panel?.effectiveAppearance).cgColor
    }

    var childPasteTargetContext: PasteTargetContext? {
        pasteTargetContext
    }

#if DEBUG
    var pasteTargetProcessIdentifierForTesting: pid_t? {
        pasteTargetContext?.processIdentifier
    }
#endif

    func openHistoryFromPinnedMenu() {
        onOpenHistory()
    }

    func openSnippetsFromPinnedMenu() {
        onOpenSnippets()
    }

    func beginChildPanelPresentation() {
        keepsVisibleWhileChildPanelOpen = true
        if let panel {
            panel.hidesOnDeactivate = false
        }
    }

    func endChildPanelPresentation() {
        keepsVisibleWhileChildPanelOpen = false
        if let panel {
            applyBehavior(to: panel)
        }
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
        panel.animationBehavior = .none
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.onCancel = { [weak self] in self?.onPinnedChange(false) }
        panel.onKeyDown = { [weak self] event in self?.handleKeyboardNavigation(event) ?? false }
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
        guard !isPinned, !keepsVisibleWhileChildPanelOpen else { return }
        panel?.orderOut(nil)
    }

    private func reloadContent() {
        contentView.subviews.forEach { $0.removeFromSuperview() }
        keyboardEntries.removeAll()
        selectedKeyboardEntryIndex = nil
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = MainMenuPanelLayout.cornerRadius
        contentView.layer?.masksToBounds = true
        contentView.layer?.backgroundColor = CPYWindowAppearance.backgroundColor().cgColor

        let items = itemsProvider()
        let height = preferredHeight(for: items)
        contentView.frame = NSRect(x: 0, y: 0, width: MainMenuPanelLayout.width, height: height)
        panel?.setContentSize(NSSize(width: MainMenuPanelLayout.width, height: height))

        var currentY = height - MainMenuPanelLayout.topInset - MainMenuPanelLayout.headerHeight
        let headerView = MainMenuHeaderItemView(
            title: historyTitle,
            image: historyImage,
            isPinned: isPinned,
            showsPin: false,
            shortcutText: historyShortcutText
        )
        headerView.allowsWindowDrag = isPinned
        headerView.frame = NSRect(x: 0, y: currentY, width: MainMenuPanelLayout.width, height: MainMenuPanelLayout.headerHeight)
        headerView.onOpen = { [weak self] in self?.openHistoryFromPinnedMenu() }
        headerView.onHoverOpen = { [weak self] in self?.openHistoryFromPinnedMenu() }
        let historyEntryIndex = appendKeyboardEntry(
            title: historyTitle,
            view: headerView,
            openChildPanel: { [weak self] in self?.openHistoryFromPinnedMenu() },
            confirm: { [weak self] in self?.openHistoryFromPinnedMenu() }
        )
        headerView.onHoverFocus = { [weak self] in
            self?.selectKeyboardEntry(at: historyEntryIndex, triggerChildPanel: false)
        }
        contentView.addSubview(headerView)

        currentY -= MainMenuPanelLayout.separatorVerticalInset + MainMenuPanelLayout.separatorHeight
        addSeparator(at: currentY)
        currentY -= MainMenuPanelLayout.separatorVerticalInset

        var pinCenterY: CGFloat?

        for item in items {
            switch item {
            case .separator:
                currentY -= MainMenuPanelLayout.separatorVerticalInset
                addSeparator(at: currentY)
                currentY -= MainMenuPanelLayout.separatorVerticalInset
            case let .snippetFolder(title, image, shortcutText, onOpen):
                currentY -= MainMenuPanelLayout.snippetFolderRowHeight
                let rowView = MainMenuPanelRowView(
                    title: title,
                    image: image,
                    shortcutText: shortcutText,
                    rowKind: .snippetFolder,
                    rowHeight: MainMenuPanelLayout.snippetFolderRowHeight,
                    showsChevron: true,
                    onHoverOpen: onOpen,
                    onConfirm: onOpen
                )
                rowView.frame = NSRect(
                    x: 0,
                    y: currentY,
                    width: MainMenuPanelLayout.width,
                    height: MainMenuPanelLayout.snippetFolderRowHeight
                )
                let entryIndex = appendKeyboardEntry(
                    title: title,
                    view: rowView,
                    openChildPanel: { [weak rowView] in onOpen(rowView?.screenFrameForOpening) },
                    confirm: { [weak rowView] in onOpen(rowView?.screenFrameForOpening) }
                )
                rowView.onHoverFocus = { [weak self] in
                    self?.selectKeyboardEntry(at: entryIndex, triggerChildPanel: false)
                }
                contentView.addSubview(rowView)
            case let .action(title, image, shortcutText, onSelect):
                currentY -= MainMenuPanelLayout.rowHeight
                let rowView = MainMenuPanelRowView(
                    title: title,
                    image: image,
                    shortcutText: shortcutText,
                    rowKind: .action
                ) { _ in onSelect() }
                rowView.frame = NSRect(
                    x: 0,
                    y: currentY,
                    width: MainMenuPanelLayout.width,
                    height: MainMenuPanelLayout.rowHeight
                )
                let entryIndex = appendKeyboardEntry(
                    title: title,
                    view: rowView,
                    openChildPanel: { [weak self] in self?.onCloseChildPanels() },
                    confirm: onSelect
                )
                rowView.onHoverFocus = { [weak self] in
                    self?.selectKeyboardEntry(at: entryIndex, triggerChildPanel: false)
                }
                contentView.addSubview(rowView)
                pinCenterY = rowView.frame.midY
            }
        }

        addPinButton(centerY: pinCenterY ?? MainMenuPanelLayout.bottomInset + MainMenuPanelLayout.pinButtonSize / 2)
    }

    private func preferredHeight(for items: [MainMenuPanelItem]) -> CGFloat {
        let rowHeights = items.reduce(CGFloat(0)) { total, item in
            switch item {
            case .separator:
                return total + MainMenuPanelLayout.separatorHeight + MainMenuPanelLayout.separatorVerticalInset * 2
            case .snippetFolder:
                return total + MainMenuPanelLayout.snippetFolderRowHeight
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

    private func addPinButton(centerY: CGFloat) {
        let pinButton = HistoryMenuPinButton(frame: NSRect(
            x: MainMenuPanelLayout.width - MainMenuPanelLayout.pinTrailingInset - MainMenuPanelLayout.pinButtonSize,
            y: centerY - MainMenuPanelLayout.pinButtonSize / 2,
            width: MainMenuPanelLayout.pinButtonSize,
            height: MainMenuPanelLayout.pinButtonSize
        ))
        pinButton.identifier = NSUserInterfaceItemIdentifier("mainMenuPinButton")
        pinButton.setButtonType(.momentaryPushIn)
        pinButton.bezelStyle = .inline
        pinButton.isBordered = false
        pinButton.imagePosition = .imageOnly
        pinButton.target = self
        pinButton.action = #selector(togglePinnedFromPinButton(_:))
        updatePinButtonAppearance(pinButton)
        contentView.addSubview(pinButton)
    }

    private func updatePinButtonAppearance(_ pinButton: HistoryMenuPinButton) {
        let symbolName = isPinned ? "pin.fill" : "pin"
        pinButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        pinButton.contentTintColor = isPinned ? .controlAccentColor : .secondaryLabelColor
        pinButton.toolTip = isPinned ? "Unpin Menu" : "Pin Menu"
        pinButton.setAccessibilityLabel(pinButton.toolTip)
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

    @objc private func togglePinnedFromPinButton(_ sender: HistoryMenuPinButton) {
        updatePinnedState(!isPinned)
    }
}

extension MainMenuPanelController {
    func handleKeyboardNavigationFromChild(_ event: NSEvent) -> Bool {
        handleKeyboardNavigation(event)
    }

    fileprivate func handleKeyboardNavigation(_ event: NSEvent) -> Bool {
        guard panel?.isVisible == true else { return false }
        let direction: Int
        switch event.keyCode {
        case 125:
            direction = 1
        case 126:
            direction = -1
        case 36, 49, 76:
            guard let selectedKeyboardEntryIndex,
                  keyboardEntries.indices.contains(selectedKeyboardEntryIndex) else { return false }
            keyboardEntries[selectedKeyboardEntryIndex].confirm()
            return true
        default:
            return false
        }
        guard !keyboardEntries.isEmpty else { return false }

        let currentIndex: Int
        if let selectedKeyboardEntryIndex {
            currentIndex = selectedKeyboardEntryIndex
        } else {
            currentIndex = direction > 0 ? -1 : keyboardEntries.count
        }

        let nextIndex = min(max(currentIndex + direction, 0), keyboardEntries.count - 1)
        selectKeyboardEntry(at: nextIndex, triggerChildPanel: true)
        return true
    }

    @discardableResult
    fileprivate func appendKeyboardEntry(
        title: String,
        view: NSView,
        openChildPanel: (() -> Void)?,
        confirm: @escaping () -> Void
    ) -> Int {
        let index = keyboardEntries.count
        keyboardEntries.append(KeyboardEntry(
            title: title,
            setSelected: { [weak view] selected in
                if let headerView = view as? MainMenuHeaderItemView {
                    headerView.setKeyboardSelected(selected)
                } else if let rowView = view as? MainMenuPanelRowView {
                    rowView.setKeyboardSelected(selected)
                }
            },
            openChildPanel: openChildPanel,
            confirm: confirm
        ))
        return index
    }

    fileprivate func selectKeyboardEntry(at index: Int, triggerChildPanel: Bool) {
        guard keyboardEntries.indices.contains(index) else { return }
        if let selectedKeyboardEntryIndex,
           selectedKeyboardEntryIndex != index,
           keyboardEntries.indices.contains(selectedKeyboardEntryIndex) {
            keyboardEntries[selectedKeyboardEntryIndex].setSelected(false)
        }
        selectedKeyboardEntryIndex = index
        keyboardEntries[index].setSelected(true)
        if triggerChildPanel {
            keyboardEntries[index].openChildPanel?()
        }
    }
}

private final class MainMenuPanelRowView: NSControl {
    enum RowKind {
        case snippetFolder
        case action
    }

    private enum Metrics {
        static let horizontalInset: CGFloat = 6
        static let iconSize: CGFloat = 16
        static let iconSpacing: CGFloat = 4
        static let titleAccessorySpacing: CGFloat = 1
        static let accessoryChevronSpacing: CGFloat = 0
        static let chevronSize: CGFloat = 5
    }

    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let shortcutBadge = PasteraShortcutBadgeView()
    private let chevronView = NSImageView()
    private let showsChevron: Bool
    private let rowKind: RowKind
    private let rowTitle: String
    private let onHoverOpen: ((NSRect?) -> Void)?
    private let onConfirm: (NSRect?) -> Void
    private var trackingArea: NSTrackingArea?
    private var hoverOpenWorkItem: DispatchWorkItem?
    private var isMouseInside = false
    private var isKeyboardSelected = false
    private var didDragWindow = false
    var onHoverFocus: (() -> Void)?

    init(
        title: String,
        image: NSImage?,
        shortcutText: String? = nil,
        rowKind: RowKind = .action,
        rowHeight: CGFloat = MainMenuPanelLayout.rowHeight,
        showsChevron: Bool = false,
        onHoverOpen: ((NSRect?) -> Void)? = nil,
        onConfirm: @escaping (NSRect?) -> Void
    ) {
        self.rowTitle = title
        self.rowKind = rowKind
        self.showsChevron = showsChevron
        self.onHoverOpen = onHoverOpen
        self.onConfirm = onConfirm
        super.init(frame: NSRect(x: 0, y: 0, width: MainMenuPanelLayout.width, height: rowHeight))
        setup(title: title, image: image, shortcutText: shortcutText)
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        replaceHistoryMenuTrackingArea(&trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        isMouseInside = true
        onHoverFocus?()
        updateAppearance()
        scheduleHoverOpenIfNeeded()
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
        cancelHoverOpen()
        updateAppearance()
    }

    override func mouseDragged(with event: NSEvent) {
        didDragWindow = true
        cancelHoverOpen()
        window?.performDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard !didDragWindow else {
            didDragWindow = false
            return
        }
        cancelHoverOpen()
        onConfirm(screenFrameForOpening)
    }

    func setKeyboardSelected(_ selected: Bool) {
        guard isKeyboardSelected != selected else { return }
        isKeyboardSelected = selected
        updateAppearance()
    }

    private func setup(title: String, image: NSImage?, shortcutText: String?) {
        wantsLayer = true
        layer?.cornerRadius = PasteraDesignTokens.Metrics.compactRowCornerRadius
        layer?.masksToBounds = true

        imageView.image = image
        imageView.imageScaling = .scaleProportionallyDown
        imageView.isHidden = image == nil
        imageView.contentTintColor = .secondaryLabelColor

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        shortcutBadge.shortcutText = shortcutText

        chevronView.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        chevronView.imageScaling = .scaleProportionallyDown
        chevronView.contentTintColor = .tertiaryLabelColor
        chevronView.isHidden = !showsChevron

        [imageView, titleLabel, shortcutBadge, chevronView].forEach {
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
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: shortcutBadge.leadingAnchor,
                constant: -Metrics.titleAccessorySpacing
            ),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            shortcutBadge.trailingAnchor.constraint(
                equalTo: showsChevron ? chevronView.leadingAnchor : trailingAnchor,
                constant: showsChevron ? -Metrics.accessoryChevronSpacing : -Metrics.horizontalInset
            ),
            shortcutBadge.centerYAnchor.constraint(equalTo: centerYAnchor),

            chevronView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalInset),
            chevronView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: showsChevron ? Metrics.chevronSize : 0),
            chevronView.heightAnchor.constraint(equalToConstant: showsChevron ? Metrics.chevronSize : 0)
        ])

        updateAppearance()
    }

    fileprivate var screenFrameForOpening: NSRect? {
        guard let window else { return nil }
        return window.convertToScreen(convert(bounds, to: nil))
    }

    private func scheduleHoverOpenIfNeeded() {
        guard let onHoverOpen else { return }
        cancelHoverOpen()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isMouseInside else { return }
            onHoverOpen(self.screenFrameForOpening)
        }
        hoverOpenWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + MainMenuPanelLayout.folderHoverOpenDelay, execute: workItem)
    }

    private func cancelHoverOpen() {
        hoverOpenWorkItem?.cancel()
        hoverOpenWorkItem = nil
    }

    private func updateAppearance() {
        let isEmphasized = isMouseInside || isKeyboardSelected
        layer?.backgroundColor = isEmphasized
            ? PasteraDesignTokens.colors().hoveredRow.cgColor
            : NSColor.clear.cgColor
        titleLabel.textColor = .labelColor
        imageView.contentTintColor = isEmphasized ? .labelColor : .secondaryLabelColor
        shortcutBadge.setState(isEmphasized: isEmphasized)
        chevronView.contentTintColor = isEmphasized ? .secondaryLabelColor : .tertiaryLabelColor
    }
}

#if DEBUG
extension MainMenuPanelController {
    var mainMenuPinButtonFramesForTesting: [NSRect] {
        contentView.layoutSubtreeIfNeeded()
        return mainMenuPinButtonsForTesting.map { button in
            button.superview?.convert(button.frame, to: contentView) ?? .zero
        }
    }

    func mainMenuActionRowFrameForTesting(title: String) -> NSRect? {
        rowViewsForTesting
            .first { $0.rowKindForTesting == .action && $0.rowTitleForTesting == title }
            .map { $0.superview?.convert($0.frame, to: contentView) ?? .zero }
    }

    func mainMenuSnippetRowFrameForTesting(title: String) -> NSRect? {
        rowViewsForTesting
            .first { $0.rowKindForTesting == .snippetFolder && $0.rowTitleForTesting == title }
            .map { $0.superview?.convert($0.frame, to: contentView) ?? .zero }
    }

    func mainMenuSnippetTitleFrameForTesting(title: String) -> NSRect? {
        guard let row = rowViewsForTesting.first(where: {
            $0.rowKindForTesting == .snippetFolder && $0.rowTitleForTesting == title
        }) else {
            return nil
        }
        row.layoutSubtreeIfNeeded()
        return row.titleFrameForTesting
    }

    func mainMenuSnippetTitleAvailableWidthForTesting(title: String) -> CGFloat? {
        guard let row = rowViewsForTesting.first(where: {
            $0.rowKindForTesting == .snippetFolder && $0.rowTitleForTesting == title
        }) else {
            return nil
        }
        row.layoutSubtreeIfNeeded()
        return row.titleAvailableWidthForTesting
    }

    func mainMenuActionTitleAvailableWidthForTesting(title: String) -> CGFloat? {
        guard let row = rowViewsForTesting.first(where: {
            $0.rowKindForTesting == .action && $0.rowTitleForTesting == title
        }) else {
            return nil
        }
        row.layoutSubtreeIfNeeded()
        return row.titleAvailableWidthForTesting
    }

    func performMainMenuPinClickForTesting() {
        mainMenuPinButtonsForTesting.first?.performClick(nil)
    }

    var selectedMainMenuTitleForTesting: String? {
        guard let selectedKeyboardEntryIndex,
              keyboardEntries.indices.contains(selectedKeyboardEntryIndex) else { return nil }
        return keyboardEntries[selectedKeyboardEntryIndex].title
    }

    var contentBackgroundAlphaForTesting: CGFloat {
        CGFloat(contentView.layer?.backgroundColor?.alpha ?? 0)
    }

    func selectMainMenuItemForTesting(title: String) {
        guard let index = keyboardEntries.firstIndex(where: { $0.title == title }) else { return }
        selectKeyboardEntry(at: index, triggerChildPanel: false)
    }

    func handleMainMenuNavigationForTesting(_ event: NSEvent) -> Bool {
        handleKeyboardNavigation(event)
    }

    private var rowViewsForTesting: [MainMenuPanelRowView] {
        contentView.layoutSubtreeIfNeeded()
        return contentView.subviews.compactMap { $0 as? MainMenuPanelRowView }
    }

    private var mainMenuPinButtonsForTesting: [NSButton] {
        func collectButtons(in view: NSView) -> [NSButton] {
            var buttons = view.subviews
                .compactMap { $0 as? NSButton }
                .filter { $0.identifier?.rawValue == "mainMenuPinButton" && !$0.isHidden }
            for subview in view.subviews {
                buttons.append(contentsOf: collectButtons(in: subview))
            }
            return buttons
        }
        return collectButtons(in: contentView)
    }
}

private extension MainMenuPanelRowView {
    var rowTitleForTesting: String {
        rowTitle
    }

    var rowKindForTesting: RowKind {
        rowKind
    }

    var titleFrameForTesting: NSRect {
        titleLabel.frame
    }

    var titleAvailableWidthForTesting: CGFloat {
        let trailingLimit: CGFloat
        if !shortcutBadge.isHidden {
            trailingLimit = shortcutBadge.frame.minX - Metrics.titleAccessorySpacing
        } else if !chevronView.isHidden {
            trailingLimit = chevronView.frame.minX - Metrics.titleAccessorySpacing
        } else {
            trailingLimit = bounds.maxX - Metrics.horizontalInset
        }
        return max(0, trailingLimit - titleLabel.frame.minX)
    }
}
#endif
