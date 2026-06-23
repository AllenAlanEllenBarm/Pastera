//
//  SnippetBrowserPanelController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Codex on 2026/06/04.
//
//  Copyright © 2015-2026 Clipy Project.
//

import Cocoa
import Magnet

enum SnippetBrowserLayout {
    static let width: CGFloat = 260
    static let maxHeight: CGFloat = 360
    static let rowHeight: CGFloat = 24
    static let folderHeight: CGFloat = 28
    static let emptyHeight: CGFloat = 36
    static let topInset: CGFloat = 6
    static let bottomInset: CGFloat = 6
    static let horizontalOffset: CGFloat = 8
    static let cornerRadius: CGFloat = PasteraDesignTokens.Metrics.panelCornerRadius
}

private final class SnippetBrowserPanel: NSPanel {
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

final class SnippetBrowserPanelController: NSObject, NSWindowDelegate {
    private enum ContentMode {
        case folders
        case snippets(SnippetFolder.ID)
    }

    private let fetchFolders: () -> [SnippetFolder]
    private let fetchFolderDetail: (SnippetFolder.ID) -> SnippetFolderDetail?
    private let selectSnippet: (Snippet.ID, PasteTargetContext?) -> Void

    private let contentView = NSView()
    private let scrollView = NSScrollView()
    private let documentView = NSView()
    private var panel: SnippetBrowserPanel?
    private var rowViews = [NSView]()
    private var visibleSnippetIDs = [Snippet.ID]()
    private var contentMode = ContentMode.folders
    private var pasteTargetContext: PasteTargetContext?
    private var numberShortcutModifierFlags: NSEvent.ModifierFlags = []
    var onClose: (() -> Void)?
    var onMainMenuNavigationKeyDown: ((NSEvent) -> Bool)?

    init(
        fetchFolders: @escaping () -> [SnippetFolder],
        fetchFolderDetail: @escaping (SnippetFolder.ID) -> SnippetFolderDetail?,
        selectSnippet: @escaping (Snippet.ID, PasteTargetContext?) -> Void
    ) {
        self.fetchFolders = fetchFolders
        self.fetchFolderDetail = fetchFolderDetail
        self.selectSnippet = selectSnippet
        super.init()
        setupContent()
    }

    func show(
        attachedTo anchorFrame: NSRect,
        pasteTargetContext: PasteTargetContext? = nil,
        triggerKeyCombo: KeyCombo? = nil
    ) {
        contentMode = .folders
        showCurrentMode(attachedTo: anchorFrame, pasteTargetContext: pasteTargetContext, triggerKeyCombo: triggerKeyCombo)
    }

    func show(
        folderID: SnippetFolder.ID,
        attachedTo anchorFrame: NSRect,
        pasteTargetContext: PasteTargetContext? = nil,
        triggerKeyCombo: KeyCombo? = nil
    ) {
        contentMode = .snippets(folderID)
        showCurrentMode(attachedTo: anchorFrame, pasteTargetContext: pasteTargetContext, triggerKeyCombo: triggerKeyCombo)
    }

    func show(at screenPoint: NSPoint, pasteTargetContext: PasteTargetContext? = nil, triggerKeyCombo: KeyCombo? = nil) {
        contentMode = .folders
        showCurrentMode(near: screenPoint, pasteTargetContext: pasteTargetContext, triggerKeyCombo: triggerKeyCombo)
    }

    func show(
        folderID: SnippetFolder.ID,
        at screenPoint: NSPoint,
        pasteTargetContext: PasteTargetContext? = nil,
        triggerKeyCombo: KeyCombo? = nil
    ) {
        contentMode = .snippets(folderID)
        showCurrentMode(near: screenPoint, pasteTargetContext: pasteTargetContext, triggerKeyCombo: triggerKeyCombo)
    }

