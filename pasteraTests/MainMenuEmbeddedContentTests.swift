//
//  MainMenuEmbeddedContentTests.swift
//
//  Pastera
//

import AppKit
import Carbon
import Magnet
import Testing
@testable import Pastera

// swiftlint:disable type_body_length file_length

@MainActor
@Suite(.serialized)
struct MainMenuEmbeddedContentTests {
    @Test
    func mainMenuPanelRendersHistoryContentByDefault() {
        let detail = PasteboardHistoryDetail(
            history: PasteboardHistory(
                id: PasteboardHistory.ID(rawValue: "history-1"),
                title: "First copied value",
                pasteboardTypes: [.string],
                updateAt: 1,
                deviceID: nil
            ),
            thumbnailAsset: nil
        )
        var fetchCount = 0
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: { [] },
            onOpenHistory: {},
            onOpenSnippets: {},
            historyDataSource: makeHistoryDataSource(detail: detail, fetchPage: {
                    fetchCount += 1
                    return HistoryMenuPage.result([detail], pageSize: 10)
            })
        )

        controller.show(at: NSPoint(x: 100, y: 100))
        defer { controller.close() }

        #expect(fetchCount == 1)
        #expect(controller.mainMenuVisibleRowTitlesForTesting == ["First copied value"])
        #expect(controller.mainMenuSelectedModeForTesting == "history")
    }

    @Test
    func embeddedHistoryPagingUsesBareArrowsOnlyAndYieldsToSearchEditing() throws {
        let detail = PasteboardHistoryDetail(
            history: PasteboardHistory(
                id: PasteboardHistory.ID(rawValue: "history-paging"),
                title: "History",
                pasteboardTypes: [.string],
                updateAt: 1,
                deviceID: nil
            ),
            thumbnailAsset: nil
        )
        var state = HistoryMenuPaginationState(pageIndex: 1)
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: { [] },
            onOpenHistory: {},
            onOpenSnippets: {},
            historyDataSource: MainMenuHistoryDataSource(
                currentState: { state },
                updateState: { update in update(&state) },
                fetchPage: {
                    HistoryMenuPage(details: [detail], hasNextPage: true)
                },
                makeRowView: { detail, _, onConfirm in
                    HistoryMenuRowView(title: detail.history.title, image: nil, onConfirm: onConfirm)
                },
                selectHistory: { _, _ in }
            )
        )
        controller.show(at: NSPoint(x: 100, y: 100))
        defer { controller.close() }

        let bareLeft = try makeArrowEvent(keyCode: 123, modifierFlags: [])
        let bareRight = try makeArrowEvent(keyCode: 124, modifierFlags: [])
        let commandLeft = try makeArrowEvent(keyCode: 123, modifierFlags: [.command])
        let commandRight = try makeArrowEvent(keyCode: 124, modifierFlags: [.command])

        #expect(controller.handleMainMenuNavigationForTesting(bareLeft))
        #expect(state.pageIndex == 0)
        #expect(controller.handleMainMenuNavigationForTesting(bareRight))
        #expect(state.pageIndex == 1)
        #expect(!controller.handleMainMenuNavigationForTesting(commandLeft))
        #expect(!controller.handleMainMenuNavigationForTesting(commandRight))
        #expect(state.pageIndex == 1)

        #expect(controller.handleMainMenuNavigationForTesting(try makeCommandFEvent()))
        #expect(!controller.handleMainMenuNavigationForTesting(bareLeft))
        #expect(state.pageIndex == 1)
    }

    @Test
    func embeddedModeSwitchesDoNotTriggerLegacySidePanelCallbacks() {
        let detail = PasteboardHistoryDetail(
            history: PasteboardHistory(
                id: PasteboardHistory.ID(rawValue: "history-1"),
                title: "First copied value",
                pasteboardTypes: [.string],
                updateAt: 1,
                deviceID: nil
            ),
            thumbnailAsset: nil
        )
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let folderDetail = SnippetFolderDetail(
            folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
            snippets: []
        )
        var openHistoryCount = 0
        var openSnippetsCount = 0
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: { [] },
            onOpenHistory: { openHistoryCount += 1 },
            onOpenSnippets: { openSnippetsCount += 1 },
            historyDataSource: makeHistoryDataSource(detail: detail),
            snippetDataSource: MainMenuSnippetDataSource(
                fetchFolderDetails: { [folderDetail] },
                fetchFolderDetail: { id in id == folderID ? folderDetail : nil },
                selectSnippet: { _, _ in }
            )
        )

        controller.show(at: NSPoint(x: 100, y: 100))
        defer { controller.close() }

        controller.openSnippetsFromMainMenu()
        controller.openHistoryFromMainMenu()

        #expect(openHistoryCount == 0)
        #expect(openSnippetsCount == 0)
        #expect(controller.mainMenuSelectedModeForTesting == "history")
    }

    @Test
    func commandFExpandsAndFocusesEmbeddedSearchField() throws {
        let detail = PasteboardHistoryDetail(
            history: PasteboardHistory(
                id: PasteboardHistory.ID(rawValue: "history-1"),
                title: "First copied value",
                pasteboardTypes: [.string],
                updateAt: 1,
                deviceID: nil
            ),
            thumbnailAsset: nil
        )
        var fetchCount = 0
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: { [] },
            onOpenHistory: {},
            onOpenSnippets: {},
            historyDataSource: makeHistoryDataSource(detail: detail, fetchPage: {
                fetchCount += 1
                return HistoryMenuPage.result([detail], pageSize: 10)
            })
        )

        controller.show(at: NSPoint(x: 100, y: 100))
        defer { controller.close() }
        let initialFrame = try #require(controller.visibleFrame)

        #expect(fetchCount == 1)
        #expect(!controller.isMainMenuSearchFieldVisibleForTesting)
        #expect(controller.handleMainMenuNavigationForTesting(try makeCommandFEvent()))

        #expect(controller.isMainMenuSearchFieldVisibleForTesting)
        #expect(controller.isMainMenuSearchFieldFocusedForTesting)
        let expandedFrame = try #require(controller.visibleFrame)
        let extensionHeight = MainMenuPanelLayout.searchHeight + MainMenuPanelLayout.searchToolbarGap
        #expect(expandedFrame.minX == initialFrame.minX)
        #expect(expandedFrame.maxY == initialFrame.maxY)
        #expect(expandedFrame.width == initialFrame.width)
        #expect(expandedFrame.height == initialFrame.height + extensionHeight)
        #expect(fetchCount == 1)
    }

    @Test
    func embeddedSearchDefersRefreshUntilIMECompositionFinishes() throws {
        let detail = PasteboardHistoryDetail(
            history: PasteboardHistory(
                id: PasteboardHistory.ID(rawValue: "history-ime"),
                title: "中文输入",
                pasteboardTypes: [.string],
                updateAt: 1,
                deviceID: nil
            ),
            thumbnailAsset: nil
        )
        var state = HistoryMenuPaginationState()
        var fetchCount = 0
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: { [] },
            onOpenHistory: {},
            onOpenSnippets: {},
            historyDataSource: MainMenuHistoryDataSource(
                currentState: { state },
                updateState: { update in update(&state) },
                fetchPage: {
                    fetchCount += 1
                    return HistoryMenuPage.result([detail], pageSize: 10)
                },
                makeRowView: { detail, _, onConfirm in
                    HistoryMenuRowView(title: detail.history.title, image: nil, onConfirm: onConfirm)
                },
                selectHistory: { _, _ in }
            )
        )

        controller.show(at: NSPoint(x: 100, y: 100))
        defer { controller.close() }
        #expect(controller.handleMainMenuNavigationForTesting(try makeCommandFEvent()))
        let searchField = try #require(mainMenuSearchField())
        let editor = try #require(searchField.currentEditor() as? NSTextView)
        let baselineFetchCount = fetchCount
        editor.setMarkedText(
            "zhong",
            selectedRange: NSRange(location: 5, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        controller.controlTextDidChange(
            Notification(name: NSControl.textDidChangeNotification, object: searchField)
        )

        #expect(fetchCount == baselineFetchCount)
        #expect(state.query.isEmpty)
        #expect(controller.isMainMenuSearchFieldFocusedForTesting)

        editor.unmarkText()
        searchField.stringValue = "中"
        controller.controlTextDidChange(
            Notification(name: NSControl.textDidChangeNotification, object: searchField)
        )
        controller.flushPendingMainMenuSearchQueryForTesting()

        #expect(fetchCount > baselineFetchCount)
        #expect(state.query == "中")
        #expect(controller.isMainMenuSearchFieldFocusedForTesting)
    }

    @Test
    func embeddedSearchRechecksIMECompositionAfterTextChangeNotification() throws {
        let detail = PasteboardHistoryDetail(
            history: PasteboardHistory(
                id: PasteboardHistory.ID(rawValue: "history-ime-event-order"),
                title: "中文输入",
                pasteboardTypes: [.string],
                updateAt: 1,
                deviceID: nil
            ),
            thumbnailAsset: nil
        )
        var state = HistoryMenuPaginationState()
        var fetchCount = 0
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: { [] },
            onOpenHistory: {},
            onOpenSnippets: {},
            historyDataSource: MainMenuHistoryDataSource(
                currentState: { state },
                updateState: { update in update(&state) },
                fetchPage: {
                    fetchCount += 1
                    return HistoryMenuPage.result([detail], pageSize: 10)
                },
                makeRowView: { detail, _, onConfirm in
                    HistoryMenuRowView(title: detail.history.title, image: nil, onConfirm: onConfirm)
                },
                selectHistory: { _, _ in }
            )
        )

        controller.show(at: NSPoint(x: 100, y: 100))
        defer { controller.close() }
        #expect(controller.handleMainMenuNavigationForTesting(try makeCommandFEvent()))
        let searchField = try #require(mainMenuSearchField())
        let baselineFetchCount = fetchCount
        var hasMarkedText = false
        controller.mainMenuSearchMarkedTextStateProviderForTesting = { hasMarkedText }

        searchField.stringValue = "z"
        controller.controlTextDidChange(
            Notification(name: NSControl.textDidChangeNotification, object: searchField)
        )
        hasMarkedText = true
        controller.flushPendingMainMenuSearchQueryForTesting()

        #expect(fetchCount == baselineFetchCount)
        #expect(state.query.isEmpty)

        hasMarkedText = false
        searchField.stringValue = "中"
        controller.controlTextDidChange(
            Notification(name: NSControl.textDidChangeNotification, object: searchField)
        )
        controller.flushPendingMainMenuSearchQueryForTesting()

        #expect(fetchCount > baselineFetchCount)
        #expect(state.query == "中")
        #expect(controller.isMainMenuSearchFieldFocusedForTesting)
    }

    @Test
    func embeddedSearchRefreshPreservesInsertionPoint() throws {
        var state = HistoryMenuPaginationState()
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: { [] },
            onOpenHistory: {},
            onOpenSnippets: {},
            historyDataSource: MainMenuHistoryDataSource(
                currentState: { state },
                updateState: { update in update(&state) },
                fetchPage: { HistoryMenuPage.result([], pageSize: 10) },
                makeRowView: { detail, _, onConfirm in
                    HistoryMenuRowView(title: detail.history.title, image: nil, onConfirm: onConfirm)
                },
                selectHistory: { _, _ in }
            )
        )

        controller.show(at: NSPoint(x: 100, y: 100))
        defer { controller.close() }
        #expect(controller.handleMainMenuNavigationForTesting(try makeCommandFEvent()))
        let searchField = try #require(mainMenuSearchField())
        let editor = try #require(searchField.currentEditor() as? NSTextView)
        searchField.stringValue = "abcd"
        editor.string = "abcd"
        editor.setSelectedRange(NSRange(location: 2, length: 0))

        controller.controlTextDidChange(
            Notification(name: NSControl.textDidChangeNotification, object: searchField)
        )
        controller.flushPendingMainMenuSearchQueryForTesting()

        let refreshedField = try #require(mainMenuSearchField())
        let refreshedEditor = try #require(refreshedField.currentEditor() as? NSTextView)
        #expect(state.query == "abcd")
        #expect(refreshedEditor.selectedRange() == NSRange(location: 2, length: 0))
    }

    @Test
    func controlSpaceIsNotInterceptedWhileEmbeddedSearchFieldIsEditing() throws {
        let detail = PasteboardHistoryDetail(
            history: PasteboardHistory(
                id: PasteboardHistory.ID(rawValue: "history-input-source"),
                title: "Input Source",
                pasteboardTypes: [.string],
                updateAt: 1,
                deviceID: nil
            ),
            thumbnailAsset: nil
        )
        var confirmCount = 0
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: { [] },
            onOpenHistory: {},
            onOpenSnippets: {},
            historyDataSource: MainMenuHistoryDataSource(
                currentState: { HistoryMenuPaginationState() },
                updateState: { _ in },
                fetchPage: { HistoryMenuPage.result([detail], pageSize: 10) },
                makeRowView: { detail, _, onConfirm in
                    HistoryMenuRowView(title: detail.history.title, image: nil, onConfirm: onConfirm)
                },
                selectHistory: { _, _ in confirmCount += 1 }
            )
        )

        controller.show(at: NSPoint(x: 100, y: 100))
        defer { controller.close() }
        controller.selectMainMenuItemForTesting(title: "Input Source")
        #expect(controller.handleMainMenuNavigationForTesting(try makeCommandFEvent()))

        #expect(!controller.handleMainMenuNavigationForTesting(try makeControlSpaceEvent()))
        #expect(confirmCount == 0)
        #expect(controller.isMainMenuSearchFieldFocusedForTesting)
    }

    @Test
    func commandCommaOpensPreferencesFromEmbeddedMainMenu() throws {
        let detail = PasteboardHistoryDetail(
            history: PasteboardHistory(
                id: PasteboardHistory.ID(rawValue: "history-preferences"), title: "Preferences target",
                pasteboardTypes: [.string], updateAt: 1, deviceID: nil
            ),
            thumbnailAsset: nil
        )
        var openCount = 0
        let controller = MainMenuPanelController(
            historyTitle: "History", historyImage: nil, snippetTitle: "Snippet", snippetImage: nil,
            itemsProvider: { [] }, onOpenHistory: {}, onOpenSnippets: {},
            historyDataSource: makeHistoryDataSource(detail: detail),
            onOpenPreferences: { openCount += 1 }
        )
        controller.show(at: NSPoint(x: 100, y: 100))
        defer { controller.close() }

        #expect(controller.performMainMenuKeyEquivalentForTesting(try makeCommandCommaEvent()))
        #expect(openCount == 1)
    }

    @Test
    func escapeClosesEmptyEmbeddedSearchDrawerAndRestoresFrame() throws {
        let detail = PasteboardHistoryDetail(
            history: PasteboardHistory(
                id: PasteboardHistory.ID(rawValue: "history-1"),
                title: "First copied value",
                pasteboardTypes: [.string],
                updateAt: 1,
                deviceID: nil
            ),
            thumbnailAsset: nil
        )
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: { [] },
            onOpenHistory: {},
            onOpenSnippets: {},
            historyDataSource: makeHistoryDataSource(detail: detail)
        )

        controller.show(at: NSPoint(x: 100, y: 100))
        defer { controller.close() }
        let initialFrame = try #require(controller.visibleFrame)

        #expect(controller.handleMainMenuNavigationForTesting(try makeCommandFEvent()))
        #expect(controller.isMainMenuSearchFieldVisibleForTesting)

        #expect(controller.handleMainMenuNavigationForTesting(try makeEscapeEvent()))

        #expect(!controller.isMainMenuSearchFieldVisibleForTesting)
        #expect(try #require(controller.visibleFrame) == initialFrame)
    }

    @Test
    func searchButtonTogglesEmbeddedSearchDrawerAndRestoresFrame() throws {
        let detail = PasteboardHistoryDetail(
            history: PasteboardHistory(
                id: PasteboardHistory.ID(rawValue: "history-1"),
                title: "First copied value",
                pasteboardTypes: [.string],
                updateAt: 1,
                deviceID: nil
            ),
            thumbnailAsset: nil
        )
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: { [] },
            onOpenHistory: {},
            onOpenSnippets: {},
            historyDataSource: makeHistoryDataSource(detail: detail)
        )

        controller.show(at: NSPoint(x: 100, y: 100))
        defer { controller.close() }
        let initialFrame = try #require(controller.visibleFrame)

        controller.performMainMenuSearchClickForTesting()
        #expect(controller.isMainMenuSearchFieldVisibleForTesting)
        #expect(try #require(controller.visibleFrame).maxY == initialFrame.maxY)
        #expect(try #require(controller.visibleFrame).height > initialFrame.height)

        controller.performMainMenuSearchClickForTesting()
        #expect(!controller.isMainMenuSearchFieldVisibleForTesting)
        #expect(try #require(controller.visibleFrame) == initialFrame)
    }

    @Test
    func embeddedMainMenuKeepsFixedCompactSizeAcrossModesFolderAndSearch() throws {
        let historyDetail = PasteboardHistoryDetail(
            history: PasteboardHistory(
                id: PasteboardHistory.ID(rawValue: "history-1"),
                title: "First copied value",
                pasteboardTypes: [.string],
                updateAt: 1,
                deviceID: nil
            ),
            thumbnailAsset: nil
        )
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let folderDetail = SnippetFolderDetail(
            folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
            snippets: [
                Snippet(
                    id: Snippet.ID(rawValue: UUID()),
                    folderID: folderID,
                    title: "Ask GPT",
                    content: "Summarize this page",
                    index: 0,
                    isEnabled: true
                )
            ]
        )
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: { [] },
            onOpenHistory: {},
            onOpenSnippets: {},
            historyDataSource: makeHistoryDataSource(detail: historyDetail),
            snippetDataSource: MainMenuSnippetDataSource(
                fetchFolderDetails: { [folderDetail] },
                fetchFolderDetail: { id in id == folderID ? folderDetail : nil },
                selectSnippet: { _, _ in }
            )
        )
        let fixedSize = NSSize(width: MainMenuPanelLayout.width, height: MainMenuPanelLayout.fixedHeight)

        controller.show(at: NSPoint(x: 160, y: 700))
        defer { controller.close() }
        #expect(try #require(controller.visibleFrame).size == fixedSize)

        controller.openSnippetsFromMainMenu()
        #expect(try #require(controller.visibleFrame).size == fixedSize)

        controller.selectMainMenuItemForTesting(title: "AI Prompt")
        #expect(controller.handleMainMenuNavigationForTesting(try makeReturnEvent()))
        #expect(try #require(controller.visibleFrame).size == fixedSize)

        let preSearchFrame = try #require(controller.visibleFrame)
        #expect(controller.handleMainMenuNavigationForTesting(try makeCommandFEvent()))
        let searchFrame = try #require(controller.visibleFrame)
        #expect(searchFrame.width == fixedSize.width)
        #expect(searchFrame.maxY == preSearchFrame.maxY)
        #expect(searchFrame.height > fixedSize.height)
        #expect(controller.isMainMenuSearchFieldFocusedForTesting)
    }

    @Test
    func mainMenuSnippetModeShowsExpandedFolderTreeInsideMainPanel() throws {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let snippetID = Snippet.ID(rawValue: UUID())
        let detail = SnippetFolderDetail(
            folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
            snippets: [
                Snippet(
                    id: snippetID,
                    folderID: folderID,
                    title: "Ask GPT",
                    content: "Summarize this page",
                    index: 0,
                    isEnabled: true
                )
            ]
        )
        var selectedSnippetID: Snippet.ID?
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: { [] },
            onOpenHistory: {},
            onOpenSnippets: {},
            snippetDataSource: MainMenuSnippetDataSource(
                fetchFolderDetails: { [detail] },
                fetchFolderDetail: { id in id == detail.folder.id ? detail : nil },
                selectSnippet: { snippetID, _ in selectedSnippetID = snippetID }
            )
        )

        controller.show(at: NSPoint(x: 100, y: 100))
        defer { controller.close() }

        controller.openSnippetsFromMainMenu()
        #expect(controller.mainMenuSelectedModeForTesting == "snippets")
        #expect(controller.mainMenuSnippetFolderTitleForTesting == nil)
        #expect(controller.mainMenuVisibleRowTitlesForTesting == ["AI Prompt"])

        controller.selectMainMenuItemForTesting(title: "AI Prompt")
        #expect(controller.handleMainMenuNavigationForTesting(try makeReturnEvent()))

        #expect(controller.mainMenuSnippetFolderTitleForTesting == "AI Prompt")
        #expect(controller.mainMenuVisibleRowTitlesForTesting == ["AI Prompt", "Ask GPT"])
        #expect(selectedSnippetID == nil)

        controller.selectMainMenuItemForTesting(title: "Ask GPT")
        #expect(controller.handleMainMenuNavigationForTesting(try makeReturnEvent()))

        #expect(selectedSnippetID == snippetID)
    }

    @Test
    func leftArrowMovesFromSnippetRowBackToExpandedFolderRow() throws {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let detail = SnippetFolderDetail(
            folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
            snippets: [
                Snippet(
                    id: Snippet.ID(rawValue: UUID()),
                    folderID: folderID,
                    title: "Ask GPT",
                    content: "Summarize this page",
                    index: 0,
                    isEnabled: true
                )
            ]
        )
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: { [] },
            onOpenHistory: {},
            onOpenSnippets: {},
            snippetDataSource: MainMenuSnippetDataSource(
                fetchFolderDetails: { [detail] },
                fetchFolderDetail: { id in id == detail.folder.id ? detail : nil },
                selectSnippet: { _, _ in }
            )
        )

        controller.show(at: NSPoint(x: 100, y: 100))
        defer { controller.close() }

        controller.openSnippetsFromMainMenu()
        controller.selectMainMenuItemForTesting(title: "AI Prompt")
        #expect(controller.handleMainMenuNavigationForTesting(try makeReturnEvent()))
        #expect(controller.mainMenuSnippetFolderTitleForTesting == "AI Prompt")

        controller.selectMainMenuItemForTesting(title: "Ask GPT")
        #expect(controller.handleMainMenuNavigationForTesting(try makeLeftArrowEvent()))

        #expect(controller.mainMenuSnippetFolderTitleForTesting == "AI Prompt")
        #expect(controller.mainMenuVisibleRowTitlesForTesting == ["AI Prompt", "Ask GPT"])
        #expect(controller.selectedMainMenuTitleForTesting == "AI Prompt")
    }

    @Test
    func snippetTreeDefaultsToCollapsedAndKeepsOnlyOneFolderExpanded() throws {
        let firstFolderID = SnippetFolder.ID(rawValue: UUID())
        let secondFolderID = SnippetFolder.ID(rawValue: UUID())
        let details = [
            SnippetFolderDetail(
                folder: SnippetFolder(id: firstFolderID, title: "AI Prompt", index: 0, isEnabled: true),
                snippets: [
                    Snippet(id: Snippet.ID(rawValue: UUID()), folderID: firstFolderID, title: "Ask GPT", content: "Summarize", index: 0, isEnabled: true)
                ]
            ),
            SnippetFolderDetail(
                folder: SnippetFolder(id: secondFolderID, title: "Workflows", index: 1, isEnabled: true),
                snippets: [
                    Snippet(id: Snippet.ID(rawValue: UUID()), folderID: secondFolderID, title: "Ship It", content: "Release", index: 0, isEnabled: true)
                ]
            )
        ]
        let controller = makeSnippetController(details: details)

        controller.show(at: NSPoint(x: 100, y: 100))
        defer { controller.close() }
        controller.openSnippetsFromMainMenu()

        #expect(controller.mainMenuSnippetFolderTitleForTesting == nil)
        #expect(controller.mainMenuVisibleRowTitlesForTesting == ["AI Prompt", "Workflows"])

        controller.selectMainMenuItemForTesting(title: "Workflows")
        #expect(controller.handleMainMenuNavigationForTesting(try makeReturnEvent()))

        #expect(controller.mainMenuSnippetFolderTitleForTesting == "Workflows")
        #expect(controller.mainMenuVisibleRowTitlesForTesting == ["AI Prompt", "Workflows", "Ship It"])
    }

    @Test
    func snippetNumberShortcutSelectsOnlyExpandedFolderSnippet() throws {
        let firstFolderID = SnippetFolder.ID(rawValue: UUID())
        let secondFolderID = SnippetFolder.ID(rawValue: UUID())
        let firstSnippetID = Snippet.ID(rawValue: UUID())
        let secondSnippetID = Snippet.ID(rawValue: UUID())
        let details = [
            SnippetFolderDetail(
                folder: SnippetFolder(id: firstFolderID, title: "AI Prompt", index: 0, isEnabled: true),
                snippets: [
                    Snippet(id: firstSnippetID, folderID: firstFolderID, title: "Ask GPT", content: "Summarize", index: 0, isEnabled: true)
                ]
            ),
            SnippetFolderDetail(
                folder: SnippetFolder(id: secondFolderID, title: "Workflows", index: 1, isEnabled: true),
                snippets: [
                    Snippet(id: secondSnippetID, folderID: secondFolderID, title: "Ship It", content: "Release", index: 0, isEnabled: true)
                ]
            )
        ]
        var selectedSnippetID: Snippet.ID?
        let controller = makeSnippetController(details: details) { snippetID, _ in
            selectedSnippetID = snippetID
        }
        let returnEvent = try makeReturnEvent()
        let firstNumberEvent = try makeTextEvent("1", keyCode: 18)

        withMenuTitlesStartingAtOne {
            controller.show(at: NSPoint(x: 100, y: 100))
            defer { controller.close() }
            controller.openSnippetsFromMainMenu()
            controller.performMainMenuRowConfirmForTesting(title: "AI Prompt")
            controller.selectMainMenuItemForTesting(title: "Workflows")
            #expect(controller.handleMainMenuNavigationForTesting(returnEvent))

            #expect(controller.handleMainMenuNavigationForTesting(firstNumberEvent))

            #expect(selectedSnippetID == secondSnippetID)
            #expect(selectedSnippetID != firstSnippetID)
        }
    }

    @Test
    func snippetNumberShortcutOpensFolderThenSelectsEntry() throws {
        let firstFolderID = SnippetFolder.ID(rawValue: UUID())
        let secondFolderID = SnippetFolder.ID(rawValue: UUID())
        let firstFolderSnippets = (0..<2).map { index in
            Snippet(
                id: Snippet.ID(rawValue: UUID()),
                folderID: firstFolderID,
                title: "AI \(index + 1)",
                content: "Prompt \(index + 1)",
                index: index,
                isEnabled: true
            )
        }
        let secondFolderSnippets = (0..<2).map { index in
            Snippet(
                id: Snippet.ID(rawValue: UUID()),
                folderID: secondFolderID,
                title: "Workflow \(index + 1)",
                content: "Step \(index + 1)",
                index: index,
                isEnabled: true
            )
        }
        let details = [
            SnippetFolderDetail(
                folder: SnippetFolder(id: firstFolderID, title: "AI Prompt", index: 0, isEnabled: true),
                snippets: firstFolderSnippets
            ),
            SnippetFolderDetail(
                folder: SnippetFolder(id: secondFolderID, title: "Workflows", index: 1, isEnabled: true),
                snippets: secondFolderSnippets
            )
        ]
        var selectedSnippetID: Snippet.ID?
        let controller = makeSnippetController(details: details) { snippetID, _ in
            selectedSnippetID = snippetID
        }
        let firstNumber = try makeTextEvent("1", keyCode: 18)
        let secondNumber = try makeTextEvent("2", keyCode: 19)

        try withMenuTitlesStartingAtOne {
            controller.show(at: NSPoint(x: 100, y: 100))
            defer { controller.close() }
            controller.openSnippetsFromMainMenu()

            #expect(controller.handleMainMenuNavigationForTesting(firstNumber))
            #expect(controller.mainMenuExpandedSnippetFolderIDForTesting == firstFolderID)
            #expect(selectedSnippetID == nil)

            #expect(controller.handleMainMenuNavigationForTesting(secondNumber))
            #expect(selectedSnippetID == firstFolderSnippets[1].id)
        }
    }

    @Test
    func snippetFolderNumberShortcutHonorsZeroBasedPreference() throws {
        let firstFolderID = SnippetFolder.ID(rawValue: UUID())
        let secondFolderID = SnippetFolder.ID(rawValue: UUID())
        let details = [
            SnippetFolderDetail(
                folder: SnippetFolder(id: firstFolderID, title: "First", index: 0, isEnabled: true),
                snippets: []
            ),
            SnippetFolderDetail(
                folder: SnippetFolder(id: secondFolderID, title: "Second", index: 1, isEnabled: true),
                snippets: []
            )
        ]
        let controller = makeSnippetController(details: details)
        let zero = try makeTextEvent("0", keyCode: 29)

        try withMenuTitlesStartingAtZero {
            controller.show(at: NSPoint(x: 100, y: 100))
            defer { controller.close() }
            controller.openSnippetsFromMainMenu()

            #expect(controller.mainMenuRowItemNumberTextForTesting(title: "First") == "0")
            #expect(controller.handleMainMenuNavigationForTesting(zero))
            #expect(controller.mainMenuExpandedSnippetFolderIDForTesting == firstFolderID)
        }
    }

    @Test
    func zeroSelectsTenthSnippetFolderAndTenthEntry() throws {
        let folderIDs = (0..<10).map { _ in SnippetFolder.ID(rawValue: UUID()) }
        let tenthSnippets = (0..<10).map { index in
            Snippet(
                id: Snippet.ID(rawValue: UUID()),
                folderID: folderIDs[9],
                title: "Tenth Folder Snippet \(index + 1)",
                content: "Content \(index + 1)",
                index: index,
                isEnabled: true
            )
        }
        let details = folderIDs.enumerated().map { index, folderID in
            SnippetFolderDetail(
                folder: SnippetFolder(id: folderID, title: "Folder \(index + 1)", index: index, isEnabled: true),
                snippets: index == 9 ? tenthSnippets : []
            )
        }
        var selectedSnippetID: Snippet.ID?
        let controller = makeSnippetController(details: details) { snippetID, _ in
            selectedSnippetID = snippetID
        }
        let zero = try makeTextEvent("0", keyCode: 29)

        try withMenuTitlesStartingAtOne {
            controller.show(at: NSPoint(x: 100, y: 100))
            defer { controller.close() }
            controller.openSnippetsFromMainMenu()

            #expect(controller.mainMenuRowItemNumberTextForTesting(title: "Folder 10") == "0")
            #expect(controller.handleMainMenuNavigationForTesting(zero))
            #expect(controller.mainMenuExpandedSnippetFolderIDForTesting == folderIDs[9])
            #expect(controller.mainMenuRowItemNumberTextForTesting(title: "Tenth Folder Snippet 10") == "0")

            #expect(controller.handleMainMenuNavigationForTesting(zero))
            #expect(selectedSnippetID == tenthSnippets[9].id)
        }
    }

    @Test
    func numberShortcutReturnsFalseInsideEmptyExpandedSnippetFolder() throws {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let detail = SnippetFolderDetail(
            folder: SnippetFolder(id: folderID, title: "Empty", index: 0, isEnabled: true),
            snippets: []
        )
        let controller = makeSnippetController(details: [detail])

        try withMenuTitlesStartingAtOne {
            controller.show(at: NSPoint(x: 100, y: 100))
            defer { controller.close() }
            controller.openSnippetsFromMainMenu()

            let firstNumber = try makeTextEvent("1", keyCode: 18)
            #expect(controller.handleMainMenuNavigationForTesting(firstNumber))
            #expect(controller.mainMenuExpandedSnippetFolderIDForTesting == folderID)
            #expect(!controller.handleMainMenuNavigationForTesting(firstNumber))
        }
    }

    @Test
    func snippetSearchAndInlineEditorKeepDigitInput() throws {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let detail = SnippetFolderDetail(
            folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
            snippets: []
        )
        let numberEvent = try makeTextEvent("1", keyCode: 18)

        let searchController = makeSnippetController(details: [detail])
        searchController.show(at: NSPoint(x: 100, y: 100))
        searchController.openSnippetsFromMainMenu()
        #expect(searchController.handleMainMenuNavigationForTesting(try makeCommandFEvent()))
        #expect(!searchController.handleMainMenuNavigationForTesting(numberEvent))
        #expect(searchController.mainMenuExpandedSnippetFolderIDForTesting == nil)
        searchController.close()

        let editorController = makeSnippetController(details: [detail])
        editorController.show(at: NSPoint(x: 100, y: 100))
        defer { editorController.close() }
        editorController.openSnippetsFromMainMenu()
        editorController.beginEditingSnippetFolderForTesting(id: folderID)
        #expect(!editorController.handleMainMenuNavigationForTesting(numberEvent))
    }

    @Test
    func historyNumberKeyEquivalentUsesTheSameSelectionPathAsTheRow() throws {
        let detail = PasteboardHistoryDetail(
            history: PasteboardHistory(
                id: PasteboardHistory.ID(rawValue: "history-number"), title: "Number target",
                pasteboardTypes: [.string], updateAt: 1, deviceID: nil
            ),
            thumbnailAsset: nil
        )
        var selectedID: PasteboardHistory.ID?
        let controller = MainMenuPanelController(
            historyTitle: "History", historyImage: nil, snippetTitle: "Snippet", snippetImage: nil,
            itemsProvider: { [] }, onOpenHistory: {}, onOpenSnippets: {},
            historyDataSource: MainMenuHistoryDataSource(
                currentState: { HistoryMenuPaginationState() }, updateState: { _ in },
                fetchPage: { HistoryMenuPage.result([detail], pageSize: 10) },
                makeRowView: { detail, _, onConfirm in
                    HistoryMenuRowView(title: detail.history.title, image: nil, onConfirm: onConfirm)
                },
                selectHistory: { id, _ in selectedID = id }
            )
        )

        let numberEvent = try makeTextEvent("1", keyCode: 18)
        withMenuTitlesStartingAtOne {
            controller.show(at: NSPoint(x: 100, y: 100))
            #expect(controller.performMainMenuKeyEquivalentForTesting(numberEvent))
        }

        #expect(selectedID == detail.history.id)
    }

    @Test
    func snippetItemNumberBadgeSitsAtLeadingEdgeBeforeTitle() throws {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let detail = SnippetFolderDetail(
            folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
            snippets: [
                Snippet(id: Snippet.ID(rawValue: UUID()), folderID: folderID, title: "Ask GPT", content: "Summarize", index: 0, isEnabled: true)
            ]
        )
        let controller = makeSnippetController(details: [detail])

        try withMenuTitlesStartingAtOne {
            controller.show(at: NSPoint(x: 100, y: 100))
            defer { controller.close() }
            controller.openSnippetsFromMainMenu()
            controller.performMainMenuRowConfirmForTesting(title: "AI Prompt")

            let rowFrame = try #require(controller.mainMenuActionRowFrameForTesting(title: "Ask GPT"))
            let titleFrame = try #require(controller.mainMenuActionTitleFrameForTesting(title: "Ask GPT"))
            let itemNumberFrame = try #require(controller.mainMenuRowItemNumberFrameForTesting(title: "Ask GPT"))

            #expect(controller.mainMenuRowItemNumberTextForTesting(title: "Ask GPT") == "1")
            #expect(itemNumberFrame.minX <= rowFrame.minX + 36)
            #expect(itemNumberFrame.maxX < titleFrame.minX)
        }
    }

    @Test
    func snippetFolderRowsDisplayConfiguredShortcutAndExposeShortcutEditor() throws {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let folderKeyCombo = try #require(KeyCombo(QWERTYKeyCode: 12, carbonModifiers: cmdKey | optionKey))
        let detail = SnippetFolderDetail(
            folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
            snippets: [
                Snippet(id: Snippet.ID(rawValue: UUID()), folderID: folderID, title: "Ask GPT", content: "Summarize", index: 0, isEnabled: true)
            ]
        )
        let controller = makeSnippetController(
            details: [detail],
            folderKeyCombo: { id in id == folderID ? folderKeyCombo : nil }
        )

        controller.show(at: NSPoint(x: 100, y: 100))
        defer { controller.close() }
        controller.openSnippetsFromMainMenu()

        #expect(controller.mainMenuRowItemNumberTextForTesting(title: "AI Prompt") == "1")
        #expect(controller.mainMenuRowShortcutTextForTesting(title: "AI Prompt") == "⌥⌘Q")
        #expect(controller.mainMenuRowButtonIdentifiersForTesting(title: "AI Prompt").contains("mainMenuRowShortcutButton"))
        #expect(controller.mainMenuRowContextMenuTitlesForTesting(title: "AI Prompt") == [
            String(localized: "Edit"),
            String(localized: "Edit Shortcut"),
            String(localized: "Clear Shortcut"),
            String(localized: "Delete Folder")
        ])
    }

    @Test
    func snippetFolderShortcutEditorRecordsAndClearsFolderShortcut() throws {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let detail = SnippetFolderDetail(
            folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
            snippets: []
        )
        let recordedKeyCombo = try #require(KeyCombo(QWERTYKeyCode: 13, carbonModifiers: cmdKey | optionKey))
        var updatedKeyCombos = [(SnippetFolder.ID, KeyCombo)]()
        var clearedFolderIDs = [SnippetFolder.ID]()
        let controller = makeSnippetController(
            details: [detail],
            updateFolderKeyCombo: { folderID, keyCombo in updatedKeyCombos.append((folderID, keyCombo)) },
            clearFolderKeyCombo: { folderID in clearedFolderIDs.append(folderID) }
        )

        controller.show(at: NSPoint(x: 100, y: 100))
        defer { controller.close() }
        controller.openSnippetsFromMainMenu()

        controller.beginEditingSnippetFolderShortcutForTesting(id: folderID)
        #expect(controller.isMainMenuFolderShortcutEditorVisibleForTesting)

        controller.recordMainMenuFolderShortcutForTesting(recordedKeyCombo)
        #expect(updatedKeyCombos.map(\.0) == [folderID])
        #expect(updatedKeyCombos.map(\.1) == [recordedKeyCombo])
        #expect(!controller.isMainMenuFolderShortcutEditorVisibleForTesting)

        controller.beginEditingSnippetFolderShortcutForTesting(id: folderID)
        controller.clearMainMenuFolderShortcutForTesting()
        #expect(clearedFolderIDs == [folderID])
        #expect(!controller.isMainMenuFolderShortcutEditorVisibleForTesting)
    }

    @Test
    func snippetSearchFallsBackToFirstMatchingFolderWhenExpandedFolderIsFilteredOut() {
        let firstFolderID = SnippetFolder.ID(rawValue: UUID())
        let secondFolderID = SnippetFolder.ID(rawValue: UUID())
        let details = [
            SnippetFolderDetail(
                folder: SnippetFolder(id: firstFolderID, title: "AI Prompt", index: 0, isEnabled: true),
                snippets: [
                    Snippet(id: Snippet.ID(rawValue: UUID()), folderID: firstFolderID, title: "Ask GPT", content: "Summarize", index: 0, isEnabled: true)
                ]
            ),
            SnippetFolderDetail(
                folder: SnippetFolder(id: secondFolderID, title: "Workflows", index: 1, isEnabled: true),
                snippets: [
                    Snippet(id: Snippet.ID(rawValue: UUID()), folderID: secondFolderID, title: "Ship It", content: "Release", index: 0, isEnabled: true)
                ]
            )
        ]
        let controller = makeSnippetController(details: details)

        controller.show(at: NSPoint(x: 100, y: 100))
        defer { controller.close() }
        controller.openSnippetsFromMainMenu()
        controller.performMainMenuRowConfirmForTesting(title: "AI Prompt")
        #expect(controller.mainMenuSnippetFolderTitleForTesting == "AI Prompt")

        controller.updateMainMenuSearchQueryForTesting("Ship")

        #expect(controller.mainMenuSnippetFolderTitleForTesting == "Workflows")
        #expect(controller.mainMenuVisibleRowTitlesForTesting == ["Workflows", "Ship It"])
    }

    @Test
    func snippetRowShowsDeleteEntryAndCommandDDeletesConfirmedSnippet() throws {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let firstSnippetID = Snippet.ID(rawValue: UUID())
        let secondSnippetID = Snippet.ID(rawValue: UUID())
        var details = [
            SnippetFolderDetail(
                folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
                snippets: [
                    Snippet(id: firstSnippetID, folderID: folderID, title: "Ask GPT", content: "Summarize", index: 0, isEnabled: true),
                    Snippet(id: secondSnippetID, folderID: folderID, title: "Ship It", content: "Release", index: 1, isEnabled: true)
                ]
            )
        ]
        var deletedSnippetIDs = [Snippet.ID]()
        var confirmationOptions: PasteraConfirmationOptions?
        let controller = makeSnippetController(
            fetchFolderDetails: { details },
            deleteSnippet: { snippetID in
                deletedSnippetIDs.append(snippetID)
                details[0] = SnippetFolderDetail(
                    folder: details[0].folder,
                    snippets: details[0].snippets.filter { $0.id != snippetID }
                )
            }
        )

        controller.show(at: NSPoint(x: 100, y: 100))
        defer { controller.close() }
        controller.openSnippetsFromMainMenu()
        controller.performMainMenuRowConfirmForTesting(title: "AI Prompt")

        #expect(controller.mainMenuRowButtonIdentifiersForTesting(title: "Ask GPT").contains("mainMenuRowDeleteButton"))
        #expect(controller.mainMenuRowContextMenuTitlesForTesting(title: "Ask GPT") == [
            String(localized: "Edit"),
            String(localized: "Delete Snippet")
        ])

        controller.selectMainMenuItemForTesting(title: "Ask GPT")
        controller.setMainMenuDeleteConfirmationRunnerForTesting { options, sourceWindow in
            confirmationOptions = options
            #expect(sourceWindow != nil)
            return PasteraConfirmationResult(confirmed: true, suppressionChecked: false)
        }

        #expect(controller.handleMainMenuNavigationForTesting(try makeCommandDEvent()))

        #expect(deletedSnippetIDs == [firstSnippetID])
        #expect(confirmationOptions?.title == String(localized: "Delete Snippet"))
        #expect(confirmationOptions?.isDestructive == true)
        #expect(controller.mainMenuVisibleRowTitlesForTesting == ["AI Prompt", "Ship It"])
        #expect(controller.selectedMainMenuTitleForTesting == "Ship It")
    }

    @Test
    func snippetDeleteCancellationDoesNotWriteRepository() throws {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let snippetID = Snippet.ID(rawValue: UUID())
        let detail = SnippetFolderDetail(
            folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
            snippets: [
                Snippet(id: snippetID, folderID: folderID, title: "Ask GPT", content: "Summarize", index: 0, isEnabled: true)
            ]
        )
        var deletedSnippetIDs = [Snippet.ID]()
        let controller = makeSnippetController(
            details: [detail],
            deleteSnippet: { deletedSnippetIDs.append($0) }
        )

        controller.show(at: NSPoint(x: 100, y: 100))
        defer { controller.close() }
        controller.openSnippetsFromMainMenu()
        controller.performMainMenuRowConfirmForTesting(title: "AI Prompt")
        controller.selectMainMenuItemForTesting(title: "Ask GPT")
        controller.setMainMenuDeleteConfirmationRunnerForTesting { _, _ in .cancelled }

        #expect(controller.handleMainMenuNavigationForTesting(try makeCommandDEvent()))

        #expect(deletedSnippetIDs.isEmpty)
        #expect(controller.mainMenuVisibleRowTitlesForTesting == ["AI Prompt", "Ask GPT"])
    }

    @Test
    func deletingSnippetFolderLeavesNextAvailableFolderCollapsed() throws {
        let firstFolderID = SnippetFolder.ID(rawValue: UUID())
        let secondFolderID = SnippetFolder.ID(rawValue: UUID())
        var details = [
            SnippetFolderDetail(
                folder: SnippetFolder(id: firstFolderID, title: "AI Prompt", index: 0, isEnabled: true),
                snippets: [
                    Snippet(id: Snippet.ID(rawValue: UUID()), folderID: firstFolderID, title: "Ask GPT", content: "Summarize", index: 0, isEnabled: true)
                ]
            ),
            SnippetFolderDetail(
                folder: SnippetFolder(id: secondFolderID, title: "Workflows", index: 1, isEnabled: true),
                snippets: [
                    Snippet(id: Snippet.ID(rawValue: UUID()), folderID: secondFolderID, title: "Ship It", content: "Release", index: 0, isEnabled: true)
                ]
            )
        ]
        var deletedFolderIDs = [SnippetFolder.ID]()
        var confirmationOptions: PasteraConfirmationOptions?
        let controller = makeSnippetController(
            fetchFolderDetails: { details },
            deleteFolder: { folderID in
                deletedFolderIDs.append(folderID)
                details.removeAll { $0.folder.id == folderID }
            }
        )

        controller.show(at: NSPoint(x: 100, y: 100))
        defer { controller.close() }
        controller.openSnippetsFromMainMenu()
        controller.performMainMenuRowConfirmForTesting(title: "AI Prompt")
        #expect(controller.mainMenuSnippetFolderTitleForTesting == "AI Prompt")
        #expect(controller.mainMenuRowContextMenuTitlesForTesting(title: "AI Prompt") == [
            String(localized: "Edit"),
            String(localized: "Edit Shortcut"),
            String(localized: "Delete Folder")
        ])

        controller.selectMainMenuItemForTesting(title: "AI Prompt")
        controller.setMainMenuDeleteConfirmationRunnerForTesting { options, _ in
            confirmationOptions = options
            return PasteraConfirmationResult(confirmed: true, suppressionChecked: false)
        }

        #expect(controller.handleMainMenuNavigationForTesting(try makeCommandDEvent()))

        #expect(deletedFolderIDs == [firstFolderID])
        #expect(confirmationOptions?.title == String(localized: "Delete Folder"))
        #expect(confirmationOptions?.isDestructive == true)
        #expect(controller.mainMenuSnippetFolderTitleForTesting == nil)
        #expect(controller.mainMenuVisibleRowTitlesForTesting == ["Workflows"])
        #expect(controller.selectedMainMenuTitleForTesting == nil)
    }

    @Test
    func commandDDoesNotDeleteWhileSnippetInlineEditorIsActive() throws {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let snippetID = Snippet.ID(rawValue: UUID())
        let detail = SnippetFolderDetail(
            folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
            snippets: [
                Snippet(id: snippetID, folderID: folderID, title: "Ask GPT", content: "Summarize", index: 0, isEnabled: true)
            ]
        )
        var deletedSnippetIDs = [Snippet.ID]()
        let controller = makeSnippetController(
            details: [detail],
            deleteSnippet: { deletedSnippetIDs.append($0) }
        )

        controller.show(at: NSPoint(x: 100, y: 100))
        defer { controller.close() }
        controller.openSnippetsFromMainMenu()
        controller.beginEditingSnippetForTesting(id: snippetID)

        #expect(!controller.handleMainMenuNavigationForTesting(try makeCommandDEvent()))

        #expect(deletedSnippetIDs.isEmpty)
        #expect(controller.mainMenuEditorTitleForTesting == "Ask GPT")
    }

    @Test
    func historyInlineEditorOmitsButtonsAndCommitsDraftWhenEditingEnds() {
        let historyID = PasteboardHistory.ID(rawValue: "history-1")
        let detail = PasteboardHistoryDetail(
            history: PasteboardHistory(
                id: historyID,
                title: "Original",
                pasteboardTypes: [.string],
                updateAt: 1,
                deviceID: nil
            ),
            thumbnailAsset: nil
        )
        var updatedText: String?
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: { [] },
            onOpenHistory: {},
            onOpenSnippets: {},
            historyDataSource: makeHistoryDataSource(
                detail: detail,
                fetchEditableText: { id in id == historyID ? "Original" : nil },
                updateTextHistory: { id, text in
                    guard id == historyID else { return false }
                    updatedText = text
                    return true
                }
            )
        )

        controller.show(at: NSPoint(x: 100, y: 100))
        defer { controller.close() }

        controller.beginEditingHistoryForTesting(id: historyID)
        #expect(controller.mainMenuEditorButtonTitlesForTesting.isEmpty)

        controller.updateMainMenuEditorDraftForTesting(content: "Updated")
        #expect(controller.commitMainMenuEditorForTesting())
        #expect(updatedText == "Updated")
        #expect(controller.mainMenuEditorContentForTesting == nil)
    }

    @Test
    func historyInlineEditorRejectsBlankAndEscapeDiscardsDraft() throws {
        let historyID = PasteboardHistory.ID(rawValue: "history-1")
        let detail = PasteboardHistoryDetail(
            history: PasteboardHistory(
                id: historyID,
                title: "Original",
                pasteboardTypes: [.string],
                updateAt: 1,
                deviceID: nil
            ),
            thumbnailAsset: nil
        )
        var updatedText: String?
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: { [] },
            onOpenHistory: {},
            onOpenSnippets: {},
            historyDataSource: makeHistoryDataSource(
                detail: detail,
                fetchEditableText: { id in id == historyID ? "Original" : nil },
                updateTextHistory: { id, text in
                    guard id == historyID else { return false }
                    updatedText = text
                    return true
                }
            )
        )

        controller.show(at: NSPoint(x: 100, y: 100))
        defer { controller.close() }

        controller.beginEditingHistoryForTesting(id: historyID)
        controller.updateMainMenuEditorDraftForTesting(content: "   \n")
        #expect(!controller.commitMainMenuEditorForTesting())
        #expect(updatedText == nil)
        #expect(controller.mainMenuEditorContentForTesting == "   \n")
        #expect(controller.mainMenuEditorErrorForTesting != nil)

        controller.updateMainMenuEditorDraftForTesting(content: "Should not save")
        #expect(controller.handleMainMenuNavigationForTesting(try makeEscapeEvent()))
        #expect(updatedText == nil)
        #expect(controller.mainMenuEditorContentForTesting == nil)
    }

    @Test
    func snippetFolderEditorCommitsOnReturnAndKeepsDuplicateDraft() throws {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let snippetID = Snippet.ID(rawValue: UUID())
        let detail = SnippetFolderDetail(
            folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
            snippets: [
                Snippet(id: snippetID, folderID: folderID, title: "Ask GPT", content: "Summarize", index: 0, isEnabled: true)
            ]
        )
        var updatedFolderTitle: String?
        var updatedSnippetTitle: String?
        var updatedSnippetContent: String?
        let controller = makeSnippetController(
            details: [detail],
            updateFolderTitle: { id, title in
                guard id == folderID else { return false }
                guard title != "Duplicate" else { return false }
                updatedFolderTitle = title
                return true
            },
            updateSnippetTitle: { id, title in
                guard id == snippetID else { return }
                updatedSnippetTitle = title
            },
            updateSnippetContent: { id, content in
                guard id == snippetID else { return false }
                updatedSnippetContent = content
                return true
            }
        )

        controller.show(at: NSPoint(x: 100, y: 100))
        defer { controller.close() }
        controller.openSnippetsFromMainMenu()

        controller.beginEditingSnippetFolderForTesting(id: folderID)
        controller.updateMainMenuEditorDraftForTesting(title: "Duplicate")
        #expect(controller.handleMainMenuNavigationForTesting(try makeReturnEvent()))
        #expect(updatedFolderTitle == nil)
        #expect(controller.mainMenuEditorTitleForTesting == "Duplicate")
        #expect(controller.mainMenuEditorErrorForTesting != nil)

        controller.updateMainMenuEditorDraftForTesting(title: "Renamed")
        #expect(controller.handleMainMenuNavigationForTesting(try makeReturnEvent()))
        #expect(updatedFolderTitle == "Renamed")
        #expect(controller.mainMenuEditorTitleForTesting == nil)
    }

    @Test
    func snippetContentUsesCommandReturnToCommitAndPlainReturnKeepsEditing() throws {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let snippetID = Snippet.ID(rawValue: UUID())
        let detail = SnippetFolderDetail(
            folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
            snippets: [
                Snippet(id: snippetID, folderID: folderID, title: "Ask GPT", content: "Summarize", index: 0, isEnabled: true)
            ]
        )
        var updatedSnippetTitle: String?
        var updatedSnippetContent: String?
        let controller = makeSnippetController(
            details: [detail],
            updateSnippetTitle: { id, title in
                guard id == snippetID else { return }
                updatedSnippetTitle = title
            },
            updateSnippetContent: { id, content in
                guard id == snippetID else { return false }
                updatedSnippetContent = content
                return true
            }
        )

        controller.show(at: NSPoint(x: 100, y: 100))
        defer { controller.close() }
        controller.openSnippetsFromMainMenu()

        controller.beginEditingSnippetForTesting(id: snippetID)
        controller.updateMainMenuEditorDraftForTesting(title: "Better Ask", content: "New content")

        #expect(!controller.handleMainMenuNavigationForTesting(try makeReturnEvent()))
        #expect(updatedSnippetTitle == nil)
        #expect(updatedSnippetContent == nil)
        #expect(controller.mainMenuEditorContentForTesting == "New content")

        #expect(controller.handleMainMenuNavigationForTesting(try makeCommandReturnEvent()))
        #expect(updatedSnippetTitle == "Better Ask")
        #expect(updatedSnippetContent == "New content")
        #expect(controller.mainMenuEditorContentForTesting == nil)
    }

    @Test
    func snippetInlineEditorKeepsDraftWhenContentIsRejected() {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let snippetID = Snippet.ID(rawValue: UUID())
        let detail = SnippetFolderDetail(
            folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
            snippets: [
                Snippet(id: snippetID, folderID: folderID, title: "Ask GPT", content: "Summarize", index: 0, isEnabled: true)
            ]
        )
        var updatedSnippetTitle: String?
        let controller = makeSnippetController(
            details: [detail],
            updateSnippetTitle: { _, title in updatedSnippetTitle = title },
            updateSnippetContent: { _, _ in false }
        )

        controller.show(at: NSPoint(x: 100, y: 100))
        defer { controller.close() }
        controller.openSnippetsFromMainMenu()

        controller.beginEditingSnippetForTesting(id: snippetID)
        controller.updateMainMenuEditorDraftForTesting(title: "Better Ask", content: "Duplicate")
        #expect(!controller.commitMainMenuEditorForTesting())

        #expect(updatedSnippetTitle == nil)
        #expect(controller.mainMenuEditorTitleForTesting == "Better Ask")
        #expect(controller.mainMenuEditorContentForTesting == "Duplicate")
        #expect(controller.mainMenuEditorErrorForTesting != nil)
    }

    private func makeHistoryDataSource(
        detail: PasteboardHistoryDetail,
        fetchPage: (() -> HistoryMenuPage)? = nil,
        fetchEditableText: @escaping (PasteboardHistory.ID) -> String? = { _ in nil },
        updateTextHistory: @escaping (PasteboardHistory.ID, String) -> Bool = { _, _ in false }
    ) -> MainMenuHistoryDataSource {
        var state = HistoryMenuPaginationState()
        return MainMenuHistoryDataSource(
            currentState: { state },
            updateState: { update in update(&state) },
            fetchPage: {
                fetchPage?() ?? HistoryMenuPage.result([detail], pageSize: 10)
            },
            makeRowView: { detail, _, onConfirm in
                HistoryMenuRowView(title: detail.history.title, image: nil, onConfirm: onConfirm)
            },
            selectHistory: { _, _ in },
            fetchEditableText: fetchEditableText,
            updateTextHistory: updateTextHistory
        )
    }

    private func makeSnippetController(
        details: [SnippetFolderDetail],
        selectSnippet: @escaping (Snippet.ID, PasteTargetContext?) -> Void = { _, _ in },
        updateFolderTitle: @escaping (SnippetFolder.ID, String) -> Bool = { _, _ in false },
        updateSnippetTitle: @escaping (Snippet.ID, String) -> Void = { _, _ in },
        updateSnippetContent: @escaping (Snippet.ID, String) -> Bool = { _, _ in false },
        deleteFolder: @escaping (SnippetFolder.ID) -> Void = { _ in },
        deleteSnippet: @escaping (Snippet.ID) -> Void = { _ in },
        folderKeyCombo: @escaping (SnippetFolder.ID) -> KeyCombo? = { _ in nil },
        updateFolderKeyCombo: @escaping (SnippetFolder.ID, KeyCombo) -> Void = { _, _ in },
        clearFolderKeyCombo: @escaping (SnippetFolder.ID) -> Void = { _ in }
    ) -> MainMenuPanelController {
        makeSnippetController(
            fetchFolderDetails: { details },
            selectSnippet: selectSnippet,
            updateFolderTitle: updateFolderTitle,
            updateSnippetTitle: updateSnippetTitle,
            updateSnippetContent: updateSnippetContent,
            deleteFolder: deleteFolder,
            deleteSnippet: deleteSnippet,
            folderKeyCombo: folderKeyCombo,
            updateFolderKeyCombo: updateFolderKeyCombo,
            clearFolderKeyCombo: clearFolderKeyCombo
        )
    }

    private func makeSnippetController(
        fetchFolderDetails: @escaping () -> [SnippetFolderDetail],
        selectSnippet: @escaping (Snippet.ID, PasteTargetContext?) -> Void = { _, _ in },
        updateFolderTitle: @escaping (SnippetFolder.ID, String) -> Bool = { _, _ in false },
        updateSnippetTitle: @escaping (Snippet.ID, String) -> Void = { _, _ in },
        updateSnippetContent: @escaping (Snippet.ID, String) -> Bool = { _, _ in false },
        deleteFolder: @escaping (SnippetFolder.ID) -> Void = { _ in },
        deleteSnippet: @escaping (Snippet.ID) -> Void = { _ in },
        folderKeyCombo: @escaping (SnippetFolder.ID) -> KeyCombo? = { _ in nil },
        updateFolderKeyCombo: @escaping (SnippetFolder.ID, KeyCombo) -> Void = { _, _ in },
        clearFolderKeyCombo: @escaping (SnippetFolder.ID) -> Void = { _ in }
    ) -> MainMenuPanelController {
        MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: { [] },
            onOpenHistory: {},
            onOpenSnippets: {},
            snippetDataSource: MainMenuSnippetDataSource(
                fetchFolderDetails: fetchFolderDetails,
                fetchFolderDetail: { id in fetchFolderDetails().first { $0.folder.id == id } },
                selectSnippet: selectSnippet,
                updateFolderTitle: updateFolderTitle,
                updateSnippetTitle: updateSnippetTitle,
                updateSnippetContent: updateSnippetContent,
                deleteFolder: deleteFolder,
                deleteSnippet: deleteSnippet,
                folderKeyCombo: folderKeyCombo,
                updateFolderKeyCombo: updateFolderKeyCombo,
                clearFolderKeyCombo: clearFolderKeyCombo
            )
        )
    }

    private func makeReturnEvent() throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ))
    }

    private func makeCommandReturnEvent() throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ))
    }

    private func makeCommandFEvent() throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "f",
            charactersIgnoringModifiers: "f",
            isARepeat: false,
            keyCode: 3
        ))
    }

    private func makeControlSpaceEvent() throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.control],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: 49
        ))
    }

    private func mainMenuSearchField() -> NSSearchField? {
        NSApp.windows.lazy.compactMap { searchField(in: $0.contentView) }.first
    }

    private func searchField(in view: NSView?) -> NSSearchField? {
        guard let view else { return nil }
        if let searchField = view as? NSSearchField,
           searchField.identifier?.rawValue == "mainMenuSearchField" {
            return searchField
        }
        for subview in view.subviews {
            if let searchField = searchField(in: subview) {
                return searchField
            }
        }
        return nil
    }

    private func makeCommandCommaEvent() throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: ",",
            charactersIgnoringModifiers: ",",
            isARepeat: false,
            keyCode: 43
        ))
    }

    private func makeCommandDEvent() throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "d",
            charactersIgnoringModifiers: "d",
            isARepeat: false,
            keyCode: 2
        ))
    }

    private func makeTextEvent(_ text: String, keyCode: UInt16) throws -> NSEvent {
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

    private func makeLeftArrowEvent() throws -> NSEvent {
        try makeArrowEvent(keyCode: 123, modifierFlags: [])
    }

    private func makeArrowEvent(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) throws -> NSEvent {
        let character = keyCode == 123 ? NSLeftArrowFunctionKey : NSRightArrowFunctionKey
        let text = String(UnicodeScalar(character)!)
        return try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: text,
            charactersIgnoringModifiers: text,
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    private func makeEscapeEvent() throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        ))
    }

    private func withMenuTitlesStartingAtOne(operation: () throws -> Void) rethrows {
        try withMenuTitles(startingAtZero: false, operation: operation)
    }

    private func withMenuTitlesStartingAtZero(operation: () throws -> Void) rethrows {
        try withMenuTitles(startingAtZero: true, operation: operation)
    }

    private func withMenuTitles(startingAtZero: Bool, operation: () throws -> Void) rethrows {
        let defaults = AppEnvironment.current.defaults
        let key = Constants.UserDefaults.menuItemsTitleStartWithZero
        let previousValue = defaults.object(forKey: key)
        defaults.set(startingAtZero, forKey: key)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        try operation()
    }
}
