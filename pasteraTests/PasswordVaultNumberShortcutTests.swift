import AppKit
import Testing
@testable import Pastera

@MainActor
@Suite("Password vault number shortcuts", .serialized)
struct PasswordVaultNumberShortcutTests {
    @Test("folder numbers open the matching folder, then entry numbers paste passwords")
    func numberOpensFolderThenPastesEntry() throws {
        try withNumbering(startingAtZero: false) {
            let work = folder("Work")
            let personal = folder("Personal")
            let mail = entry("Mail", in: work)
            let bank = entry("Bank", in: personal)
            let calendar = entry("Calendar", in: personal)
            var actions: [PasteAction] = []
            let controller = makeController(folders: [work, personal], entries: [mail, bank, calendar]) {
                actions.append($0)
            }
            show(controller)
            defer { _ = controller.close() }
            let secondNumber = try key("2", code: 19)

            #expect(controller.mainMenuRowItemNumberTextForTesting(title: "Work") == "1")
            #expect(controller.mainMenuRowItemNumberTextForTesting(title: "Personal") == "2")
            #expect(controller.handleMainMenuNavigationForTesting(secondNumber))
            #expect(controller.mainMenuVisibleRowTitlesForTesting.contains("Bank"))
            #expect(!controller.mainMenuVisibleRowTitlesForTesting.contains("Mail"))
            #expect(actions.isEmpty)
            #expect(controller.mainMenuRowItemNumberTextForTesting(title: "Work") == nil)
            #expect(controller.mainMenuRowItemNumberTextForTesting(title: "Personal") == nil)
            #expect(controller.mainMenuRowItemNumberTextForTesting(title: "Bank") == "1")
            #expect(controller.mainMenuRowItemNumberTextForTesting(title: "Calendar") == "2")
            try controller.mainMenuSnapshotPNGForTesting().write(
                to: URL(fileURLWithPath: "/tmp/pastera-password-vault-numbered-entries.png")
            )

            #expect(controller.handleMainMenuNavigationForTesting(secondNumber))
            #expect(actions == [.password(calendar.id)])
        }
    }

    @Test("Control changes numbered paste from password to account", arguments: [false, true])
    func numberedPasteRoutesToMatchingField(control: Bool) throws {
        try withNumbering(startingAtZero: false) {
            let work = folder("Work")
            let mail = entry("Mail", in: work)
            let calendar = entry("Calendar", in: work)
            var actions: [PasteAction] = []
            let controller = makeController(folders: [work], entries: [mail, calendar]) { actions.append($0) }
            show(controller)
            defer { _ = controller.close() }
            controller.performMainMenuRowConfirmForTesting(title: "Work")
            controller.selectMainMenuItemForTesting(title: "Mail")
            let number = try key("2", code: 19, modifiers: control ? .control : [])

            #expect(controller.handleMainMenuNavigationForTesting(number))

            #expect(actions == [control ? .username(calendar.id) : .password(calendar.id)])
        }
    }

    @Test("read-only warning retains numbered folder selection and paste", arguments: [false, true])
    func readOnlyWarningAllowsNumberedPaste(control: Bool) throws {
        try withNumbering(startingAtZero: false) {
            let work = folder("Work")
            let mail = entry("Mail", in: work)
            var actions: [PasteAction] = []
            let controller = makeController(
                folders: [work], entries: [mail], state: { .readOnlyWarning("conflict-copy") }
            ) { actions.append($0) }
            show(controller)
            defer { _ = controller.close() }
            let folderNumber = try key("1", code: 18)
            let entryNumber = try key("1", code: 18, modifiers: control ? .control : [])

            #expect(controller.mainMenuRowItemNumberTextForTesting(title: "Work") == "1")
            #expect(controller.handleMainMenuNavigationForTesting(folderNumber))
            #expect(controller.mainMenuVisibleRowTitlesForTesting.contains("Mail"))
            #expect(actions.isEmpty)
            #expect(controller.mainMenuRowItemNumberTextForTesting(title: "Mail") == "1")

            #expect(controller.handleMainMenuNavigationForTesting(entryNumber))
            #expect(actions == [control ? .username(mail.id) : .password(mail.id)])
        }
    }

