//
//  CPYPreferencesWindowController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/02/25.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import KeyHolder

// swiftlint:disable file_length

private final class PasteraPreferencesWindow: NSWindow {
    var onKeyDown: ((NSEvent) -> Bool)?
    var onRestoreDefaultFrameSize: (() -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, onKeyDown?(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func performZoom(_ sender: Any?) {
        if onRestoreDefaultFrameSize?() == true {
            return
        }
        super.performZoom(sender)
    }

    override func zoom(_ sender: Any?) {
        if onRestoreDefaultFrameSize?() == true {
            return
        }
        super.zoom(sender)
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true {
            return
        }
        super.keyDown(with: event)
    }
}

private final class PasteraPreferencePaneDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class CPYPreferencesWindowController: NSWindowController {
    static let sharedController = CPYPreferencesWindowController()

    private enum Pane: Int, CaseIterable {
        case general
        case type
        case exclude
        case shortcuts
        case sync
        case updates

        var title: String {
            switch self {
            case .general:
                return "通用"
            case .type:
                return "类型"
            case .exclude:
                return "排除"
            case .shortcuts:
                return "快捷键"
            case .sync:
                return "同步"
            case .updates:
                return "更新"
            }
        }

        var symbolName: String {
            switch self {
            case .general:
                return "switch.2"
            case .type:
                return "doc"
            case .exclude:
                return "nosign"
            case .shortcuts:
                return "command"
            case .sync:
                return "arrow.up.arrow.down.circle"
            case .updates:
                return "arrow.triangle.2.circlepath"
            }
        }
    }

    private enum Metrics {
        static let sidebarWidth: CGFloat = 112
        static let sidebarInset: CGFloat = 8
        static let paneInset: CGFloat = 16
        static let paneDocumentInset: CGFloat = 16
        static let minimumPaneControlGap: CGFloat = 12
        static let minimumWidth: CGFloat = 560
        static let minimumHeight: CGFloat = 320
        static let defaultFrameSize = NSSize(width: 600, height: 340)
        static let maximumPaneWidth: CGFloat = 700
    }

    private let rootView = NSView()
    private let sidebarView = NSView()
    private let sidebarStack = NSStackView()
    private let separatorView = NSView()
    private let paneContainerView = NSView()
    private let paneScrollView = NSScrollView()
    private let paneDocumentView = PasteraPreferencePaneDocumentView()
    private var sidebarButtons = [PasteraPreferenceSidebarButton]()
    private let viewController: [NSViewController] = [
        CPYGeneralPreferenceViewController(nibName: "CPYGeneralPreferenceViewController", bundle: nil),
        CPYTypePreferenceViewController(nibName: "CPYTypePreferenceViewController", bundle: nil),
        CPYExcludeAppPreferenceViewController(nibName: "CPYExcludeAppPreferenceViewController", bundle: nil),
        CPYShortcutsPreferenceViewController(nibName: "CPYShortcutsPreferenceViewController", bundle: nil),
        CPYSyncPreferenceViewController(),
        CPYUpdatesPreferenceViewController(nibName: "CPYUpdatesPreferenceViewController", bundle: nil)
    ]
    private var selectedView: NSView?
    private var selectedTabIndex = -1
    private var paneSizes = [Int: NSSize]()
    private var didPreloadPaneViews = false
    private var defaultsObserver: NSObjectProtocol?
    private var hasShownWindow = false

    init() {
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        let contentRect = NSWindow.contentRect(
            forFrameRect: NSRect(origin: .zero, size: Metrics.defaultFrameSize),
            styleMask: styleMask
        )
        let window = PasteraPreferencesWindow(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Pastera - Settings")
        window.minSize = NSSize(width: Metrics.minimumWidth, height: Metrics.minimumHeight)
        super.init(window: window)
        window.delegate = self
        window.onKeyDown = { [weak self] event in
            self?.handleKeyboardEvent(event) ?? false
        }
        window.onRestoreDefaultFrameSize = { [weak self] in
            self?.restoreDefaultWindowFrameSize(animated: false) ?? false
        }
        setupContent()
        installOpacityObserver()
        preloadPaneViews()
        switchView(Pane.general.rawValue)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        let wasVisible = window?.isVisible == true
        super.showWindow(sender)
        if !hasShownWindow {
            window?.center()
            hasShownWindow = true
        }
        CPYWindowAppearance.apply(to: window)
        refreshBackgroundColors()
        window?.makeKeyAndOrderFront(self)
        if !wasVisible {
            focusSelectedSidebarButton()
        }
    }

    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }
}

extension CPYPreferencesWindowController: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) {
        layoutSelectedPane()
    }

