//
//  HistoryMenuPaginationState.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Codex on 2026/06/02.
//
//  Copyright © 2015-2026 Clipy Project.
//

import Cocoa

enum HistoryBrowserLayout {
    static let width: CGFloat = 352
    static let minimumTitlePreviewLength = 60
}

enum HistoryMenuTypeFilter: Int, CaseIterable, Equatable {
    case all
    case text
    case images
    case files
    case pdf

    var title: String {
        switch self {
        case .all:
            return "All"
        case .text:
            return "Text"
        case .images:
            return "Image"
        case .files:
            return "File"
        case .pdf:
            return "PDF"
        }
    }

    var pasteboardTypes: Set<NSPasteboard.PasteboardType> {
        switch self {
        case .all:
            return []
        case .text:
            return [.string, .deprecatedString]
        case .images:
            return NSPasteboard.PasteboardType.clipyImageTypes
        case .files:
            return [.fileURL]
        case .pdf:
            return [.pdf, .deprecatedPDF]
        }
    }
}

enum HistoryMenuSelectionDirection {
    case previous
    case next
}

enum HistoryMenuNumberShortcutMapper {
    static let maximumShortcutRowCount = 10

    static func rowIndex(
        for event: NSEvent,
        startsAtZero: Bool,
        rowCount: Int,
        allowedModifierFlags: NSEvent.ModifierFlags = []
    ) -> Int? {
        guard event.type == .keyDown, rowCount > 0 else { return nil }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.numericPad)
        guard modifierFlagsMatch(flags, allowedModifierFlags: allowedModifierFlags),
              let text = event.charactersIgnoringModifiers,
              text.count == 1,
              let digit = Int(text) else {
            return nil
        }

        let index: Int
        if startsAtZero {
            index = digit
        } else {
            index = digit == 0 ? 9 : digit - 1
        }
        guard (0..<rowCount).contains(index) else { return nil }
        return index
    }

    private static func modifierFlagsMatch(
        _ flags: NSEvent.ModifierFlags,
        allowedModifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        if flags.isEmpty { return true }
        let normalizedAllowedFlags = allowedModifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(.numericPad)
        return !normalizedAllowedFlags.isEmpty && flags == normalizedAllowedFlags
    }

    static func shortcutText(forRowIndex index: Int, startsAtZero: Bool) -> String? {
        guard (0..<maximumShortcutRowCount).contains(index) else { return nil }
        var shortcutNumber = startsAtZero ? index : index + 1
        if shortcutNumber == maximumShortcutRowCount {
            shortcutNumber = 0
        }
        return "\(shortcutNumber)"
    }
}

struct HistoryMenuPage {
    let details: [PasteboardHistoryDetail]
    let hasNextPage: Bool
    let error: HistorySearchError?

    init(details: [PasteboardHistoryDetail] = [], hasNextPage: Bool = false, error: HistorySearchError? = nil) { self.details = details; self.hasNextPage = hasNextPage; self.error = error }

    static func result(_ details: [PasteboardHistoryDetail], pageSize: Int) -> HistoryMenuPage {
        HistoryMenuPage(details: Array(details.prefix(pageSize)), hasNextPage: details.count > pageSize)
    }
}

extension HistorySearchError {
    var historyMenuTitle: String {
        switch self {
        case .invalidRegularExpression:
            return String(localized: "Invalid Regex")
        }
    }
}

struct HistoryMenuPaginationState: Equatable {
    static let defaultPageSize = 10

    private(set) var query: String
    private(set) var mode: HistorySearchQuery.Mode
    private(set) var caseSensitive: Bool
    private(set) var typeFilter: HistoryMenuTypeFilter
    private(set) var pageIndex: Int
    let pageSize: Int

    init(
        query: String = "",
        mode: HistorySearchQuery.Mode = .plain,
        caseSensitive: Bool = false,
        typeFilter: HistoryMenuTypeFilter = .all,
        pageIndex: Int = 0,
        pageSize: Int = defaultPageSize
    ) {
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.mode = mode
        self.caseSensitive = caseSensitive
        self.typeFilter = typeFilter
        self.pageIndex = max(0, pageIndex)
        self.pageSize = max(1, pageSize)
    }

