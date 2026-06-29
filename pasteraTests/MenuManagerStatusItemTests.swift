//
//  MenuManagerStatusItemTests.swift
//
//  Clipy
//

import AppKit
import Combine
import Carbon
import Dependencies
import Testing
@testable import Pastera

@MainActor
@Suite(.serialized)
struct MenuManagerStatusItemTests {
    @Test
    func fromStoragePreservesInjectedDefaultsForStartupPreferences() throws {
        let suiteName = "MenuManagerStatusItemTests.fromStorage.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let environment = AppEnvironment.fromStorage(defaults: defaults)

        #expect(environment.defaults === defaults)
    }

    @Test
    func fromStorageRecreatesRuntimeServicesAfterDependencyBootstrap() throws {
        let suiteName = "MenuManagerStatusItemTests.freshServices.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let clipService = ClipService()
        let hotKeyService = HotKeyService()
        let pasteService = PasteService()
        let excludeAppService = ExcludeAppService(applications: [])
        let accessibilityService = AccessibilityService()
        let menuManager = MenuManager()
        AppEnvironment.push(
            clipService: clipService,
            hotKeyService: hotKeyService,
            pasteService: pasteService,
            excludeAppService: excludeAppService,
            accessibilityService: accessibilityService,
            menuManager: menuManager,
            defaults: defaults
        )
        defer { _ = AppEnvironment.popLast() }

        let environment = AppEnvironment.fromStorage(defaults: defaults)

        #expect(environment.defaults === defaults)
        #expect(environment.clipService !== clipService)
        #expect(environment.hotKeyService !== hotKeyService)
        #expect(environment.pasteService !== pasteService)
        #expect(environment.excludeAppService !== excludeAppService)
        #expect(environment.accessibilityService !== accessibilityService)
        #expect(environment.menuManager !== menuManager)
    }

    @Test
    func setupCreatesStatusItemFromRegisteredDefaultWhenNoPersistentPreferenceExists() throws {
        try withRegisteredDefaultEnvironment { defaults, suiteName in
            #expect(defaults.persistentDomain(forName: suiteName)?[Constants.UserDefaults.showStatusItem] == nil)

            let manager = MenuManager()
            manager.setup()
            defer { manager.removeStatusItemForTesting() }

            #expect(manager.hasStatusItemForTesting)
            #expect(manager.statusItemImageForTesting?.isTemplate == true)
            #expect(manager.statusItemActionForTesting == #selector(MenuManager.statusItemButtonClicked(_:)))
        }
    }

    @Test
    func statusItemTooltipExplainsSecureKeyboardEntryFallback() throws {
        try withRegisteredDefaultEnvironment { _, _ in
            let manager = MenuManager()
            manager.secureEventInputEnabledProvider = { true }
            manager.setup()
            defer { manager.removeStatusItemForTesting() }

            let toolTip = try #require(manager.statusItem?.toolTip)
            #expect(toolTip.contains(String(localized: "Secure Keyboard Entry is active. macOS may block global shortcuts; click this menu bar icon to open Pastera.")))
        }
    }

    @Test
    func statusItemUsesWarningTintWhileSecureKeyboardEntryIsActive() throws {
        try withRegisteredDefaultEnvironment { _, _ in
            var isSecureEventInputEnabled = true
            let manager = MenuManager()
            manager.secureEventInputEnabledProvider = { isSecureEventInputEnabled }
            manager.setup()
            defer { manager.removeStatusItemForTesting() }

            #expect(manager.statusItemTintColorForTesting?.isEqual(NSColor.systemOrange) == true)

            isSecureEventInputEnabled = false
            manager.refreshSecureEventInputStatus()

            #expect(manager.statusItemTintColorForTesting == nil)
        }
    }

