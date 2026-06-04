//
//  HistoryMenuKeyEquivalentTests.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Codex on 2026/06/03.
//
//  Copyright © 2015-2026 Clipy Project.
//

import AppKit
import Combine
import Dependencies
import Testing
@testable import Pastera

@MainActor
@Suite(.serialized)
struct HistoryMenuKeyEquivalentTests {
    @Test
    func pinnedMainMenuPanelBehaviorKeepsPanelVisibleAndMovable() {
        let behavior = MainMenuPanelBehavior()

        #expect(!behavior.hidesOnDeactivate)
        #expect(behavior.level == .floating)
        #expect(behavior.isMovableByWindowBackground)
        #expect(!behavior.collectionBehavior.contains(.transient))
    }

    @Test
    func mainMenuHistoryRowShowsPinControl() throws {
        let menuItemView = MainMenuHeaderItemView(title: "History", image: nil, isPinned: false)

        let pinButton = try #require(menuItemView.subviews.compactMap { $0 as? NSButton }
            .first { $0.identifier?.rawValue == "mainMenuPinButton" })

        #expect(!pinButton.isHidden)
        #expect(pinButton.isEnabled)
        #expect(pinButton.image != nil)
    }

    @Test
    func mainMenuPinButtonTogglesMainMenuPinnedState() throws {
        let menuItemView = MainMenuHeaderItemView(title: "History", image: nil, isPinned: false)
        var pinnedValues = [Bool]()
        menuItemView.onPinnedChange = { pinned, _ in pinnedValues.append(pinned) }

        let pinButton = try #require(menuItemView.subviews.compactMap { $0 as? NSButton }
            .first { $0.identifier?.rawValue == "mainMenuPinButton" })
        pinButton.performClick(nil)

        #expect(pinnedValues == [true])
    }

    @Test
    func mainMenuPinButtonDoesNotOpenHistory() throws {
        let menuItemView = MainMenuHeaderItemView(title: "History", image: nil, isPinned: false)
        var didOpenHistory = false
        menuItemView.onOpen = { didOpenHistory = true }

        let pinButton = try #require(menuItemView.subviews.compactMap { $0 as? NSButton }
            .first { $0.identifier?.rawValue == "mainMenuPinButton" })
        pinButton.performClick(nil)

        #expect(!didOpenHistory)
    }

    @Test
    func mainMenuPinButtonSendsCurrentMenuFrame() throws {
        let window = TestKeyWindow(
            contentRect: NSRect(x: 240, y: 360, width: 168, height: 220),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let menuItemView = MainMenuHeaderItemView(title: "History", image: nil, isPinned: false)
        window.contentView = menuItemView
        defer { window.close() }

        var capturedFrame: NSRect?
        menuItemView.onPinnedChange = { _, frame in capturedFrame = frame }
        let pinButton = try #require(menuItemView.subviews.compactMap { $0 as? NSButton }
            .first { $0.identifier?.rawValue == "mainMenuPinButton" })

        pinButton.performClick(nil)

        #expect(capturedFrame == window.frame)
    }

    @Test
    func pinnedMainMenuPanelUsesNarrowMenuWidth() {
        #expect(MainMenuPanelLayout.width <= 168)
        #expect(MainMenuHeaderItemView.Metrics.width == MainMenuPanelLayout.width)
    }

    @Test
    func historyBrowserPanelIsNarrowedByOneQuarter() {
        #expect(HistoryBrowserLayout.width == 315)
    }

    @Test
    func pinnedMainMenuPanelUsesCompactMenuMetrics() {
        #expect(MainMenuPanelLayout.rowHeight <= 30)
        #expect(MainMenuPanelLayout.separatorVerticalInset <= 4)
        #expect(MainMenuPanelLayout.topInset <= 4)
        #expect(MainMenuPanelLayout.bottomInset <= 4)
    }

    @Test
    func pinnedMainMenuPanelUsesMenuLikeSeparatorMetrics() {
        #expect(MainMenuPanelLayout.separatorHorizontalInset == MainMenuHeaderItemView.Metrics.horizontalInset)
        #expect(MainMenuPanelLayout.separatorAlpha <= 0.25)
    }

    @Test
    func pinnedMainMenuPanelCanAnchorToOriginalMenuFrame() throws {
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            itemsProvider: { [] },
            onOpenHistory: {},
            onPinnedChange: { _ in }
        )
        let menuFrame = NSRect(x: 240, y: 360, width: 168, height: 220)

        controller.show(anchoredTo: menuFrame)
        defer { controller.close() }

        let panelFrame = try #require(controller.visibleFrame)
        #expect(panelFrame.minX == menuFrame.minX)
        #expect(panelFrame.maxY == menuFrame.maxY)
    }

    @Test
    func pinnedMainMenuPanelKeepsOriginalMenuTopLeftPosition() throws {
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            itemsProvider: {
                [
                    .action(title: "Clear History", image: nil) {},
                    .action(title: "Edit Snippets", image: nil) {},
                    .action(title: "Preferences", image: nil) {},
                    .separator,
                    .action(title: "Quit Pastera", image: nil) {}
                ]
            },
            onOpenHistory: {},
            onPinnedChange: { _ in }
        )
        let menuFrame = NSRect(x: 96, y: 420, width: 168, height: 332)

        controller.show(anchoredTo: menuFrame)
        defer { controller.close() }

        let panelFrame = try #require(controller.visibleFrame)
        #expect(panelFrame.minX == menuFrame.minX)
        #expect(panelFrame.maxY == menuFrame.maxY)
    }

    @Test
    func openingHistoryFromPinnedMenuKeepsPinnedMenuVisible() {
        var didOpenHistory = false
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            itemsProvider: { [] },
            onOpenHistory: { didOpenHistory = true },
            onPinnedChange: { _ in }
        )
        controller.show(at: NSPoint(x: 100, y: 100))
        #expect(controller.isVisibleForTesting)

        controller.openHistoryFromPinnedMenu()

        #expect(controller.isVisibleForTesting)
        #expect(didOpenHistory)
    }

    @Test
    func showingHistoryBrowserPanelFromPinnedMenuKeepsMainMenuVisibleAndAttachesToSide() throws {
        let manager = MenuManager()

        let result = withDependencies {
            $0.pasteboardHistoryRepository = EmptyPasteboardHistoryRepository()
        } operation: {
            manager.showMainMenuPanelForTesting(at: NSPoint(x: 100, y: 500))
            #expect(manager.isMainMenuPanelVisibleForTesting)
            let mainMenuFrame = manager.mainMenuPanelFrameForTesting

            manager.showHistoryBrowserPanelForTesting(at: NSPoint(x: 120, y: 480))

            let isMainMenuVisible = manager.isMainMenuPanelVisibleForTesting
            let historyFrame = manager.historyBrowserPanelFrameForTesting
            manager.closeHistoryBrowserPanelForTesting()
            return (isMainMenuVisible, mainMenuFrame, historyFrame)
        }

        #expect(result.0)
        let mainMenuFrame = try #require(result.1)
        let historyFrame = try #require(result.2)
        #expect(historyFrame.minX >= mainMenuFrame.maxX)
        #expect(!historyFrame.intersects(mainMenuFrame))
    }

    @Test
    func historyBrowserHeaderDoesNotExposePinButton() {
        let headerView = HistoryMenuHeaderView()
        headerView.configure(state: HistoryMenuPaginationState(pageIndex: 0), hasNextPage: true)

        let pinButtons = headerView.subviews.compactMap { $0 as? NSButton }
            .filter { $0.identifier?.rawValue == "historyPinButton" }

        #expect(pinButtons.allSatisfy { $0.isHidden || !$0.isEnabled })
    }

    @Test
    func tabKeyEquivalentAdvancesFromLastRowToPaginationControl() throws {
        let window = makeWindow()
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        let lastRow = HistoryMenuRowView(title: "0. Last", image: nil) {}
        attach([headerView, firstRow, lastRow], to: window)
        headerView.configure(state: HistoryMenuPaginationState(pageIndex: 0), hasNextPage: true)
        headerView.connectKeyboardNavigation(to: [firstRow, lastRow])
        defer { window.close() }

        let nextButton = try #require(headerView.subviews.compactMap { $0 as? NSButton }.dropFirst().first)
        window.makeFirstResponder(lastRow)

        #expect(lastRow.performKeyEquivalent(with: try makeTabEvent()))
        #expect(firstResponder(in: window, belongsTo: nextButton))
    }

    @Test
    func tabKeyEquivalentAdvancesFromPaginationControlToSearchField() throws {
        let window = makeWindow()
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        attach([headerView, firstRow], to: window)
        headerView.configure(state: HistoryMenuPaginationState(pageIndex: 0), hasNextPage: true)
        headerView.connectKeyboardNavigation(to: [firstRow])
        defer { window.close() }

        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        let nextButton = try #require(headerView.subviews.compactMap { $0 as? NSButton }.dropFirst().first)
        window.makeFirstResponder(nextButton)

        #expect(nextButton.performKeyEquivalent(with: try makeTabEvent()))
        #expect(firstResponder(in: window, belongsTo: searchField))
    }

    @Test
    func tabKeyEquivalentAdvancesFromSearchFieldToTypeFilter() throws {
        let window = makeWindow()
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        attach([headerView, firstRow], to: window)
        headerView.configure(state: HistoryMenuPaginationState(pageIndex: 0), hasNextPage: true)
        headerView.connectKeyboardNavigation(to: [firstRow])
        defer { window.close() }

        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        let typeControl = try #require(
            headerView.subviews.compactMap { $0 as? NSSegmentedControl }
                .first { $0.segmentCount == HistoryMenuTypeFilter.allCases.count }
        )
        window.makeFirstResponder(searchField)

        #expect(searchField.performKeyEquivalent(with: try makeTabEvent()))
        #expect(firstResponder(in: window, belongsTo: typeControl))
    }

    @Test
    func menuTrackingKeyDownInsertsUnicodeTextIntoSearchField() throws {
        let window = makeWindow()
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        attach([headerView, firstRow], to: window)
        headerView.configure(state: HistoryMenuPaginationState(pageIndex: 0), hasNextPage: true)
        headerView.connectKeyboardNavigation(to: [firstRow])
        defer { window.close() }

        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        window.makeFirstResponder(searchField)

        #expect(headerView.handleMenuTrackingKeyDown(try makeTextEvent("中")))
        #expect(searchField.stringValue == "中")
    }

    @Test
    func menuTrackingCommandVPastesIntoSearchField() throws {
        let window = makeWindow()
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        attach([headerView, firstRow], to: window)
        headerView.configure(state: HistoryMenuPaginationState(pageIndex: 0), hasNextPage: true)
        headerView.connectKeyboardNavigation(to: [firstRow])
        defer { window.close() }

        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("中文粘贴", forType: .string)
        window.makeFirstResponder(searchField)

        #expect(headerView.handleMenuTrackingKeyDown(try makeCommandEvent("v", keyCode: 9)))
        #expect(searchField.stringValue == "中文粘贴")
    }

    @Test
    func menuTrackingTextDoesNotStealFocusFromHistoryRow() throws {
        let window = makeWindow()
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        attach([headerView, firstRow], to: window)
        headerView.configure(state: HistoryMenuPaginationState(pageIndex: 0), hasNextPage: true)
        headerView.connectKeyboardNavigation(to: [firstRow])
        defer { window.close() }

        window.makeFirstResponder(firstRow)

        #expect(!headerView.handleMenuTrackingKeyDown(try makeTextEvent("a")))
        #expect(firstResponder(in: window, belongsTo: firstRow))
    }

    @Test
    func markedTextDoesNotTriggerQueryChangeDuringIMEComposition() throws {
        let window = makeWindow()
        let headerView = HistoryMenuHeaderView()
        attach([headerView], to: window)
        headerView.configure(state: HistoryMenuPaginationState(pageIndex: 0), hasNextPage: true)
        defer { window.close() }

        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        var queries = [String]()
        headerView.onQueryChange = { queries.append($0) }
        searchField.stringValue = "zhong"
        headerView.markedTextStateProvider = { true }

        headerView.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))

        #expect(queries.isEmpty)
    }

    @Test
    func queryRefreshWaitsUntilIMECompositionFinishes() throws {
        let headerView = HistoryMenuHeaderView()
        headerView.configure(state: HistoryMenuPaginationState(pageIndex: 0), hasNextPage: true)
        headerView.queryDebounceInterval = 0.01

        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        var queries = [String]()
        var hasMarkedText = false
        headerView.markedTextStateProvider = { hasMarkedText }
        headerView.onQueryChange = { queries.append($0) }

        searchField.stringValue = "n"
        headerView.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))
        hasMarkedText = true
        headerView.flushPendingQueryChangeForTesting()

        #expect(queries.isEmpty)

        hasMarkedText = false
        searchField.stringValue = "你"
        headerView.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))
        headerView.flushPendingQueryChangeForTesting()

        #expect(queries == ["你"])
    }

    @Test
    func searchFieldActionDoesNotTriggerQueryChangeDuringIMEComposition() throws {
        let window = makeWindow()
        let headerView = HistoryMenuHeaderView()
        attach([headerView], to: window)
        headerView.configure(state: HistoryMenuPaginationState(pageIndex: 0), hasNextPage: true)
        defer { window.close() }

        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        var queries = [String]()
        headerView.onQueryChange = { queries.append($0) }
        searchField.stringValue = "zhong"
        headerView.markedTextStateProvider = { true }

        #expect(searchField.sendAction(try #require(searchField.action), to: searchField.target))

        #expect(queries.isEmpty)
    }

    @Test
    func movingPointerOverHeaderDoesNotStealFocusFromHistoryRow() throws {
        let window = makeWindow()
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        attach([headerView, firstRow], to: window)
        headerView.configure(state: HistoryMenuPaginationState(pageIndex: 0), hasNextPage: true)
        headerView.connectKeyboardNavigation(to: [firstRow])
        defer { window.close() }

        window.makeFirstResponder(firstRow)

        headerView.mouseMoved(with: try makeMouseMovedEvent())

        #expect(firstResponder(in: window, belongsTo: firstRow))
    }

    private func makeWindow() -> NSWindow {
        let window = TestKeyWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 170),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        return window
    }

    private func attach(_ views: [NSView], to window: NSWindow) {
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 170))
        views.forEach(containerView.addSubview)
        window.contentView = containerView
    }

    private func makeTabEvent(shift: Bool = false) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: shift ? [.shift] : [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            isARepeat: false,
            keyCode: 48
        ))
    }

    private func makeTextEvent(_ text: String, keyCode: UInt16 = 0) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: text,
            charactersIgnoringModifiers: text,
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    private func makeCommandEvent(_ text: String, keyCode: UInt16) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: text,
            charactersIgnoringModifiers: text,
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    private func makeMouseMovedEvent() throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: .mouseMoved,
            location: NSPoint(x: 12, y: 12),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        ))
    }

    private func firstResponder(in window: NSWindow, belongsTo view: NSView) -> Bool {
        if window.firstResponder === view {
            return true
        }
        guard let responderView = window.firstResponder as? NSView else {
            return false
        }
        return responderView.isDescendant(of: view)
    }

}