    func windowWillClose(_ notification: Notification) {
        if let viewController = viewController[Pane.type.rawValue] as? CPYTypePreferenceViewController {
            AppEnvironment.current.defaults.set(viewController.storeTypes, forKey: Constants.UserDefaults.storeTypes)
            AppEnvironment.current.defaults.set(
                viewController.filePreviewTypes,
                forKey: Constants.UserDefaults.filePreviewTypes
            )
            AppEnvironment.current.defaults.synchronize()
        }
        if let window = window, !window.makeFirstResponder(window) {
            window.endEditing(for: nil)
        }
        NSApp.deactivate()
    }
}

private extension CPYPreferencesWindowController {
    func setupContent() {
        guard let window else { return }
        let tokens = currentColorSet()
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = tokens.panelBackground.cgColor
        window.contentView = rootView

        sidebarView.wantsLayer = true
        sidebarView.layer?.backgroundColor = tokens.surface.cgColor
        separatorView.wantsLayer = true
        separatorView.layer?.backgroundColor = tokens.separator.cgColor
        paneContainerView.wantsLayer = true
        paneContainerView.layer?.backgroundColor = NSColor.clear.cgColor
        paneDocumentView.wantsLayer = true
        paneDocumentView.layer?.backgroundColor = NSColor.clear.cgColor
        paneDocumentView.frame = NSRect(origin: .zero, size: NSSize(width: 1, height: 1))
        paneScrollView.translatesAutoresizingMaskIntoConstraints = false
        paneScrollView.drawsBackground = false
        paneScrollView.backgroundColor = .clear
        paneScrollView.contentView.drawsBackground = false
        paneScrollView.contentView.backgroundColor = .clear
        paneScrollView.borderType = .noBorder
        paneScrollView.hasHorizontalScroller = false
        paneScrollView.hasVerticalScroller = true
        paneScrollView.autohidesScrollers = true
        paneScrollView.horizontalScrollElasticity = .none
        paneScrollView.verticalScrollElasticity = .allowed
        paneScrollView.documentView = paneDocumentView

        sidebarStack.orientation = .vertical
        sidebarStack.spacing = 4
        sidebarStack.alignment = .leading
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false

        [sidebarView, separatorView, paneContainerView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            rootView.addSubview($0)
        }
        sidebarView.addSubview(sidebarStack)
        paneContainerView.addSubview(paneScrollView)

        Pane.allCases.forEach { pane in
            let button = PasteraPreferenceSidebarButton(title: pane.title, symbolName: pane.symbolName)
            button.tag = pane.rawValue
            button.target = self
            button.action = #selector(sidebarButtonTapped(_:))
            button.onFocus = { [weak self] button in
                self?.selectPaneFromFocusedSidebarButton(button)
            }
            sidebarButtons.append(button)
            sidebarStack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: Metrics.sidebarWidth - Metrics.sidebarInset * 2).isActive = true
            button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        }

        NSLayoutConstraint.activate([
            sidebarView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            sidebarView.topAnchor.constraint(equalTo: rootView.topAnchor),
            sidebarView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            sidebarView.widthAnchor.constraint(equalToConstant: Metrics.sidebarWidth),

            sidebarStack.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor, constant: Metrics.sidebarInset),
            sidebarStack.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor, constant: -Metrics.sidebarInset),
            sidebarStack.topAnchor.constraint(equalTo: sidebarView.topAnchor, constant: 14),

            separatorView.leadingAnchor.constraint(equalTo: sidebarView.trailingAnchor),
            separatorView.topAnchor.constraint(equalTo: rootView.topAnchor),
            separatorView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            separatorView.widthAnchor.constraint(equalToConstant: PasteraDesignTokens.Metrics.hairlineWidth),

