//
//  HistoryBrowserPanelShortcutTests.swift
//
//  Pastera
//

import AppKit
import Carbon
import Magnet
import Testing
@testable import Pastera

@MainActor
@Suite(.serialized)
struct HistoryBrowserPanelShortcutTests {
    @Test
    func commandFFocusesSearchField() throws {
        let service = HotKeyService()
        AppEnvironment.push(hotKeyService: service)
        defer { _ = AppEnvironment.popLast() }
        service.changeHistoryPanelKeyCombo(.search, keyCombo: HistoryPanelShortcut.search.defaultKeyCombo)

        let stateBox = HistoryMenuPaginationStateBox()
        let controller = makeController(stateBox: stateBox, hasNextPage: true)
        controller.show(at: NSPoint(x: 120, y: 420))
        defer { controller.close() }

        controller.focusFirstHistoryForTesting()

        #expect(controller.handleHistoryPanelKeyDownForTesting(try makeKeyEvent(
            keyCode: 3,
            characters: "f",
            modifierFlags: [.command]
        )))
        #expect(controller.isSearchFieldFocusedForTesting)
        #expect(stateBox.state.query.isEmpty)
    }

    @Test
    func commandArrowsPageWithoutRefreshingAtBounds() throws {
        let service = HotKeyService()
        AppEnvironment.push(hotKeyService: service)
        defer { _ = AppEnvironment.popLast() }
        service.changeHistoryPanelKeyCombo(.previousPage, keyCombo: HistoryPanelShortcut.previousPage.defaultKeyCombo)
        service.changeHistoryPanelKeyCombo(.nextPage, keyCombo: HistoryPanelShortcut.nextPage.defaultKeyCombo)

        let stateBox = HistoryMenuPaginationStateBox()
        let controller = makeController(stateBox: stateBox, hasNextPage: true)
        controller.show(at: NSPoint(x: 120, y: 420))
        defer { controller.close() }

        #expect(controller.handleHistoryPanelKeyDownForTesting(try makeArrowEvent(keyCode: 124)))
        #expect(stateBox.state.pageIndex == 1)

        #expect(controller.handleHistoryPanelKeyDownForTesting(try makeArrowEvent(keyCode: 123)))
        #expect(stateBox.state.pageIndex == 0)

        #expect(controller.handleHistoryPanelKeyDownForTesting(try makeArrowEvent(keyCode: 123)))
        #expect(stateBox.state.pageIndex == 0)
    }

    @Test
    func commandArrowShortcutsTakePriorityOverMainMenuChildNavigation() throws {
        let service = HotKeyService()
        AppEnvironment.push(hotKeyService: service)
        defer { _ = AppEnvironment.popLast() }
        service.changeHistoryPanelKeyCombo(.nextPage, keyCombo: HistoryPanelShortcut.nextPage.defaultKeyCombo)

        let stateBox = HistoryMenuPaginationStateBox()
        let controller = makeController(stateBox: stateBox, hasNextPage: true)
        var forwardedKeyCodes = [UInt16]()
        controller.onMainMenuNavigationKeyDown = { event in
            forwardedKeyCodes.append(event.keyCode)
            return true
        }
        controller.show(at: NSPoint(x: 120, y: 420))
        defer { controller.close() }

        #expect(controller.dispatchHistoryPanelKeyDownForTesting(try makeArrowEvent(keyCode: 124)))
        #expect(stateBox.state.pageIndex == 1)
        #expect(forwardedKeyCodes.isEmpty)
    }

    @Test
    func commandArrowShortcutsIgnoreSystemArrowModifierFlags() throws {
        let service = HotKeyService()
        AppEnvironment.push(hotKeyService: service)
        defer { _ = AppEnvironment.popLast() }
        service.changeHistoryPanelKeyCombo(.nextPage, keyCombo: HistoryPanelShortcut.nextPage.defaultKeyCombo)

        let stateBox = HistoryMenuPaginationStateBox()
        let controller = makeController(stateBox: stateBox, hasNextPage: true)
        controller.show(at: NSPoint(x: 120, y: 420))
        defer { controller.close() }

        #expect(controller.dispatchHistoryPanelKeyDownForTesting(try makeArrowEvent(
            keyCode: 124,
            modifierFlags: [.command, .numericPad, .function]
        )))
        #expect(stateBox.state.pageIndex == 1)
    }

    @Test
    func menuTrackingCommandArrowTriggersHistoryPanelShortcut() throws {
        let service = HotKeyService()
        AppEnvironment.push(hotKeyService: service)
        defer { _ = AppEnvironment.popLast() }
        service.changeHistoryPanelKeyCombo(.nextPage, keyCombo: HistoryPanelShortcut.nextPage.defaultKeyCombo)

        let stateBox = HistoryMenuPaginationStateBox()
        let controller = makeController(stateBox: stateBox, hasNextPage: true)
        controller.show(at: NSPoint(x: 120, y: 420))
        defer { controller.close() }

        controller.focusSearchFieldForTesting()

        #expect(controller.dispatchHistoryHeaderMenuTrackingKeyDownForTesting(try makeArrowEvent(keyCode: 124)))
        #expect(stateBox.state.pageIndex == 1)
    }

    @Test
    func searchFieldCommandArrowTriggersHistoryPanelShortcut() throws {
        let service = HotKeyService()
        AppEnvironment.push(hotKeyService: service)
        defer { _ = AppEnvironment.popLast() }
        service.changeHistoryPanelKeyCombo(.nextPage, keyCombo: HistoryPanelShortcut.nextPage.defaultKeyCombo)

        let stateBox = HistoryMenuPaginationStateBox()
        let controller = makeController(stateBox: stateBox, hasNextPage: true)
        controller.show(at: NSPoint(x: 120, y: 420))
        defer { controller.close() }

        controller.focusSearchFieldForTesting()

        #expect(controller.dispatchSearchFieldKeyEquivalentForTesting(try makeArrowEvent(keyCode: 124)))
        #expect(stateBox.state.pageIndex == 1)
    }

    @Test
    func focusedHistoryRowCommandArrowTriggersHistoryPanelShortcut() throws {
        let service = HotKeyService()
        AppEnvironment.push(hotKeyService: service)
        defer { _ = AppEnvironment.popLast() }
        service.changeHistoryPanelKeyCombo(.nextPage, keyCombo: HistoryPanelShortcut.nextPage.defaultKeyCombo)

        let stateBox = HistoryMenuPaginationStateBox()
        let controller = makeController(stateBox: stateBox, hasNextPage: true)
        controller.show(at: NSPoint(x: 120, y: 420))
        defer { controller.close() }
        controller.focusFirstHistoryForTesting()

        #expect(controller.dispatchFirstHistoryRowKeyDownForTesting(try makeArrowEvent(keyCode: 124)))
        #expect(stateBox.state.pageIndex == 1)
    }

    @Test
    func customShortcutReplacesDefaultCommandF() throws {
        let service = HotKeyService()
        AppEnvironment.push(hotKeyService: service)
        defer { _ = AppEnvironment.popLast() }
        let customSearchKeyCombo = try #require(KeyCombo(QWERTYKeyCode: 17, carbonModifiers: cmdKey | optionKey))
        service.changeHistoryPanelKeyCombo(.search, keyCombo: customSearchKeyCombo)

        let stateBox = HistoryMenuPaginationStateBox()
        let controller = makeController(stateBox: stateBox, hasNextPage: false)
        controller.show(at: NSPoint(x: 120, y: 420))
        defer { controller.close() }

        controller.focusFirstHistoryForTesting()

        #expect(!controller.handleHistoryPanelKeyDownForTesting(try makeKeyEvent(
            keyCode: 3,
            characters: "f",
            modifierFlags: [.command]
        )))
        #expect(!controller.isSearchFieldFocusedForTesting)

        #expect(controller.handleHistoryPanelKeyDownForTesting(try makeKeyEvent(
            keyCode: 17,
            characters: "t",
            modifierFlags: [.command, .option]
        )))
        #expect(controller.isSearchFieldFocusedForTesting)
    }

    @Test
    func searchFieldCommandEditingCommandsAreNotIntercepted() throws {
        let service = HotKeyService()
        AppEnvironment.push(hotKeyService: service)
        defer { _ = AppEnvironment.popLast() }
        let commandA = try #require(KeyCombo(QWERTYKeyCode: 0, carbonModifiers: cmdKey))
        service.changeHistoryPanelKeyCombo(.nextPage, keyCombo: commandA)

        let stateBox = HistoryMenuPaginationStateBox()
        let controller = makeController(stateBox: stateBox, hasNextPage: true)
        controller.show(at: NSPoint(x: 120, y: 420))
        defer { controller.close() }
        controller.focusSearchFieldForTesting()

        #expect(!controller.handleHistoryPanelKeyDownForTesting(try makeKeyEvent(
            keyCode: 0,
            characters: "a",
            modifierFlags: [.command]
        )))
        #expect(stateBox.state.pageIndex == 0)
    }

    private func makeController(
        stateBox: HistoryMenuPaginationStateBox,
        hasNextPage: Bool
    ) -> HistoryBrowserPanelController {
        let histories = (1...10).map { index in
            PasteboardHistory(
                id: PasteboardHistory.ID("history-\(index)"),
                title: "History \(index)",
                pasteboardTypes: [.string],
                updateAt: index,
                deviceID: CPYUtilities.deviceID
            )
        }
        return HistoryBrowserPanelController(
            currentState: { stateBox.state },
            updateState: { update in update(&stateBox.state) },
            fetchPage: {
                HistoryMenuPage(
                    details: histories.map { PasteboardHistoryDetail(history: $0, thumbnailAsset: nil) },
                    hasNextPage: hasNextPage
                )
            },
            makeRowView: { detail, _, onConfirm in
                HistoryMenuRowView(title: detail.history.title, image: nil, shortcutText: nil, onConfirm: onConfirm)
            },
            selectHistory: { _, _ in }
        )
    }

    private func makeArrowEvent(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags = [.command]
    ) throws -> NSEvent {
        let character: String
        switch keyCode {
        case 123:
            character = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        case 124:
            character = String(UnicodeScalar(NSRightArrowFunctionKey)!)
        default:
            character = ""
        }
        return try makeKeyEvent(
            keyCode: keyCode,
            characters: character,
            modifierFlags: modifierFlags
        )
    }

    private func makeKeyEvent(
        keyCode: UInt16,
        characters: String,
        modifierFlags: NSEvent.ModifierFlags
    ) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ))
    }
}

private final class HistoryMenuPaginationStateBox {
    var state = HistoryMenuPaginationState()
}
