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
import QuartzCore

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

final class CPYPreferencesWindowController: NSWindowController {
    static let sharedController = CPYPreferencesWindowController()

    private enum Metrics {
        static let sidebarWidth: CGFloat = 188
        static let sidebarInset: CGFloat = 16
        static let sidebarRowHeight: CGFloat = 40
        static let paneDocumentInset: CGFloat = 16
        static let minimumWidth: CGFloat = 680
        static let minimumHeight: CGFloat = 480
        static let defaultFrameSize = NSSize(width: 760, height: 600)
        static let paneEntryAnimationKey = "PasteraPreferencePaneEntry"
    }

    private let catalog: PasteraPreferenceCatalog
    private let search: PasteraPreferenceSearch
    private let pageControllerProvider: PasteraPreferencePageControllerProvider
    private let reduceMotion: () -> Bool
    private let frameAutosaveName: String
    private let applicationWindows: () -> [NSWindow]
    private let deactivateApplication: () -> Void

    private let rootView = NSView()
    private let sidebarView = NSView()
    private let sidebarStack = NSStackView()
    private let searchField = NSSearchField()
    private let separatorView = NSView()
    private let paneContainerView = NSView()
    private let paneScrollView = NSScrollView()
    private let paneDocumentView = PasteraPreferenceFlippedView()
    private let searchResultsController = PasteraPreferenceSearchResultsViewController()

    private var sidebarButtons = [PasteraPreferenceSidebarButton]()
    private var sidebarGroupSeparators = [NSView]()
    private var pageControllers = [PasteraPreferencePaneID: PasteraPreferencePageController]()
    private var paneSizes = [PasteraPreferencePaneID: NSSize]()
    private var selectedView: NSView?
    private var selectedPaneID: PasteraPreferencePaneID?
    private var paneBeforeSearch: PasteraPreferencePaneID?
    private var currentSearchPages = [PasteraPreferenceCatalogPage]()
    private var isShowingSearchResults = false
    private var lastPaneTransitionDuration: TimeInterval = 0
    private var defaultsObserver: NSObjectProtocol?
    private var hasShownWindow = false
    private var didRestoreAutosavedFrame = false

    convenience init(
        frameAutosaveName: String = "PasteraPreferencesWindow",
        reduceMotion: @escaping () -> Bool = {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        },
        deactivateApplication: @escaping () -> Void = { NSApp.deactivate() }
    ) {
        let catalog = PasteraPreferenceCatalog.default
        self.init(
            catalog: catalog,
            pageControllerProvider: { paneID in
                Self.makePageController(paneID: paneID)
            },
            reduceMotion: reduceMotion,
            frameAutosaveName: frameAutosaveName,
            deactivateApplication: deactivateApplication
        )
    }

    init(
        catalog: PasteraPreferenceCatalog,
        pageControllerProvider: @escaping PasteraPreferencePageControllerProvider,
        reduceMotion: @escaping () -> Bool,
        frameAutosaveName: String,
        applicationWindows: @escaping () -> [NSWindow] = { NSApp.windows },
        deactivateApplication: @escaping () -> Void = { NSApp.deactivate() }
    ) {
        self.catalog = catalog
        self.search = PasteraPreferenceSearch(catalog: catalog)
        self.pageControllerProvider = pageControllerProvider
        self.reduceMotion = reduceMotion
        self.frameAutosaveName = frameAutosaveName
        self.applicationWindows = applicationWindows
        self.deactivateApplication = deactivateApplication

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
        didRestoreAutosavedFrame = window.setFrameUsingName(frameAutosaveName)
        window.setFrameAutosaveName(frameAutosaveName)

        setupContent()
        installOpacityObserver()
        switchView(.general)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        let wasVisible = window?.isVisible == true
        super.showWindow(sender)
        if !hasShownWindow {
            if !didRestoreAutosavedFrame {
                window?.center()
            }
            hasShownWindow = true
        }
        CPYWindowAppearance.applyStablePreferencesAppearance(to: window)
        refreshBackgroundColors()
        window?.makeKeyAndOrderFront(self)
        if !wasVisible {
            focusSelectedSidebarButton()
        }
    }

    func showPreferencePane(_ paneID: PasteraPreferencePaneID) {
        switchView(paneID)
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
        if let window, !window.makeFirstResponder(window) {
            window.endEditing(for: nil)
        }
        let hasOtherVisibleWindow = applicationWindows().contains { candidate in
            candidate !== window && candidate.isVisible && !candidate.isMiniaturized
        }
        if !hasOtherVisibleWindow {
            deactivateApplication()
        }
    }
}