    @Test
    func mainMenuShowsSecureKeyboardEntryNoticeWhenShortcutsAreBlocked() throws {
        try withRegisteredDefaultEnvironment { _, _ in
            let manager = MenuManager()
            manager.secureEventInputEnabledProvider = { true }

            #expect(manager.mainMenuNoticeTitlesForTesting == [String(localized: "Shortcuts are paused")])
        }
    }

    @Test
    func mainMenuHidesSecureKeyboardEntryNoticeWhenShortcutsAreAvailable() throws {
        try withRegisteredDefaultEnvironment { _, _ in
            let manager = MenuManager()
            manager.secureEventInputEnabledProvider = { false }

            #expect(manager.mainMenuNoticeTitlesForTesting.isEmpty)
        }
    }

    @Test
    func secureKeyboardEntryUsesLegacyMenuFallbackForHotkeyPopups() throws {
        try withRegisteredDefaultEnvironment { _, _ in
            let manager = MenuManager()
            manager.secureEventInputEnabledProvider = { true }

            #expect(manager.shouldUseLegacyMenuFallbackForTesting)
        }
    }

    @Test
    func normalInputUsesPanelPresentationForHotkeyPopups() throws {
        try withRegisteredDefaultEnvironment { _, _ in
            let manager = MenuManager()
            manager.secureEventInputEnabledProvider = { false }

            #expect(!manager.shouldUseLegacyMenuFallbackForTesting)
        }
    }

    @Test
    func setupUsesTemplateStatusItemWhenPreferenceIsLegacyWhite() throws {
        try withRegisteredDefaultEnvironment { defaults, _ in
            defaults.set(2, forKey: Constants.UserDefaults.showStatusItem)

            let manager = MenuManager()
            manager.setup()
            defer { manager.removeStatusItemForTesting() }

            #expect(manager.hasStatusItemForTesting)
            #expect(manager.statusItemImageForTesting?.isTemplate == true)
        }
    }

    @Test
    func setupMigratesLegacyNonePreferenceToVisibleStatusItem() throws {
        try withRegisteredDefaultEnvironment { defaults, _ in
            defaults.set(0, forKey: Constants.UserDefaults.showStatusItem)

            let manager = MenuManager()
            manager.setup()
            defer { manager.removeStatusItemForTesting() }

            #expect(manager.hasStatusItemForTesting)
            #expect(manager.statusItemImageForTesting?.isTemplate == true)
        }
    }

    @Test
    func legacyMenuIconsStayVisibleWhenRetiredPreferenceWasPreviouslyDisabled() throws {
        try withRegisteredDefaultEnvironment { defaults, _ in
            defaults.set(false, forKey: "kCPYPrefShowIconInTheMenuKey")
            let snippet = Snippet(
                id: Snippet.ID(rawValue: UUID()),
                folderID: SnippetFolder.ID(rawValue: UUID()),
                title: "Ask GPT",
                content: "Summarize this",
                index: 0,
                isEnabled: true
            )
            let menuManager = MenuManager()

            #expect(menuManager.makeSubmenuItem("AI Prompt").image != nil)
            #expect(menuManager.makeSnippetMenuItemForTesting(snippet, listNumber: 1, rowIndex: 0).image != nil)
        }
    }

    @Test
    func setupDoesNotFetchHistoryDetailsWhenHistoryChangesAndPanelsAreClosed() throws {
        try withRegisteredDefaultEnvironment { _, _ in
            let historyRepository = CountingHistoryChangeRepository()

            try withDependencies {
                $0.mainQueue = .immediate
                $0.pasteboardHistoryRepository = historyRepository
                $0.snippetRepository = StatusItemEmptySnippetRepository()
            } operation: {
                let manager = MenuManager()
                manager.setup()
                defer { manager.removeStatusItemForTesting() }

                historyRepository.sendChange()

                #expect(historyRepository.fetchHistoryDetailsCallCount == 0)
                #expect(historyRepository.searchHistoryDetailsCallCount == 0)
            }
        }
    }