    private func showCurrentMode(
        attachedTo anchorFrame: NSRect,
        pasteTargetContext: PasteTargetContext?,
        triggerKeyCombo: KeyCombo?
    ) {
        capturePasteTargetContext(pasteTargetContext)
        numberShortcutModifierFlags = triggerKeyCombo.numberShortcutModifierFlags
        let panel = makePanelIfNeeded()
        reloadRows()
        position(panel, attachedTo: anchorFrame)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func showCurrentMode(
        near screenPoint: NSPoint,
        pasteTargetContext: PasteTargetContext?,
        triggerKeyCombo: KeyCombo?
    ) {
        capturePasteTargetContext(pasteTargetContext)
        numberShortcutModifierFlags = triggerKeyCombo.numberShortcutModifierFlags
        let panel = makePanelIfNeeded()
        reloadRows()
        position(panel, near: screenPoint)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func capturePasteTargetContext(_ context: PasteTargetContext?) {
        pasteTargetContext = context ?? PasteTargetContext.capture()
    }

    func close() {
        panel?.orderOut(nil)
        onClose?()
    }

    func reloadRowsIfVisible() {
        guard panel?.isVisible == true else { return }
        reloadRows()
    }

    func refreshAppearanceIfVisible() {
        guard panel?.isVisible == true else { return }
        contentView.layer?.backgroundColor = CPYWindowAppearance.backgroundColor(for: panel?.effectiveAppearance).cgColor
    }

    var visibleFrame: NSRect? {
        guard panel?.isVisible == true else { return nil }
        return panel?.frame
    }

    private func setupContent() {
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = SnippetBrowserLayout.cornerRadius
        contentView.layer?.masksToBounds = true

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = documentView
        contentView.addSubview(scrollView)
    }

    private func makePanelIfNeeded() -> SnippetBrowserPanel {
        if let panel { return panel }

        let panel = SnippetBrowserPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SnippetBrowserLayout.width,
                height: SnippetBrowserLayout.emptyHeight
            ),
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
            if self?.onMainMenuNavigationKeyDown?(event) == true {
                return true
            }
            return self?.confirmSnippetForNumberShortcut(event) ?? false
        }
        panel.delegate = self
        panel.contentView = contentView
        self.panel = panel
        return panel
    }

    private func reloadRows() {
        contentView.layer?.backgroundColor = CPYWindowAppearance.backgroundColor().cgColor
        rowViews.forEach { $0.removeFromSuperview() }
        rowViews.removeAll()
        visibleSnippetIDs.removeAll()

        switch contentMode {
        case .folders:
            rowViews.append(contentsOf: makeFolderRows())
        case let .snippets(folderID):
            rowViews.append(contentsOf: makeSnippetRows(for: folderID))
        }

        if rowViews.isEmpty {
            rowViews.append(SnippetBrowserEmptyRowView(title: String(localized: "No Snippets")))
        }

        rowViews.forEach(documentView.addSubview)
        layoutContent()
    }

    private func layoutContent() {
        let documentHeight = SnippetBrowserLayout.topInset
            + rowViews.reduce(CGFloat(0)) { $0 + $1.frame.height }
            + SnippetBrowserLayout.bottomInset
        let height = min(documentHeight, SnippetBrowserLayout.maxHeight)
        let size = NSSize(width: SnippetBrowserLayout.width, height: height)
        contentView.setFrameSize(size)
        panel?.setContentSize(size)

        scrollView.frame = NSRect(origin: .zero, size: size)
        documentView.frame = NSRect(x: 0, y: 0, width: SnippetBrowserLayout.width, height: documentHeight)

        var currentY = documentHeight - SnippetBrowserLayout.topInset
        for rowView in rowViews {
            currentY -= rowView.frame.height
            rowView.frame = NSRect(x: 0, y: currentY, width: SnippetBrowserLayout.width, height: rowView.frame.height)
        }
    }

