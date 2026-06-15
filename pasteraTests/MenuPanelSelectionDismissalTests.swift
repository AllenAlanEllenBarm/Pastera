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

    @Test
    func historyPanelInheritsMainMenuPasteTargetContext() throws {
        let history = PasteboardHistory(
            id: PasteboardHistory.ID("history-1"),
            title: "First History",
            pasteboardTypes: [.string],
            updateAt: 1,
            deviceID: CPYUtilities.deviceID
        )
        let targetContext = PasteTargetContext(
            processIdentifier: 24_680,
            bundleIdentifier: "com.example.editor",
            application: nil,
            focusedElement: nil
        )

        try withDependencies {
            $0.pasteboardHistoryRepository = StaticHistoryRepository(details: [
                PasteboardHistoryDetail(history: history, thumbnailAsset: nil)
            ])
            $0.snippetRepository = StaticSelectionSnippetRepository(details: [])
        } operation: {
            let manager = MenuManager()
            manager.showMainMenuPanelForTesting(at: NSPoint(x: 120, y: 480), pasteTargetContext: targetContext)
            manager.showHistoryBrowserPanelForTesting(at: NSPoint(x: 120, y: 480))
            defer { manager.closeMainMenuPanelForTesting() }

            #expect(manager.mainMenuTargetPIDForTesting == targetContext.processIdentifier)
            #expect(manager.historyTargetPIDForTesting == targetContext.processIdentifier)
        }
    }

    @Test
    func selectingHistoryItemSchedulesSelectionAfterPanelDismissal() throws {
        let history = PasteboardHistory(
            id: PasteboardHistory.ID("history-1"),
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
            var scheduledDelays = [TimeInterval]()
            var scheduledWork = [() -> Void]()
            manager.selectionActionScheduler = { delay, work in
                scheduledDelays.append(delay)
                scheduledWork.append(work)
            }

            manager.popUpMenu(.main)
            manager.showHistoryBrowserPanelForTesting(at: NSPoint(x: 120, y: 480))
            defer { manager.closeMainMenuPanelForTesting() }

            manager.confirmFirstHistoryForTesting()

            #expect(!manager.isMainMenuPanelVisibleForTesting)
            #expect(manager.historyBrowserPanelFrameForTesting == nil)
            #expect(scheduledDelays.count == 1)
            let delay = try #require(scheduledDelays.first)
            #expect((0.04...0.06).contains(delay))
            #expect(scheduledWork.count == 1)
        }
    }

    @Test
    func selectingImageHistoryItemHidesPreviewBeforeSchedulingSelection() throws {
        let history = PasteboardHistory(
            id: PasteboardHistory.ID("history-image"),
            title: "(Image)",
            pasteboardTypes: [.png],
            updateAt: 1,
            deviceID: CPYUtilities.deviceID
        )
        let image = NSImage.create(with: .red, size: NSSize(width: 24, height: 18))
        let imageData = try #require(image.tiffRepresentation)

        try withDependencies {
            $0.pasteboardHistoryRepository = StaticHistoryRepository(details: [
                PasteboardHistoryDetail(
                    history: history,
                    thumbnailAsset: PasteboardHistoryThumbnailAsset(
                        pasteboardHistoryID: history.id,
                        kind: .image,
                        data: imageData
                    )
                )
            ])
            $0.snippetRepository = StaticSelectionSnippetRepository(details: [])
        } operation: {
            let manager = MenuManager()
            var scheduledWork = [() -> Void]()
            manager.selectionActionScheduler = { _, work in
                scheduledWork.append(work)
            }

            manager.popUpMenu(.main)
            manager.showHistoryBrowserPanelForTesting(at: NSPoint(x: 120, y: 480))
            defer { manager.closeMainMenuPanelForTesting() }

            manager.focusFirstHistoryForTesting()
            #expect(HistoryMenuRowView.isImagePreviewVisibleForTesting)

            manager.confirmFirstHistoryForTesting()

            #expect(!HistoryMenuRowView.isImagePreviewVisibleForTesting)
            #expect(manager.historyBrowserPanelFrameForTesting == nil)
            #expect(scheduledWork.count == 1)
        }
    }

    @Test
    func snippetFolderPanelInheritsMainMenuPasteTargetContext() throws {
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
        let targetContext = PasteTargetContext(
            processIdentifier: 13_579,
            bundleIdentifier: "com.example.editor",
            application: nil,
            focusedElement: nil
        )

        try withDependencies {
            $0.snippetRepository = StaticSelectionSnippetRepository(details: [detail])
        } operation: {
            let manager = MenuManager()
            manager.showMainMenuPanelForTesting(at: NSPoint(x: 120, y: 480), pasteTargetContext: targetContext)
            manager.showSnippetFolderPanelForTesting(folderID)
            defer { manager.closeMainMenuPanelForTesting() }

            #expect(manager.mainMenuTargetPIDForTesting == targetContext.processIdentifier)
            #expect(manager.snippetTargetPIDForTesting == targetContext.processIdentifier)
        }
    }

    @Test
    func selectingSnippetItemSchedulesSelectionAfterPanelDismissal() throws {
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

        try withDependencies {
            $0.snippetRepository = StaticSelectionSnippetRepository(details: [detail])
        } operation: {
            let manager = MenuManager()
            var scheduledDelays = [TimeInterval]()
            var scheduledWork = [() -> Void]()
            manager.selectionActionScheduler = { delay, work in
                scheduledDelays.append(delay)
                scheduledWork.append(work)
            }

            manager.popUpMenu(.main)
            manager.showSnippetFolderPanelForTesting(folderID)
            defer { manager.closeMainMenuPanelForTesting() }

            manager.confirmFirstSnippetForTesting()

            #expect(!manager.isMainMenuPanelVisibleForTesting)
            #expect(manager.snippetBrowserPanelFrameForTesting == nil)
            #expect(scheduledDelays.count == 1)
            let delay = try #require(scheduledDelays.first)
            #expect((0.04...0.06).contains(delay))
            #expect(scheduledWork.count == 1)
        }
    }
}

