//
//  MenuPanelSelectionDismissalTests.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Codex on 2026/06/08.
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
struct MenuPanelSelectionDismissalTests {
    @Test
    func selectingHistoryItemDismissesMainMenuPanel() throws {
        let historyID = PasteboardHistory.ID("history-1")
        let history = PasteboardHistory(
            id: historyID,
            title: "First History",
            pasteboardTypes: [.string],
            updateAt: 1,
            deviceID: CPYUtilities.deviceID
        )

        try withDependencies {
            $0.pasteboardHistoryRepository = StaticHistoryRepository(details: [
                PasteboardHistoryDetail(history: history, thumbnailAsset: nil)
            ])
            $0.snippetRepository = StaticSelectionSnippetRepository(details: [])
        } operation: {
            let manager = MenuManager()
            manager.popUpMenu(.main)
            manager.showHistoryBrowserPanelForTesting(at: NSPoint(x: 120, y: 480))
            defer { manager.closeMainMenuPanelForTesting() }

            #expect(manager.isMainMenuPanelVisibleForTesting)
            #expect(manager.historyBrowserPanelFrameForTesting != nil)

            manager.confirmFirstHistoryForTesting()

            #expect(!manager.isMainMenuPanelVisibleForTesting)
            #expect(manager.historyBrowserPanelFrameForTesting == nil)
        }
    }

    @Test
    func selectingSnippetItemDismissesMainMenuPanel() throws {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let snippetID = Snippet.ID(rawValue: UUID())
        let detail = SnippetFolderDetail(
            folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
            snippets: [
                Snippet(
                    id: snippetID,
                    folderID: folderID,
                    title: "Ask GPT",
                    content: "Summarize this",
                    index: 0,
                    isEnabled: true
                )
            ]
        )

        try withDependencies {
            $0.snippetRepository = StaticSelectionSnippetRepository(details: [detail])
        } operation: {
            let manager = MenuManager()
            manager.popUpMenu(.main)
            manager.showSnippetFolderPanelForTesting(folderID)
            defer { manager.closeMainMenuPanelForTesting() }

            #expect(manager.isMainMenuPanelVisibleForTesting)
            #expect(manager.snippetBrowserPanelFrameForTesting != nil)

            manager.confirmFirstSnippetForTesting()

            #expect(!manager.isMainMenuPanelVisibleForTesting)
            #expect(manager.snippetBrowserPanelFrameForTesting == nil)
        }
    }
}

private struct StaticHistoryRepository: PasteboardHistoryRepositoryProtocol {
    let details: [PasteboardHistoryDetail]

    func observeHistories() -> AnyPublisher<[PasteboardHistory], Never> {
        Just(details.map(\.history)).eraseToAnyPublisher()
    }

    func hasHistories() -> Bool { !details.isEmpty }
    func fetchHistoryDetails(ascending: Bool, includesThumbnailAsset: Bool, limit: Int, offset: Int) -> [PasteboardHistoryDetail] { details }
    func searchHistoryDetails(query: HistorySearchQuery, includesThumbnailAsset: Bool, limit: Int, offset: Int) throws -> [PasteboardHistoryDetail] { details }
    func fetchHistory(id: PasteboardHistory.ID) -> PasteboardHistory? { details.map(\.history).first { $0.id == id } }
    func fetchContent(id: PasteboardHistory.ID) -> PasteboardContent? { nil }
    func save(id: PasteboardHistory.ID, content: PasteboardContent, updateAt: Int) {}
    func deleteHistory(id: PasteboardHistory.ID) {}
    func deleteAll() {}
    func deleteOverflowingHistories(maxHistorySize: Int) {}
    func pruneHistories(settings: HistoryRetentionSettings) {}
}

private struct StaticSelectionSnippetRepository: SnippetRepositoryProtocol {
    let details: [SnippetFolderDetail]

    func observeFolderDetails() -> AnyPublisher<[SnippetFolderDetail], Never> {
        Just(details).eraseToAnyPublisher()
    }

    func fetchFolderDetails() -> [SnippetFolderDetail] { details }

    func fetchFolderDetail(id: SnippetFolder.ID) -> SnippetFolderDetail? {
        details.first { $0.folder.id == id }
    }

    func fetchSyncSnapshot() -> SnippetSyncSnapshot { SnippetSyncSnapshot(folders: [], snippets: []) }
    func insertFolder() -> SnippetFolder? { nil }
    func insertFolders(_ folders: [(title: String, snippets: [(title: String, content: String)])]) -> [SnippetFolderDetail]? { nil }
    func upsertSyncSnapshot(_ snapshot: SnippetSyncSnapshot) {}
    func mergeSyncTombstones(_ records: [SyncRecord]) {}
    func updateFolderTitle(_ id: SnippetFolder.ID, title: String) {}
    func updateFolderIsEnabled(_ id: SnippetFolder.ID, isEnabled: Bool) {}
    func updateFolderIndexes(_ folderIDs: [SnippetFolder.ID]) {}
    func deleteFolder(_ id: SnippetFolder.ID) {}
    func fetchSnippet(id: Snippet.ID) -> Snippet? { details.flatMap(\.snippets).first { $0.id == id } }
    func insertSnippet(to id: SnippetFolder.ID) -> Snippet? { nil }
    func updateSnippetTitle(_ id: Snippet.ID, title: String) {}
    func updateSnippetContent(_ id: Snippet.ID, content: String) {}
    func updateSnippetIsEnabled(_ id: Snippet.ID, isEnabled: Bool) {}
    func updateSnippetIndexes(_ snippetIDs: [Snippet.ID]) {}
    func moveSnippet(_ id: Snippet.ID, to folderID: SnippetFolder.ID, snippetIDs: [Snippet.ID]) {}
    func deleteSnippet(_ id: Snippet.ID) {}
}