extension CPYPreferencesWindowController: NSSearchFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        updateSearch(query: searchField.stringValue)
    }
}

private extension CPYPreferencesWindowController {
    static func makePageController(paneID: PasteraPreferencePaneID) -> PasteraPreferencePageController {
        switch paneID {
        case .general:
            return CPYGeneralPreferenceViewController()
        case .history:
            return CPYHistoryPreferenceViewController()
        case .scripts:
            return CPYScriptsPreferenceViewController()
        case .shortcuts:
            return CPYShortcutsPreferenceViewController()
        case .excludedApps:
            return CPYExcludeAppPreferenceViewController()
        case .agentIntegrations:
            return CPYAgentIntegrationPreferenceViewController()
        case .sync:
            return CPYSyncPreferenceViewController()
        case .about:
            return CPYAboutPreferenceViewController()
        }
    }

    func setupContent() {
        guard let window else { return }
        let colors = currentColorSet()
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = colors.panelBackground.cgColor
        window.contentView = rootView

        sidebarView.wantsLayer = true
        sidebarView.layer?.backgroundColor = colors.surface.cgColor
        separatorView.wantsLayer = true
        separatorView.layer?.backgroundColor = colors.separator.cgColor
        paneContainerView.wantsLayer = true
        paneContainerView.layer?.backgroundColor = NSColor.clear.cgColor

        searchField.placeholderString = pasteraPreferenceString("Search Settings")
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.setAccessibilityLabel(pasteraPreferenceString("Search Settings"))

        sidebarStack.orientation = .vertical
        sidebarStack.spacing = 4
        sidebarStack.alignment = .leading
        sidebarStack.distribution = .fill
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false
        sidebarStack.addArrangedSubview(searchField)
        sidebarStack.setCustomSpacing(8, after: searchField)

        var previousGroupTitle: String?
        for page in catalog.pages {
            if page.groupTitle != previousGroupTitle {
                if previousGroupTitle != nil {
                    let groupSeparator = NSView()
                    groupSeparator.wantsLayer = true
                    groupSeparator.layer?.backgroundColor = colors.separator.cgColor
                    sidebarStack.addArrangedSubview(groupSeparator)
                    groupSeparator.widthAnchor.constraint(equalTo: sidebarStack.widthAnchor).isActive = true
                    groupSeparator.heightAnchor.constraint(
                        equalToConstant: PasteraDesignTokens.Metrics.hairlineWidth
                    ).isActive = true
                    sidebarStack.setCustomSpacing(8, after: groupSeparator)
                    sidebarGroupSeparators.append(groupSeparator)
                }
                previousGroupTitle = page.groupTitle
            }
            let button = PasteraPreferenceSidebarButton(
                paneID: page.paneID,
                title: page.title,
                symbolName: page.symbolName
            )
            button.target = self
            button.action = #selector(sidebarButtonTapped(_:))
            button.onFocus = { [weak self] button in
                self?.switchView(button.paneID)
            }
            sidebarButtons.append(button)
            sidebarStack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: Metrics.sidebarWidth - Metrics.sidebarInset * 2).isActive = true
            button.heightAnchor.constraint(equalToConstant: Metrics.sidebarRowHeight).isActive = true
        }
        let bottomSpacer = NSView()
        bottomSpacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        bottomSpacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        sidebarStack.addArrangedSubview(bottomSpacer)
        bottomSpacer.widthAnchor.constraint(equalTo: sidebarStack.widthAnchor).isActive = true

        paneScrollView.translatesAutoresizingMaskIntoConstraints = false
        paneScrollView.drawsBackground = false
        paneScrollView.contentView.drawsBackground = false
        paneScrollView.borderType = .noBorder
        paneScrollView.hasHorizontalScroller = false
        paneScrollView.hasVerticalScroller = true
        paneScrollView.autohidesScrollers = true
        paneScrollView.horizontalScrollElasticity = .none
        paneScrollView.documentView = paneDocumentView
        paneDocumentView.frame = NSRect(origin: .zero, size: NSSize(width: 1, height: 1))

        let resultsView = searchResultsController.view
        resultsView.translatesAutoresizingMaskIntoConstraints = false
        resultsView.isHidden = true
        searchResultsController.onActivate = { [weak self] item in
            _ = self?.activateSearchResult(item)
        }

        [sidebarView, separatorView, paneContainerView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            rootView.addSubview($0)
        }
        sidebarView.addSubview(sidebarStack)
        paneContainerView.addSubview(paneScrollView)
        paneContainerView.addSubview(resultsView)