            paneContainerView.leadingAnchor.constraint(equalTo: separatorView.trailingAnchor),
            paneContainerView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            paneContainerView.topAnchor.constraint(equalTo: rootView.topAnchor),
            paneContainerView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            paneScrollView.leadingAnchor.constraint(equalTo: paneContainerView.leadingAnchor),
            paneScrollView.trailingAnchor.constraint(equalTo: paneContainerView.trailingAnchor),
            paneScrollView.topAnchor.constraint(equalTo: paneContainerView.topAnchor),
            paneScrollView.bottomAnchor.constraint(equalTo: paneContainerView.bottomAnchor)
        ])
    }

    @objc func sidebarButtonTapped(_ sender: PasteraPreferenceSidebarButton) {
        switchView(sender.tag)
        window?.makeFirstResponder(sender)
    }

    func switchView(_ index: Int) {
        guard viewController.indices.contains(index), index != selectedTabIndex else { return }
        let newView = viewController[index].view
        CPYWindowAppearance.apply(to: newView)
        PasteraSemanticViewStyler.apply(to: newView, appearance: window?.effectiveAppearance)
        let paneSize = PasteraPreferencePaneLayoutNormalizer.adapt(to: newView, minimumGap: Metrics.minimumPaneControlGap)
        paneSizes[index] = paneSize

        selectedView?.removeFromSuperview()
        newView.translatesAutoresizingMaskIntoConstraints = true
        paneDocumentView.addSubview(newView)

        selectedView = newView
        selectedTabIndex = index
        updateSidebarSelection(index)
        layoutSelectedPane(contentSize: paneSize)
        installKeyViewLoop()
        if let syncViewController = viewController[index] as? CPYSyncPreferenceViewController {
            syncViewController.refreshDefaultFolderAvailability()
        }
        CPYWindowAppearance.apply(to: window)
    }

    func updateSidebarSelection(_ index: Int) {
        sidebarButtons.forEach { $0.isSelected = $0.tag == index }
    }

    func selectPaneFromFocusedSidebarButton(_ button: PasteraPreferenceSidebarButton) {
        guard sidebarButtons.contains(where: { $0 === button }) else { return }
        switchView(button.tag)
    }

    func layoutSelectedPane(contentSize: NSSize? = nil) {
        guard let selectedView else { return }
        rootView.layoutSubtreeIfNeeded()
        let viewport = paneScrollView.contentView.bounds.size
        let visibleWidth = max(1, viewport.width)
        let visibleHeight = max(1, viewport.height)
        let targetSize = contentSize ?? paneSizes[selectedTabIndex] ?? selectedView.frame.size
        let availableWidth = max(1, visibleWidth - Metrics.paneDocumentInset * 2)
        let contentWidth = availableWidth
        var contentHeight = max(1, targetSize.height)
        let documentHeight = max(visibleHeight, contentHeight + Metrics.paneDocumentInset * 2)
        paneDocumentView.frame.size = NSSize(
            width: visibleWidth,
            height: documentHeight
        )
        let initialOriginY = selectedPaneOriginY(
            visibleHeight: visibleHeight,
            contentHeight: contentHeight
        )
        selectedView.frame = NSRect(
            x: Metrics.paneDocumentInset,
            y: initialOriginY,
            width: contentWidth,
            height: contentHeight
        )
        if let pane = Pane(rawValue: selectedTabIndex),
           let alignmentKind = alignmentKind(for: pane) {
            PasteraPreferencePaneAlignmentAdapter.layout(
                selectedView,
                pane: alignmentKind,
                availableWidth: contentWidth
            )
            let compactSize = PasteraPreferencePaneLayoutNormalizer.adapt(
                to: selectedView,
                minimumGap: Metrics.minimumPaneControlGap
            )
            contentHeight = max(1, compactSize.height)
            paneSizes[selectedTabIndex] = NSSize(width: contentWidth, height: contentHeight)
            paneDocumentView.frame.size = NSSize(
                width: visibleWidth,
                height: max(visibleHeight, contentHeight + Metrics.paneDocumentInset * 2)
            )
            let compactOriginY = selectedPaneOriginY(
                visibleHeight: visibleHeight,
                contentHeight: contentHeight
            )
            selectedView.frame = NSRect(
                x: Metrics.paneDocumentInset,
                y: compactOriginY,
                width: contentWidth,
                height: contentHeight
            )
            PasteraPreferencePaneAlignmentAdapter.layout(
                selectedView,
                pane: alignmentKind,
                availableWidth: contentWidth
            )
        }
        centerSelectedGeneralPaneContent(visibleHeight: visibleHeight)
    }

    @discardableResult
    func restoreDefaultWindowFrameSize(animated: Bool) -> Bool {
        guard let window else { return false }
        window.setFrame(defaultWindowFrame(for: window), display: true, animate: animated)
        layoutSelectedPane()
        return true
    }

    func defaultWindowFrame(for window: NSWindow) -> NSRect {
        guard let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame else {
            return centeredFrame(size: Metrics.defaultFrameSize, around: window.frame.center)
        }
        let targetSize = NSSize(
            width: min(Metrics.defaultFrameSize.width, visibleFrame.width),
            height: min(Metrics.defaultFrameSize.height, visibleFrame.height)
        )
        return centeredFrame(size: targetSize, around: window.frame.center).constrained(to: visibleFrame)
    }

    func centeredFrame(size: NSSize, around center: NSPoint) -> NSRect {
        NSRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    func selectedPaneOriginY(visibleHeight: CGFloat, contentHeight: CGFloat) -> CGFloat {
        guard Pane(rawValue: selectedTabIndex) == .general else {
            return Metrics.paneDocumentInset
        }
        let centeredOriginY = floor((visibleHeight - contentHeight) / 2)
        return max(Metrics.paneDocumentInset, centeredOriginY)
    }

    func centerSelectedGeneralPaneContent(visibleHeight: CGFloat) {
        guard Pane(rawValue: selectedTabIndex) == .general,
              let selectedView,
              let contentBounds = visibleControlBounds(in: selectedView) else { return }
        let contentFrame = selectedView.convert(contentBounds, to: paneDocumentView)
        let deltaY = contentFrame.midY - visibleHeight / 2
        selectedView.frame.origin.y = max(
            Metrics.paneDocumentInset,
            floor(selectedView.frame.origin.y - deltaY)
        )
    }

    func visibleControlBounds(in view: NSView) -> NSRect? {
        view.subviews
            .filter { !$0.isHidden && $0.alphaValue > 0 && !$0.frame.isEmpty && $0 is NSControl }
            .map(\.frame)
            .reduce(nil as NSRect?) { partial, frame in
                partial.map { $0.union(frame) } ?? frame
            }
    }

    private func alignmentKind(for pane: Pane) -> PasteraPreferencePaneAlignmentKind? {
        switch pane {
        case .exclude:
            return .exclude
        case .shortcuts:
            return .shortcuts
        case .general, .type, .sync, .updates:
            return nil
        }
    }

    func preloadPaneViews() {
        guard !didPreloadPaneViews else { return }
        didPreloadPaneViews = true
        viewController.enumerated().forEach { index, viewController in
            let paneView = viewController.view
            CPYWindowAppearance.apply(to: paneView)
            PasteraSemanticViewStyler.apply(to: paneView, appearance: window?.effectiveAppearance)
            paneSizes[index] = PasteraPreferencePaneLayoutNormalizer.adapt(
                to: paneView,
                minimumGap: Metrics.minimumPaneControlGap
            )
        }
    }

    func installOpacityObserver() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: CPYWindowAppearance.opacityDidChangeNotification,
            object: AppEnvironment.current.defaults,
            queue: .main
        ) { [weak self] _ in
            CPYWindowAppearance.apply(to: self?.window)
            self?.refreshBackgroundColors()
        }
    }

    func refreshBackgroundColors() {
        let tokens = currentColorSet()
        rootView.layer?.backgroundColor = tokens.panelBackground.cgColor
        sidebarView.layer?.backgroundColor = tokens.surface.cgColor
        separatorView.layer?.backgroundColor = tokens.separator.cgColor
        selectedView.map { PasteraSemanticViewStyler.apply(to: $0, appearance: window?.effectiveAppearance) }
        sidebarButtons.forEach { $0.refreshAppearance() }
    }

    func currentColorSet() -> PasteraDesignTokens.ColorSet {
        PasteraDesignTokens.colors(
            for: window?.effectiveAppearance,
            opacity: CGFloat(CPYWindowAppearance.opacity())
        )
    }

    func handleKeyboardEvent(_ event: NSEvent) -> Bool {
        guard let firstResponder = window?.firstResponder as? NSView else { return false }
        if event.keyCode == 48, !event.modifierFlags.contains(.option) {
            return focusKeyView(relativeTo: firstResponder, offset: event.modifierFlags.contains(.shift) ? -1 : 1)
        }

        if firstResponder is RecordView {
            return false
        }

        if let focusedSidebarButton = sidebarButtons.first(where: { $0 === firstResponder }) {
            switch event.keyCode {
            case 125:
                return focusSidebarButton(relativeTo: focusedSidebarButton, offset: 1)
            case 126:
                return focusSidebarButton(relativeTo: focusedSidebarButton, offset: -1)
            case 36, 49, 76:
                return focusFirstPaneControl()
            default:
                return false
            }
        }

        switch event.keyCode {
        case 125:
            return focusPaneControl(relativeTo: firstResponder, offset: 1)
        case 126:
            return focusPaneControl(relativeTo: firstResponder, offset: -1)
        case 36, 49, 76:
            return triggerFocusedPaneControl(firstResponder)
        default:
            return false
        }
    }

    func focusSidebarButton(relativeTo button: PasteraPreferenceSidebarButton, offset: Int) -> Bool {
        guard let currentIndex = sidebarButtons.firstIndex(where: { $0 === button }) else { return false }
        let nextIndex = min(max(currentIndex + offset, 0), sidebarButtons.count - 1)
        return focusSidebarButton(at: nextIndex)
    }

    @discardableResult
    func focusSelectedSidebarButton() -> Bool {
        focusSidebarButton(at: selectedTabIndex)
    }

    @discardableResult
    func focusSidebarButton(at index: Int) -> Bool {
        guard sidebarButtons.indices.contains(index) else { return false }
        let button = sidebarButtons[index]
        switchView(button.tag)
        window?.makeFirstResponder(button)
        return true
    }

    @discardableResult
    func focusFirstPaneControl() -> Bool {
        guard let firstControl = focusablePaneControls().first else { return false }
        window?.makeFirstResponder(firstControl)
        scrollPaneControlToVisible(firstControl)
        return true
    }

    func focusPaneControl(relativeTo view: NSView, offset: Int) -> Bool {
        let controls = focusablePaneControls()
        guard let currentIndex = controls.firstIndex(where: { $0 === view || view.isDescendant(of: $0) }) else {
            return false
        }
        let nextIndex = min(max(currentIndex + offset, 0), controls.count - 1)
        guard controls.indices.contains(nextIndex), nextIndex != currentIndex else { return false }
        window?.makeFirstResponder(controls[nextIndex])
        scrollPaneControlToVisible(controls[nextIndex])
        return true
    }

    func triggerFocusedPaneControl(_ view: NSView) -> Bool {
        switch view {
        case let button as NSButton:
            button.performClick(nil)
            return true
        case let popup as NSPopUpButton:
            popup.performClick(nil)
            return true
        case let recordView as RecordView:
            _ = recordView.beginRecording()
            return true
        default:
            return false
        }
    }

    func focusKeyView(relativeTo view: NSView, offset: Int) -> Bool {
        let chain: [NSView] = sidebarButtons + focusablePaneControls()
        guard let index = chain.firstIndex(where: { view === $0 || view.isDescendant(of: $0) }) else { return false }
        let nextView = chain[(index + offset + chain.count) % chain.count]
        if let sidebarButton = nextView as? PasteraPreferenceSidebarButton {
            switchView(sidebarButton.tag)
        }
        window?.makeFirstResponder(nextView)
        scrollPaneControlToVisible(nextView)
        return true
    }

    func installKeyViewLoop() {
        let paneControls = focusablePaneControls()
        let chain: [NSView] = sidebarButtons + paneControls
        guard chain.count > 1 else { return }
        for index in chain.indices {
            chain[index].nextKeyView = chain[(index + 1) % chain.count]
        }
    }

    func focusablePaneControls() -> [NSView] {
        guard let selectedView else { return [] }
        return PasteraPreferenceFocusableCollector.collect(in: selectedView)
    }

    func scrollPaneControlToVisible(_ view: NSView) {
        guard view.isDescendant(of: paneDocumentView) else { return }
        let rect = view.convert(view.bounds, to: paneDocumentView)
        paneDocumentView.scrollToVisible(rect.insetBy(dx: 0, dy: -PasteraDesignTokens.Spacing.medium))
    }
}

