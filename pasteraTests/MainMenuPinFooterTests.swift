//
//  MainMenuPinFooterTests.swift
//
//  Clipy
//

import AppKit
import Combine
import Dependencies
import Testing
@testable import Pastera

@MainActor
@Suite(.serialized)
struct MainMenuPinFooterTests {
    @Test
    func mainMenuPanelAlignsPinControlWithQuitRow() throws {
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: {
                [
                    .snippetFolder(title: "AI Prompt", image: nil, shortcutText: "⌃⌥⌘1") { _ in },
                    .separator,
                    .action(title: "Quit Pastera", image: nil) {}
                ]
            },
            onOpenHistory: {},
            onOpenSnippets: {},
            onPinnedChange: { _ in }
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: false)
        defer { controller.close() }

        let pinFrames = controller.mainMenuPinButtonFramesForTesting
        #expect(pinFrames.count == 1)
        let pinFrame = try #require(pinFrames.first)
        let folderRowFrame = try #require(controller.mainMenuSnippetRowFrameForTesting(title: "AI Prompt"))
        let folderTitleFrame = try #require(controller.mainMenuSnippetTitleFrameForTesting(title: "AI Prompt"))
        let quitRowFrame = try #require(controller.mainMenuActionRowFrameForTesting(title: "Quit Pastera"))

