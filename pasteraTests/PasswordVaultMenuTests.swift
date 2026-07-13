import AppKit
import Foundation
import Testing
@testable import Pastera

@MainActor
@Suite("Password vault menu", .serialized)
struct PasswordVaultMenuTests {
    @Test("snippet mode matches vault folder styling and creates items inline")
    func snippetModeCreatesInlineWithoutRowIcons() {
        let folderID = SnippetFolder.ID(rawValue: UUID())
        var details = [SnippetFolderDetail(
            folder: SnippetFolder(id: folderID, title: "Work", index: 0, isEnabled: true),
            snippets: []
        )]
        let controller = MainMenuPanelController(
            historyTitle: "History", historyImage: nil, snippetTitle: "Snippet", snippetImage: NSImage(),
            itemsProvider: { [] }, onOpenHistory: {}, onOpenSnippets: {},
            snippetDataSource: MainMenuSnippetDataSource(
                fetchFolderDetails: { details },
                fetchFolderDetail: { id in details.first { $0.folder.id == id } },
                selectSnippet: { _, _ in },
                createFolder: { title in
                    let folder = SnippetFolder(id: .init(rawValue: UUID()), title: title, index: details.count, isEnabled: true)
                    details.append(SnippetFolderDetail(folder: folder, snippets: []))
                    return folder
                },
                createSnippet: { id, title, content in
                    let snippet = Snippet(id: .init(rawValue: UUID()), folderID: id, title: title, content: content, index: 0, isEnabled: true)
                    details[0] = SnippetFolderDetail(folder: details[0].folder, snippets: details[0].snippets + [snippet])
                    return snippet
                }
            )
        )
        controller.openSnippetsFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
        defer { _ = controller.close() }

        #expect(!controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuContextCreateButton"))
        #expect(controller.mainMenuRowHasImageForTesting(title: "Work"))

        controller.performMainMenuRowDoubleClickForTesting(title: "Work")
        #expect(controller.mainMenuEditorTitleForTesting == "Work")
        controller.discardMainMenuEditorForTesting()

        controller.toggleWorkspaceEditingForTesting()
        #expect(controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuContextCreateButton"))

        controller.beginCreatingSnippetForTesting()
        #expect(controller.mainMenuVisibleRowTitlesForTesting.contains("Work"))
        controller.updateMainMenuEditorDraftForTesting(title: "Deploy", content: "make release")
        #expect(controller.commitMainMenuEditorForTesting())
        #expect(details[0].snippets.map(\.title) == ["Deploy"])

        controller.beginCreatingSnippetFolderForTesting()
        controller.updateMainMenuEditorDraftForTesting(title: "Personal")
        #expect(controller.commitMainMenuEditorForTesting())
        #expect(details.map { $0.folder.title } == ["Work", "Personal"])
    }

    @Test("single-line Return saves and Escape cancels")
    func singleLineKeyboardActions() throws {
        var saved = 0
        var cancelled = 0
        let field = PasswordVaultReturnTextField()
        field.onReturn = { saved += 1 }
        field.onEscape = { cancelled += 1 }

        field.keyDown(with: try #require(keyEvent(keyCode: 36, characters: "\r")))
        field.keyDown(with: try #require(keyEvent(keyCode: 53, characters: "\u{1b}")))

        #expect(saved == 1)
        #expect(cancelled == 1)
    }

    @Test("folder creation uses one compact inline row")
    func folderCreationUsesCompactInlineRow() {
        let editor = PasswordVaultFolderEditorView(name: "", onSave: { _ in }, onCancel: {})

        #expect(editor.frame.height == MainMenuPanelLayout.rowHeight)
        #expect(editor.subviews.compactMap { $0 as? NSButton }.isEmpty)
        #expect(editor.subviews.contains { $0 is NSImageView })
        #expect(editor.subviews.contains { $0 is PasswordVaultReturnTextField })
    }

    @Test("note Return inserts a newline and Command-Return saves")
    func noteKeyboardActions() throws {
        var saved = 0
        let note = PasswordVaultNoteTextView()
        note.onSave = { saved += 1 }

        note.keyDown(with: try #require(keyEvent(keyCode: 36, characters: "\r")))
        #expect(note.string == "\n")
        #expect(saved == 0)

        note.keyDown(with: try #require(keyEvent(keyCode: 36, characters: "\r", modifiers: .command)))
        #expect(note.string == "\n")
        #expect(saved == 1)
    }

    @Test("vault is an independent searchable main-menu mode")
    func vaultIsIndependentSearchableMode() {
        let entries = [
            PasswordVaultEntry(
                id: UUID(), folderID: UUID(), title: "Mail", website: "mail.example.com", username: "alice", note: "",
                createdAt: .distantPast, updatedAt: .distantPast
            ),
            PasswordVaultEntry(
                id: UUID(), folderID: UUID(), title: "Cloud", website: "cloud.example.com", username: "bob", note: "",
                createdAt: .distantPast, updatedAt: .distantPast
            )
        ]
        let controller = MainMenuPanelController(
            historyTitle: "History",
            historyImage: nil,
            snippetTitle: "Snippet",
            snippetImage: nil,
            itemsProvider: { [] },
            onOpenHistory: {},
            onOpenSnippets: {},
            passwordVaultDataSource: MainMenuPasswordVaultDataSource(
                fetchFolders: {
                    [PasswordVaultFolder(id: entries[0].folderID, name: "Work", createdAt: .distantPast, updatedAt: .distantPast)]
                },
                fetchEntries: { entries },
                copyPassword: { _, completion in completion(.success(())) },
                loadDraft: { _, completion in
                    completion(.success(PasswordVaultDraft(
                        folderID: entries[0].folderID, title: "Mail", website: "mail.example.com",
                        username: "alice", note: "", password: "test-password"
                    )))
                },
                createEntry: { _, completion in completion(.success(())) },
                updateEntry: { _, _, completion in completion(.success(())) },
                deleteEntry: { _, completion in completion(.success(())) },
                createFolder: { _ in throw PasswordVaultError.keychainUnavailable },
                renameFolder: { _, _ in throw PasswordVaultError.keychainUnavailable },
                deleteFolder: { _ in }
            )
        )

        controller.openPasswordVaultFromMainMenu()
        controller.updateMainMenuSearchQueryForTesting("alice")
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)

        #expect(controller.mainMenuSelectedModeForTesting == "passwordVault")
        #expect(!controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuContextCreateButton"))
        controller.updateMainMenuSearchQueryForTesting("")
        controller.toggleWorkspaceEditingForTesting()
        #expect(controller.mainMenuButtonIdentifiersForTesting.contains("mainMenuContextCreateButton"))
        #expect(controller.mainMenuVisibleRowTitlesForTesting == ["Work", "Mail"])
        #expect(controller.mainMenuRowContextMenuTitlesForTesting(title: "Work").contains(String(localized: "Edit")))
        controller.performMainMenuRowDoubleClickForTesting(title: "Mail")
        #expect(controller.mainMenuPasswordEditorIsVisibleForTesting)
        controller.openHistoryFromMainMenu()
        #expect(controller.mainMenuSelectedModeForTesting == "history")
        #expect(controller.mainMenuVisibleRowTitlesForTesting == [String(localized: "No History")])
        _ = controller.close()
    }

    private func keyEvent(
        keyCode: UInt16,
        characters: String,
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )
    }
}
