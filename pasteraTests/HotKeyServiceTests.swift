import Carbon
import Foundation
import Magnet
import Testing
@testable import Pastera

@Suite(.serialized)
final class HotKeyServiceTests {
    init() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Constants.UserDefaults.hotKeys)
        defaults.removeObject(forKey: Constants.HotKey.migrateNewKeyCombo)
        defaults.removeObject(forKey: Constants.HotKey.mainKeyCombo)
        defaults.removeObject(forKey: Constants.HotKey.historyKeyCombo)
        defaults.removeObject(forKey: Constants.HotKey.snippetKeyCombo)
        defaults.removeObject(forKey: Constants.HotKey.clearHistoryKeyCombo)
        defaults.removeObject(forKey: Constants.HotKey.historyPanelShortcutDefaultsMigrated)
        defaults.removeObject(forKey: Constants.HotKey.migrateHistoryPanelOptionCommand)
        defaults.removeObject(forKey: Constants.HotKey.migrateHistoryPanelCanonicalDefaults)
        defaults.removeObject(forKey: Constants.HotKey.migrateHistoryPanelCanonicalDefaultsV2)
        defaults.removeObject(forKey: Constants.HotKey.migrateHistoryPanelCommandDefaults)
        defaults.removeObject(forKey: Constants.HotKey.historySearchKeyCombo)
        defaults.removeObject(forKey: Constants.HotKey.historyNextPageKeyCombo)
        defaults.removeObject(forKey: Constants.HotKey.historyPreviousPageKeyCombo)
        defaults.removeObject(forKey: Constants.HotKey.migrateOptionCommandDefaultKeyCombos)
        defaults.removeObject(forKey: Constants.HotKey.folderKeyCombos)
        defaults.synchronize()
    }

    deinit {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Constants.UserDefaults.hotKeys)
        defaults.removeObject(forKey: Constants.HotKey.migrateNewKeyCombo)
        defaults.removeObject(forKey: Constants.HotKey.mainKeyCombo)
        defaults.removeObject(forKey: Constants.HotKey.historyKeyCombo)
        defaults.removeObject(forKey: Constants.HotKey.snippetKeyCombo)
        defaults.removeObject(forKey: Constants.HotKey.clearHistoryKeyCombo)
        defaults.removeObject(forKey: Constants.HotKey.historyPanelShortcutDefaultsMigrated)
        defaults.removeObject(forKey: Constants.HotKey.migrateHistoryPanelOptionCommand)
        defaults.removeObject(forKey: Constants.HotKey.migrateHistoryPanelCanonicalDefaults)
        defaults.removeObject(forKey: Constants.HotKey.migrateHistoryPanelCanonicalDefaultsV2)
        defaults.removeObject(forKey: Constants.HotKey.migrateHistoryPanelCommandDefaults)
        defaults.removeObject(forKey: Constants.HotKey.historySearchKeyCombo)
        defaults.removeObject(forKey: Constants.HotKey.historyNextPageKeyCombo)
        defaults.removeObject(forKey: Constants.HotKey.historyPreviousPageKeyCombo)
        defaults.removeObject(forKey: Constants.HotKey.migrateOptionCommandDefaultKeyCombos)
        defaults.removeObject(forKey: Constants.HotKey.folderKeyCombos)
        defaults.synchronize()
    }

    @Test
    func migrateDefaultSettings() throws {
        let service = HotKeyService()
        #expect(service.mainKeyCombo == nil)
        #expect(service.historyKeyCombo == nil)
        #expect(service.snippetKeyCombo == nil)

        let defaults = UserDefaults.standard
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
        #expect(snippetKeyCombo.QWERTYKeyCode == 11)
        #expect(snippetKeyCombo.modifiers == cmdKey | optionKey)
        #expect(snippetKeyCombo.doubledModifiers == false)
        #expect(snippetKeyCombo.keyEquivalent.uppercased() == "B")
    }

    @Test
    func shortcutFormatterUsesCompactMacSymbols() throws {
        let mainKeyCombo = try #require(KeyCombo(QWERTYKeyCode: 9, carbonModifiers: cmdKey | shiftKey))
        let historyKeyCombo = try #require(KeyCombo(QWERTYKeyCode: 9, carbonModifiers: cmdKey | optionKey))
        let snippetKeyCombo = try #require(KeyCombo(QWERTYKeyCode: 11, carbonModifiers: cmdKey | optionKey))
        let searchKeyCombo = try #require(KeyCombo(QWERTYKeyCode: 3, carbonModifiers: cmdKey))
        let previousPageKeyCombo = try #require(KeyCombo(QWERTYKeyCode: 123, carbonModifiers: cmdKey))
        let nextPageKeyCombo = try #require(KeyCombo(QWERTYKeyCode: 124, carbonModifiers: cmdKey))
        let doubleCommandCombo = try #require(KeyCombo(doubledCocoaModifiers: .command))

        #expect(PasteraShortcutFormatter.string(for: mainKeyCombo) == "⇧⌘V")
        #expect(PasteraShortcutFormatter.string(for: historyKeyCombo) == "⌥⌘V")
        #expect(PasteraShortcutFormatter.string(for: snippetKeyCombo) == "⌥⌘B")
        #expect(PasteraShortcutFormatter.string(for: searchKeyCombo) == "⌘F")
        #expect(PasteraShortcutFormatter.string(for: previousPageKeyCombo) == "⌘←")
        #expect(PasteraShortcutFormatter.string(for: nextPageKeyCombo) == "⌘→")
        #expect(PasteraShortcutFormatter.string(for: doubleCommandCombo) == "⌘⌘")
        #expect(PasteraShortcutFormatter.string(for: nil) == nil)
    }

    @Test
    func historyPanelShortcutDefaultsAreLocalKeyCombos() throws {
        let service = HotKeyService()

        service.setupDefaultHotKeys()

        let searchKeyCombo = try #require(service.historyPanelKeyCombo(for: .search))
        let previousPageKeyCombo = try #require(service.historyPanelKeyCombo(for: .previousPage))
        let nextPageKeyCombo = try #require(service.historyPanelKeyCombo(for: .nextPage))

        #expect(searchKeyCombo.QWERTYKeyCode == 3)
        #expect(searchKeyCombo.modifiers == cmdKey)
        #expect(PasteraShortcutFormatter.string(for: searchKeyCombo) == "⌘F")

        #expect(previousPageKeyCombo.QWERTYKeyCode == 123)
        #expect(previousPageKeyCombo.modifiers == cmdKey)
        #expect(PasteraShortcutFormatter.string(for: previousPageKeyCombo) == "⌘←")

        #expect(nextPageKeyCombo.QWERTYKeyCode == 124)
        #expect(nextPageKeyCombo.modifiers == cmdKey)
        #expect(PasteraShortcutFormatter.string(for: nextPageKeyCombo) == "⌘→")
    }

    @Test
    func historyPanelDefaultsAreRestoredWhenMigrationMarkerExistsButKeysAreMissing() throws {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: Constants.HotKey.historyPanelShortcutDefaultsMigrated)
        defaults.removeObject(forKey: Constants.HotKey.historySearchKeyCombo)
        defaults.removeObject(forKey: Constants.HotKey.historyPreviousPageKeyCombo)
        defaults.removeObject(forKey: Constants.HotKey.historyNextPageKeyCombo)

        let service = HotKeyService()
        service.setupDefaultHotKeys()

        #expect(service.historyPanelKeyCombo(for: .search) == HistoryPanelShortcut.search.defaultKeyCombo)
        #expect(service.historyPanelKeyCombo(for: .previousPage) == HistoryPanelShortcut.previousPage.defaultKeyCombo)
        #expect(service.historyPanelKeyCombo(for: .nextPage) == HistoryPanelShortcut.nextPage.defaultKeyCombo)
    }

    @Test
    func preservesCommandHistoryPanelShortcutsAsDefaults() throws {
        let defaults = UserDefaults.standard
        let legacySearch = try #require(KeyCombo(QWERTYKeyCode: 3, carbonModifiers: cmdKey))
        let legacyPreviousPage = try #require(KeyCombo(QWERTYKeyCode: 123, carbonModifiers: cmdKey))
        let legacyNextPage = try #require(KeyCombo(QWERTYKeyCode: 124, carbonModifiers: cmdKey))
        defaults.setArchiveData(legacySearch, forKey: Constants.HotKey.historySearchKeyCombo)
        defaults.setArchiveData(legacyPreviousPage, forKey: Constants.HotKey.historyPreviousPageKeyCombo)
        defaults.setArchiveData(legacyNextPage, forKey: Constants.HotKey.historyNextPageKeyCombo)
        defaults.set(true, forKey: Constants.HotKey.historyPanelShortcutDefaultsMigrated)
        defaults.set(false, forKey: Constants.HotKey.migrateHistoryPanelOptionCommand)

        let service = HotKeyService()
        service.setupDefaultHotKeys()

        #expect(service.historyPanelKeyCombo(for: .search) == HistoryPanelShortcut.search.defaultKeyCombo)
        #expect(service.historyPanelKeyCombo(for: .previousPage) == HistoryPanelShortcut.previousPage.defaultKeyCombo)
        #expect(service.historyPanelKeyCombo(for: .nextPage) == HistoryPanelShortcut.nextPage.defaultKeyCombo)
    }

    @Test
    func preservesCustomizedHistoryPanelShortcutsDuringDefaultMigration() throws {
        let defaults = UserDefaults.standard
        let customSearch = try #require(KeyCombo(QWERTYKeyCode: 3, carbonModifiers: cmdKey | shiftKey))
        let customPreviousPage = try #require(KeyCombo(QWERTYKeyCode: 123, carbonModifiers: cmdKey | controlKey))
        let customNextPage = try #require(KeyCombo(QWERTYKeyCode: 124, carbonModifiers: cmdKey | shiftKey))
        defaults.setArchiveData(customSearch, forKey: Constants.HotKey.historySearchKeyCombo)
        defaults.setArchiveData(customPreviousPage, forKey: Constants.HotKey.historyPreviousPageKeyCombo)
        defaults.setArchiveData(customNextPage, forKey: Constants.HotKey.historyNextPageKeyCombo)
        defaults.set(true, forKey: Constants.HotKey.historyPanelShortcutDefaultsMigrated)
        defaults.set(false, forKey: Constants.HotKey.migrateHistoryPanelOptionCommand)

        let service = HotKeyService()
        service.setupDefaultHotKeys()

        #expect(service.historyPanelKeyCombo(for: .search) == customSearch)
        #expect(service.historyPanelKeyCombo(for: .previousPage) == customPreviousPage)
        #expect(service.historyPanelKeyCombo(for: .nextPage) == customNextPage)
    }

    @Test
    func migratesKnownIncorrectBetaHistoryPanelShortcutsToCommandDefaults() throws {
        let defaults = UserDefaults.standard
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

        let service = HotKeyService()
        service.setupDefaultHotKeys()

        #expect(service.historyPanelKeyCombo(for: .search) == HistoryPanelShortcut.search.defaultKeyCombo)
        #expect(service.historyPanelKeyCombo(for: .previousPage) == HistoryPanelShortcut.previousPage.defaultKeyCombo)
        #expect(service.historyPanelKeyCombo(for: .nextPage) == HistoryPanelShortcut.nextPage.defaultKeyCombo)
    }

    @Test
    func changingHistoryPanelShortcutPersistsWithoutGlobalRegistration() throws {
        let defaults = UserDefaults.standard
        let service = HotKeyService()
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
    func shortcutFormatterUsesNumericShortcutText() {
        #expect(PasteraShortcutFormatter.numericString(forRowIndex: 0, startsAtZero: false) == "1")
        #expect(PasteraShortcutFormatter.numericString(forRowIndex: 8, startsAtZero: false) == "9")
        #expect(PasteraShortcutFormatter.numericString(forRowIndex: 9, startsAtZero: false) == "0")
        #expect(PasteraShortcutFormatter.numericString(forRowIndex: 0, startsAtZero: true) == "0")
        #expect(PasteraShortcutFormatter.numericString(forRowIndex: 10, startsAtZero: false) == nil)
    }

    @Test
    func migrateCustomizeSettings() throws {
        let service = HotKeyService()
        #expect(service.mainKeyCombo == nil)
        #expect(service.historyKeyCombo == nil)
        #expect(service.snippetKeyCombo == nil)

        let defaults = UserDefaults.standard
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
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: Constants.HotKey.migrateNewKeyCombo)

        let service = HotKeyService()
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
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: Constants.HotKey.migrateNewKeyCombo)

        let mainKeyCombo = try #require(KeyCombo(QWERTYKeyCode: 9, carbonModifiers: 768))
        let historyKeyCombo = try #require(KeyCombo(doubledCocoaModifiers: .command))
        let snippetKeyCombo = try #require(KeyCombo(QWERTYKeyCode: 0, cocoaModifiers: .shift))

        defaults.setArchiveData(mainKeyCombo, forKey: Constants.HotKey.mainKeyCombo)
        defaults.setArchiveData(historyKeyCombo, forKey: Constants.HotKey.historyKeyCombo)
        defaults.setArchiveData(snippetKeyCombo, forKey: Constants.HotKey.snippetKeyCombo)

        let service = HotKeyService()
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

        #expect(snippetCombos?["keyCode"] == 11)
        #expect(snippetCombos?["modifiers"] == cmdKey | optionKey)
    }

    @Test
    func migratesLegacyDefaultHistoryAndSnippetHotkeysToOptionCommandDefaults() throws {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: Constants.HotKey.migrateNewKeyCombo)
        defaults.set(false, forKey: Constants.HotKey.migrateOptionCommandDefaultKeyCombos)
        let legacyHistory = try #require(KeyCombo(QWERTYKeyCode: 9, carbonModifiers: cmdKey | controlKey))
        let legacySnippet = try #require(KeyCombo(QWERTYKeyCode: 11, carbonModifiers: cmdKey | shiftKey))
        defaults.setArchiveData(legacyHistory, forKey: Constants.HotKey.historyKeyCombo)
        defaults.setArchiveData(legacySnippet, forKey: Constants.HotKey.snippetKeyCombo)

        let service = HotKeyService()
        service.setupDefaultHotKeys()

        let historyKeyCombo = try #require(service.historyKeyCombo)
        #expect(historyKeyCombo.QWERTYKeyCode == 9)
        #expect(historyKeyCombo.modifiers == cmdKey | optionKey)
        #expect(historyKeyCombo.keyEquivalent.uppercased() == "V")

        let snippetKeyCombo = try #require(service.snippetKeyCombo)
        #expect(snippetKeyCombo.QWERTYKeyCode == 11)
        #expect(snippetKeyCombo.modifiers == cmdKey | optionKey)
        #expect(snippetKeyCombo.keyEquivalent.uppercased() == "B")
        #expect(defaults.bool(forKey: Constants.HotKey.migrateOptionCommandDefaultKeyCombos))
    }

    @Test
    func preservesCustomizedHistoryAndSnippetHotkeysDuringOptionCommandDefaultMigration() throws {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: Constants.HotKey.migrateNewKeyCombo)
        defaults.set(false, forKey: Constants.HotKey.migrateOptionCommandDefaultKeyCombos)
        let customHistory = try #require(KeyCombo(QWERTYKeyCode: 9, carbonModifiers: cmdKey | shiftKey))
        let customSnippet = try #require(KeyCombo(QWERTYKeyCode: 11, carbonModifiers: cmdKey | controlKey))
        defaults.setArchiveData(customHistory, forKey: Constants.HotKey.historyKeyCombo)
        defaults.setArchiveData(customSnippet, forKey: Constants.HotKey.snippetKeyCombo)

        let service = HotKeyService()
        service.setupDefaultHotKeys()

        #expect(service.historyKeyCombo == customHistory)
        #expect(service.snippetKeyCombo == customSnippet)
        #expect(defaults.bool(forKey: Constants.HotKey.migrateOptionCommandDefaultKeyCombos))
    }

    @Test
    func defaultSnippetFolderHotkeysUsePreferredOptionCommandOrder() throws {
        let service = HotKeyService()
        let identifiers = (0..<8).map { "default-folder-\($0)" }
        defer { identifiers.forEach(service.unregisterSnippetHotKey) }

        let expectedKeys: [(keyCode: Int, key: String)] = [
            (12, "Q"),
            (13, "W"),
            (14, "E"),
            (15, "R"),
            (0, "A"),
            (1, "S"),
            (2, "D"),
            (3, "F")
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
        let service = HotKeyService()
        let identifiers = (0..<9).map { "reserved-folder-\($0)" }
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
    func remoteSessionPolicySuspendsLocalHotkeysForScreenSharing() {
        #expect(RemoteSessionHotKeyPolicy.shouldSuspendLocalHotKeys(frontmostApplicationBundleIdentifier: "com.apple.ScreenSharing"))
        #expect(!RemoteSessionHotKeyPolicy.shouldSuspendLocalHotKeys(frontmostApplicationBundleIdentifier: "com.apple.finder"))
        #expect(!RemoteSessionHotKeyPolicy.shouldSuspendLocalHotKeys(frontmostApplicationBundleIdentifier: nil))
    }

    @Test
    func addAndRemoveClearHistoryHotkey() throws {
        let service = HotKeyService()

        #expect(service.clearHistoryKeyCombo == nil)

        let keyCombo = try #require(KeyCombo(QWERTYKeyCode: 10, carbonModifiers: cmdKey))
        service.changeClearHistoryKeyCombo(keyCombo)

        #expect(service.clearHistoryKeyCombo != nil)
        #expect(service.clearHistoryKeyCombo == keyCombo)

        let defaults = UserDefaults.standard
        let savedData = try #require(defaults.object(forKey: Constants.HotKey.clearHistoryKeyCombo) as? Data)
        let savedKeyCombo = try #require(NSKeyedUnarchiver.unarchiveObject(with: savedData) as? KeyCombo)
        #expect(savedKeyCombo == keyCombo)

        service.changeClearHistoryKeyCombo(nil)
        #expect(service.clearHistoryKeyCombo == nil)
    }
}