extension HistoryMenuKeyEquivalentTests {
    @Test
    func downArrowMovesFocusToNextHistoryRow() throws {
        let window = makeWindow()
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        let secondRow = HistoryMenuRowView(title: "2. Second", image: nil) {}
        attach([headerView, firstRow, secondRow], to: window)
        headerView.configure(state: HistoryMenuPaginationState(pageIndex: 0), hasNextPage: true)
        headerView.connectKeyboardNavigation(to: [firstRow, secondRow])
        defer { window.close() }

        window.makeFirstResponder(firstRow)

        #expect(headerView.handleMenuTrackingKeyDown(try makeArrowEvent(keyCode: 125)))
        #expect(firstResponder(in: window, belongsTo: secondRow))
    }

    @Test
    func upArrowMovesFocusToPreviousHistoryRow() throws {
        let window = makeWindow()
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        let secondRow = HistoryMenuRowView(title: "2. Second", image: nil) {}
        attach([headerView, firstRow, secondRow], to: window)
        headerView.configure(state: HistoryMenuPaginationState(pageIndex: 0), hasNextPage: true)
        headerView.connectKeyboardNavigation(to: [firstRow, secondRow])
        defer { window.close() }

        window.makeFirstResponder(secondRow)

        #expect(headerView.handleMenuTrackingKeyDown(try makeArrowEvent(keyCode: 126)))
        #expect(firstResponder(in: window, belongsTo: firstRow))
    }