private final class PasteraPreferenceSidebarButton: NSButton {
    var onFocus: ((PasteraPreferenceSidebarButton) -> Void)?
    var isSelected = false {
        didSet {
            refreshAppearance()
        }
    }

    private let symbolName: String
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    init(title: String, symbolName: String) {
        self.symbolName = symbolName
        super.init(frame: .zero)
        self.title = title
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        setup()
    }

    required init?(coder: NSCoder) {
        symbolName = ""
        super.init(coder: coder)
        setup()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        replaceHistoryMenuTrackingArea(&trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        refreshAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        refreshAppearance()
    }

    override func keyDown(with event: NSEvent) {
        if let window = window as? PasteraPreferencesWindow,
           window.onKeyDown?(event) == true {
            return
        }
        super.keyDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        if didBecome {
            onFocus?(self)
        }
        return didBecome
    }

    func refreshAppearance() {
        let tokens = PasteraDesignTokens.colors(for: effectiveAppearance)
        wantsLayer = true
        layer?.cornerRadius = PasteraDesignTokens.Metrics.compactRowCornerRadius
        layer?.masksToBounds = true
        if isSelected {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
        } else if isHovered {
            layer?.backgroundColor = tokens.hoveredRow.cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
        contentTintColor = isSelected ? .controlAccentColor : .secondaryLabelColor
        let textColor: NSColor = isSelected ? .controlAccentColor : .labelColor
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: isSelected ? .semibold : .medium),
                .foregroundColor: textColor
            ]
        )
    }

    private func setup() {
        setButtonType(.momentaryPushIn)
        isBordered = false
        imagePosition = .imageLeading
        alignment = .left
        font = .systemFont(ofSize: 13, weight: .medium)
        setAccessibilityLabel(title)
        refreshAppearance()
    }

    #if DEBUG
    var symbolNameForTesting: String {
        symbolName
    }
    #endif
}