    var offset: Int {
        pageIndex * pageSize
    }

    var displayPage: Int {
        pageIndex + 1
    }

    var selectedTypes: Set<NSPasteboard.PasteboardType> {
        typeFilter.pasteboardTypes
    }

    var hasActiveSearchOptions: Bool {
        !query.isEmpty || typeFilter != .all
    }

    mutating func updateQuery(_ newValue: String) {
        let normalizedValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query != normalizedValue else { return }
        query = normalizedValue
        pageIndex = 0
    }

    mutating func updateMode(_ newValue: HistorySearchQuery.Mode) {
        guard mode != newValue else { return }
        mode = newValue
        pageIndex = 0
    }

    mutating func updateCaseSensitive(_ newValue: Bool) {
        guard caseSensitive != newValue else { return }
        caseSensitive = newValue
        pageIndex = 0
    }

    mutating func updateTypeFilter(_ newValue: HistoryMenuTypeFilter) {
        guard typeFilter != newValue else { return }
        typeFilter = newValue
        pageIndex = 0
    }

    mutating func goToNextPage(if hasNextPage: Bool) {
        guard hasNextPage else { return }
        pageIndex += 1
    }

    mutating func goToPreviousPage() {
        pageIndex = max(0, pageIndex - 1)
    }

    mutating func resetPage() {
        pageIndex = 0
    }
}

extension NSView {
    func replaceHistoryMenuTrackingArea(_ trackingArea: inout NSTrackingArea?) {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let newTrackingArea = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect], owner: self)
        trackingArea = newTrackingArea
        addTrackingArea(newTrackingArea)
    }

    @discardableResult
    func moveHistoryMenuFocus(with event: NSEvent) -> Bool {
        guard event.keyCode == 48 else { return false }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isBackward = flags.contains(.shift)
        if let segmentedControl = self as? HistoryMenuFocusableSegmentedControl,
           segmentedControl.moveFocusedSegment(backward: isBackward) {
            return true
        }

        if isBackward {
            window?.selectKeyView(preceding: self)
        } else if let nextKeyView {
            (nextKeyView as? HistoryMenuFocusableSegmentedControl)?.prepareForKeyboardFocus(backward: false)
            window?.makeFirstResponder(nextKeyView)
        } else {
            window?.selectKeyView(following: self)
        }
        return true
    }
}

final class HistoryMenuHeaderView: NSView, NSSearchFieldDelegate {
    private enum Metrics {
        static let width: CGFloat = HistoryBrowserLayout.width
        static let height: CGFloat = 64
        static let inset: CGFloat = 10
        static let searchTopInset: CGFloat = 7
        static let searchHeight: CGFloat = 28
        static let filterTopSpacing: CGFloat = 5
        static let filterHeight: CGFloat = 22
        static let buttonSize: CGFloat = 24
        static let pinButtonSize: CGFloat = 24
        static let pageWidth: CGFloat = 28
    }

    private let searchField = HistoryMenuSearchField()
    private let previousButton = HistoryMenuFocusableButton()
    private let nextButton = HistoryMenuFocusableButton()
    private let pinButton = HistoryMenuPinButton()
    private let pageLabel = NSTextField(labelWithString: "")
    private let regexOptionControl = HistoryMenuFocusableSegmentedControl(
        labels: [".*"],
        trackingMode: .selectAny,
        target: nil,
        action: nil
    )
    private let caseSensitiveOptionControl = HistoryMenuFocusableSegmentedControl(
        labels: ["Aa"],
        trackingMode: .selectAny,
        target: nil,
        action: nil
    )
    private let typeSegmentedControl = HistoryMenuFocusableSegmentedControl(
        labels: HistoryMenuTypeFilter.allCases.map(\.title),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )

    var onQueryChange: ((String) -> Void)?
    var onModeChange: ((HistorySearchQuery.Mode) -> Void)?
    var onCaseSensitiveChange: ((Bool) -> Void)?
    var onTypeFilterChange: ((HistoryMenuTypeFilter) -> Void)?
    var onPreviousPage: (() -> Void)?
    var onNextPage: (() -> Void)?
    var onPanelShortcutKeyDown: ((NSEvent) -> Bool)? {
        didSet { searchField.onPanelShortcutKeyDown = onPanelShortcutKeyDown }
    }
    var onPinnedChange: ((Bool) -> Void)? {
        didSet {
            let supportsPinning = onPinnedChange != nil
            pinButton.isHidden = !supportsPinning
            pinButton.isEnabled = supportsPinning
        }
    }

    var firstHeaderFocusableView: NSView { searchField }
    var lastHeaderFocusableView: NSView { headerFocusableViews.last ?? searchField }
    private weak var firstHistoryFocusableView: NSView?
    private var historyFocusableViews = [NSView]()
    private var keyDownMonitor: Any?
    private weak var lastKeyboardFocusOwner: NSView?
    private var trackingArea: NSTrackingArea?
    private var queryChangeTimer: Timer?
    private var isPinned = false
    var markedTextStateProvider: (() -> Bool)?
    var queryDebounceInterval: TimeInterval = 0.12
    var usesMenuTrackingKeyMonitor = true {
        didSet {
            guard oldValue != usesMenuTrackingKeyMonitor else { return }
            if usesMenuTrackingKeyMonitor {
                installKeyDownMonitorIfNeeded()
            } else {
                removeKeyDownMonitor()
            }
        }
    }

    private var searchFilterFocusableViews: [NSView] {
        [searchField, typeSegmentedControl]
    }

    private var pageFocusableViews: [NSView] {
        var views: [NSView] = []
        if nextButton.isEnabled { views.append(nextButton) }
        if previousButton.isEnabled { views.append(previousButton) }
        return views
    }

    private var headerFocusableViews: [NSView] {
        historyFocusableViews.isEmpty ? pageFocusableViews + searchFilterFocusableViews : searchFilterFocusableViews
    }