    @Test
    func arrowKeysWrapBetweenFirstAndLastHistoryRows() throws {
        let window = makeWindow()
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        let lastRow = HistoryMenuRowView(title: "0. Last", image: nil) {}
        attach([headerView, firstRow, lastRow], to: window)
        headerView.configure(state: HistoryMenuPaginationState(pageIndex: 0), hasNextPage: true)
        headerView.connectKeyboardNavigation(to: [firstRow, lastRow])
        defer { window.close() }

        window.makeFirstResponder(firstRow)

        #expect(headerView.handleMenuTrackingKeyDown(try makeArrowEvent(keyCode: 126)))
        #expect(firstResponder(in: window, belongsTo: lastRow))

        #expect(headerView.handleMenuTrackingKeyDown(try makeArrowEvent(keyCode: 125)))
        #expect(firstResponder(in: window, belongsTo: firstRow))
    }

    @Test
    func downArrowFromSearchFieldFocusesFirstHistoryRowWithoutChangingQuery() throws {
        let window = makeWindow()
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        attach([headerView, firstRow], to: window)
        headerView.configure(state: HistoryMenuPaginationState(query: "abc", pageIndex: 0), hasNextPage: true)
        headerView.connectKeyboardNavigation(to: [firstRow])
        defer { window.close() }

        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        window.makeFirstResponder(searchField)

        #expect(headerView.handleMenuTrackingKeyDown(try makeArrowEvent(keyCode: 125)))
        #expect(firstResponder(in: window, belongsTo: firstRow))
        #expect(searchField.stringValue == "abc")
    }