        NSLayoutConstraint.activate([
            sidebarView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            sidebarView.topAnchor.constraint(equalTo: rootView.topAnchor),
            sidebarView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            sidebarView.widthAnchor.constraint(equalToConstant: Metrics.sidebarWidth),
            sidebarStack.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor, constant: Metrics.sidebarInset),
            sidebarStack.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor, constant: -Metrics.sidebarInset),
            sidebarStack.topAnchor.constraint(equalTo: sidebarView.topAnchor, constant: 12),
            sidebarStack.bottomAnchor.constraint(equalTo: sidebarView.bottomAnchor, constant: -12),
            searchField.widthAnchor.constraint(equalTo: sidebarStack.widthAnchor),

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
            paneScrollView.bottomAnchor.constraint(equalTo: paneContainerView.bottomAnchor),

            resultsView.leadingAnchor.constraint(equalTo: paneContainerView.leadingAnchor),
            resultsView.trailingAnchor.constraint(equalTo: paneContainerView.trailingAnchor),
            resultsView.topAnchor.constraint(equalTo: paneContainerView.topAnchor),
            resultsView.bottomAnchor.constraint(equalTo: paneContainerView.bottomAnchor)
        ])
    }

    @objc func sidebarButtonTapped(_ sender: PasteraPreferenceSidebarButton) {
        clearSearchAndRestorePane()
        switchView(sender.paneID)
        window?.makeFirstResponder(sender)
    }

    func pageController(for paneID: PasteraPreferencePaneID) -> PasteraPreferencePageController {
        if let cachedController = pageControllers[paneID] {
            return cachedController
        }
        let controller = pageControllerProvider(paneID)
        precondition(controller.paneID == paneID, "Preference page provider returned a mismatched pane ID")
        if let page = controller as? PasteraPreferencePageViewController {
            page.onContentSizeChange = { [weak self, weak page] size in
                guard let self else { return }
                self.paneSizes[paneID] = size
                guard self.selectedPaneID == paneID, self.selectedView === page?.view else { return }
                self.layoutSelectedPane(contentSize: size)
                self.installKeyViewLoop()
            }
        }
        pageControllers[paneID] = controller
        return controller
    }

    func switchView(_ paneID: PasteraPreferencePaneID) {
        setSearchResultsVisible(false)
        if selectedPaneID == paneID, selectedView?.superview === paneDocumentView {
            updateSidebarSelection(paneID)
            return
        }

        let controller = pageController(for: paneID)
        let newView = controller.view
        CPYWindowAppearance.apply(to: newView)
        PasteraSemanticViewStyler.apply(to: newView, appearance: window?.effectiveAppearance)
        rootView.layoutSubtreeIfNeeded()
        let viewportWidth = max(1, paneScrollView.contentView.bounds.width)
        newView.frame.size.width = max(1, viewportWidth - Metrics.paneDocumentInset * 2)
        newView.needsLayout = true
        newView.layoutSubtreeIfNeeded()
        let paneSize = newView.fittingSize
        paneSizes[paneID] = paneSize

        selectedView?.layer?.removeAnimation(forKey: Metrics.paneEntryAnimationKey)
        selectedView?.removeFromSuperview()
        newView.translatesAutoresizingMaskIntoConstraints = true
        paneDocumentView.addSubview(newView)
        selectedView = newView
        selectedPaneID = paneID
        animatePaneEntry(newView)
        updateSidebarSelection(paneID)
        layoutSelectedPane(contentSize: paneSize)
        paneScrollView.contentView.scroll(to: .zero)
        paneScrollView.reflectScrolledClipView(paneScrollView.contentView)
        installKeyViewLoop()
        refreshSyncControllerIfNeeded(controller)
        CPYWindowAppearance.applyStablePreferencesAppearance(to: window)
    }

    func animatePaneEntry(_ paneView: NSView) {
        let duration: TimeInterval = reduceMotion() ? 0 : 0.12
        lastPaneTransitionDuration = duration
        guard duration > 0 else {
            paneView.alphaValue = 1
            return
        }
        paneView.wantsLayer = true
        paneView.alphaValue = 1
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0
        animation.toValue = 1
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        paneView.layer?.add(animation, forKey: Metrics.paneEntryAnimationKey)
    }

    func updateSidebarSelection(_ paneID: PasteraPreferencePaneID) {
        sidebarButtons.forEach { $0.isSelected = $0.paneID == paneID }
    }

    func refreshSyncControllerIfNeeded(_ controller: PasteraPreferencePageController) {
        (controller as? CPYSyncPreferenceViewController)?.refreshDefaultFolderAvailability()
    }

    func updateSearch(query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            clearSearchAndRestorePane()
            return
        }
        if !isShowingSearchResults {
            paneBeforeSearch = selectedPaneID
        }
        currentSearchPages = search.search(trimmedQuery)
        searchResultsController.updateResults(currentSearchPages)
        setSearchResultsVisible(true)
        installKeyViewLoop()
    }

    func clearSearchAndRestorePane() {
        searchField.stringValue = ""
        currentSearchPages = []
        setSearchResultsVisible(false)
        if let paneBeforeSearch {
            self.paneBeforeSearch = nil
            switchView(paneBeforeSearch)
        }
        installKeyViewLoop()
    }

    func setSearchResultsVisible(_ visible: Bool) {
        isShowingSearchResults = visible
        paneScrollView.isHidden = visible
        searchResultsController.view.isHidden = !visible
    }

    @discardableResult
    func activateSearchResult(_ item: PasteraPreferenceSearchItem) -> Bool {
        clearSearchAndRestorePane()
        switchView(item.paneID)
        let controller = pageController(for: item.paneID)
        return controller.revealSetting(anchorID: item.anchorID, animated: !reduceMotion())
    }

    func layoutSelectedPane(contentSize: NSSize? = nil) {
        guard let selectedView, let selectedPaneID else { return }
        rootView.layoutSubtreeIfNeeded()
        let viewport = paneScrollView.contentView.bounds.size
        let visibleWidth = max(1, viewport.width)
        let visibleHeight = max(1, viewport.height)
        let contentWidth = max(1, visibleWidth - Metrics.paneDocumentInset * 2)
        let measuredSize: NSSize
        if let contentSize {
            measuredSize = contentSize
        } else {
            selectedView.frame.size.width = contentWidth
            selectedView.needsLayout = true
            selectedView.layoutSubtreeIfNeeded()
            measuredSize = selectedView.fittingSize
            paneSizes[selectedPaneID] = measuredSize
        }
        let contentHeight = max(1, measuredSize.height)

        paneDocumentView.frame.size = NSSize(
            width: visibleWidth,
            height: max(visibleHeight, contentHeight + Metrics.paneDocumentInset * 2)
        )
        selectedView.frame = NSRect(
            x: Metrics.paneDocumentInset,
            y: selectedPaneOriginY(visibleHeight: visibleHeight, contentHeight: contentHeight),
            width: contentWidth,
            height: contentHeight
        )

    }

    func selectedPaneOriginY(visibleHeight: CGFloat, contentHeight: CGFloat) -> CGFloat {
        Metrics.paneDocumentInset
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

    func installOpacityObserver() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: CPYWindowAppearance.opacityDidChangeNotification,
            object: AppEnvironment.current.defaults,
            queue: .main
        ) { [weak self] _ in
            CPYWindowAppearance.applyStablePreferencesAppearance(to: self?.window)
            self?.refreshBackgroundColors()
        }
    }

    func refreshBackgroundColors() {
        let colors = currentColorSet()
        rootView.layer?.backgroundColor = colors.panelBackground.cgColor
        sidebarView.layer?.backgroundColor = colors.surface.cgColor
        separatorView.layer?.backgroundColor = colors.separator.cgColor
        sidebarGroupSeparators.forEach { $0.layer?.backgroundColor = colors.separator.cgColor }
        selectedView.map {
            PasteraSemanticViewStyler.apply(to: $0, appearance: window?.effectiveAppearance)
        }
        sidebarButtons.forEach { $0.refreshAppearance() }
    }

    func currentColorSet() -> PasteraDesignTokens.ColorSet {
        PasteraDesignTokens.colors(
            for: window?.effectiveAppearance,
            opacity: 1
        )
    }

    func handleKeyboardEvent(_ event: NSEvent) -> Bool {
        let firstResponder = window?.firstResponder as? NSView
        if let firstResponder, isInsideRecordView(firstResponder) {
            return false
        }
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "f" {
            return focusSearchField()
        }
        if event.keyCode == 53,
           let textView = firstResponder as? NSTextView,
           textView.isFieldEditor,
           !isSearchFieldFirstResponder(textView) {
            textView.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
            return true
        }
        if event.keyCode == 53 {
            if !searchField.stringValue.isEmpty {
                clearSearchAndRestorePane()
                return true
            }
            window?.close()
            return true
        }

        guard let firstResponder else { return false }
        if event.keyCode == 48, !event.modifierFlags.contains(.option) {
            return focusKeyView(
                relativeTo: firstResponder,
                offset: event.modifierFlags.contains(.shift) ? -1 : 1
            )
        }
        if isSearchFieldFirstResponder(firstResponder) {
            switch event.keyCode {
            case 36, 76:
                return searchResultsController.activateFirstResult()
            case 125:
                return focusFirstPaneControl()
            default:
                return false
            }
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

    func focusSearchField() -> Bool {
        guard let window else { return false }
        window.makeFirstResponder(searchField)
        searchField.selectText(nil)
        return true
    }

    func isSearchFieldFirstResponder(_ view: NSView) -> Bool {
        view === searchField || view === searchField.currentEditor()
    }

    func isInsideRecordView(_ view: NSView) -> Bool {
        var currentView: NSView? = view
        while let current = currentView {
            if current is RecordView {
                return true
            }
            currentView = current.superview
        }
        return false
    }

    func focusSidebarButton(relativeTo button: PasteraPreferenceSidebarButton, offset: Int) -> Bool {
        guard let currentIndex = sidebarButtons.firstIndex(where: { $0 === button }) else { return false }
        return focusSidebarButton(at: min(max(currentIndex + offset, 0), sidebarButtons.count - 1))
    }

    @discardableResult
    func focusSelectedSidebarButton() -> Bool {
        guard let selectedPaneID,
              let index = sidebarButtons.firstIndex(where: { $0.paneID == selectedPaneID }) else { return false }
        return focusSidebarButton(at: index)
    }

    @discardableResult
    func focusSidebarButton(at index: Int) -> Bool {
        guard sidebarButtons.indices.contains(index) else { return false }
        let button = sidebarButtons[index]
        switchView(button.paneID)
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
        default:
            return false
        }
    }

    func focusKeyView(relativeTo view: NSView, offset: Int) -> Bool {
        let chain: [NSView] = sidebarButtons + focusablePaneControls()
        guard !chain.isEmpty,
              let index = chain.firstIndex(where: { view === $0 || view.isDescendant(of: $0) }) else { return false }
        let nextView = chain[(index + offset + chain.count) % chain.count]
        if let sidebarButton = nextView as? PasteraPreferenceSidebarButton {
            switchView(sidebarButton.paneID)
        }
        window?.makeFirstResponder(nextView)
        scrollPaneControlToVisible(nextView)
        return true
    }

    func installKeyViewLoop() {
        let chain: [NSView] = sidebarButtons + focusablePaneControls()
        guard chain.count > 1 else { return }
        for index in chain.indices {
            chain[index].nextKeyView = chain[(index + 1) % chain.count]
        }
    }

    func focusablePaneControls() -> [NSView] {
        let contentView = isShowingSearchResults ? searchResultsController.view : selectedView
        return contentView.map { PasteraPreferenceFocusableCollector.collect(in: $0) } ?? []
    }

    func scrollPaneControlToVisible(_ view: NSView) {
        if view.isDescendant(of: paneDocumentView) {
            let rect = view.convert(view.bounds, to: paneDocumentView)
            paneDocumentView.scrollToVisible(rect.insetBy(dx: 0, dy: -12))
        } else {
            view.scrollToVisible(view.bounds.insetBy(dx: 0, dy: -12))
        }
    }
}