    @Test("zero-based numbering selects the first folder and first entry", arguments: [false, true])
    func zeroBasedPreferenceRoutesFirstEntry(control: Bool) throws {
        try withNumbering(startingAtZero: true) {
            let work = folder("Work")
            let personal = folder("Personal")
            let mail = entry("Mail", in: work)
            let calendar = entry("Calendar", in: work)
            var actions: [PasteAction] = []
            let controller = makeController(folders: [work, personal], entries: [mail, calendar]) { actions.append($0) }
            show(controller)
            defer { _ = controller.close() }
            let zero = try key("0", code: 29)
            let entryNumber = try key("0", code: 29, modifiers: control ? .control : [])

            #expect(controller.mainMenuRowItemNumberTextForTesting(title: "Work") == "0")
            #expect(controller.mainMenuRowItemNumberTextForTesting(title: "Personal") == "1")
            #expect(controller.handleMainMenuNavigationForTesting(zero))
            #expect(actions.isEmpty)
            #expect(controller.mainMenuRowItemNumberTextForTesting(title: "Mail") == "0")
            #expect(controller.mainMenuRowItemNumberTextForTesting(title: "Calendar") == "1")
            #expect(controller.handleMainMenuNavigationForTesting(entryNumber))
            #expect(actions == [control ? .username(mail.id) : .password(mail.id)])
        }
    }

    @Test("one-based numbering uses zero for the tenth folder and tenth entry")
    func zeroSelectsTenthFolderAndEntry() throws {
        try withNumbering(startingAtZero: false) {
            let folders = (1...11).map { folder("Folder \($0)") }
            let entries = (1...11).map { entry("Entry \($0)", in: folders[9]) }
            var actions: [PasteAction] = []
            let controller = makeController(folders: folders, entries: entries) { actions.append($0) }
            show(controller)
            defer { _ = controller.close() }
            let zero = try key("0", code: 29)

            #expect(controller.mainMenuRowItemNumberTextForTesting(title: "Folder 10") == "0")
            #expect(controller.mainMenuRowItemNumberTextForTesting(title: "Folder 11") == nil)
            #expect(controller.handleMainMenuNavigationForTesting(zero))
            #expect(actions.isEmpty)
            #expect(controller.mainMenuRowItemNumberTextForTesting(title: "Entry 10") == "0")
            #expect(controller.mainMenuRowItemNumberTextForTesting(title: "Entry 11") == nil)

            #expect(controller.handleMainMenuNavigationForTesting(zero))
            #expect(actions == [.password(entries[9].id)])
        }
    }

    @Test("search numbers entries continuously across folders in visible order", arguments: [false, true])
    func searchNumberingDoesNotRestartAtEachFolder(control: Bool) throws {
        try withNumbering(startingAtZero: false) {
            let work = folder("Work")
            let personal = folder("Personal")
            let first = entry("Shared Mail", in: work)
            let second = entry("Shared Calendar", in: work)
            let third = entry("Shared Bank", in: personal)
            let excluded = entry("Unrelated", in: personal)
            var actions: [PasteAction] = []
            let controller = makeController(folders: [work, personal], entries: [third, first, excluded, second]) {
                actions.append($0)
            }
            show(controller)
            defer { _ = controller.close() }
            controller.updateMainMenuSearchQueryForTesting("Shared")
            controller.selectMainMenuItemForTesting(title: "Shared Mail")
            let number = try key("3", code: 20, modifiers: control ? .control : [])

            #expect(controller.mainMenuRowItemNumberTextForTesting(title: "Work") == nil)
            #expect(controller.mainMenuRowItemNumberTextForTesting(title: "Personal") == nil)
            #expect(controller.mainMenuRowItemNumberTextForTesting(title: "Shared Mail") == "1")
            #expect(controller.mainMenuRowItemNumberTextForTesting(title: "Shared Calendar") == "2")
            #expect(controller.mainMenuRowItemNumberTextForTesting(title: "Shared Bank") == "3")
            #expect(!controller.mainMenuVisibleRowTitlesForTesting.contains("Unrelated"))

            #expect(controller.handleMainMenuNavigationForTesting(number))
            #expect(actions == [control ? .username(third.id) : .password(third.id)])
        }
    }

    @Test("search and both inline editors retain digits without pasting", arguments: ["search", "folder", "entry"])
    func textInputDoesNotTriggerPaste(input: String) throws {
        try withNumbering(startingAtZero: false) {
            let work = folder("Work")
            let mail = entry("Mail", in: work)
            var actions: [PasteAction] = []
            let controller = makeController(folders: [work], entries: [mail]) { actions.append($0) }
            show(controller)
            defer { _ = controller.close() }
            controller.performMainMenuRowConfirmForTesting(title: "Work")
            let number = try key("1", code: 18)
            let controlNumber = try key("1", code: 18, modifiers: .control)

            switch input {
            case "search":
                let commandF = try key("f", code: 3, modifiers: .command)
                #expect(controller.handleMainMenuNavigationForTesting(commandF))
                #expect(controller.isMainMenuSearchFieldFocusedForTesting)
            case "folder":
                controller.toggleWorkspaceEditingForTesting()
                controller.performMainMenuRowDoubleClickForTesting(title: "Work")
                #expect(controller.passwordVaultFolderEditorIsVisibleForTesting)
            default:
                controller.toggleWorkspaceEditingForTesting()
                controller.performMainMenuRowDoubleClickForTesting(title: "Mail")
                #expect(controller.mainMenuPasswordEditorIsVisibleForTesting)
            }

            #expect(!controller.handleMainMenuNavigationForTesting(number))
            #expect(!controller.handleMainMenuNavigationForTesting(controlNumber))
            #expect(actions.isEmpty)
        }
    }