private enum PasteraPreferenceFocusableCollector {
    static func collect(in view: NSView) -> [NSView] {
        var controls = [NSView]()
        collect(in: view, into: &controls)
        return controls.sorted { lhs, rhs in
            let lhsFrame = lhs.superview?.convert(lhs.frame, to: view) ?? lhs.frame
            let rhsFrame = rhs.superview?.convert(rhs.frame, to: view) ?? rhs.frame
            if abs(lhsFrame.midY - rhsFrame.midY) > 1 {
                return lhsFrame.midY > rhsFrame.midY
            }
            return lhsFrame.minX < rhsFrame.minX
        }
    }

    private static func collect(in view: NSView, into controls: inout [NSView]) {
        guard !view.isHidden, view.alphaValue > 0 else { return }
        if isFocusable(view) {
            controls.append(view)
        }
        view.subviews.forEach { collect(in: $0, into: &controls) }
    }

    private static func isFocusable(_ view: NSView) -> Bool {
        switch view {
        case let button as NSButton:
            return button.isEnabled
        case let textField as NSTextField:
            return textField.isEnabled && textField.isEditable
        case let popup as NSPopUpButton:
            return popup.isEnabled
        case let slider as NSSlider:
            return slider.isEnabled
        case let recordView as RecordView:
            return recordView.isEnabled
        case let tableView as NSTableView:
            return tableView.isEnabled
        case let textView as NSTextView:
            return textView.isEditable
        default:
            return false
        }
    }
}