    private var focusableViewChain: [NSView] {
        historyFocusableViews.isEmpty ? headerFocusableViews : historyFocusableViews + pageFocusableViews + searchFilterFocusableViews
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Metrics.width, height: Metrics.height))
        setup()
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        queryChangeTimer?.invalidate()
        removeKeyDownMonitor()
    }

    func configure(state: HistoryMenuPaginationState, hasNextPage: Bool, isPinned: Bool = false) {
        if searchField.stringValue != state.query {
            searchField.stringValue = state.query
        }
        regexOptionControl.setSelected(state.mode == .regex, forSegment: 0)
        caseSensitiveOptionControl.setSelected(state.caseSensitive, forSegment: 0)
        typeSegmentedControl.selectedSegment = state.typeFilter.rawValue
        previousButton.isEnabled = state.pageIndex > 0
        nextButton.isEnabled = hasNextPage
        pageLabel.stringValue = "\(state.displayPage)"
        updatePinnedState(isPinned)
        configureKeyViewLoop()
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        focusInitialView()
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureKeyViewLoop()
        if window == nil {
            removeKeyDownMonitor()
        } else {
            installKeyDownMonitorIfNeeded()
            focusInitialView()
        }
    }

    override func updateTrackingAreas() { super.updateTrackingAreas(); replaceHistoryMenuTrackingArea(&trackingArea) }

    override func mouseDown(with event: NSEvent) {
        focusSearchField()
        super.mouseDown(with: event)
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        searchField.placeholderString = "Keyword"
        searchField.controlSize = .regular
        searchField.font = .systemFont(ofSize: 13)
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = false
        searchField.sendsWholeSearchString = true
        searchField.target = self
        searchField.action = #selector(searchFieldChanged(_:))
        searchField.toolTip = "Keyword"

        configureButton(previousButton, symbolName: "chevron.left", accessibilityLabel: "Previous Page", action: #selector(previousPage(_:)))
        configureButton(nextButton, symbolName: "chevron.right", accessibilityLabel: "Next Page", action: #selector(nextPage(_:)))
        configureButton(pinButton, symbolName: "pin", accessibilityLabel: "Pin History", action: #selector(pinOptionChanged(_:)))
        pinButton.identifier = NSUserInterfaceItemIdentifier("historyPinButton")
        pinButton.isHidden = true
        pinButton.isEnabled = false
        previousButton.isEnabled = false
        nextButton.isEnabled = false

        regexOptionControl.controlSize = .small
        regexOptionControl.segmentStyle = .rounded
        regexOptionControl.target = self
        regexOptionControl.action = #selector(regexOptionChanged(_:))
        regexOptionControl.setWidth(34, forSegment: 0)
        regexOptionControl.setToolTip("Regex", forSegment: 0)

        caseSensitiveOptionControl.controlSize = .small
        caseSensitiveOptionControl.segmentStyle = .rounded
        caseSensitiveOptionControl.target = self
        caseSensitiveOptionControl.action = #selector(caseSensitiveOptionChanged(_:))
        caseSensitiveOptionControl.setWidth(34, forSegment: 0)
        caseSensitiveOptionControl.setToolTip("Case Sensitive", forSegment: 0)

        typeSegmentedControl.controlSize = .small
        typeSegmentedControl.segmentStyle = .rounded
        typeSegmentedControl.target = self
        typeSegmentedControl.action = #selector(typeFilterChanged(_:))
        typeSegmentedControl.toolTip = "Type"
        for (index, filter) in HistoryMenuTypeFilter.allCases.enumerated() {
            typeSegmentedControl.setLabel(filter.title, forSegment: index)
            typeSegmentedControl.setWidth(segmentWidth(for: filter), forSegment: index)
        }

        pageLabel.alignment = .center
        pageLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        pageLabel.textColor = .secondaryLabelColor

        [
            searchField,
            previousButton,
            pageLabel,
            nextButton,
            pinButton,
            regexOptionControl,
            caseSensitiveOptionControl,
            typeSegmentedControl
        ].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.inset),
            searchField.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.searchTopInset),
            searchField.trailingAnchor.constraint(equalTo: previousButton.leadingAnchor, constant: -10),
            searchField.heightAnchor.constraint(equalToConstant: Metrics.searchHeight),

            previousButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            previousButton.widthAnchor.constraint(equalToConstant: Metrics.buttonSize),
            previousButton.heightAnchor.constraint(equalToConstant: Metrics.buttonSize),

            pageLabel.leadingAnchor.constraint(equalTo: previousButton.trailingAnchor, constant: 4),
            pageLabel.centerYAnchor.constraint(equalTo: previousButton.centerYAnchor),
            pageLabel.widthAnchor.constraint(equalToConstant: Metrics.pageWidth),

            nextButton.leadingAnchor.constraint(equalTo: pageLabel.trailingAnchor, constant: 4),
            nextButton.centerYAnchor.constraint(equalTo: previousButton.centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: Metrics.buttonSize),
            nextButton.heightAnchor.constraint(equalToConstant: Metrics.buttonSize),

            pinButton.leadingAnchor.constraint(equalTo: nextButton.trailingAnchor, constant: 3),
            pinButton.centerYAnchor.constraint(equalTo: nextButton.centerYAnchor),
            pinButton.widthAnchor.constraint(equalToConstant: Metrics.pinButtonSize),
            pinButton.heightAnchor.constraint(equalToConstant: Metrics.pinButtonSize),
            pinButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.inset),

            regexOptionControl.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            regexOptionControl.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: Metrics.filterTopSpacing),
            regexOptionControl.heightAnchor.constraint(equalToConstant: Metrics.filterHeight),

            caseSensitiveOptionControl.leadingAnchor.constraint(equalTo: regexOptionControl.trailingAnchor, constant: 2),
            caseSensitiveOptionControl.centerYAnchor.constraint(equalTo: regexOptionControl.centerYAnchor),
            caseSensitiveOptionControl.heightAnchor.constraint(equalToConstant: Metrics.filterHeight),

            typeSegmentedControl.leadingAnchor.constraint(greaterThanOrEqualTo: caseSensitiveOptionControl.trailingAnchor, constant: 10),
            typeSegmentedControl.trailingAnchor.constraint(equalTo: pinButton.trailingAnchor),
            typeSegmentedControl.centerYAnchor.constraint(equalTo: regexOptionControl.centerYAnchor),
            typeSegmentedControl.heightAnchor.constraint(equalToConstant: Metrics.filterHeight)
        ])

        configureKeyViewLoop()
    }

    func connectKeyboardNavigation(to historyRows: [NSView]) {
        historyFocusableViews.compactMap { $0 as? HistoryMenuRowView }.forEach {
            $0.onLogicalFocusChange = nil
            $0.onKeyboardEvent = nil
        }
        historyFocusableViews = historyRows
        guard let firstHistoryRow = historyRows.first else {
            firstHistoryFocusableView = nil
            lastKeyboardFocusOwner = searchField
            configureKeyViewLoop()
            return
        }

        firstHistoryFocusableView = firstHistoryRow
        lastKeyboardFocusOwner = firstHistoryRow
        historyRows.forEach { view in
            (view as? HistoryMenuRowView)?.onLogicalFocusChange = { [weak self, weak view] in
                guard let view else { return }
                self?.lastKeyboardFocusOwner = view
            }
            (view as? HistoryMenuRowView)?.onKeyboardEvent = { [weak self] event in
                if self?.onPanelShortcutKeyDown?(event) == true { return true }
                return self?.handleHistoryKeyboardEvent(event) == true
            }
        }
        configureKeyViewLoop()
    }

    func focusDefaultHistoryBrowserItem() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            let initialView = self.firstHistoryFocusableView ?? self.searchField
            self.lastKeyboardFocusOwner = initialView
            window.makeFirstResponder(initialView)
        }
    }

    func flushPendingQueryChangeForTesting() {
        queryChangeTimer?.invalidate()
        emitQueryChangeIfReady()
    }

    private func configureButton(_ button: NSButton, symbolName: String, accessibilityLabel: String, action: Selector) {
        button.setButtonType(.momentaryPushIn)
        button.bezelStyle = .inline
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = accessibilityLabel
        button.setAccessibilityLabel(accessibilityLabel)
        button.target = self
        button.action = action
    }

    private func segmentWidth(for filter: HistoryMenuTypeFilter) -> CGFloat {
        switch filter {
        case .all:
            return 40
        case .text:
            return 44
        case .images:
            return 54
        case .files:
            return 44
        case .pdf:
            return 44
        }
    }

    private func configureKeyViewLoop() {
        let views = focusableViewChain
        for (current, next) in zip(views, views.dropFirst()) {
            current.nextKeyView = next
        }
        views.last?.nextKeyView = views.first
        pageLabel.nextKeyView = searchField
    }

    private func installKeyDownMonitorIfNeeded() {
        guard usesMenuTrackingKeyMonitor else { return }
        guard keyDownMonitor == nil else { return }
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.handleMenuTrackingKeyDown(event) else {
                return event
            }
            return nil
        }
    }

    private func removeKeyDownMonitor() {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
    }

    private func currentFocusOwner(in window: NSWindow) -> NSView? {
        if window.firstResponder === searchField.currentEditor() {
            return searchField
        }

        guard let responderView = window.firstResponder as? NSView else {
            return nil
        }
        return focusableViewChain.first { focusableView in
            responderView === focusableView || responderView.isDescendant(of: focusableView)
        }
    }

    private func fallbackFocusOwner() -> NSView? {
        if let lastKeyboardFocusOwner,
           focusableViewChain.contains(where: { $0 === lastKeyboardFocusOwner }) { return lastKeyboardFocusOwner }
        return firstHistoryFocusableView ?? firstHeaderFocusableView
    }

    private func moveFocus(from owner: NSView, backward: Bool) {
        if let segmentedControl = owner as? HistoryMenuFocusableSegmentedControl,
           segmentedControl.moveFocusedSegment(backward: backward) {
            lastKeyboardFocusOwner = segmentedControl
            return
        }

        let views = focusableViewChain
        guard let currentIndex = views.firstIndex(where: { $0 === owner }), !views.isEmpty else {
            return
        }
        let nextIndex = backward
            ? (currentIndex - 1 + views.count) % views.count
            : (currentIndex + 1) % views.count
        let nextView = views[nextIndex]
        (nextView as? HistoryMenuFocusableSegmentedControl)?.prepareForKeyboardFocus(backward: backward)
        lastKeyboardFocusOwner = nextView
        window?.makeFirstResponder(nextView)
    }

    private func focusSearchField() {
        DispatchQueue.main.async { [weak self] in self?.focusSearchFieldImmediately() }
    }

    private func focusSearchFieldImmediately() { lastKeyboardFocusOwner = searchField; window?.makeFirstResponder(searchField) }

    private func focusInitialView() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            guard self.currentFocusOwner(in: window) == nil else { return }
            let initialView = self.firstHistoryFocusableView ?? self.searchField
            self.lastKeyboardFocusOwner = initialView; window.makeFirstResponder(initialView)
        }
    }

    @objc private func searchFieldChanged(_ sender: NSSearchField) {
        if hasActiveMarkedText() {
            return
        }
        scheduleQueryChange()
    }

    @objc private func regexOptionChanged(_ sender: NSSegmentedControl) {
        onModeChange?(sender.isSelected(forSegment: 0) ? .regex : .plain)
    }

    @objc private func caseSensitiveOptionChanged(_ sender: NSSegmentedControl) {
        onCaseSensitiveChange?(sender.isSelected(forSegment: 0))
    }

    @objc private func typeFilterChanged(_ sender: NSSegmentedControl) {
        let selectedFilter = HistoryMenuTypeFilter(rawValue: sender.selectedSegment) ?? .all
        typeSegmentedControl.focusSegment(at: selectedFilter.rawValue)
        onTypeFilterChange?(selectedFilter)
    }

    @objc private func previousPage(_ sender: NSButton) {
        onPreviousPage?()
    }

    @objc private func nextPage(_ sender: NSButton) {
        onNextPage?()
    }

    func controlTextDidChange(_ obj: Notification) {
        if hasActiveMarkedText() {
            return
        }
        scheduleQueryChange()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard !hasActiveMarkedText() else { return }
        queryChangeTimer?.invalidate()
        emitQueryChangeIfReady()
    }

    private func scheduleQueryChange() {
        queryChangeTimer?.invalidate()
        queryChangeTimer = Timer.scheduledTimer(withTimeInterval: queryDebounceInterval, repeats: false) { [weak self] _ in
            self?.emitQueryChangeIfReady()
        }
    }

    private func emitQueryChangeIfReady() {
        guard !hasActiveMarkedText() else { return }
        onQueryChange?(searchField.stringValue)
    }
}

