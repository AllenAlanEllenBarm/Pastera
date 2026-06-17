//
//  SnippetBrowserHotPathPerformanceTests.swift
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
struct SnippetBrowserHotPathPerformanceTests {
    @Test
    func folderListUsesFoldersProviderWithoutFetchingSnippetDetails() {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let folder = SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true)
        let detail = SnippetFolderDetail(
            folder: folder,
            snippets: [
                Snippet(
                    id: Snippet.ID(rawValue: UUID()),
                    folderID: folderID,
                    title: "Ask GPT",
                    content: String(repeating: "large payload", count: 1000),
                    index: 0,
                    isEnabled: true
                )
            ]
        )
        var fetchFoldersCount = 0
        var fetchFolderDetailCount = 0
        let controller = SnippetBrowserPanelController(
            fetchFolders: {
                fetchFoldersCount += 1
                return [folder]
            },
            fetchFolderDetail: { id in
                fetchFolderDetailCount += 1
                return id == folderID ? detail : nil
            },
            selectSnippet: { _, _ in }
        )

        controller.show(attachedTo: NSRect(x: 120, y: 420, width: MainMenuPanelLayout.width, height: 220))
        defer { controller.close() }

        #expect(controller.rowTitlesForTesting == ["AI Prompt"])
        #expect(fetchFoldersCount == 1)
        #expect(fetchFolderDetailCount == 0)
    }

    @Test
    func openingFolderFetchesOnlyThatFolderDetail() {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let otherFolderID = SnippetFolder.ID(rawValue: UUID())
        let snippet = Snippet(
            id: Snippet.ID(rawValue: UUID()),
            folderID: folderID,
            title: "Ask GPT",
            content: "Summarize this",
            index: 0,
            isEnabled: true
        )
        let detail = SnippetFolderDetail(
            folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
            snippets: [snippet]
        )
        var fetchedFolderIDs = [SnippetFolder.ID]()
        let controller = SnippetBrowserPanelController(
            fetchFolders: { [] },
            fetchFolderDetail: { id in
                fetchedFolderIDs.append(id)
                return id == folderID ? detail : nil
            },
            selectSnippet: { _, _ in }
        )

        controller.show(folderID: folderID, attachedTo: NSRect(x: 120, y: 420, width: MainMenuPanelLayout.width, height: 220))
        defer { controller.close() }

        #expect(controller.rowTitlesForTesting == ["Ask GPT"])
        #expect(fetchedFolderIDs == [folderID])
        #expect(!fetchedFolderIDs.contains(otherFolderID))
    }

    @Test
    func mainMenuSnippetFolderRowsUseFolderMetadataWithoutFetchingDetails() {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let folder = SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true)
        let repository = CountingSnippetRepository(folders: [folder], details: [])

        let titles = withDependencies {
            $0.snippetRepository = repository
        } operation: {
            MenuManager().mainMenuSnippetTitlesForTesting
        }

        #expect(titles == ["AI Prompt"])
        #expect(repository.fetchFoldersCallCount == 1)
        #expect(repository.fetchFolderDetailsCallCount == 0)
    }
}

private final class CountingSnippetRepository: SnippetRepositoryProtocol {
    let folders: [SnippetFolder]
    let details: [SnippetFolderDetail]
    private(set) var fetchFoldersCallCount = 0
    private(set) var fetchFolderDetailsCallCount = 0

    init(folders: [SnippetFolder], details: [SnippetFolderDetail]) {
        self.folders = folders
        self.details = details
    }

    func observeFolderDetails() -> AnyPublisher<[SnippetFolderDetail], Never> {
        Just(details).eraseToAnyPublisher()
    }

    func fetchFolders() -> [SnippetFolder] {
        fetchFoldersCallCount += 1
        return folders
    }

    func fetchFolderDetails() -> [SnippetFolderDetail] {
        fetchFolderDetailsCallCount += 1
        return details
    }

    func fetchFolderDetail(id: SnippetFolder.ID) -> SnippetFolderDetail? {
        details.first { $0.folder.id == id }
    }

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
