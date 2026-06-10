//
//  SnippetHotkeyPanelEntrypointTests.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Codex on 2026/06/10.
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
struct SnippetHotkeyPanelEntrypointTests {
    @Test
    func displaysEnabledFoldersWhenShownStandaloneFromGlobalSnippetHotkey() {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let detail = SnippetFolderDetail(
            folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
            snippets: []
        )
        let controller = SnippetBrowserPanelController(
            fetchDetails: { [detail] },
            selectSnippet: { _, _ in }
        )

        controller.show(at: NSPoint(x: 120, y: 420))
        defer { controller.close() }

        #expect(controller.rowTitlesForTesting == ["AI Prompt"])
        #expect(controller.isVisibleForTesting)
    }

    @Test
    func opensFolderWhenShownStandaloneFromFolderHotkey() throws {
        try withNumericShortcutDefaults(enabled: true, startsAtZero: false) {
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
            let controller = SnippetBrowserPanelController(
                fetchDetails: { [detail] },
                selectSnippet: { _, _ in }
            )

            controller.show(folderID: folderID, at: NSPoint(x: 120, y: 420))
            defer { controller.close() }

            #expect(controller.rowTitlesForTesting == ["Ask GPT"])
            #expect(controller.rowShortcutTextsForTesting == ["1"])
            #expect(controller.rowShortcutStylesForTesting == [.itemNumber])
            #expect(!controller.rowTextValuesForTesting.flatMap { $0 }.contains("Summarize this"))
            #expect(controller.isVisibleForTesting)
        }
    }

    @Test
    func globalSnippetMenuHotkeyShowsStandaloneSnippetPanel() {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let detail = SnippetFolderDetail(
            folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
            snippets: []
        )

        withDependencies {
            $0.snippetRepository = HotkeyPanelStaticSnippetRepository(details: [detail])
        } operation: {
            let manager = MenuManager()
            manager.popUpMenu(.snippet)
            defer { manager.closeSnippetBrowserPanelForTesting() }

            #expect(manager.snippetBrowserPanelFrameForTesting != nil)
            #expect(manager.snippetBrowserRowTitlesForTesting == ["AI Prompt"])
        }
    }

    @Test
    func folderHotkeyShowsStandaloneSnippetPanel() throws {
        try withNumericShortcutDefaults(enabled: true, startsAtZero: false) {
            let folderID = SnippetFolder.ID(rawValue: UUID())
            let detail = SnippetFolderDetail(
                folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
                snippets: [
                    Snippet(
                        id: Snippet.ID(rawValue: UUID()),
                        folderID: folderID,
                        title: "Ask GPT",
                        content: "Summarize this",
                        index: 0,
                        isEnabled: true
                    )
                ]
            )

            withDependencies {
                $0.snippetRepository = HotkeyPanelStaticSnippetRepository(details: [detail])
            } operation: {
                let manager = MenuManager()
                manager.showSnippetFolderPanelForTesting(folderID, at: NSPoint(x: 120, y: 420))
                defer { manager.closeSnippetBrowserPanelForTesting() }

                #expect(manager.snippetBrowserPanelFrameForTesting != nil)
                #expect(manager.snippetBrowserRowTitlesForTesting == ["Ask GPT"])
                #expect(manager.snippetBrowserShortcutTextsForTesting == ["1"])
            }
        }
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

private struct HotkeyPanelStaticSnippetRepository: SnippetRepositoryProtocol {
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