extension HistoryMenuHeaderView {
    func focusSearchFieldFromShortcut() {
        focusSearchFieldImmediately()
    }

    func shouldPreserveSearchFieldEditingCommand(_ event: NSEvent) -> Bool {
        guard searchFieldOwnsFocus() else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command),
              !flags.contains(.control),
              !flags.contains(.option) else { return false }
        return ["a", "c", "v", "x"].contains(searchFieldEditingCommandKey(for: event))
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertTab(_:)):
            moveFocus(from: searchField, backward: false)
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            moveFocus(from: searchField, backward: true)
            return true
        case #selector(NSResponder.moveDown(_:)):
            guard !hasActiveMarkedText(in: textView) else { return false }
            return moveHistorySelection(.next, fromSearchField: true)
        case #selector(NSResponder.moveUp(_:)):
            guard !hasActiveMarkedText(in: textView) else { return false }
            return moveHistorySelection(.previous, fromSearchField: true)
        default:
            return false
        }
    }
}

extension HistoryMenuHeaderView {
    func updatePinnedState(_ pinned: Bool) {
        isPinned = pinned
        let symbolName = pinned ? "pin.fill" : "pin"
        pinButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        pinButton.contentTintColor = pinned ? .controlAccentColor : .secondaryLabelColor
        pinButton.toolTip = pinned ? "Unpin History" : "Pin History"
        pinButton.setAccessibilityLabel(pinButton.toolTip)
    }