    @Test("locking the vault prevents stale numbered entries from pasting")
    func lockedVaultRejectsOldNumberMapping() throws {
        try withNumbering(startingAtZero: false) {
            let work = folder("Work")
            let mail = entry("Mail", in: work)
            var state: PasswordVaultState = .unlocked
            var actions: [PasteAction] = []
            let controller = makeController(folders: [work], entries: [mail], state: { state }) { actions.append($0) }
            show(controller)
            defer { _ = controller.close() }
            controller.performMainMenuRowConfirmForTesting(title: "Work")
            let number = try key("1", code: 18)
            let controlNumber = try key("1", code: 18, modifiers: .control)
            #expect(controller.mainMenuRowItemNumberTextForTesting(title: "Mail") == "1")

            state = .locked
            #expect(!controller.handleMainMenuNavigationForTesting(number))
            #expect(!controller.handleMainMenuNavigationForTesting(controlNumber))
            #expect(actions.isEmpty)

            controller.reloadContentIfVisible()
            #expect(!controller.mainMenuVisibleRowTitlesForTesting.contains("Mail"))
            #expect(!controller.handleMainMenuNavigationForTesting(number))
            #expect(actions.isEmpty)
        }
    }

    @Test("panel key equivalents use the numbered account paste route")
    func keyEquivalentPastesNumberedAccount() throws {
        try withNumbering(startingAtZero: false) {
            let work = folder("Work")
            let mail = entry("Mail", in: work)
            var actions: [PasteAction] = []
            let controller = makeController(folders: [work], entries: [mail]) { actions.append($0) }
            show(controller)
            defer { _ = controller.close() }
            controller.performMainMenuRowConfirmForTesting(title: "Work")
            let controlNumber = try key("1", code: 18, modifiers: .control)

            #expect(controller.performMainMenuKeyEquivalentForTesting(controlNumber))
            #expect(actions == [.username(mail.id)])
        }
    }

    private enum PasteAction: Equatable {
        case username(UUID)
        case password(UUID)
        case copy(UUID)
    }

    private func folder(_ name: String) -> PasswordVaultFolder {
        PasswordVaultFolder(id: UUID(), name: name, createdAt: .distantPast, updatedAt: .distantPast)
    }

    private func entry(_ title: String, in folder: PasswordVaultFolder) -> PasswordVaultEntry {
        PasswordVaultEntry(
            id: UUID(), folderID: folder.id, title: title, website: "", username: "fixture-account", note: "",
            createdAt: .distantPast, updatedAt: .distantPast
        )
    }

    private func makeController(
        folders: [PasswordVaultFolder],
        entries: [PasswordVaultEntry],
        state: @escaping () -> PasswordVaultState = { .unlocked },
        onAction: @escaping (PasteAction) -> Void
    ) -> MainMenuPanelController {
        MainMenuPanelController(
            historyTitle: "History", historyImage: nil, snippetTitle: "Snippet", snippetImage: nil,
            itemsProvider: { [] }, onOpenHistory: {}, onOpenSnippets: {},
            passwordVaultDataSource: MainMenuPasswordVaultDataSource(
                state: state,
                fetchFolders: { folders }, fetchEntries: { entries },
                copyPassword: { id, completion in onAction(.copy(id)); completion(.success(())) },
                pasteUsername: { id, _, completion in onAction(.username(id)); completion(.success(())) },
                pastePassword: { id, _, completion in onAction(.password(id)); completion(.success(())) },
                loadDraft: { id, completion in
                    guard let entry = entries.first(where: { $0.id == id }) else {
                        completion(.failure(.entryNotFound))
                        return
                    }
                    completion(.success(PasswordVaultDraft(
                        folderID: entry.folderID, title: entry.title, website: entry.website,
                        username: entry.username, note: entry.note, password: "fixture-password"
                    )))
                },
                createEntry: { _, completion in completion(.failure(.saveFailed)) },
                updateEntry: { _, _, completion in completion(.failure(.saveFailed)) },
                deleteEntry: { _, completion in completion(.failure(.saveFailed)) },
                createFolder: { _ in throw PasswordVaultError.saveFailed },
                renameFolder: { _, _ in throw PasswordVaultError.saveFailed },
                deleteFolder: { _ in throw PasswordVaultError.saveFailed }
            )
        )
    }

    private func show(_ controller: MainMenuPanelController) {
        controller.openPasswordVaultFromMainMenu()
        controller.show(at: NSPoint(x: 200, y: 200), pinned: true)
    }

    private func key(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: code
        ))
    }

    private func withNumbering(startingAtZero: Bool, operation: () throws -> Void) rethrows {
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