    @Test
    func setupDoesNotFetchSnippetDetailsWhenFoldersChangeAndPanelsAreClosed() throws {
        try withRegisteredDefaultEnvironment { _, _ in
            let snippetRepository = CountingFolderChangeRepository()

            try withDependencies {
                $0.mainQueue = .immediate
                $0.pasteboardHistoryRepository = StatusItemEmptyHistoryRepository()
                $0.snippetRepository = snippetRepository
            } operation: {
                let manager = MenuManager()
                manager.setup()
                defer { manager.removeStatusItemForTesting() }

                snippetRepository.sendChange()

                #expect(snippetRepository.fetchFoldersCallCount == 0)
                #expect(snippetRepository.fetchFolderDetailsCallCount == 0)
            }
        }
    }

    private func withRegisteredDefaultEnvironment(
        operation: (UserDefaults, String) throws -> Void
    ) throws {
        let suiteName = "MenuManagerStatusItemTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        AppEnvironment.push(defaults: defaults)
        defer {
            _ = AppEnvironment.popLast()
            defaults.removePersistentDomain(forName: suiteName)
        }

        CPYUtilities.registerUserDefaultKeys()
        try withDependencies {
            $0.mainQueue = .immediate
            $0.pasteboardHistoryRepository = StatusItemEmptyHistoryRepository()
            $0.snippetRepository = StatusItemEmptySnippetRepository()
        } operation: {
            try operation(defaults, suiteName)
        }
    }
}

private struct StatusItemEmptyHistoryRepository: PasteboardHistoryRepositoryProtocol {
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

private final class CountingHistoryChangeRepository: PasteboardHistoryRepositoryProtocol {
    private let changes = PassthroughSubject<Void, Never>()
    private(set) var fetchHistoryDetailsCallCount = 0
    private(set) var searchHistoryDetailsCallCount = 0

    func sendChange() {
        changes.send(())
    }

    func observeHistoryChanges() -> AnyPublisher<Void, Never> {
        changes.eraseToAnyPublisher()
    }

    func observeHistories() -> AnyPublisher<[PasteboardHistory], Never> {
        Just([]).eraseToAnyPublisher()
    }

    func hasHistories() -> Bool { false }

    func fetchHistoryDetails(
        ascending: Bool,
        includesThumbnailAsset: Bool,
        limit: Int,
        offset: Int
    ) -> [PasteboardHistoryDetail] {
        fetchHistoryDetailsCallCount += 1
        return []
    }

    func searchHistoryDetails(
        query: HistorySearchQuery,
        includesThumbnailAsset: Bool,
        limit: Int,
        offset: Int
    ) throws -> [PasteboardHistoryDetail] {
        searchHistoryDetailsCallCount += 1
        return []
    }

    func fetchHistory(id: PasteboardHistory.ID) -> PasteboardHistory? { nil }
    func fetchContent(id: PasteboardHistory.ID) -> PasteboardContent? { nil }
    func save(id: PasteboardHistory.ID, content: PasteboardContent, updateAt: Int) {}
    func deleteHistory(id: PasteboardHistory.ID) {}
    func deleteAll() {}
    func deleteOverflowingHistories(maxHistorySize: Int) {}
    func pruneHistories(settings: HistoryRetentionSettings) {}
}

private struct StatusItemEmptySnippetRepository: SnippetRepositoryProtocol {
    func observeFolderDetails() -> AnyPublisher<[SnippetFolderDetail], Never> {
        Just([]).eraseToAnyPublisher()
    }