    private func position(_ panel: NSPanel, attachedTo anchorFrame: NSRect) {
        let screen = NSScreen.screens.first { $0.frame.intersects(anchorFrame) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            panel.setFrameOrigin(NSPoint(x: anchorFrame.maxX + SnippetBrowserLayout.horizontalOffset, y: anchorFrame.minY))
            return
        }

        let size = panel.frame.size
        let rightOriginX = anchorFrame.maxX + SnippetBrowserLayout.horizontalOffset
        let leftOriginX = anchorFrame.minX - size.width - SnippetBrowserLayout.horizontalOffset
        let fitsRight = rightOriginX + size.width <= visibleFrame.maxX
        let originX = fitsRight ? rightOriginX : max(visibleFrame.minX, leftOriginX)
        let preferredY = anchorFrame.maxY - size.height
        let originY = min(max(preferredY, visibleFrame.minY), visibleFrame.maxY - size.height)
        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    private func position(_ panel: NSPanel, near screenPoint: NSPoint) {
        let screen = NSScreen.screens.first { NSMouseInRect(screenPoint, $0.frame, false) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            panel.setFrameOrigin(screenPoint)
            return
        }

        let size = panel.frame.size
        var origin = NSPoint(
            x: screenPoint.x + SnippetBrowserLayout.horizontalOffset,
            y: screenPoint.y - size.height + SnippetBrowserLayout.horizontalOffset
        )
        origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - size.width)
        origin.y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - size.height)
        panel.setFrameOrigin(origin)
    }

    private func makeFolderRows() -> [NSView] {
        fetchFolders()
            .filter(\.isEnabled)
            .map { folder in
                let shortcutText = PasteraShortcutFormatter.string(
                    for: AppEnvironment.current.hotKeyService.snippetKeyCombo(forIdentifier: folder.id.uuidString)
                )
                return SnippetBrowserFolderRowView(title: folder.title, shortcutText: shortcutText) { [weak self] in
                    self?.contentMode = .snippets(folder.id)
                    self?.reloadRows()
                }
            }
    }

    private func makeSnippetRows(for folderID: SnippetFolder.ID) -> [NSView] {
        guard let detail = fetchFolderDetail(folderID), detail.folder.isEnabled else {
            return []
        }

        let firstIndex = firstIndexOfMenuItems()
        let snippets = detail.snippets.filter(\.isEnabled)
        visibleSnippetIDs = snippets.map(\.id)
        return snippets.enumerated().map { index, snippet in
            let shortcutText = numericShortcutText(forRowIndex: index)
            let title = snippetTitle(
                snippet.title,
                listNumber: firstIndex + index,
                usesLeadingNumber: false
            )
            return SnippetBrowserSnippetRowView(title: title, shortcutText: shortcutText) { [weak self] in
                self?.confirmSelection(snippet.id)
            }
        }
    }

    private func snippetTitle(_ title: String, listNumber: Int, usesLeadingNumber: Bool?) -> String {
        let shouldMark = usesLeadingNumber
            ?? AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsAreMarkedWithNumbers)
        guard shouldMark else {
            return title
        }
        return "\(listNumber). \(title)"
    }

    private func numericShortcutText(forRowIndex index: Int) -> String? {
        let startsAtZero = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsTitleStartWithZero)
        return PasteraShortcutFormatter.numericString(forRowIndex: index, startsAtZero: startsAtZero)
    }

    private func firstIndexOfMenuItems() -> Int {
        AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsTitleStartWithZero) ? 0 : 1
    }

    private func confirmSnippetForNumberShortcut(_ event: NSEvent) -> Bool {
        let startsAtZero = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsTitleStartWithZero)
        guard let rowIndex = HistoryMenuNumberShortcutMapper.rowIndex(
            for: event,
            startsAtZero: startsAtZero,
            rowCount: visibleSnippetIDs.count,
            allowedModifierFlags: numberShortcutModifierFlags
        ) else {
            return false
        }
        confirmSelection(visibleSnippetIDs[rowIndex])
        return true
    }

    private func confirmSelection(_ snippetID: Snippet.ID) {
        let targetContext = pasteTargetContext
        close()
        selectSnippet(snippetID, targetContext)
    }
}