        #expect(pinFrame.maxX <= MainMenuPanelLayout.width - MainMenuPanelLayout.pinTrailingInset)
        #expect(abs(pinFrame.midY - quitRowFrame.midY) <= 1)
        #expect(MainMenuPanelLayout.headerHeight == 32)
        #expect(MainMenuPanelLayout.snippetFolderRowHeight == 26)
        #expect(folderRowFrame.height == MainMenuPanelLayout.snippetFolderRowHeight)
        #expect(quitRowFrame.height == MainMenuPanelLayout.rowHeight)
        #expect(abs(folderTitleFrame.midY - MainMenuPanelLayout.snippetFolderRowHeight / 2) <= 1)
        #expect(controller.visibleFrame?.height == expectedMainMenuHeight(
            snippetFolderCount: 1,
            actionRowCount: 1,
            separatorCount: 2
        ))
    }

    @Test
    func mainMenuKeepsReadableFolderTitleAtCompactWidth() throws {
        let folderImage = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            historyShortcutText: "⌃⌘V",
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: {
                [
                    .snippetFolder(title: "AI Prompt", image: folderImage, shortcutText: "⌃⌥⌘1") { _ in },
                    .separator,
                    .action(title: "Quit Pastera", image: nil) {}
                ]
            },
            onOpenHistory: {},
            onOpenSnippets: {},
            onPinnedChange: { _ in }
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: false)
        defer { controller.close() }

        let titleAvailableWidth = try #require(
            controller.mainMenuSnippetTitleAvailableWidthForTesting(title: "AI Prompt")
        )
        let quitTitleAvailableWidth = try #require(
            controller.mainMenuActionTitleAvailableWidthForTesting(title: "Quit Pastera")
        )

        #expect(MainMenuPanelLayout.width == 168)
        #expect(titleAvailableWidth >= menuTitleWidth("AI Prompt"))
        #expect(quitTitleAvailableWidth >= menuTitleWidth("Quit Pastera"))
    }

    @Test
    func visibleMainMenuPanelBackgroundFollowsOpacityChange() throws {
        let suiteName = "MainMenuPinFooterTests.opacity.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(0.94, forKey: Constants.UserDefaults.windowBackgroundOpacity)
        AppEnvironment.push(defaults: defaults)
        defer { _ = AppEnvironment.popLast() }

        try withDependencies {
            $0.mainQueue = .immediate
            $0.pasteboardHistoryRepository = MainMenuEmptyHistoryRepository()
            $0.snippetRepository = MainMenuEmptySnippetRepository()
        } operation: {
            let manager = MenuManager()
            manager.setup()
            manager.showMainMenuPanelForTesting(at: NSPoint(x: 180, y: 700))
            defer {
                manager.closeMainMenuPanelForTesting()
                manager.removeStatusItemForTesting()
            }

            #expect(abs((manager.mainMenuPanelBackgroundAlphaForTesting ?? 0) - 0.94) < 0.001)

            CPYWindowAppearance.setOpacity(0.82, defaults: defaults)

            #expect(abs((manager.mainMenuPanelBackgroundAlphaForTesting ?? 0) - 0.82) < 0.001)
        }
    }

    @Test
    func mainMenuDoesNotShowClearHistoryAction() throws {
        let suiteName = "MainMenuPinFooterTests.clearHistory.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: Constants.UserDefaults.addClearHistoryMenuItem)
        AppEnvironment.push(defaults: defaults)
        defer { _ = AppEnvironment.popLast() }

        let titles = withDependencies {
            $0.snippetRepository = MainMenuEmptySnippetRepository()
        } operation: {
            MenuManager().mainMenuPanelActionTitlesForTesting
        }

        #expect(!titles.contains(String(localized: "Clear History")))
        #expect(titles.contains(String(localized: "Edit Snippets")))
        #expect(titles.contains(String(localized: "Preferences")))
    }

    @Test
    func mainMenuFooterPinTogglesWithoutOpeningHistory() {
        var didOpenHistory = false
        var pinnedValues = [Bool]()
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: { [] },
            onOpenHistory: { didOpenHistory = true },
            onOpenSnippets: {},
            onPinnedChange: { pinnedValues.append($0) }
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: false)
        defer { controller.close() }

        controller.performMainMenuPinClickForTesting()

        #expect(pinnedValues == [true])
        #expect(!didOpenHistory)
    }

    @Test
    func downArrowFromHoveredHistorySelectsSnippetFolderAndOpensIt() throws {
        var openHistoryCount = 0
        var openedSnippetTitles = [String]()
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: {
                [
                    .snippetFolder(title: "AI Prompt", image: nil) { _ in
                        openedSnippetTitles.append("AI Prompt")
                    },
                    .separator,
                    .action(title: "Quit Pastera", image: nil) {}
                ]
            },
            onOpenHistory: { openHistoryCount += 1 },
            onOpenSnippets: {},
            onPinnedChange: { _ in }
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: true)
        defer { controller.close() }
        controller.selectMainMenuItemForTesting(title: "History")

        #expect(controller.handleMainMenuNavigationForTesting(try makeArrowEvent(keyCode: 125)))

        #expect(controller.selectedMainMenuTitleForTesting == "AI Prompt")
        #expect(openHistoryCount == 0)
        #expect(openedSnippetTitles == ["AI Prompt"])
    }

    @Test
    func upArrowFromHoveredSnippetFolderSelectsHistoryAndOpensIt() throws {
        var openHistoryCount = 0
        var openedSnippetCount = 0
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: {
                [
                    .snippetFolder(title: "AI Prompt", image: nil) { _ in
                        openedSnippetCount += 1
                    },
                    .separator,
                    .action(title: "Quit Pastera", image: nil) {}
                ]
            },
            onOpenHistory: { openHistoryCount += 1 },
            onOpenSnippets: {},
            onPinnedChange: { _ in }
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: true)
        defer { controller.close() }
        controller.selectMainMenuItemForTesting(title: "AI Prompt")

        #expect(controller.handleMainMenuNavigationForTesting(try makeArrowEvent(keyCode: 126)))

        #expect(controller.selectedMainMenuTitleForTesting == "History")
        #expect(openHistoryCount == 1)
        #expect(openedSnippetCount == 0)
    }

    @Test
    func returnKeyConfirmsSelectedHistoryRow() throws {
        var openHistoryCount = 0
        var openedSnippetCount = 0
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: {
                [
                    .snippetFolder(title: "AI Prompt", image: nil) { _ in
                        openedSnippetCount += 1
                    },
                    .separator,
                    .action(title: "Quit Pastera", image: nil) {}
                ]
            },
            onOpenHistory: { openHistoryCount += 1 },
            onOpenSnippets: {},
            onPinnedChange: { _ in }
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: true)
        defer { controller.close() }
        controller.selectMainMenuItemForTesting(title: "History")

        #expect(controller.handleMainMenuNavigationForTesting(try makeKeyboardEvent(keyCode: 36, characters: "\r")))

        #expect(openHistoryCount == 1)
        #expect(openedSnippetCount == 0)
        #expect(controller.selectedMainMenuTitleForTesting == "History")
    }

    @Test
    func spaceKeyConfirmsSelectedSnippetFolderRow() throws {
        var openHistoryCount = 0
        var openedSnippetTitles = [String]()
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: {
                [
                    .snippetFolder(title: "AI Prompt", image: nil) { _ in
                        openedSnippetTitles.append("AI Prompt")
                    },
                    .separator,
                    .action(title: "Quit Pastera", image: nil) {}
                ]
            },
            onOpenHistory: { openHistoryCount += 1 },
            onOpenSnippets: {},
            onPinnedChange: { _ in }
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: true)
        defer { controller.close() }
        controller.selectMainMenuItemForTesting(title: "AI Prompt")

        #expect(controller.handleMainMenuNavigationForTesting(try makeKeyboardEvent(keyCode: 49, characters: " ")))

        #expect(openHistoryCount == 0)
        #expect(openedSnippetTitles == ["AI Prompt"])
        #expect(controller.selectedMainMenuTitleForTesting == "AI Prompt")
    }

    @Test
    func returnKeyConfirmsSelectedActionRow() throws {
        var didOpenHistory = false
        var didOpenSnippet = false
        var didSelectAction = false
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: {
                [
                    .snippetFolder(title: "AI Prompt", image: nil) { _ in
                        didOpenSnippet = true
                    },
                    .separator,
                    .action(title: "Preferences", image: nil) {
                        didSelectAction = true
                    }
                ]
            },
            onOpenHistory: { didOpenHistory = true },
            onOpenSnippets: {},
            onPinnedChange: { _ in }
        )

        controller.show(at: NSPoint(x: 180, y: 700), pinned: true)
        defer { controller.close() }
        controller.selectMainMenuItemForTesting(title: "Preferences")

        #expect(controller.handleMainMenuNavigationForTesting(try makeKeyboardEvent(keyCode: 36, characters: "\r")))

        #expect(didSelectAction)
        #expect(!didOpenHistory)
        #expect(!didOpenSnippet)
    }

    private func expectedMainMenuHeight(
        snippetFolderCount: Int,
        actionRowCount: Int,
        separatorCount: Int
    ) -> CGFloat {
        MainMenuPanelLayout.topInset
            + MainMenuPanelLayout.headerHeight
            + MainMenuPanelLayout.separatorHeight
            + MainMenuPanelLayout.separatorVerticalInset * 2
            + CGFloat(snippetFolderCount) * MainMenuPanelLayout.snippetFolderRowHeight
            + CGFloat(actionRowCount) * MainMenuPanelLayout.rowHeight
            + CGFloat(separatorCount - 1) * (
                MainMenuPanelLayout.separatorHeight
                    + MainMenuPanelLayout.separatorVerticalInset * 2
            )
            + MainMenuPanelLayout.bottomInset
    }

    private func menuTitleWidth(_ title: String) -> CGFloat {
        ceil((title as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 13.5, weight: .medium)
        ]).width)
    }

    private func makeArrowEvent(keyCode: UInt16) throws -> NSEvent {
        let characters: String
        switch keyCode {
        case 125:
            characters = "\u{F701}"
        case 126:
            characters = "\u{F700}"
        default:
            characters = ""
        }
        return try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    private func makeKeyboardEvent(keyCode: UInt16, characters: String) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
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

private struct MainMenuEmptyHistoryRepository: PasteboardHistoryRepositoryProtocol {
    func observeHistoryChanges() -> AnyPublisher<Void, Never> {
        Empty().eraseToAnyPublisher()
    }

    func observeHistories() -> AnyPublisher<[PasteboardHistory], Never> {
        Just([]).eraseToAnyPublisher()
    }

    func hasHistories() -> Bool { false }
    func fetchHistoryDetails(ascending: Bool, includesThumbnailAsset: Bool, limit: Int, offset: Int) -> [PasteboardHistoryDetail] { [] }
    func searchHistoryDetails(query: HistorySearchQuery, includesThumbnailAsset: Bool, limit: Int, offset: Int) throws -> [PasteboardHistoryDetail] { [] }
    func fetchHistory(id: PasteboardHistory.ID) -> PasteboardHistory? { nil }
    func fetchContent(id: PasteboardHistory.ID) -> PasteboardContent? { nil }
    func save(id: PasteboardHistory.ID, content: PasteboardContent, updateAt: Int) {}
    func deleteHistory(id: PasteboardHistory.ID) {}
    func deleteAll() {}
    func deleteOverflowingHistories(maxHistorySize: Int) {}
    func pruneHistories(settings: HistoryRetentionSettings) {}
}

private struct MainMenuEmptySnippetRepository: SnippetRepositoryProtocol {
    func observeFolders() -> AnyPublisher<[SnippetFolder], Never> {
        Empty().eraseToAnyPublisher()
    }

    func observeFolderDetails() -> AnyPublisher<[SnippetFolderDetail], Never> {
        Just([]).eraseToAnyPublisher()
    }

    func fetchFolders() -> [SnippetFolder] { [] }
    func fetchFolderDetails() -> [SnippetFolderDetail] { [] }
    func fetchFolderDetail(id: SnippetFolder.ID) -> SnippetFolderDetail? { nil }
    func fetchSyncSnapshot() -> SnippetSyncSnapshot { SnippetSyncSnapshot(folders: [], snippets: []) }
    func insertFolder() -> SnippetFolder? { nil }
    func insertFolders(_ folders: [(title: String, snippets: [(title: String, content: String)])]) -> [SnippetFolderDetail]? { nil }
    func upsertSyncSnapshot(_ snapshot: SnippetSyncSnapshot) -> Int { 0 }
    func mergeSyncTombstones(_ records: [SyncRecord]) {}
    func updateFolderTitle(_ id: SnippetFolder.ID, title: String) {}
    func updateFolderIsEnabled(_ id: SnippetFolder.ID, isEnabled: Bool) {}
    func updateFolderIndexes(_ folderIDs: [SnippetFolder.ID]) {}
    func deleteFolder(_ id: SnippetFolder.ID) {}
    func fetchSnippet(id: Snippet.ID) -> Snippet? { nil }
    func insertSnippet(to id: SnippetFolder.ID) -> Snippet? { nil }
    func updateSnippetTitle(_ id: Snippet.ID, title: String) {}
    func updateSnippetContent(_ id: Snippet.ID, content: String) {}
    func updateSnippetIsEnabled(_ id: Snippet.ID, isEnabled: Bool) {}
    func updateSnippetIndexes(_ snippetIDs: [Snippet.ID]) {}
    func moveSnippet(_ id: Snippet.ID, to folderID: SnippetFolder.ID, snippetIDs: [Snippet.ID]) {}
    func deleteSnippet(_ id: Snippet.ID) {}
}
