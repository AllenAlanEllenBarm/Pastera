//
//  DeleteShortcutTests.swift
//
//  Pastera
//

import AppKit
import Combine
import Dependencies
import Testing
@testable import Pastera

@MainActor
@Suite(.serialized)
struct DeleteShortcutTests {
    @Test
    func commandDDeletesHistoryRow() throws {
        var didDeleteFirstRow = false
        let firstRow = HistoryMenuRowView(
            title: "1. First",
            image: nil,
            onDelete: { didDeleteFirstRow = true },
            onConfirm: {}
        )

        #expect(firstRow.performKeyEquivalent(with: try makeCommandD()))
        #expect(didDeleteFirstRow)
    }

    @Test
    func snippetEditorCommandDDeletesSelectedItemAfterConfirmation() throws {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        let snippetID = Snippet.ID(rawValue: UUID())
        let detail = SnippetFolderDetail(
            folder: SnippetFolder(id: folderID, title: "AI Prompt", index: 0, isEnabled: true),
            snippets: [
                Snippet(
                    id: snippetID,
                    folderID: folderID,
                    title: "test1",
                    content: "value",
                    index: 0,
                    isEnabled: true
                )
            ]
        )
        var deletedSnippetID: Snippet.ID?
        var usedSnippetWindowAsSource = false
        let commandD = try makeCommandD()

        withDependencies {
            $0.snippetRepository = DeleteShortcutSnippetRepository(
                details: [detail],
                onDeleteSnippet: { id in deletedSnippetID = id }
            )
        } operation: {
            let controller = CPYSnippetsEditorWindowController()
            defer { controller.close() }

            controller.showWindow(nil)
            controller.selectSnippetForTesting(id: snippetID)
            controller.setDeleteConfirmationRunnerForTesting { options, sourceWindow in
                usedSnippetWindowAsSource = sourceWindow === controller.window
                #expect(options.title == String(localized: "Delete Item"))
                #expect(options.isDestructive)
                return PasteraConfirmationResult(confirmed: true, suppressionChecked: false)
            }

            #expect(controller.handleSnippetEditorKeyboardEventForTesting(commandD))
            #expect(deletedSnippetID == snippetID)
            #expect(usedSnippetWindowAsSource)
        }
    }

    private func makeCommandD() throws -> NSEvent {
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
}

private struct DeleteShortcutSnippetRepository: SnippetRepositoryProtocol {
    var details: [SnippetFolderDetail]
    var onDeleteSnippet: (Snippet.ID) -> Void = { _ in }

    func observeFolderDetails() -> AnyPublisher<[SnippetFolderDetail], Never> {
        Just(details).eraseToAnyPublisher()
    }

    func fetchFolderDetails() -> [SnippetFolderDetail] { details }
    func fetchFolderDetail(id: SnippetFolder.ID) -> SnippetFolderDetail? { details.first { $0.folder.id == id } }
    func fetchSyncSnapshot() -> SnippetSyncSnapshot { SnippetSyncSnapshot(folders: [], snippets: []) }
    func insertFolder() -> SnippetFolder? { nil }
    func insertFolders(_ folders: [(title: String, snippets: [(title: String, content: String)])]) -> [SnippetFolderDetail]? { nil }
    func upsertSyncSnapshot(_ snapshot: SnippetSyncSnapshot) -> Int { 0 }
    func removeDuplicateFoldersAndSnippets() -> Int { 0 }
    func updateFolderTitle(_ id: SnippetFolder.ID, title: String) -> Bool { true }
    func updateFolderIsEnabled(_ id: SnippetFolder.ID, isEnabled: Bool) {}
    func updateFolderIndexes(_ folderIDs: [SnippetFolder.ID]) {}
    func deleteFolder(_ id: SnippetFolder.ID) {}
    func fetchSnippet(id: Snippet.ID) -> Snippet? { details.flatMap(\.snippets).first { $0.id == id } }
    func insertSnippet(to id: SnippetFolder.ID) -> Snippet? { nil }
    func updateSnippetTitle(_ id: Snippet.ID, title: String) {}
    func updateSnippetContent(_ id: Snippet.ID, content: String) -> Bool { true }
    func updateSnippetIsEnabled(_ id: Snippet.ID, isEnabled: Bool) {}
    func updateSnippetIndexes(_ snippetIDs: [Snippet.ID]) {}
    func moveSnippet(_ id: Snippet.ID, to folderID: SnippetFolder.ID, snippetIDs: [Snippet.ID]) {}
    func deleteSnippet(_ id: Snippet.ID) { onDeleteSnippet(id) }
}