    @Test
    func arrowKeysDoNotStealSearchFieldFocusDuringIMEComposition() throws {
        let window = makeWindow()
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        attach([headerView, firstRow], to: window)
        headerView.configure(state: HistoryMenuPaginationState(query: "zhong", pageIndex: 0), hasNextPage: true)
        headerView.connectKeyboardNavigation(to: [firstRow])
        headerView.markedTextStateProvider = { true }
        defer { window.close() }

        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        window.makeFirstResponder(searchField)

        #expect(!headerView.handleMenuTrackingKeyDown(try makeArrowEvent(keyCode: 125)))
        #expect(firstResponder(in: window, belongsTo: searchField))
    }

    @Test
    func numberKeyConfirmsMatchingHistoryRowWhenShortcutsAreEnabled() throws {
        try withNumericShortcutDefaults(enabled: true, startsAtZero: false) {
            let window = makeWindow()
            let headerView = HistoryMenuHeaderView()
            var confirmedRows = [Int]()
            let rows = (0..<10).map { index in
                HistoryMenuRowView(title: "\(index + 1). Row", image: nil) { confirmedRows.append(index) }
            }
            attach([headerView] + rows, to: window)
            headerView.configure(state: HistoryMenuPaginationState(pageIndex: 0), hasNextPage: true)
            headerView.connectKeyboardNavigation(to: rows)
            defer { window.close() }

            window.makeFirstResponder(rows[4])
            let firstEvent = try makeTextEvent("1", keyCode: 18)
            let tenthEvent = try makeTextEvent("0", keyCode: 29)

            #expect(headerView.handleMenuTrackingKeyDown(firstEvent))
            #expect(headerView.handleMenuTrackingKeyDown(tenthEvent))
            #expect(confirmedRows == [0, 9])
        }
    }