    @objc func pinOptionChanged(_ sender: NSButton) {
        onPinnedChange?(!isPinned)
    }

    @discardableResult
    func handleHistoryKeyboardEvent(_ event: NSEvent) -> Bool {
        if let direction = historySelectionDirection(for: event) {
            if searchFieldOwnsFocus(), hasActiveMarkedText() {
                return false
            }
            return moveHistorySelection(direction, fromSearchField: searchFieldOwnsFocus())
        }
        return confirmHistoryRowForNumberShortcut(event)
    }

    @discardableResult
    private func moveHistorySelection(_ direction: HistoryMenuSelectionDirection, fromSearchField: Bool = false) -> Bool {
        guard !historyFocusableViews.isEmpty else { return false }

        let targetIndex: Int
        if fromSearchField {
            targetIndex = direction == .next ? 0 : historyFocusableViews.count - 1
        } else if let owner = window.flatMap({ currentFocusOwner(in: $0) }),
                  let currentIndex = historyFocusableViews.firstIndex(where: { view in
                      owner === view || owner.isDescendant(of: view)
                  }) {
            switch direction {
            case .previous:
                targetIndex = (currentIndex - 1 + historyFocusableViews.count) % historyFocusableViews.count
            case .next:
                targetIndex = (currentIndex + 1) % historyFocusableViews.count
            }
        } else {
            targetIndex = direction == .next ? 0 : historyFocusableViews.count - 1
        }

        let targetView = historyFocusableViews[targetIndex]
        lastKeyboardFocusOwner = targetView
        window?.makeFirstResponder(targetView)
        return true
    }