@MainActor
@Suite(.serialized)
struct PasteServiceTargetRestoreTests {
    @Test
    func waitsForTargetBeforeSendingPasteCommand() {
        let context = makeTargetContext(processIdentifier: 4_242)
        var isTargetFrontmost = false
        let probe = PasteRestoreProbe()
        let service = makePasteService(
            context: context,
            isTargetFrontmost: { isTargetFrontmost },
            probe: probe
        )

        service.paste(restoring: context)

        #expect(probe.events == ["activate", "schedule"])
        #expect(probe.delays == [0.02])
        isTargetFrontmost = true
        probe.scheduledWork.removeFirst()()
        #expect(probe.events == ["activate", "schedule", "focus", "schedule"])
        #expect(probe.delays == [0.02, 0.04])
        probe.scheduledWork.removeFirst()()
        #expect(probe.events == ["activate", "schedule", "focus", "schedule", "paste"])
        #expect(probe.scheduledWork.isEmpty)
    }

    @Test
    func timeoutUsesBoundedRetriesAndSendsPasteOnce() {
        let context = makeTargetContext(processIdentifier: 5_353)
        let probe = PasteRestoreProbe()
        let service = makePasteService(
            context: context,
            isTargetFrontmost: { false },
            probe: probe
        )

        service.paste(restoring: context)
        while !probe.scheduledWork.isEmpty {
            probe.scheduledWork.removeFirst()()
        }

        #expect(probe.delays.filter { $0 == 0.02 }.count == 12)
        #expect(probe.delays.last == 0.04)
        #expect(probe.events.filter { $0 == "paste" }.count == 1)
        #expect(Array(probe.events.suffix(3)) == ["focus", "schedule", "paste"])
    }

    @Test
    func missingAccessibilityPermissionDoesNotSchedulePaste() {
        let context = makeTargetContext(processIdentifier: 6_464)
        let probe = PasteRestoreProbe()
        let service = PasteService(
            inputPasteCommandEnabledProvider: { true },
            accessibilityEnabledProvider: { false },
            accessibilityAlertPresenter: { probe.events.append("alert") },
            frontmostProcessIdentifierProvider: { context.processIdentifier },
            targetApplicationActivator: { _ in probe.events.append("activate") },
            focusedElementRestorer: { _ in probe.events.append("focus") },
            pasteCommandSender: { probe.events.append("paste") },
            scheduleAfter: { _, _ in probe.events.append("schedule") }
        )

        service.paste(restoring: context)

        #expect(probe.events == ["alert"])
    }

    private func makeTargetContext(processIdentifier: pid_t) -> PasteTargetContext {
        PasteTargetContext(
            processIdentifier: processIdentifier,
            bundleIdentifier: "com.example.editor",
            application: nil,
            focusedElement: nil
        )
    }

    private func makePasteService(
        context: PasteTargetContext,
        isTargetFrontmost: @escaping () -> Bool,
        probe: PasteRestoreProbe
    ) -> PasteService {
        PasteService(
            inputPasteCommandEnabledProvider: { true },
            accessibilityEnabledProvider: { true },
            accessibilityAlertPresenter: { probe.events.append("alert") },
            frontmostProcessIdentifierProvider: {
                isTargetFrontmost() ? context.processIdentifier : 0
            },
            targetApplicationActivator: { _ in probe.events.append("activate") },
            focusedElementRestorer: { _ in probe.events.append("focus") },
            pasteCommandSender: { probe.events.append("paste") },
            scheduleAfter: { delay, work in
                #expect(delay == 0.02 || delay == 0.04)
                probe.delays.append(delay)
                probe.events.append("schedule")
                probe.scheduledWork.append(work)
            }
        )
    }
}

private final class PasteRestoreProbe {
    var events = [String]()
    var delays = [TimeInterval]()
    var scheduledWork = [() -> Void]()
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