    @Test
    func zeroKeyConfirmsFirstHistoryRowWhenTitlesStartAtZero() throws {
        try withNumericShortcutDefaults(enabled: true, startsAtZero: true) {
            let window = makeWindow()
            let headerView = HistoryMenuHeaderView()
            var confirmedRows = [Int]()
            let rows = (0..<10).map { index in
                HistoryMenuRowView(title: "\(index). Row", image: nil) { confirmedRows.append(index) }
            }
            attach([headerView] + rows, to: window)
            headerView.configure(state: HistoryMenuPaginationState(pageIndex: 0), hasNextPage: true)
            headerView.connectKeyboardNavigation(to: rows)
            defer { window.close() }

            window.makeFirstResponder(rows[3])
            let zeroEvent = try makeTextEvent("0", keyCode: 29)

            #expect(headerView.handleMenuTrackingKeyDown(zeroEvent))
            #expect(confirmedRows == [0])
        }
    }

    @Test
    func numberKeyDoesNotConfirmHistoryRowWhenShortcutsAreDisabled() throws {
        try withNumericShortcutDefaults(enabled: false, startsAtZero: false) {
            let window = makeWindow()
            let headerView = HistoryMenuHeaderView()
            var didConfirm = false
            let firstRow = HistoryMenuRowView(title: "1. First", image: nil) { didConfirm = true }
            attach([headerView, firstRow], to: window)
            headerView.configure(state: HistoryMenuPaginationState(pageIndex: 0), hasNextPage: true)
            headerView.connectKeyboardNavigation(to: [firstRow])
            defer { window.close() }

            window.makeFirstResponder(firstRow)
            let firstEvent = try makeTextEvent("1", keyCode: 18)

            #expect(!headerView.handleMenuTrackingKeyDown(firstEvent))
            #expect(!didConfirm)
        }
    }