    private func confirmHistoryRowForNumberShortcut(_ event: NSEvent) -> Bool {
        guard !searchFieldOwnsFocus(),
              AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.addNumericKeyEquivalents) else {
            return false
        }
        let startsAtZero = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsTitleStartWithZero)
        guard let rowIndex = HistoryMenuNumberShortcutMapper.rowIndex(
            for: event,
            startsAtZero: startsAtZero,
            rowCount: historyFocusableViews.count
        ),
            let rowView = historyFocusableViews[rowIndex] as? HistoryMenuRowView else {
            return false
        }

        lastKeyboardFocusOwner = rowView
        window?.makeFirstResponder(rowView)
        rowView.confirmFromKeyboard()
        return true
    }

    private func historySelectionDirection(for event: NSEvent) -> HistoryMenuSelectionDirection? {
        guard event.type == .keyDown else { return nil }
        switch event.keyCode {
        case 125:
            return .next
        case 126:
            return .previous
        default:
            return nil
        }
    }

    @discardableResult
    func handleTabKeyFromCurrentResponder(_ event: NSEvent) -> Bool {
        guard event.keyCode == 48 else {
            return false
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let owner = window.flatMap({ currentFocusOwner(in: $0) }) ?? fallbackFocusOwner() else {
            return false
        }
        moveFocus(from: owner, backward: flags.contains(.shift))
        return true
    }

    @discardableResult
    func handleMenuTrackingKeyDown(_ event: NSEvent) -> Bool {
        if onPanelShortcutKeyDown?(event) == true { return true }
        if handleTabKeyFromCurrentResponder(event) {
            return true
        }
        if handleHistoryKeyboardEvent(event) {
            return true
        }
        guard shouldForwardKeyDownToSearchField(event) else {
            return false
        }

        if let directText = directCommittedText(from: event) {
            insertCommittedTextIntoSearchField(directText)
            return true
        }

        guard let editor = activeSearchFieldEditor() else { return false }
        return handleSearchFieldKeyDownWithEditor(event, editor: editor)
    }

    private func handleSearchFieldKeyDownWithEditor(_ event: NSEvent, editor: NSText) -> Bool {
        if performSearchFieldEditingCommand(for: event, editor: editor) {
            syncSearchFieldText(from: editor)
            return true
        }

        if editor.inputContext?.handleEvent(event) != true {
            editor.interpretKeyEvents([event])
        }
        syncSearchFieldText(from: editor)
        return true
    }

    private func shouldForwardKeyDownToSearchField(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, searchFieldOwnsFocus() else {
            return false
        }
        if historySelectionDirection(for: event) != nil {
            return false
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            return searchFieldEditingCommandKey(for: event) != nil
        }
        return !flags.contains(.control)
    }

    private func searchFieldOwnsFocus() -> Bool {
        if let window,
           currentFocusOwner(in: window) === searchField {
            return true
        }
        return lastKeyboardFocusOwner === searchField
    }

    private func activeSearchFieldEditor() -> NSText? {
        if let editor = searchField.currentEditor() {
            return editor
        }

        let insertionIndex = (searchField.stringValue as NSString).length
        window?.makeFirstResponder(searchField)
        if let editor = searchField.currentEditor() {
            return editor
        }

        searchField.selectText(nil)
        guard let editor = searchField.currentEditor() else {
            return nil
        }
        editor.selectedRange = NSRange(location: insertionIndex, length: 0)
        return editor
    }

    private func searchFieldEditingCommandKey(for event: NSEvent) -> String? {
        event.charactersIgnoringModifiers?.lowercased()
    }

    private func performSearchFieldEditingCommand(for event: NSEvent, editor: NSText) -> Bool {
        switch searchFieldEditingCommandKey(for: event) {
        case "a":
            editor.selectAll(searchField)
        case "c":
            editor.copy(searchField)
        case "v":
            editor.paste(searchField)
        case "x":
            editor.cut(searchField)
        default:
            return false
        }
        return true
    }

    private func directCommittedText(from event: NSEvent) -> String? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.isEmpty,
              let text = event.characters,
              !text.isEmpty,
              text.rangeOfCharacter(from: .controlCharacters) == nil,
              text.unicodeScalars.contains(where: { $0.value > 0x7f }) else {
            return nil
        }
        return text
    }

    private func insertCommittedTextIntoSearchField(_ text: String) {
        let currentValue = searchField.stringValue as NSString
        let replacementRange: NSRange
        if let editor = searchField.currentEditor() {
            replacementRange = boundedRange(editor.selectedRange, in: currentValue.length)
        } else {
            replacementRange = NSRange(location: currentValue.length, length: 0)
        }

        let nextValue = currentValue.replacingCharacters(in: replacementRange, with: text)
        searchField.stringValue = nextValue
        if let editor = searchField.currentEditor() {
            editor.string = nextValue
            editor.selectedRange = NSRange(location: replacementRange.location + (text as NSString).length, length: 0)
        }
        onQueryChange?(searchField.stringValue)
    }

    private func boundedRange(_ range: NSRange, in length: Int) -> NSRange {
        let location = min(max(range.location, 0), length)
        let upperBound = min(max(range.location + range.length, location), length)
        return NSRange(location: location, length: upperBound - location)
    }

    private func syncSearchFieldText(from editor: NSText) {
        searchField.stringValue = editor.string
        if hasActiveMarkedText(in: editor) {
            return
        }
        onQueryChange?(editor.string)
    }

    private func hasActiveMarkedText(in editor: NSText? = nil) -> Bool {
        if markedTextStateProvider?() == true {
            return true
        }
        guard let textView = (editor ?? searchField.currentEditor()) as? NSTextView else {
            return false
        }
        return textView.hasMarkedText()
    }
}

#if DEBUG
extension HistoryMenuHeaderView {
    func dispatchSearchFieldKeyEquivalentForTesting(_ event: NSEvent) -> Bool { searchField.performKeyEquivalent(with: event) }

    var isSearchFieldFocusedForTesting: Bool {
        searchFieldOwnsFocus()
    }
}
#endif