#if DEBUG
extension SnippetBrowserPanelController {
    var pasteTargetProcessIdentifierForTesting: pid_t? {
        pasteTargetContext?.processIdentifier
    }

    var rowTitlesForTesting: [String] {
        rowViews.compactMap { rowView in
            rowView.subviews
                .compactMap { ($0 as? NSTextField)?.stringValue }
                .first
        }
    }

    var rowShortcutTextsForTesting: [String] {
        rowViews.compactMap { rowView in
            let text = rowView.subviews
                .compactMap { $0 as? PasteraShortcutBadgeView }
                .first { $0.identifier?.rawValue == "shortcutTextLabel" }?
                .shortcutTextForTesting
            return text?.isEmpty == false ? text : nil
        }
    }

    var rowShortcutStylesForTesting: [PasteraShortcutBadgeView.Style] {
        rowViews.compactMap { rowView in
            rowView.subviews
                .compactMap { $0 as? PasteraShortcutBadgeView }
                .first { badge in
                    badge.identifier?.rawValue == "shortcutTextLabel"
                        && !badge.shortcutTextForTesting.isEmpty
                }?
                .styleForTesting
        }
    }

    var rowTextValuesForTesting: [[String]] {
        rowViews.map { collectTextValues(in: $0) }
    }

    var isVisibleForTesting: Bool {
        panel?.isVisible == true
    }

    func confirmFirstSnippetForTesting() {
        let firstSnippetID = visibleSnippetIDs.first
        guard let firstSnippetID else { return }
        confirmSelection(firstSnippetID)
    }

    func handleNumberShortcutForTesting(_ event: NSEvent) -> Bool {
        confirmSnippetForNumberShortcut(event)
    }

    func handleKeyDownForTesting(_ event: NSEvent) -> Bool {
        panel?.onKeyDown?(event) ?? false
    }

    var contentBackgroundAlphaForTesting: CGFloat {
        CGFloat(contentView.layer?.backgroundColor?.alpha ?? 0)
    }

    private func collectTextValues(in view: NSView) -> [String] {
        var values = [String]()
        if let label = view as? NSTextField, !label.stringValue.isEmpty {
            values.append(label.stringValue)
        }
        for subview in view.subviews {
            values.append(contentsOf: collectTextValues(in: subview))
        }
        return values
    }
}
#endif

private extension Optional where Wrapped == KeyCombo {
    var numberShortcutModifierFlags: NSEvent.ModifierFlags {
        guard let keyCombo = self, !keyCombo.doubledModifiers else { return [] }
        return keyCombo.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask)
    }
}

private final class SnippetBrowserFolderRowView: NSControl {
    private enum Metrics {
        static let horizontalInset: CGFloat = 14
        static let iconSize: CGFloat = 16
        static let chevronSize: CGFloat = 10
    }

    private let imageView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let shortcutBadge = PasteraShortcutBadgeView()
    private let chevronView = NSImageView()
    private let onConfirm: () -> Void
    private var trackingArea: NSTrackingArea?
    private var isMouseInside = false