private extension NSRect {
    var center: NSPoint {
        NSPoint(x: midX, y: midY)
    }

    func constrained(to bounds: NSRect) -> NSRect {
        var constrainedFrame = self
        constrainedFrame.origin.x = min(
            max(constrainedFrame.origin.x, bounds.minX),
            bounds.maxX - constrainedFrame.width
        )
        constrainedFrame.origin.y = min(
            max(constrainedFrame.origin.y, bounds.minY),
            bounds.maxY - constrainedFrame.height
        )
        return constrainedFrame
    }
}

#if DEBUG
extension CPYPreferencesWindowController {
    var defaultPreferenceWindowFrameSizeForTesting: NSSize {
        Metrics.defaultFrameSize
    }

    var rootBackgroundAlphaForTesting: CGFloat {
        CGFloat(rootView.layer?.backgroundColor?.alpha ?? 0)
    }

    var sidebarBackgroundBrightnessForTesting: CGFloat {
        perceivedBrightness(for: sidebarView.layer?.backgroundColor)
    }

    var preferenceSidebarTitlesForTesting: [String] {
        sidebarButtons.map(\.title)
    }

    var preferenceSidebarSymbolNamesForTesting: [String] {
        sidebarButtons.map(\.symbolNameForTesting)
    }

    func showPreferencePaneForTesting(title: String) {
        guard let pane = paneForTestingTitle(title) else { return }
        switchView(pane.rawValue)
    }

