import Carbon
import Foundation
import Magnet
import Testing
@testable import Pastera

@MainActor
@Suite(.serialized)
// swiftlint:disable:next type_body_length
final class HotKeyServiceTests {
    private let suiteName: String
    private let defaults: UserDefaults

    init() {
        suiteName = "HotKeyServiceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test
    func migrateDefaultSettings() throws {
        let service = HotKeyService(defaults: defaults)
        #expect(service.mainKeyCombo == nil)
        #expect(service.historyKeyCombo == nil)
        #expect(service.snippetKeyCombo == nil)

        #expect(defaults.bool(forKey: Constants.HotKey.migrateNewKeyCombo) == false)
        service.setupDefaultHotKeys()
        #expect(defaults.bool(forKey: Constants.HotKey.migrateNewKeyCombo) == true)

        let mainKeyCombo = try #require(service.mainKeyCombo)
        #expect(mainKeyCombo.QWERTYKeyCode == 9)
        #expect(mainKeyCombo.modifiers == 768)
        #expect(mainKeyCombo.doubledModifiers == false)
        #expect(mainKeyCombo.keyEquivalent.uppercased() == "V")

        let historyKeyCombo = try #require(service.historyKeyCombo)
        #expect(historyKeyCombo.QWERTYKeyCode == 9)
        #expect(historyKeyCombo.modifiers == cmdKey | optionKey)
        #expect(historyKeyCombo.doubledModifiers == false)
        #expect(historyKeyCombo.keyEquivalent.uppercased() == "V")

        let snippetKeyCombo = try #require(service.snippetKeyCombo)
        #expect(snippetKeyCombo.QWERTYKeyCode == 3)
        #expect(snippetKeyCombo.modifiers == cmdKey | optionKey)
        #expect(snippetKeyCombo.doubledModifiers == false)
        #expect(snippetKeyCombo.keyEquivalent.uppercased() == "F")
    }

    @Test
    func shortcutFormatterUsesCompactMacSymbols() throws {
        let mainKeyCombo = try #require(KeyCombo(QWERTYKeyCode: 9, carbonModifiers: cmdKey | shiftKey))
        let historyKeyCombo = try #require(KeyCombo(QWERTYKeyCode: 9, carbonModifiers: cmdKey | optionKey))
        let snippetKeyCombo = try #require(KeyCombo(QWERTYKeyCode: 3, carbonModifiers: cmdKey | optionKey))
        let searchKeyCombo = try #require(KeyCombo(QWERTYKeyCode: 3, carbonModifiers: cmdKey))
        let previousPageKeyCombo = try #require(KeyCombo(QWERTYKeyCode: 123, carbonModifiers: cmdKey))
        let nextPageKeyCombo = try #require(KeyCombo(QWERTYKeyCode: 124, carbonModifiers: cmdKey))
        let doubleCommandCombo = try #require(KeyCombo(doubledCocoaModifiers: .command))

        #expect(PasteraShortcutFormatter.string(for: mainKeyCombo) == "⇧⌘V")
        #expect(PasteraShortcutFormatter.string(for: historyKeyCombo) == "⌥⌘V")
        #expect(PasteraShortcutFormatter.string(for: snippetKeyCombo) == "⌥⌘F")
        #expect(PasteraShortcutFormatter.string(for: searchKeyCombo) == "⌘F")
        #expect(PasteraShortcutFormatter.string(for: previousPageKeyCombo) == "⌘←")
        #expect(PasteraShortcutFormatter.string(for: nextPageKeyCombo) == "⌘→")
        #expect(PasteraShortcutFormatter.string(for: doubleCommandCombo) == "⌘⌘")
        #expect(PasteraShortcutFormatter.string(for: nil) == nil)
    }

    @Test
    func historyPanelShortcutDefaultsAreLocalKeyCombos() throws {
        let service = HotKeyService(defaults: defaults)

        service.setupDefaultHotKeys()

        let searchKeyCombo = try #require(service.historyPanelKeyCombo(for: .search))
        let previousPageKeyCombo = try #require(service.historyPanelKeyCombo(for: .previousPage))
        let nextPageKeyCombo = try #require(service.historyPanelKeyCombo(for: .nextPage))

        #expect(searchKeyCombo.QWERTYKeyCode == 3)
        #expect(searchKeyCombo.modifiers == cmdKey)
        #expect(PasteraShortcutFormatter.string(for: searchKeyCombo) == "⌘F")

        #expect(previousPageKeyCombo.QWERTYKeyCode == 123)
        #expect(previousPageKeyCombo.modifiers == 0)
        #expect(PasteraShortcutFormatter.string(for: previousPageKeyCombo) == "←")

        #expect(nextPageKeyCombo.QWERTYKeyCode == 124)
        #expect(nextPageKeyCombo.modifiers == 0)
        #expect(PasteraShortcutFormatter.string(for: nextPageKeyCombo) == "→")
    }

    @Test
    func historyPanelDefaultsAreRestoredWhenMigrationMarkerExistsButKeysAreMissing() throws {
        defaults.set(true, forKey: Constants.HotKey.historyPanelShortcutDefaultsMigrated)
        defaults.removeObject(forKey: Constants.HotKey.historySearchKeyCombo)
        defaults.removeObject(forKey: Constants.HotKey.historyPreviousPageKeyCombo)
        defaults.removeObject(forKey: Constants.HotKey.historyNextPageKeyCombo)

        let service = HotKeyService(defaults: defaults)
        service.setupDefaultHotKeys()

        #expect(service.historyPanelKeyCombo(for: .search) == HistoryPanelShortcut.search.defaultKeyCombo)
        #expect(service.historyPanelKeyCombo(for: .previousPage) == HistoryPanelShortcut.previousPage.defaultKeyCombo)
        #expect(service.historyPanelKeyCombo(for: .nextPage) == HistoryPanelShortcut.nextPage.defaultKeyCombo)
    }

    @Test
    func preservesCommandHistoryPanelShortcutsAsDefaults() throws {
        let legacySearch = try #require(KeyCombo(QWERTYKeyCode: 3, carbonModifiers: cmdKey))
        let legacyPreviousPage = try #require(KeyCombo(QWERTYKeyCode: 123, carbonModifiers: cmdKey))
        let legacyNextPage = try #require(KeyCombo(QWERTYKeyCode: 124, carbonModifiers: cmdKey))
        defaults.setArchiveData(legacySearch, forKey: Constants.HotKey.historySearchKeyCombo)
        defaults.setArchiveData(legacyPreviousPage, forKey: Constants.HotKey.historyPreviousPageKeyCombo)
        defaults.setArchiveData(legacyNextPage, forKey: Constants.HotKey.historyNextPageKeyCombo)
        defaults.set(true, forKey: Constants.HotKey.historyPanelShortcutDefaultsMigrated)
        defaults.set(false, forKey: Constants.HotKey.migrateHistoryPanelOptionCommand)

        let service = HotKeyService(defaults: defaults)
        service.setupDefaultHotKeys()

        #expect(service.historyPanelKeyCombo(for: .search) == HistoryPanelShortcut.search.defaultKeyCombo)
        #expect(service.historyPanelKeyCombo(for: .previousPage) == HistoryPanelShortcut.previousPage.defaultKeyCombo)
        #expect(service.historyPanelKeyCombo(for: .nextPage) == HistoryPanelShortcut.nextPage.defaultKeyCombo)
    }

    @Test
    func ignoresStoredPagingShortcutsWhilePreservingCustomizedSearch() throws {
        let customSearch = try #require(KeyCombo(QWERTYKeyCode: 3, carbonModifiers: cmdKey | shiftKey))
        let customPreviousPage = try #require(KeyCombo(QWERTYKeyCode: 123, carbonModifiers: cmdKey | controlKey))
        let customNextPage = try #require(KeyCombo(QWERTYKeyCode: 124, carbonModifiers: cmdKey | shiftKey))
        defaults.setArchiveData(customSearch, forKey: Constants.HotKey.historySearchKeyCombo)
        defaults.setArchiveData(customPreviousPage, forKey: Constants.HotKey.historyPreviousPageKeyCombo)
        defaults.setArchiveData(customNextPage, forKey: Constants.HotKey.historyNextPageKeyCombo)
        defaults.set(true, forKey: Constants.HotKey.historyPanelShortcutDefaultsMigrated)
        defaults.set(false, forKey: Constants.HotKey.migrateHistoryPanelOptionCommand)

        let service = HotKeyService(defaults: defaults)
        service.setupDefaultHotKeys()

        #expect(service.historyPanelKeyCombo(for: .search) == customSearch)
        #expect(service.historyPanelKeyCombo(for: .previousPage) == HistoryPanelShortcut.previousPage.defaultKeyCombo)
        #expect(service.historyPanelKeyCombo(for: .nextPage) == HistoryPanelShortcut.nextPage.defaultKeyCombo)
        #expect(defaults.archiveDataForKey(
            KeyCombo.self,
            key: Constants.HotKey.historyPreviousPageKeyCombo
        ) == customPreviousPage)
        #expect(defaults.archiveDataForKey(
            KeyCombo.self,
            key: Constants.HotKey.historyNextPageKeyCombo
        ) == customNextPage)
    }

    @Test
    func migratesKnownIncorrectLegacyHistoryPanelShortcutsToCommandDefaults() throws {
        let incorrectSearch = try #require(KeyCombo(QWERTYKeyCode: 17, carbonModifiers: cmdKey | optionKey))
        let incorrectPreviousPage = try #require(KeyCombo(QWERTYKeyCode: 123, carbonModifiers: cmdKey | optionKey))
        let incorrectNextPage = try #require(KeyCombo(QWERTYKeyCode: 0, carbonModifiers: cmdKey))
        defaults.setArchiveData(incorrectSearch, forKey: Constants.HotKey.historySearchKeyCombo)
        defaults.setArchiveData(incorrectPreviousPage, forKey: Constants.HotKey.historyPreviousPageKeyCombo)
        defaults.setArchiveData(incorrectNextPage, forKey: Constants.HotKey.historyNextPageKeyCombo)
        defaults.set(true, forKey: Constants.HotKey.historyPanelShortcutDefaultsMigrated)
        defaults.set(true, forKey: Constants.HotKey.migrateHistoryPanelOptionCommand)
        defaults.set(true, forKey: Constants.HotKey.migrateHistoryPanelCanonicalDefaults)
        defaults.set(true, forKey: Constants.HotKey.migrateHistoryPanelCanonicalDefaultsV2)
        defaults.set(false, forKey: Constants.HotKey.migrateHistoryPanelCommandDefaults)

        let service = HotKeyService(defaults: defaults)
        service.setupDefaultHotKeys()

        #expect(service.historyPanelKeyCombo(for: .search) == HistoryPanelShortcut.search.defaultKeyCombo)
        #expect(service.historyPanelKeyCombo(for: .previousPage) == HistoryPanelShortcut.previousPage.defaultKeyCombo)
        #expect(service.historyPanelKeyCombo(for: .nextPage) == HistoryPanelShortcut.nextPage.defaultKeyCombo)
    }

    @Test
    func changingHistoryPanelShortcutPersistsWithoutGlobalRegistration() throws {
        let service = HotKeyService(defaults: defaults)
        let customSearchKeyCombo = try #require(KeyCombo(QWERTYKeyCode: 17, carbonModifiers: cmdKey | optionKey))

        service.changeHistoryPanelKeyCombo(.search, keyCombo: customSearchKeyCombo)

        #expect(service.historyPanelKeyCombo(for: .search) == customSearchKeyCombo)
        let savedSearchKeyCombo = try #require(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.historySearchKeyCombo))
        #expect(savedSearchKeyCombo == customSearchKeyCombo)

        service.changeHistoryPanelKeyCombo(.search, keyCombo: nil)

        #expect(service.historyPanelKeyCombo(for: .search) == nil)
        #expect(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.historySearchKeyCombo) == nil)
    }

    @Test
    func resetMenuShortcutsToDefaultsPreservesHistoryPanelAndUnrelatedState() throws {
        let service = HotKeyService(defaults: defaults)
        let customMain = try #require(KeyCombo(QWERTYKeyCode: 0, carbonModifiers: cmdKey | controlKey))
        let customHistory = try #require(KeyCombo(QWERTYKeyCode: 1, carbonModifiers: cmdKey | shiftKey))
        let customSnippet = try #require(KeyCombo(QWERTYKeyCode: 2, carbonModifiers: cmdKey | controlKey))
        let customSearch = try #require(KeyCombo(QWERTYKeyCode: 17, carbonModifiers: cmdKey | shiftKey))
        let customPrevious = try #require(KeyCombo(QWERTYKeyCode: 123, carbonModifiers: cmdKey | controlKey))
        let customNext = try #require(KeyCombo(QWERTYKeyCode: 124, carbonModifiers: cmdKey | shiftKey))
        let clearHistory = try #require(KeyCombo(QWERTYKeyCode: 10, carbonModifiers: cmdKey | controlKey))
        let folderCombo = try #require(KeyCombo(QWERTYKeyCode: 12, carbonModifiers: cmdKey | optionKey))
        let folderIdentifier = "menu-reset-folder"
        let nextFolderIdentifier = "menu-reset-next-folder"
        defer {
            service.unregisterSnippetHotKey(with: folderIdentifier)
            service.unregisterSnippetHotKey(with: nextFolderIdentifier)
        }

        service.change(with: .main, keyCombo: customMain)
        service.change(with: .history, keyCombo: customHistory)
        service.change(with: .snippet, keyCombo: customSnippet)
        service.changeHistoryPanelKeyCombo(.search, keyCombo: customSearch)
        service.changeHistoryPanelKeyCombo(.previousPage, keyCombo: customPrevious)
        service.changeHistoryPanelKeyCombo(.nextPage, keyCombo: customNext)
        service.changeClearHistoryKeyCombo(clearHistory)
        service.registerSnippetHotKey(with: folderIdentifier, keyCombo: folderCombo)
        let savedFolderKeyCombos = try #require(defaults.object(forKey: Constants.HotKey.folderKeyCombos) as? Data)
        setMigrationFlagSentinels(in: defaults)

        service.resetMenuShortcutsToDefaults()

        let defaultMain = try #require(KeyCombo(QWERTYKeyCode: 9, carbonModifiers: cmdKey | shiftKey))
        let defaultHistory = try #require(KeyCombo(QWERTYKeyCode: 9, carbonModifiers: cmdKey | optionKey))
        let defaultSnippet = try #require(KeyCombo(QWERTYKeyCode: 3, carbonModifiers: cmdKey | optionKey))
        let defaultPasswordVault = try #require(KeyCombo(QWERTYKeyCode: 35, carbonModifiers: controlKey | optionKey))
        #expect(service.mainKeyCombo == defaultMain)
        #expect(service.historyKeyCombo == defaultHistory)
        #expect(service.snippetKeyCombo == defaultSnippet)
        #expect(service.passwordVaultKeyCombo == defaultPasswordVault)
        #expect(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.mainKeyCombo) == defaultMain)
        #expect(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.historyKeyCombo) == defaultHistory)
        #expect(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.snippetKeyCombo) == defaultSnippet)
        #expect(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.passwordVaultKeyCombo) == defaultPasswordVault)
        #expect(service.historyPanelKeyCombo(for: .search) == customSearch)
        #expect(service.historyPanelKeyCombo(for: .previousPage) == HistoryPanelShortcut.previousPage.defaultKeyCombo)
        #expect(service.historyPanelKeyCombo(for: .nextPage) == HistoryPanelShortcut.nextPage.defaultKeyCombo)
        #expect(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.historySearchKeyCombo) == customSearch)
        #expect(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.historyPreviousPageKeyCombo) == nil)
        #expect(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.historyNextPageKeyCombo) == nil)
        #expect(service.clearHistoryKeyCombo == clearHistory)
        #expect(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.clearHistoryKeyCombo) == clearHistory)
        #expect(service.snippetKeyCombo(forIdentifier: folderIdentifier) == folderCombo)
        #expect(defaults.object(forKey: Constants.HotKey.folderKeyCombos) as? Data == savedFolderKeyCombos)
        expectMigrationFlagSentinels(in: defaults)

        let nextFolderCombo = try #require(service.registerDefaultSnippetHotKeyIfAvailable(forIdentifier: nextFolderIdentifier))
        #expect(nextFolderCombo.QWERTYKeyCode == 13)
        #expect(nextFolderCombo.modifiers == cmdKey | optionKey)
    }

    @Test
    func resetHistoryPanelShortcutsToDefaultsPreservesMenuAndUnrelatedState() throws {
        let service = HotKeyService(defaults: defaults)
        let customMain = try #require(KeyCombo(QWERTYKeyCode: 0, carbonModifiers: cmdKey | controlKey))
        let customHistory = try #require(KeyCombo(QWERTYKeyCode: 1, carbonModifiers: cmdKey | shiftKey))
        let customSnippet = try #require(KeyCombo(QWERTYKeyCode: 2, carbonModifiers: cmdKey | controlKey))
        let customSearch = try #require(KeyCombo(QWERTYKeyCode: 17, carbonModifiers: cmdKey | shiftKey))
        let customPrevious = try #require(KeyCombo(QWERTYKeyCode: 123, carbonModifiers: cmdKey | controlKey))
        let customNext = try #require(KeyCombo(QWERTYKeyCode: 124, carbonModifiers: cmdKey | shiftKey))
        let clearHistory = try #require(KeyCombo(QWERTYKeyCode: 10, carbonModifiers: cmdKey | controlKey))
        let folderCombo = try #require(KeyCombo(QWERTYKeyCode: 12, carbonModifiers: cmdKey | optionKey))
        let folderIdentifier = "history-reset-folder"
        let nextFolderIdentifier = "history-reset-next-folder"
        defer {
            service.unregisterSnippetHotKey(with: folderIdentifier)
            service.unregisterSnippetHotKey(with: nextFolderIdentifier)
        }

        service.change(with: .main, keyCombo: customMain)
        service.change(with: .history, keyCombo: customHistory)
        service.change(with: .snippet, keyCombo: customSnippet)
        service.changeHistoryPanelKeyCombo(.search, keyCombo: customSearch)
        service.changeHistoryPanelKeyCombo(.previousPage, keyCombo: customPrevious)
        service.changeHistoryPanelKeyCombo(.nextPage, keyCombo: customNext)
        service.changeClearHistoryKeyCombo(clearHistory)
        service.registerSnippetHotKey(with: folderIdentifier, keyCombo: folderCombo)
        let savedFolderKeyCombos = try #require(defaults.object(forKey: Constants.HotKey.folderKeyCombos) as? Data)
        setMigrationFlagSentinels(in: defaults)

        service.resetHistoryPanelShortcutsToDefaults()

        #expect(service.historyPanelKeyCombo(for: .search) == HistoryPanelShortcut.search.defaultKeyCombo)
        #expect(service.historyPanelKeyCombo(for: .previousPage) == HistoryPanelShortcut.previousPage.defaultKeyCombo)
        #expect(service.historyPanelKeyCombo(for: .nextPage) == HistoryPanelShortcut.nextPage.defaultKeyCombo)
        #expect(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.historySearchKeyCombo) == HistoryPanelShortcut.search.defaultKeyCombo)
        #expect(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.historyPreviousPageKeyCombo) == nil)
        #expect(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.historyNextPageKeyCombo) == nil)
        #expect(service.mainKeyCombo == customMain)
        #expect(service.historyKeyCombo == customHistory)
        #expect(service.snippetKeyCombo == customSnippet)
        #expect(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.mainKeyCombo) == customMain)
        #expect(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.historyKeyCombo) == customHistory)
        #expect(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.snippetKeyCombo) == customSnippet)
        #expect(service.clearHistoryKeyCombo == clearHistory)
        #expect(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.clearHistoryKeyCombo) == clearHistory)
        #expect(service.snippetKeyCombo(forIdentifier: folderIdentifier) == folderCombo)
        #expect(defaults.object(forKey: Constants.HotKey.folderKeyCombos) as? Data == savedFolderKeyCombos)
        expectMigrationFlagSentinels(in: defaults)

        let nextFolderCombo = try #require(service.registerDefaultSnippetHotKeyIfAvailable(forIdentifier: nextFolderIdentifier))
        #expect(nextFolderCombo.QWERTYKeyCode == 13)
        #expect(nextFolderCombo.modifiers == cmdKey | optionKey)
    }

    @Test
    func shortcutFormatterUsesNumericShortcutText() {
        #expect(PasteraShortcutFormatter.numericString(forRowIndex: 0, startsAtZero: false) == "1")
        #expect(PasteraShortcutFormatter.numericString(forRowIndex: 8, startsAtZero: false) == "9")
        #expect(PasteraShortcutFormatter.numericString(forRowIndex: 9, startsAtZero: false) == "0")
        #expect(PasteraShortcutFormatter.numericString(forRowIndex: 0, startsAtZero: true) == "0")
        #expect(PasteraShortcutFormatter.numericString(forRowIndex: 10, startsAtZero: false) == nil)
    }

    @Test
    func migrateCustomizeSettings() throws {
        let service = HotKeyService(defaults: defaults)
        #expect(service.mainKeyCombo == nil)
        #expect(service.historyKeyCombo == nil)
        #expect(service.snippetKeyCombo == nil)

        let defaultKeyCombos: [String: Any] = [Constants.Menu.clip: ["keyCode": 0, "modifiers": 4352],
                                               Constants.Menu.history: ["keyCode": 9, "modifiers": 768],
                                               Constants.Menu.snippet: ["keyCode": 11, "modifiers": 4352]]
        defaults.set(defaultKeyCombos, forKey: Constants.UserDefaults.hotKeys)
        defaults.synchronize()

        #expect(defaults.bool(forKey: Constants.HotKey.migrateNewKeyCombo) == false)
        service.setupDefaultHotKeys()
        #expect(defaults.bool(forKey: Constants.HotKey.migrateNewKeyCombo) == true)

        let mainKeyCombo = try #require(service.mainKeyCombo)
        #expect(mainKeyCombo.QWERTYKeyCode == 0)
        #expect(mainKeyCombo.modifiers == 4352)
        #expect(mainKeyCombo.doubledModifiers == false)
        #expect(mainKeyCombo.keyEquivalent.uppercased() == "A")

        let historyKeyCombo = try #require(service.historyKeyCombo)
        #expect(historyKeyCombo.QWERTYKeyCode == 9)
        #expect(historyKeyCombo.modifiers == 768)
        #expect(historyKeyCombo.doubledModifiers == false)
        #expect(historyKeyCombo.keyEquivalent.uppercased() == "V")

        let snippetKeyCombo = try #require(service.snippetKeyCombo)
        #expect(snippetKeyCombo.QWERTYKeyCode == 11)
        #expect(snippetKeyCombo.modifiers == 4352)
        #expect(snippetKeyCombo.doubledModifiers == false)
        #expect(snippetKeyCombo.keyEquivalent.uppercased() == "B")
    }

    @Test
    func saveKeyCombos() throws {
        defaults.set(true, forKey: Constants.HotKey.migrateNewKeyCombo)

        let service = HotKeyService(defaults: defaults)
        #expect(service.mainKeyCombo == nil)
        #expect(service.historyKeyCombo == nil)
        #expect(service.snippetKeyCombo == nil)

        #expect(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.mainKeyCombo) == nil)
        #expect(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.historyKeyCombo) == nil)
        #expect(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.snippetKeyCombo) == nil)

        service.setupDefaultHotKeys()
        #expect(service.mainKeyCombo == nil)
        #expect(service.historyKeyCombo == nil)
        #expect(service.snippetKeyCombo == nil)

        let mainKeyCombo = try #require(KeyCombo(QWERTYKeyCode: 9, carbonModifiers: 768))
        let historyKeyCombo = try #require(KeyCombo(doubledCocoaModifiers: .command))
        let snippetKeyCombo = try #require(KeyCombo(QWERTYKeyCode: 0, cocoaModifiers: .shift))

        service.change(with: .main, keyCombo: mainKeyCombo)
        service.change(with: .history, keyCombo: historyKeyCombo)
        service.change(with: .snippet, keyCombo: snippetKeyCombo)

        let savedMainKeyCombo = try #require(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.mainKeyCombo))
        let savedHistoryKeyCombo = try #require(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.historyKeyCombo))
        let savedSnippetKeyCombo = try #require(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.snippetKeyCombo))

        #expect(savedMainKeyCombo.QWERTYKeyCode == 9)
        #expect(savedMainKeyCombo.modifiers == 768)
        #expect(savedMainKeyCombo.doubledModifiers == false)
        #expect(savedMainKeyCombo.keyEquivalent.uppercased() == "V")

        #expect(savedHistoryKeyCombo.QWERTYKeyCode == 0)
        #expect(savedHistoryKeyCombo.modifiers == cmdKey)
        #expect(savedHistoryKeyCombo.doubledModifiers == true)
        #expect(savedHistoryKeyCombo.keyEquivalent.uppercased() == "")

        #expect(savedSnippetKeyCombo.QWERTYKeyCode == 0)
        #expect(savedSnippetKeyCombo.modifiers == shiftKey)
        #expect(savedSnippetKeyCombo.doubledModifiers == false)
        #expect(savedSnippetKeyCombo.keyEquivalent.uppercased() == "A")

        service.change(with: .main, keyCombo: nil)
        #expect(service.mainKeyCombo == nil)
        #expect(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.mainKeyCombo) == nil)
    }

    @Test
    func unarchiveSavedKeyCombos() throws {
        defaults.set(true, forKey: Constants.HotKey.migrateNewKeyCombo)

        let mainKeyCombo = try #require(KeyCombo(QWERTYKeyCode: 9, carbonModifiers: 768))
        let historyKeyCombo = try #require(KeyCombo(doubledCocoaModifiers: .command))
        let snippetKeyCombo = try #require(KeyCombo(QWERTYKeyCode: 0, cocoaModifiers: .shift))

        defaults.setArchiveData(mainKeyCombo, forKey: Constants.HotKey.mainKeyCombo)
        defaults.setArchiveData(historyKeyCombo, forKey: Constants.HotKey.historyKeyCombo)
        defaults.setArchiveData(snippetKeyCombo, forKey: Constants.HotKey.snippetKeyCombo)

        let service = HotKeyService(defaults: defaults)
        #expect(service.mainKeyCombo == nil)
        #expect(service.historyKeyCombo == nil)
        #expect(service.snippetKeyCombo == nil)

        service.setupDefaultHotKeys()

        let savedMainKeyCombo = try #require(service.mainKeyCombo)
        #expect(savedMainKeyCombo.QWERTYKeyCode == 9)
        #expect(savedMainKeyCombo.modifiers == 768)
        #expect(savedMainKeyCombo.doubledModifiers == false)
        #expect(savedMainKeyCombo.keyEquivalent.uppercased() == "V")

        let savedHistoryKeyCombo = try #require(service.historyKeyCombo)
        #expect(savedHistoryKeyCombo.QWERTYKeyCode == 0)
        #expect(savedHistoryKeyCombo.modifiers == cmdKey)
        #expect(savedHistoryKeyCombo.doubledModifiers == true)
        #expect(savedHistoryKeyCombo.keyEquivalent.uppercased() == "")

        let savedSnippetKeyCombo = try #require(service.snippetKeyCombo)
        #expect(savedSnippetKeyCombo.QWERTYKeyCode == 0)
        #expect(savedSnippetKeyCombo.modifiers == shiftKey)
        #expect(savedSnippetKeyCombo.doubledModifiers == false)
        #expect(savedSnippetKeyCombo.keyEquivalent.uppercased() == "A")
    }

    @Test
    func defaultKeyCombos() {
        let keyCombos = HotKeyService.defaultKeyCombos
        let mainCombos = keyCombos[Constants.Menu.clip] as? [String: Int]
        let historyCombos = keyCombos[Constants.Menu.history] as? [String: Int]
        let snippetCombos = keyCombos[Constants.Menu.snippet] as? [String: Int]

        #expect(mainCombos?["keyCode"] == 9)
        #expect(mainCombos?["modifiers"] == 768)

        #expect(historyCombos?["keyCode"] == 9)
        #expect(historyCombos?["modifiers"] == cmdKey | optionKey)

        #expect(snippetCombos?["keyCode"] == 3)
        #expect(snippetCombos?["modifiers"] == cmdKey | optionKey)
    }

    @Test
    func migratesLegacyDefaultHistoryAndSnippetHotkeysToOptionCommandDefaults() throws {
        defaults.set(true, forKey: Constants.HotKey.migrateNewKeyCombo)
        defaults.set(false, forKey: Constants.HotKey.migrateOptionCommandDefaultKeyCombos)
        let legacyHistory = try #require(KeyCombo(QWERTYKeyCode: 9, carbonModifiers: cmdKey | controlKey))
        let legacySnippet = try #require(KeyCombo(QWERTYKeyCode: 11, carbonModifiers: cmdKey | shiftKey))
        defaults.setArchiveData(legacyHistory, forKey: Constants.HotKey.historyKeyCombo)
        defaults.setArchiveData(legacySnippet, forKey: Constants.HotKey.snippetKeyCombo)

        let service = HotKeyService(defaults: defaults)
        service.setupDefaultHotKeys()

        let historyKeyCombo = try #require(service.historyKeyCombo)
        #expect(historyKeyCombo.QWERTYKeyCode == 9)
        #expect(historyKeyCombo.modifiers == cmdKey | optionKey)
        #expect(historyKeyCombo.keyEquivalent.uppercased() == "V")

        let snippetKeyCombo = try #require(service.snippetKeyCombo)
        #expect(snippetKeyCombo.QWERTYKeyCode == 3)
        #expect(snippetKeyCombo.modifiers == cmdKey | optionKey)
        #expect(snippetKeyCombo.keyEquivalent.uppercased() == "F")
        #expect(defaults.bool(forKey: Constants.HotKey.migrateOptionCommandDefaultKeyCombos))
        #expect(defaults.bool(forKey: Constants.HotKey.migrateSnippetDefaultKeyComboToF))
    }

    @Test
    func migratesOldOptionCommandSnippetDefaultToF() throws {
        defaults.set(true, forKey: Constants.HotKey.migrateNewKeyCombo)
        defaults.set(true, forKey: Constants.HotKey.migrateOptionCommandDefaultKeyCombos)
        defaults.set(false, forKey: Constants.HotKey.migrateSnippetDefaultKeyComboToF)
        let oldDefaultSnippet = try #require(KeyCombo(QWERTYKeyCode: 11, carbonModifiers: cmdKey | optionKey))
        defaults.setArchiveData(oldDefaultSnippet, forKey: Constants.HotKey.snippetKeyCombo)

        let service = HotKeyService(defaults: defaults)
        service.setupDefaultHotKeys()

        let snippetKeyCombo = try #require(service.snippetKeyCombo)
        #expect(snippetKeyCombo.QWERTYKeyCode == 3)
        #expect(snippetKeyCombo.modifiers == cmdKey | optionKey)
        #expect(snippetKeyCombo.keyEquivalent.uppercased() == "F")
        #expect(defaults.bool(forKey: Constants.HotKey.migrateSnippetDefaultKeyComboToF))
    }

    @Test
    func preservesCustomizedHistoryAndSnippetHotkeysDuringOptionCommandDefaultMigration() throws {
        defaults.set(true, forKey: Constants.HotKey.migrateNewKeyCombo)
        defaults.set(false, forKey: Constants.HotKey.migrateOptionCommandDefaultKeyCombos)
        let customHistory = try #require(KeyCombo(QWERTYKeyCode: 9, carbonModifiers: cmdKey | shiftKey))
        let customSnippet = try #require(KeyCombo(QWERTYKeyCode: 11, carbonModifiers: cmdKey | controlKey))
        defaults.setArchiveData(customHistory, forKey: Constants.HotKey.historyKeyCombo)
        defaults.setArchiveData(customSnippet, forKey: Constants.HotKey.snippetKeyCombo)

        let service = HotKeyService(defaults: defaults)
        service.setupDefaultHotKeys()

        #expect(service.historyKeyCombo == customHistory)
        #expect(service.snippetKeyCombo == customSnippet)
        #expect(defaults.bool(forKey: Constants.HotKey.migrateOptionCommandDefaultKeyCombos))
        #expect(defaults.bool(forKey: Constants.HotKey.migrateSnippetDefaultKeyComboToF))
    }

    @Test
    func defaultSnippetFolderHotkeysUsePreferredOptionCommandOrder() throws {
        let service = HotKeyService(defaults: defaults)
        let identifiers = (0..<6).map { "default-folder-\($0)" }
        defer { identifiers.forEach(service.unregisterSnippetHotKey) }

        let expectedKeys: [(keyCode: Int, key: String)] = [
            (12, "Q"),
            (13, "W"),
            (14, "E"),
            (17, "T"),
            (16, "Y"),
            (32, "U")
        ]

        for (identifier, expectedKey) in zip(identifiers, expectedKeys) {
            let keyCombo = try #require(service.registerDefaultSnippetHotKeyIfAvailable(forIdentifier: identifier))

            #expect(keyCombo.QWERTYKeyCode == expectedKey.keyCode)
            #expect(keyCombo.modifiers == cmdKey | optionKey)
            #expect(keyCombo.keyEquivalent.uppercased() == expectedKey.key)
            #expect(service.snippetKeyCombo(forIdentifier: identifier) == keyCombo)
        }
    }

    @Test
    func defaultSnippetFolderHotkeysSkipUsedCombosAndStopWhenSequenceIsExhausted() throws {
        let service = HotKeyService(defaults: defaults)
        let identifiers = (0..<8).map { "reserved-folder-\($0)" }
        defer { identifiers.forEach(service.unregisterSnippetHotKey) }

        let qCombo = try #require(KeyCombo(QWERTYKeyCode: 12, carbonModifiers: cmdKey | optionKey))
        service.registerSnippetHotKey(with: identifiers[0], keyCombo: qCombo)

        let nextCombo = try #require(service.registerDefaultSnippetHotKeyIfAvailable(forIdentifier: identifiers[1]))
        #expect(nextCombo.QWERTYKeyCode == 13)
        #expect(nextCombo.keyEquivalent.uppercased() == "W")

        for identifier in identifiers.dropFirst(2) {
            _ = service.registerDefaultSnippetHotKeyIfAvailable(forIdentifier: identifier)
        }

        #expect(service.registerDefaultSnippetHotKeyIfAvailable(forIdentifier: "overflow-folder") == nil)
    }

    @Test
    func remoteSessionPolicyDoesNotSuspendByDefault() {
        #expect(!RemoteSessionHotKeyPolicy.shouldSuspendLocalHotKeys(
            frontmostApplicationBundleIdentifier: "com.apple.ScreenSharing",
            isEnabled: false
        ))
    }

    @Test
    func remoteSessionPolicySuspendsWhenPreferenceIsEnabled() {
        #expect(RemoteSessionHotKeyPolicy.shouldSuspendLocalHotKeys(
            frontmostApplicationBundleIdentifier: "com.apple.ScreenSharing",
            isEnabled: true
        ))
        #expect(!RemoteSessionHotKeyPolicy.shouldSuspendLocalHotKeys(
            frontmostApplicationBundleIdentifier: "com.apple.finder",
            isEnabled: true
        ))
        #expect(!RemoteSessionHotKeyPolicy.shouldSuspendLocalHotKeys(
            frontmostApplicationBundleIdentifier: nil,
            isEnabled: true
        ))
    }

    @Test
    func remoteSessionStateRefreshUsesTheServicesBoundDefaultsImmediately() {
        let service = HotKeyService(defaults: defaults)
        defaults.set(true, forKey: Constants.HotKey.suspendDuringRemoteSession)

        service.updateRemoteSessionHotKeyState(
            frontmostApplicationBundleIdentifier: "com.apple.ScreenSharing"
        )
        #expect(service.isSuspendedForRemoteSession)

        defaults.set(false, forKey: Constants.HotKey.suspendDuringRemoteSession)
        service.updateRemoteSessionHotKeyState(
            frontmostApplicationBundleIdentifier: "com.apple.ScreenSharing"
        )
        #expect(!service.isSuspendedForRemoteSession)
    }

    @Test
    func addAndRemoveClearHistoryHotkey() throws {
        let service = HotKeyService(defaults: defaults)

        #expect(service.clearHistoryKeyCombo == nil)

        let keyCombo = try #require(KeyCombo(QWERTYKeyCode: 10, carbonModifiers: cmdKey))
        service.changeClearHistoryKeyCombo(keyCombo)

        #expect(service.clearHistoryKeyCombo != nil)
        #expect(service.clearHistoryKeyCombo == keyCombo)

        let savedData = try #require(defaults.object(forKey: Constants.HotKey.clearHistoryKeyCombo) as? Data)
        let savedKeyCombo = try #require(NSKeyedUnarchiver.unarchiveObject(with: savedData) as? KeyCombo)
        #expect(savedKeyCombo == keyCombo)

        service.changeClearHistoryKeyCombo(nil)
        #expect(service.clearHistoryKeyCombo == nil)
    }

    @Test
    func scriptTransformShortcutPersistsAndCanBeRemoved() throws {
        let service = HotKeyService(defaults: defaults)
        let keyCombo = try #require(KeyCombo(QWERTYKeyCode: 1, carbonModifiers: cmdKey | optionKey))

        service.changeScriptTransformKeyCombo(keyCombo)

        #expect(service.scriptTransformKeyCombo == keyCombo)
        #expect(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.scriptTransformKeyCombo) == keyCombo)

        service.changeScriptTransformKeyCombo(nil)
        #expect(service.scriptTransformKeyCombo == nil)
        #expect(defaults.object(forKey: Constants.HotKey.scriptTransformKeyCombo) == nil)
    }

    private func setMigrationFlagSentinels(in defaults: UserDefaults) {
        migrationFlagSentinels.forEach { defaults.set($0.value, forKey: $0.key) }
        defaults.synchronize()
    }

    private func expectMigrationFlagSentinels(in defaults: UserDefaults) {
        migrationFlagSentinels.forEach { flag in
            #expect(defaults.object(forKey: flag.key) as? Bool == flag.value)
        }
    }

    private var migrationFlagSentinels: [(key: String, value: Bool)] {
        [
            (Constants.HotKey.migrateNewKeyCombo, false),
            (Constants.HotKey.migrateOptionCommandDefaultKeyCombos, true),
            (Constants.HotKey.migrateSnippetDefaultKeyComboToF, false),
            (Constants.HotKey.historyPanelShortcutDefaultsMigrated, false),
            (Constants.HotKey.migrateHistoryPanelOptionCommand, true),
            (Constants.HotKey.migrateHistoryPanelCanonicalDefaults, false),
            (Constants.HotKey.migrateHistoryPanelCanonicalDefaultsV2, true),
            (Constants.HotKey.migrateHistoryPanelCommandDefaults, false)
        ]
    }
}