    @Test
    func numberKeyInSearchFieldUpdatesKeywordInsteadOfConfirmingHistoryRow() throws {
        try withNumericShortcutDefaults(enabled: true, startsAtZero: false) {
            let window = makeWindow()
            let headerView = HistoryMenuHeaderView()
            var didConfirm = false
            let firstRow = HistoryMenuRowView(title: "1. First", image: nil) { didConfirm = true }
            attach([headerView, firstRow], to: window)
            headerView.configure(state: HistoryMenuPaginationState(pageIndex: 0), hasNextPage: true)
            headerView.connectKeyboardNavigation(to: [firstRow])
            defer { window.close() }

            let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
            window.makeFirstResponder(searchField)
            let firstEvent = try makeTextEvent("1", keyCode: 18)

            #expect(headerView.handleMenuTrackingKeyDown(firstEvent))
            #expect(searchField.stringValue == "1")
            #expect(!didConfirm)
        }
    }

    private func makeArrowEvent(keyCode: UInt16) throws -> NSEvent {
        let character: String
        switch keyCode {
        case 125:
            character = String(UnicodeScalar(NSDownArrowFunctionKey)!)
        case 126:
            character = String(UnicodeScalar(NSUpArrowFunctionKey)!)
        default:
            character = ""
        }
        return try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    private func withNumericShortcutDefaults(
        enabled: Bool,
        startsAtZero: Bool,
        operation: () throws -> Void
    ) rethrows {
        let defaults = AppEnvironment.current.defaults
        let shortcutKey = Constants.UserDefaults.addNumericKeyEquivalents
        let startKey = Constants.UserDefaults.menuItemsTitleStartWithZero
        let previousShortcutValue = defaults.object(forKey: shortcutKey)
        let previousStartValue = defaults.object(forKey: startKey)
        defaults.set(enabled, forKey: shortcutKey)
        defaults.set(startsAtZero, forKey: startKey)
        defer {
            restoreDefault(previousShortcutValue, forKey: shortcutKey)
            restoreDefault(previousStartValue, forKey: startKey)
        }
        try operation()
    }

    private func restoreDefault(_ value: Any?, forKey key: String) {
        let defaults = AppEnvironment.current.defaults
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

extension HistoryMenuKeyEquivalentTests {
    @Test
    func unpinnedMainMenuPopupUsesUnifiedPanelController() {
        let manager = MenuManager()

        manager.popUpMenu(.main)

        #expect(manager.isMainMenuPanelVisibleForTesting)
    }

    @Test
    func mainMenuPanelKeepsSameSizeWhenPinnedFromTransientState() throws {
        let items: [MainMenuPanelItem] = [
            .action(title: "Clear History", image: nil) {},
            .action(title: "Edit Snippets", image: nil) {},
            .action(title: "Preferences", image: nil) {},
            .separator,
            .action(title: "Quit Pastera", image: nil) {}
        ]
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            itemsProvider: { items },
            onOpenHistory: {},
            onPinnedChange: { _ in }
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: false)
        let transientFrame = try #require(controller.visibleFrame)

        controller.show(anchoredTo: transientFrame, pinned: true)
        defer { controller.close() }

        let pinnedFrame = try #require(controller.visibleFrame)
        #expect(pinnedFrame.size == transientFrame.size)
        #expect(pinnedFrame.minX == transientFrame.minX)
        #expect(pinnedFrame.maxY == transientFrame.maxY)
    }
}

private final class TestKeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }

    override func close() {
        makeFirstResponder(nil)
        let retainedContentView = contentView
        contentView = nil
        orderOut(nil)
        TestWindowRetainer.retain(window: self, contentView: retainedContentView)
    }
}

private enum TestWindowRetainer {
    private static var windows = [NSWindow]()
    private static var contentViews = [NSView]()

    static func retain(window: NSWindow, contentView: NSView?) {
        windows.append(window)
        if let contentView {
            contentViews.append(contentView)
        }
    }
}

private struct EmptyPasteboardHistoryRepository: PasteboardHistoryRepositoryProtocol {
    func observeHistories() -> AnyPublisher<[PasteboardHistory], Never> {
        Just([]).eraseToAnyPublisher()
    }

    func hasHistories() -> Bool {
        false
    }

    func fetchHistoryDetails(
        ascending: Bool,
        includesThumbnailAsset: Bool,
        limit: Int,
        offset: Int
    ) -> [PasteboardHistoryDetail] {
        []
    }

    func searchHistoryDetails(
        query: HistorySearchQuery,
        includesThumbnailAsset: Bool,
        limit: Int,
        offset: Int
    ) throws -> [PasteboardHistoryDetail] {
        []
    }

    func fetchHistory(id: PasteboardHistory.ID) -> PasteboardHistory? {
        nil
    }

    func fetchContent(id: PasteboardHistory.ID) -> PasteboardContent? {
        nil
    }

    func save(id: PasteboardHistory.ID, content: PasteboardContent, updateAt: Int) {}
    func deleteHistory(id: PasteboardHistory.ID) {}
    func deleteAll() {}
    func deleteOverflowingHistories(maxHistorySize: Int) {}
    func pruneHistories(settings: HistoryRetentionSettings) {}
}