    var preferenceRecordViewBackgroundBrightnessValuesForTesting: [CGFloat] {
        guard let selectedView else { return [] }
        return recordViews(in: selectedView).map { perceivedBrightness(for: $0.backgroundColor.cgColor) }
    }

    var minimumVisibleControlVerticalGapForTesting: CGFloat? {
        guard let selectedView else { return nil }
        let groups = topLevelVisibleRowFrames(in: selectedView)
        guard groups.count > 1 else { return nil }
        let gaps = zip(groups, groups.dropFirst()).map { upper, lower in
            upper.minY - lower.maxY
        }
        return gaps.min()
    }

    func focusPreferenceSidebarForTesting(title: String) {
        guard let pane = paneForTestingTitle(title),
              let button = sidebarButtons.first(where: { $0.tag == pane.rawValue }) else { return }
        switchView(button.tag)
        window?.makeFirstResponder(button)
    }

    func handlePreferenceKeyboardEventForTesting(_ event: NSEvent) -> Bool {
        handleKeyboardEvent(event)
    }

    var selectedPreferencePaneTitleForTesting: String? {
        guard Pane.allCases.indices.contains(selectedTabIndex) else { return nil }
        return englishTitle(for: Pane.allCases[selectedTabIndex])
    }

    var focusedPreferencePaneControlTitleForTesting: String? {
        guard let firstResponder = window?.firstResponder as? NSView else { return nil }
        if let button = firstResponder as? NSButton, !sidebarButtons.contains(where: { $0 === button }) {
            return button.title.isEmpty ? String(describing: type(of: button)) : button.title
        }
        if let popup = firstResponder as? NSPopUpButton {
            return popup.titleOfSelectedItem ?? String(describing: type(of: popup))
        }
        if firstResponder is RecordView {
            return "RecordView"
        }
        if firstResponder is NSSlider {
            return "Slider"
        }
        if firstResponder is NSTextField || firstResponder is NSTextView || firstResponder is NSTableView {
            return String(describing: type(of: firstResponder))
        }
        return nil
    }

    var focusedPreferenceSidebarTitleForTesting: String? {
        guard let firstResponder = window?.firstResponder as? PasteraPreferenceSidebarButton,
              let pane = Pane(rawValue: firstResponder.tag) else { return nil }
        return englishTitle(for: pane)
    }

    var preferencePaneUsesScrollDocumentForTesting: Bool {
        paneScrollView.superview === paneContainerView && paneScrollView.documentView === paneDocumentView
    }

    var selectedPaneDocumentOriginForTesting: NSPoint {
        selectedView?.frame.origin ?? .zero
    }

    var selectedPaneFrameInContentViewForTesting: NSRect {
        guard let selectedView, let contentView = window?.contentView else { return .zero }
        return contentView.convert(selectedView.frame, from: selectedView.superview)
    }

    var selectedPaneDocumentWidthForTesting: CGFloat {
        selectedView?.frame.width ?? 0
    }

    var selectedPaneDocumentHeightForTesting: CGFloat {
        selectedView?.frame.height ?? 0
    }