private final class PasteraPreferenceSidebarButton: NSButton {
    static let titleFontSize: CGFloat = 14
    static let iconPointSize: CGFloat = 20
    static let iconSlotWidth: CGFloat = 26

    let paneID: PasteraPreferencePaneID
    let symbolName: String
    var onFocus: ((PasteraPreferenceSidebarButton) -> Void)?
    var isSelected = false {
        didSet { refreshAppearance() }
    }

    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    init(paneID: PasteraPreferencePaneID, title: String, symbolName: String) {
        self.paneID = paneID
        self.symbolName = symbolName
        super.init(frame: .zero)
        self.title = title
        image = Self.makeIcon(symbolName: symbolName, accessibilityDescription: title)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
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
        let colors = PasteraDesignTokens.colors(for: effectiveAppearance)
        wantsLayer = true
        layer?.cornerRadius = PasteraDesignTokens.Metrics.compactRowCornerRadius
        layer?.masksToBounds = true
        if isSelected {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
        } else if isHovered {
            layer?.backgroundColor = colors.hoveredRow.cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
        contentTintColor = isSelected ? .labelColor : .secondaryLabelColor
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: Self.titleFontSize, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ]
        )
    }

    private func setup() {
        setButtonType(.momentaryPushIn)
        isBordered = false
        imagePosition = .imageLeading
        imageScaling = .scaleNone
        alignment = .left
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
        setAccessibilityLabel(title)
        refreshAppearance()
    }

    private static func makeIcon(symbolName: String, accessibilityDescription: String) -> NSImage? {
        guard let symbol = configuredSymbol(
            symbolName: symbolName,
            accessibilityDescription: accessibilityDescription
        ), let drawRect = iconDrawRect(symbolName: symbolName) else { return nil }
        let image = NSImage(size: NSSize(width: iconSlotWidth, height: iconPointSize), flipped: false) { _ in
            symbol.draw(in: drawRect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }

    private static func configuredSymbol(
        symbolName: String,
        accessibilityDescription: String? = nil
    ) -> NSImage? {
        NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityDescription
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: iconPointSize, weight: .medium)
        )
    }

    static func iconDrawRect(symbolName: String) -> NSRect? {
        guard let symbol = configuredSymbol(symbolName: symbolName),
              symbol.size.width > 0,
              symbol.size.height > 0 else { return nil }
        let scale = min(iconPointSize / symbol.size.width, iconPointSize / symbol.size.height)
        let size = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
        return NSRect(
            x: (iconPointSize - size.width) / 2,
            y: (iconPointSize - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}

private enum PasteraPreferenceFocusableCollector {
    static func collect(in view: NSView) -> [NSView] {
        var controls = [NSView]()
        collect(in: view, into: &controls)
        return controls.sorted { lhs, rhs in
            let lhsFrame = lhs.superview?.convert(lhs.frame, to: view) ?? lhs.frame
            let rhsFrame = rhs.superview?.convert(rhs.frame, to: view) ?? rhs.frame
            if abs(lhsFrame.midY - rhsFrame.midY) > 1 {
                return view.isFlipped
                    ? lhsFrame.midY < rhsFrame.midY
                    : lhsFrame.midY > rhsFrame.midY
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
        constrainedFrame.origin.x = min(max(constrainedFrame.origin.x, bounds.minX), bounds.maxX - width)
        constrainedFrame.origin.y = min(max(constrainedFrame.origin.y, bounds.minY), bounds.maxY - height)
        return constrainedFrame
    }
}

#if DEBUG
extension CPYPreferencesWindowController {
    var defaultPreferenceWindowFrameSizeForTesting: NSSize { Metrics.defaultFrameSize }
    var preferenceSidebarWidthForTesting: CGFloat { Metrics.sidebarWidth }
    var preferenceSidebarInsetForTesting: CGFloat { Metrics.sidebarInset }
    var preferenceSidebarTitlesForTesting: [String] { sidebarButtons.map(\.title) }
    var preferenceSidebarSymbolNamesForTesting: [String] { sidebarButtons.map(\.symbolName) }
    var preferenceSidebarRowHeightForTesting: CGFloat { Metrics.sidebarRowHeight }
    var preferenceSidebarFontSizeForTesting: CGFloat { PasteraPreferenceSidebarButton.titleFontSize }
    var preferenceSidebarIconSlotWidthForTesting: CGFloat { PasteraPreferenceSidebarButton.iconSlotWidth }
    var preferenceSidebarIconPointSizeForTesting: CGFloat { PasteraPreferenceSidebarButton.iconPointSize }
    var preferenceSidebarIconDrawRectsForTesting: [NSRect] {
        sidebarButtons.compactMap { PasteraPreferenceSidebarButton.iconDrawRect(symbolName: $0.symbolName) }
    }
    var preferenceSelectedSidebarIconTintForTesting: NSColor? {
        sidebarButtons.first(where: \.isSelected)?.contentTintColor
    }
    var preferenceSelectedSidebarTitleColorForTesting: NSColor? {
        guard let button = sidebarButtons.first(where: \.isSelected), !button.attributedTitle.string.isEmpty else {
            return nil
        }
        return button.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
    }
    var preferenceSidebarButtonHeightsForTesting: [CGFloat] { sidebarButtons.map(\.frame.height) }
    var preferenceSidebarGroupTitlesForTesting: [String] { [] }
    var preferenceSidebarGroupSeparatorCountForTesting: Int { sidebarGroupSeparators.count }
    var preferencePageTopInsetForTesting: CGFloat { PasteraPreferencePageViewController.pageTopInset }
    func preferenceSidebarButtonFrameForTesting(paneID: PasteraPreferencePaneID) -> NSRect? {
        guard let button = sidebarButtons.first(where: { $0.paneID == paneID }) else { return nil }
        return button.convert(button.bounds, to: sidebarView)
    }
    var preferenceFrameAutosaveNameForTesting: String { frameAutosaveName }
    var preferenceSearchQueryForTesting: String { searchField.stringValue }
    var preferenceSearchResultsVisibleForTesting: Bool { isShowingSearchResults }
    var selectedPreferencePaneIDForTesting: PasteraPreferencePaneID? { selectedPaneID }
    var cachedPreferencePageCountForTesting: Int { pageControllers.count }
    var lastPaneTransitionDurationForTesting: TimeInterval { lastPaneTransitionDuration }

    var visiblePreferenceScrollViewCountForTesting: Int {
        window?.contentView.map { visibleScrollViewCount(in: $0) } ?? 0
    }

    var preferenceSearchFieldIsFocusedForTesting: Bool {
        guard let firstResponder = window?.firstResponder as? NSView else { return false }
        return isSearchFieldFirstResponder(firstResponder)
    }

    func cachedPreferencePageForTesting(paneID: PasteraPreferencePaneID) -> NSViewController? {
        pageControllers[paneID]
    }

    func setPreferenceSearchQueryForTesting(_ query: String) {
        searchField.stringValue = query
        updateSearch(query: query)
    }

    @discardableResult
    func activatePreferenceSearchResultForTesting(itemID: String) -> Bool {
        guard let item = currentSearchPages.flatMap(\.searchItems).first(where: { $0.id == itemID }) else {
            return false
        }
        return activateSearchResult(item)
    }

    func showPreferencePaneForTesting(paneID: PasteraPreferencePaneID) {
        switchView(paneID)
    }

    func showPreferencePaneForTesting(title: String) {
        guard let paneID = paneID(forTestingTitle: title) else { return }
        switchView(paneID)
    }

    func focusPreferenceSidebarForTesting(title: String) {
        guard let paneID = paneID(forTestingTitle: title),
              let index = sidebarButtons.firstIndex(where: { $0.paneID == paneID }) else { return }
        _ = focusSidebarButton(at: index)
    }

    func handlePreferenceKeyboardEventForTesting(_ event: NSEvent) -> Bool {
        handleKeyboardEvent(event)
    }

    var selectedPreferencePaneTitleForTesting: String? {
        selectedPaneID.map(englishTitle(for:))
    }

    var focusedPreferenceSidebarTitleForTesting: String? {
        guard let button = window?.firstResponder as? PasteraPreferenceSidebarButton else { return nil }
        return englishTitle(for: button.paneID)
    }

    var focusedPreferencePaneControlTitleForTesting: String? {
        guard let firstResponder = window?.firstResponder as? NSView else { return nil }
        if let button = firstResponder as? NSButton,
           !sidebarButtons.contains(where: { $0 === button }) {
            if !button.title.isEmpty { return button.title }
            return button.accessibilityLabel() ?? String(describing: type(of: button))
        }
        if let popup = firstResponder as? NSPopUpButton {
            return popup.titleOfSelectedItem ?? String(describing: type(of: popup))
        }
        if firstResponder is RecordView { return "RecordView" }
        if firstResponder is NSSlider { return "Slider" }
        if firstResponder is NSTextField || firstResponder is NSTextView || firstResponder is NSTableView {
            return String(describing: type(of: firstResponder))
        }
        return nil
    }

    var rootBackgroundAlphaForTesting: CGFloat {
        CGFloat(rootView.layer?.backgroundColor?.alpha ?? 0)
    }

    var sidebarBackgroundBrightnessForTesting: CGFloat {
        perceivedBrightness(for: sidebarView.layer?.backgroundColor)
    }

    var preferenceRecordViewBackgroundBrightnessValuesForTesting: [CGFloat] {
        selectedView.map { recordViews(in: $0).map { perceivedBrightness(for: $0.backgroundColor.cgColor) } } ?? []
    }

    var minimumVisibleControlVerticalGapForTesting: CGFloat? {
        guard let selectedView else { return nil }
        let groups = topLevelVisibleRowFrames(in: selectedView)
        guard groups.count > 1 else { return nil }
        return zip(groups, groups.dropFirst()).map { $0.minY - $1.maxY }.min()
    }

    var preferencePaneUsesScrollDocumentForTesting: Bool {
        paneScrollView.superview === paneContainerView && paneScrollView.documentView === paneDocumentView
    }

    var selectedPaneDocumentOriginForTesting: NSPoint { selectedView?.frame.origin ?? .zero }
    var selectedPaneDocumentWidthForTesting: CGFloat { selectedView?.frame.width ?? 0 }
    var selectedPaneDocumentHeightForTesting: CGFloat { selectedView?.frame.height ?? 0 }
    var preferencePaneViewportWidthForTesting: CGFloat { paneScrollView.contentView.bounds.width }
    var preferencePaneViewportHeightForTesting: CGFloat { paneScrollView.contentView.bounds.height }
    var preferencePaneHasVerticalScrollerForTesting: Bool { paneScrollView.hasVerticalScroller }
    var preferencePaneVisibleBottomGapForTesting: CGFloat {
        guard let selectedView else { return 0 }
        return max(0, paneScrollView.contentView.bounds.height - selectedView.frame.maxY)
    }

    var selectedPaneFrameInContentViewForTesting: NSRect {
        guard let selectedView, let contentView = window?.contentView else { return .zero }
        return contentView.convert(selectedView.frame, from: selectedView.superview)
    }

    func selectedPaneTextFrameForTesting(matching texts: Set<String>) -> NSRect? {
        guard let selectedView,
              let textField = textFields(in: selectedView).first(where: { texts.contains($0.stringValue) }) else {
            return nil
        }
        return selectedView.convert(textField.bounds, from: textField)
    }

    func selectedPaneDescendantFrameForTesting(accessibilityIdentifier: String) -> NSRect? {
        guard let selectedView,
              let descendant = descendant(
                in: selectedView,
                accessibilityIdentifier: accessibilityIdentifier
              ) else {
            return nil
        }
        return selectedView.convert(descendant.bounds, from: descendant)
    }

    var preferencePaneVisibleTopGapForTesting: CGFloat? {
        guard let selectedView,
              let firstRow = topLevelVisibleRowFrames(in: selectedView).first else { return nil }
        return selectedView.bounds.maxY - firstRow.maxY
    }

    private func paneID(forTestingTitle title: String) -> PasteraPreferencePaneID? {
        switch title.lowercased() {
        case "general", "menu":
            return .general
        case "history & preview", "history", "types":
            return .history
        case "shortcuts":
            return .shortcuts
        case "scripts", "script transforms":
            return .scripts
        case "excluded apps", "exclude":
            return .excludedApps
        case "agent integrations", "agents", "codex", "claude":
            return .agentIntegrations
        case "sync":
            return .sync
        case "about pastera", "about", "update":
            return .about
        default:
            return catalog.pages.first { $0.title == title }?.paneID
        }
    }

    private func englishTitle(for paneID: PasteraPreferencePaneID) -> String {
        switch paneID {
        case .general: return "General"
        case .history: return "History & Preview"
        case .scripts: return "Scripts"
        case .shortcuts: return "Shortcuts"
        case .excludedApps: return "Excluded Apps"
        case .agentIntegrations: return "Agent Integrations"
        case .sync: return "Sync"
        case .about: return "About Pastera"
        }
    }

    private func perceivedBrightness(for cgColor: CGColor?) -> CGFloat {
        guard let cgColor,
              let color = NSColor(cgColor: cgColor)?.usingColorSpace(.deviceRGB) else { return 0 }
        return color.redComponent * 0.299 + color.greenComponent * 0.587 + color.blueComponent * 0.114
    }

    private func recordViews(in view: NSView) -> [RecordView] {
        view.subviews.compactMap { $0 as? RecordView }
            + view.subviews.flatMap { recordViews(in: $0) }
    }

    private func textFields(in view: NSView) -> [NSTextField] {
        view.subviews.compactMap { $0 as? NSTextField }
            + view.subviews.flatMap { textFields(in: $0) }
    }

    private func topLevelVisibleRowFrames(in view: NSView) -> [NSRect] {
        visibleLayoutFrames(in: view, root: view)
            .sorted { lhs, rhs in lhs.maxY == rhs.maxY ? lhs.minX < rhs.minX : lhs.maxY > rhs.maxY }
            .reduce(into: [NSRect]()) { groups, frame in
                if let last = groups.indices.last, isSamePreferenceTestingRow(groups[last], frame) {
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
        return view.subviews.flatMap { visibleLayoutFrames(in: $0, root: root) }
    }

    private func isLayoutParticipant(_ view: NSView) -> Bool {
        switch view {
        case is NSBox, is NSScrollView, is PasteraSettingsSectionView, is PasteraSettingsRowView:
            return true
        case is NSStackView:
            return view.subviews.contains { !$0.isHidden && !$0.frame.isEmpty }
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
        lhs.minY <= rhs.maxY + 3 && lhs.maxY >= rhs.minY - 3
    }

    private func visibleScrollViewCount(in view: NSView) -> Int {
        guard !view.isHidden else { return 0 }
        let ownCount = view is NSScrollView ? 1 : 0
        return ownCount + view.subviews.reduce(0) { $0 + visibleScrollViewCount(in: $1) }
    }

    private func descendant(in view: NSView, accessibilityIdentifier: String) -> NSView? {
        if view.accessibilityIdentifier() == accessibilityIdentifier {
            return view
        }
        for subview in view.subviews {
            if let match = descendant(in: subview, accessibilityIdentifier: accessibilityIdentifier) {
                return match
            }
        }
        return nil
    }
}
#endif