    init(title: String, shortcutText: String? = nil, onConfirm: @escaping () -> Void) {
        self.onConfirm = onConfirm
        super.init(frame: NSRect(x: 0, y: 0, width: SnippetBrowserLayout.width, height: SnippetBrowserLayout.folderHeight))
        setup(title: title, shortcutText: shortcutText)
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

    override func mouseUp(with event: NSEvent) {
        onConfirm()
    }

    private func setup(title: String, shortcutText: String?) {
        wantsLayer = true
        layer?.cornerRadius = PasteraDesignTokens.Metrics.compactRowCornerRadius
        layer?.masksToBounds = true

        imageView.image = NSImage(systemSymbolName: "folder", accessibilityDescription: title)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = .secondaryLabelColor

        label.stringValue = title
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail

        shortcutBadge.identifier = NSUserInterfaceItemIdentifier("shortcutTextLabel")
        shortcutBadge.style = .command
        shortcutBadge.shortcutText = shortcutText

        chevronView.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        chevronView.imageScaling = .scaleProportionallyDown
        chevronView.contentTintColor = .tertiaryLabelColor

        [imageView, label, shortcutBadge, chevronView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalInset),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: Metrics.iconSize),
            imageView.heightAnchor.constraint(equalToConstant: Metrics.iconSize),

            label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: shortcutBadge.leadingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            shortcutBadge.trailingAnchor.constraint(equalTo: chevronView.leadingAnchor, constant: -6),
            shortcutBadge.centerYAnchor.constraint(equalTo: centerYAnchor),

            chevronView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalInset),
            chevronView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: Metrics.chevronSize),
            chevronView.heightAnchor.constraint(equalToConstant: Metrics.chevronSize)
        ])

        updateAppearance()
    }

    private func updateAppearance() {
        layer?.backgroundColor = isMouseInside
            ? PasteraDesignTokens.colors().hoveredRow.cgColor
            : NSColor.clear.cgColor
        imageView.contentTintColor = isMouseInside ? .labelColor : .secondaryLabelColor
        shortcutBadge.setState(isEmphasized: isMouseInside)
        chevronView.contentTintColor = isMouseInside ? .secondaryLabelColor : .tertiaryLabelColor
    }
}

private final class SnippetBrowserSnippetRowView: NSControl {
    private enum Metrics {
        static let horizontalInset: CGFloat = 14
        static let shortcutSpacing: CGFloat = 8
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let shortcutBadge = PasteraShortcutBadgeView()
    private let onConfirm: () -> Void
    private var trackingArea: NSTrackingArea?
    private var isMouseInside = false

    init(title: String, shortcutText: String? = nil, onConfirm: @escaping () -> Void) {
        self.onConfirm = onConfirm
        super.init(frame: NSRect(x: 0, y: 0, width: SnippetBrowserLayout.width, height: SnippetBrowserLayout.rowHeight))
        setup(title: title, shortcutText: shortcutText)
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

    override func mouseUp(with event: NSEvent) {
        onConfirm()
    }

    private func setup(title: String, shortcutText: String?) {
        wantsLayer = true
        layer?.cornerRadius = PasteraDesignTokens.Metrics.compactRowCornerRadius
        layer?.masksToBounds = true

        titleLabel.stringValue = title.isEmpty ? String(localized: "Snippet") : title
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        shortcutBadge.identifier = NSUserInterfaceItemIdentifier("shortcutTextLabel")
        shortcutBadge.style = .itemNumber
        shortcutBadge.shortcutText = shortcutText

        [shortcutBadge, titleLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        let hasShortcut = shortcutText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let shortcutSpacing = hasShortcut ? Metrics.shortcutSpacing : 0

        NSLayoutConstraint.activate([
            shortcutBadge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalInset),
            shortcutBadge.centerYAnchor.constraint(equalTo: centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: shortcutBadge.trailingAnchor, constant: shortcutSpacing),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Metrics.horizontalInset),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateAppearance()
    }

    private func updateAppearance() {
        layer?.backgroundColor = isMouseInside
            ? PasteraDesignTokens.colors().hoveredRow.cgColor
            : NSColor.clear.cgColor
        shortcutBadge.setState(isEmphasized: isMouseInside)
    }
}

private final class SnippetBrowserEmptyRowView: NSView {
    private let label = NSTextField(labelWithString: "")

    init(title: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: SnippetBrowserLayout.width, height: SnippetBrowserLayout.emptyHeight))
        label.stringValue = title
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 14, y: 8, width: SnippetBrowserLayout.width - 28, height: 20)
        addSubview(label)
    }

    required init?(coder: NSCoder) { nil }
}