    func selectedPaneTextFrameForTesting(matching texts: Set<String>) -> NSRect? {
        guard let selectedView,
              let textField = textFields(in: selectedView).first(where: { texts.contains($0.stringValue) }) else {
            return nil
        }
        return selectedView.convert(textField.bounds, from: textField)
    }

    var preferencePaneVisibleTopGapForTesting: CGFloat? {
        guard let selectedView,
              let firstRow = topLevelVisibleRowFrames(in: selectedView).first else { return nil }
        return selectedView.bounds.maxY - firstRow.maxY
    }

    var preferencePaneViewportWidthForTesting: CGFloat {
        paneScrollView.contentView.bounds.width
    }

    var preferencePaneViewportHeightForTesting: CGFloat {
        paneScrollView.contentView.bounds.height
    }

    var preferencePaneHasVerticalScrollerForTesting: Bool {
        paneScrollView.hasVerticalScroller
    }

    private func perceivedBrightness(for cgColor: CGColor?) -> CGFloat {
        guard let cgColor,
              let color = NSColor(cgColor: cgColor)?.usingColorSpace(.deviceRGB) else {
            return 0
        }
        return color.redComponent * 0.299
            + color.greenComponent * 0.587
            + color.blueComponent * 0.114
    }

    private func recordViews(in view: NSView) -> [RecordView] {
        var values = view.subviews.compactMap { $0 as? RecordView }
        view.subviews.forEach { values.append(contentsOf: recordViews(in: $0)) }
        return values
    }

    private func textFields(in view: NSView) -> [NSTextField] {
        var values = view.subviews.compactMap { $0 as? NSTextField }
        view.subviews.forEach { values.append(contentsOf: textFields(in: $0)) }
        return values
    }

    private func topLevelVisibleRowFrames(in view: NSView) -> [NSRect] {
        visibleLayoutFrames(in: view, root: view)
            .sorted { lhs, rhs in
                if lhs.maxY == rhs.maxY {
                    return lhs.minX < rhs.minX
                }
                return lhs.maxY > rhs.maxY
            }
            .reduce(into: [NSRect]()) { groups, frame in
                if let last = groups.indices.last,
                   isSamePreferenceTestingRow(groups[last], frame) {
                    groups[last] = groups[last].union(frame)
                } else {
                    groups.append(frame)
                }
            }
    }

    private func visibleLayoutFrames(in view: NSView, root: NSView) -> [NSRect] {
        guard !view.isHidden, view.alphaValue > 0 else { return [] }
        if isLayoutParticipant(view) {
            return [view.superview?.convert(view.frame, to: root) ?? view.frame]
        }
        var frames = [NSRect]()
        view.subviews.forEach { frames.append(contentsOf: visibleLayoutFrames(in: $0, root: root)) }
        return frames
    }

    private func isLayoutParticipant(_ view: NSView) -> Bool {
        switch view {
        case is NSBox:
            return true
        case is NSScrollView:
            return true
        case is NSStackView:
            return view.subviews.contains { !$0.isHidden && !$0.frame.isEmpty }
        case is PasteraSettingsSectionView:
            return true
        case is PasteraSettingsRowView:
            return true
        case let textField as NSTextField:
            return !textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case let control as NSControl:
            return control.isEnabled
        case let recordView as RecordView:
            return recordView.isEnabled
        case let textView as NSTextView:
            return textView.isEditable
        default:
            return false
        }
    }

    private func isSamePreferenceTestingRow(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        let sameRowTolerance: CGFloat = 3
        return lhs.minY <= rhs.maxY + sameRowTolerance && lhs.maxY >= rhs.minY - sameRowTolerance
    }

    private func paneForTestingTitle(_ title: String) -> Pane? {
        switch title.lowercased() {
        case "general":
            return .general
        case "types":
            return .type
        case "exclude":
            return .exclude
        case "shortcuts":
            return .shortcuts
        case "sync":
            return .sync
        case "update":
            return .updates
        default:
            return Pane.allCases.first { $0.title == title }
        }
    }

    private func englishTitle(for pane: Pane) -> String {
        switch pane {
        case .general:
            return "General"
        case .type:
            return "Types"
        case .exclude:
            return "Exclude"
        case .shortcuts:
            return "Shortcuts"
        case .sync:
            return "Sync"
        case .updates:
            return "Update"
        }
    }
}
#endif