    func fetchFolderDetails() -> [SnippetFolderDetail] { [] }
    func fetchFolderDetail(id: SnippetFolder.ID) -> SnippetFolderDetail? { nil }
    func fetchSyncSnapshot() -> SnippetSyncSnapshot { SnippetSyncSnapshot(folders: [], snippets: []) }
    func insertFolder() -> SnippetFolder? { nil }
    func insertFolders(_ folders: [(title: String, snippets: [(title: String, content: String)])]) -> [SnippetFolderDetail]? { nil }
    func upsertSyncSnapshot(_ snapshot: SnippetSyncSnapshot) -> Int { 0 }
    func removeDuplicateFoldersAndSnippets() -> Int { 0 }
    func updateFolderTitle(_ id: SnippetFolder.ID, title: String) -> Bool { true }
    func updateFolderIsEnabled(_ id: SnippetFolder.ID, isEnabled: Bool) {}
    func updateFolderIndexes(_ folderIDs: [SnippetFolder.ID]) {}
    func deleteFolder(_ id: SnippetFolder.ID) {}
    func fetchSnippet(id: Snippet.ID) -> Snippet? { nil }
    func insertSnippet(to id: SnippetFolder.ID) -> Snippet? { nil }
    func updateSnippetTitle(_ id: Snippet.ID, title: String) {}
    func updateSnippetContent(_ id: Snippet.ID, content: String) -> Bool { true }
    func updateSnippetIsEnabled(_ id: Snippet.ID, isEnabled: Bool) {}
    func updateSnippetIndexes(_ snippetIDs: [Snippet.ID]) {}
    func moveSnippet(_ id: Snippet.ID, to folderID: SnippetFolder.ID, snippetIDs: [Snippet.ID]) {}
    func deleteSnippet(_ id: Snippet.ID) {}
}

private final class CountingFolderChangeRepository: SnippetRepositoryProtocol {
    private let folders = PassthroughSubject<[SnippetFolder], Never>()
    private(set) var fetchFoldersCallCount = 0
    private(set) var fetchFolderDetailsCallCount = 0

    func sendChange() {
        folders.send([])
    }

    func observeFolders() -> AnyPublisher<[SnippetFolder], Never> {
        folders.eraseToAnyPublisher()
    }

    func observeFolderDetails() -> AnyPublisher<[SnippetFolderDetail], Never> {
        Just([]).eraseToAnyPublisher()
    }

    func fetchFolders() -> [SnippetFolder] {
        fetchFoldersCallCount += 1
        return []
    }

    func fetchFolderDetails() -> [SnippetFolderDetail] {
        fetchFolderDetailsCallCount += 1
        return []
    }

    func fetchFolderDetail(id: SnippetFolder.ID) -> SnippetFolderDetail? { nil }
    func fetchSyncSnapshot() -> SnippetSyncSnapshot { SnippetSyncSnapshot(folders: [], snippets: []) }
    func insertFolder() -> SnippetFolder? { nil }
    func insertFolders(_ folders: [(title: String, snippets: [(title: String, content: String)])]) -> [SnippetFolderDetail]? { nil }
    func upsertSyncSnapshot(_ snapshot: SnippetSyncSnapshot) -> Int { 0 }
    func removeDuplicateFoldersAndSnippets() -> Int { 0 }
    func updateFolderTitle(_ id: SnippetFolder.ID, title: String) -> Bool { true }
    func updateFolderIsEnabled(_ id: SnippetFolder.ID, isEnabled: Bool) {}
    func updateFolderIndexes(_ folderIDs: [SnippetFolder.ID]) {}
    func deleteFolder(_ id: SnippetFolder.ID) {}
    func fetchSnippet(id: Snippet.ID) -> Snippet? { nil }
    func insertSnippet(to id: SnippetFolder.ID) -> Snippet? { nil }
    func updateSnippetTitle(_ id: Snippet.ID, title: String) {}
    func updateSnippetContent(_ id: Snippet.ID, content: String) -> Bool { true }
    func updateSnippetIsEnabled(_ id: Snippet.ID, isEnabled: Bool) {}
    func updateSnippetIndexes(_ snippetIDs: [Snippet.ID]) {}
    func moveSnippet(_ id: Snippet.ID, to folderID: SnippetFolder.ID, snippetIDs: [Snippet.ID]) {}
    func deleteSnippet(_ id: Snippet.ID) {}
}
