//
//  PasteboardHistoryRepositoryTests.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Shunsuke Furubayashi on 2026/05/28.
//
//  Copyright © 2015-2026 Clipy Project.
//

// swiftlint:disable file_length

import AppKit
import Combine
import DependenciesTestSupport
import SQLiteData
import Testing
@testable import Pastera

@MainActor
@Suite(
    .dependencies {
        try $0.bootstrapDatabase()
    }
)
struct PasteboardHistoryRepositoryTests {
    let repository: PasteboardHistoryRepository

    init() {
        self.repository = PasteboardHistoryRepository()
    }

    @Test(.timeLimit(.minutes(1)))
    func observeHistories() async throws {
        var histories = [[PasteboardHistory]]()
        let cancellable = repository.observeHistories().sink { value in
            histories.append(value)
        }
        defer { _ = cancellable }

        try await waitUntil { histories.count >= 1 }

        let content = PasteboardContent("First")
        let id = PasteboardHistory.ID(rawValue: content.hash)
        repository.save(id: id, content: content, updateAt: 1)
        try await waitUntil { histories.count >= 2 }

        let content2 = PasteboardContent("Second")
        let id2 = PasteboardHistory.ID(rawValue: content2.hash)
        repository.save(id: id2, content: content2, updateAt: 2)
        try await waitUntil { histories.count >= 3 }

        repository.deleteHistory(id: id)
        try await waitUntil { histories.count >= 4 }

        #expect(
            histories == [
                [],
                [PasteboardHistory(id: id, title: "First", updateAt: 1)],
                [PasteboardHistory(id: id2, title: "Second", updateAt: 2), PasteboardHistory(id: id, title: "First", updateAt: 1)],
                [PasteboardHistory(id: id2, title: "Second", updateAt: 2)]
            ]
        )
    }

    @Test
    func saveAndFetchHistory() throws {
        #expect(!repository.hasHistories())

        let content = PasteboardContent("Hello")
        let id = PasteboardHistory.ID(rawValue: content.hash)
        let history = PasteboardHistory(id: id, title: "Hello", updateAt: 1)

        repository.save(id: id, content: content, updateAt: 1)

        #expect(repository.hasHistories())
        #expect(repository.fetchHistory(id: id) == history)
        #expect(repository.fetchContent(id: id) == content)
        #expect(
            repository.fetchHistoryDetails(ascending: false, includesThumbnailAsset: false, limit: 10) == [
                PasteboardHistoryDetail(history: history, thumbnailAsset: nil)
            ]
        )
    }

    @Test
    func fetchHistoryDetailsOrdersAndLimitsHistories() throws {
        let content = PasteboardContent("First")
        let content2 = PasteboardContent("Second")
        let content3 = PasteboardContent("Third")
        let id = PasteboardHistory.ID(rawValue: content.hash)
        let id2 = PasteboardHistory.ID(rawValue: content2.hash)
        let id3 = PasteboardHistory.ID(rawValue: content3.hash)

        repository.save(id: id, content: content, updateAt: 1)
        repository.save(id: id2, content: content2, updateAt: 2)
        repository.save(id: id3, content: content3, updateAt: 3)

        #expect(
            repository
                .fetchHistoryDetails(ascending: false, includesThumbnailAsset: false, limit: 2)
                .map(\.history.id) == [id3, id2]
        )
        #expect(
            repository
                .fetchHistoryDetails(ascending: true, includesThumbnailAsset: false, limit: 2)
                .map(\.history.id) == [id, id2]
        )
    }

    @Test
    func fetchHistoryDetailsOffsetsHistoriesForMenuPages() throws {
        let contents = (1...5).map { PasteboardContent("Item \($0)") }
        let ids = contents.map { PasteboardHistory.ID(rawValue: $0.hash) }

        for (index, content) in contents.enumerated() {
            repository.save(id: ids[index], content: content, updateAt: index + 1)
        }

        #expect(
            repository
                .fetchHistoryDetails(ascending: false, includesThumbnailAsset: false, limit: 2, offset: 2)
                .map(\.history.id) == [ids[2], ids[1]]
        )
    }

    @Test
    func fetchHistoryDetailsIncludesThumbnailAssetsOnlyWhenRequested() throws {
        let textContent = PasteboardContent("Hello")
        let colorContent = PasteboardContent("#ff0000")
        let imageContent = try #require(
            PasteboardContent(image: NSImage.create(with: .blue, size: NSSize(width: 20, height: 20)))
        )
        let textID = PasteboardHistory.ID(rawValue: textContent.hash)
        let colorID = PasteboardHistory.ID(rawValue: colorContent.hash)
        let imageID = PasteboardHistory.ID(rawValue: imageContent.hash)

        repository.save(id: textID, content: textContent, updateAt: 1)
        repository.save(id: colorID, content: colorContent, updateAt: 2)
        repository.save(id: imageID, content: imageContent, updateAt: 3)

        let details = repository.fetchHistoryDetails(
            ascending: false,
            includesThumbnailAsset: true,
            limit: 10
        )
        #expect(details.map(\.history.id) == [imageID, colorID, textID])
        #expect(details[0].thumbnailAsset?.pasteboardHistoryID == imageID)
        #expect(details[0].thumbnailAsset?.kind == .image)
        #expect(details[0].thumbnailAsset?.data.isEmpty == false)
        #expect(details[1].thumbnailAsset?.pasteboardHistoryID == colorID)
        #expect(details[1].thumbnailAsset?.kind == .colorCode)
        #expect(details[1].thumbnailAsset?.data.isEmpty == false)
        #expect(details[2].thumbnailAsset == nil)

        let detailsWithoutThumbnailAssets = repository.fetchHistoryDetails(
            ascending: false,
            includesThumbnailAsset: false,
            limit: 10
        )
        #expect(detailsWithoutThumbnailAssets.map(\.history.id) == [imageID, colorID, textID])
        #expect(detailsWithoutThumbnailAssets.allSatisfy { $0.thumbnailAsset == nil })
    }

    @Test
    func saveExistingHistoryUpdatesStoredHistory() throws {
        let content = PasteboardContent("Same")
        let id = PasteboardHistory.ID(rawValue: content.hash)

        repository.save(id: id, content: content, updateAt: 1)
        repository.save(id: id, content: content, updateAt: 2)

        #expect(
            repository.fetchHistory(id: id) == PasteboardHistory(
                id: id,
                title: "Same",
                updateAt: 2
            )
        )
        #expect(
            repository.fetchHistoryDetails(ascending: false, includesThumbnailAsset: false, limit: 10).map(\.history.id) == [id]
        )
    }

    @Test
    func screenshotImportsKeepSeparateHistoryEntriesEvenWhenImageBytesMatch() throws {
        let defaults = AppEnvironment.current.defaults
        let previousOverwriteSameHistory = defaults.object(forKey: Constants.UserDefaults.overwriteSameHistory)
        let previousCopySameHistory = defaults.object(forKey: Constants.UserDefaults.copySameHistory)
        let previousStoredHistoryLimit = defaults.object(forKey: Constants.UserDefaults.storedHistoryLimit)
        defer {
            restore(previousOverwriteSameHistory, forKey: Constants.UserDefaults.overwriteSameHistory, defaults: defaults)
            restore(previousCopySameHistory, forKey: Constants.UserDefaults.copySameHistory, defaults: defaults)
            restore(previousStoredHistoryLimit, forKey: Constants.UserDefaults.storedHistoryLimit, defaults: defaults)
        }
        defaults.set(true, forKey: Constants.UserDefaults.overwriteSameHistory)
        defaults.set(true, forKey: Constants.UserDefaults.copySameHistory)
        defaults.set(10, forKey: Constants.UserDefaults.storedHistoryLimit)

        let service = ClipService()
        let image = NSImage.create(with: .green, size: NSSize(width: 16, height: 16))

        withDependencies {
            $0.pasteboardHistoryRepository = repository
        } operation: {
            service.create(with: image)
            service.create(with: image)
        }

        let details = repository.fetchHistoryDetails(ascending: false, includesThumbnailAsset: false, limit: 10)
        #expect(details.count == 2)
        #expect(Set(details.map(\.history.id)).count == 2)
        #expect(details.allSatisfy { $0.history.pasteboardTypes == [.tiff] })
    }

    @Test
    func deleteHistory() throws {
        let content = PasteboardContent("Hello")
        let id = PasteboardHistory.ID(rawValue: content.hash)

        repository.save(id: id, content: content, updateAt: 1)
        #expect(repository.fetchHistory(id: id) != nil)

        repository.deleteHistory(id: id)
        #expect(repository.fetchHistory(id: id) == nil)
    }

    @Test
    func syncPayloadsExportOnlyCurrentDeviceChangesAfterCutoffAndSkipLargeAssets() throws {
        let current = PasteboardContent("Current")
        let old = PasteboardContent("Old")
        let remote = PasteboardContent("Remote")
        let large = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .string, data: Data(repeating: 1, count: 8))
            ]
        )
        let currentID = PasteboardHistory.ID(rawValue: current.hash)
        let oldID = PasteboardHistory.ID(rawValue: old.hash)
        let remoteID = PasteboardHistory.ID(rawValue: remote.hash)
        let largeID = PasteboardHistory.ID(rawValue: large.hash)

        repository.save(id: currentID, content: current, updateAt: 10)
        repository.save(id: oldID, content: old, updateAt: 4)
        repository.upsertSyncPayload(PasteboardHistorySyncPayload(
            id: remoteID.rawValue,
            title: "Remote",
            pasteboardTypes: [.string],
            updateAt: 12,
            deviceID: "remote-device",
            assets: [PasteboardHistorySyncPayload.Asset(type: .string, data: Data("Remote".utf8))],
            thumbnail: nil
        ))
        repository.save(id: largeID, content: large, updateAt: 13)

        let payloads = repository.fetchSyncPayloads(
            currentDeviceID: CPYUtilities.deviceID,
            updatedAtOrAfter: 5,
            maxAssetBytes: 7
        )

        #expect(payloads.map(\.id) == [currentID.rawValue])
        #expect(payloads.first?.deviceID == CPYUtilities.deviceID)
    }

    @Test
    func syncImportDoesNotReuploadRemoteHistoryAndLocalSuppressionPreventsReimport() throws {
        let id = PasteboardHistory.ID(rawValue: "remote-history")
        let payload = PasteboardHistorySyncPayload(
            id: id.rawValue,
            title: "Remote history",
            pasteboardTypes: [.string],
            updateAt: 20,
            deviceID: "remote-device",
            assets: [PasteboardHistorySyncPayload.Asset(type: .string, data: Data("Remote history".utf8))],
            thumbnail: nil
        )

        repository.upsertSyncPayload(payload)
        #expect(repository.fetchHistory(id: id)?.deviceID == "remote-device")
        #expect(repository.fetchSyncPayloads(currentDeviceID: CPYUtilities.deviceID, updatedAtOrAfter: 0, maxAssetBytes: 1024).isEmpty)

        repository.deleteHistory(id: id)
        repository.upsertSyncPayload(payload)

        #expect(repository.fetchHistory(id: id) == nil)
    }

    @Test
    func syncImportUsesLastWriteWinsAndReportsActualHistoryWrites() throws {
        let id = PasteboardHistory.ID(rawValue: "shared-history")
        let localContent = PasteboardContent("Local newer")
        repository.save(id: id, content: localContent, updateAt: 30)

        let olderRemote = PasteboardHistorySyncPayload(
            id: id.rawValue,
            title: "Remote older",
            pasteboardTypes: [.string],
            updateAt: 20,
            deviceID: "remote-device",
            assets: [PasteboardHistorySyncPayload.Asset(type: .string, data: Data("Remote older".utf8))],
            thumbnail: nil
        )
        let newerRemote = PasteboardHistorySyncPayload(
            id: id.rawValue,
            title: "Remote newer",
            pasteboardTypes: [.string],
            updateAt: 40,
            deviceID: "remote-device",
            assets: [PasteboardHistorySyncPayload.Asset(type: .string, data: Data("Remote newer".utf8))],
            thumbnail: nil
        )

        #expect(repository.upsertSyncPayload(olderRemote) == false)
        #expect(repository.fetchHistory(id: id)?.title == "Local newer")
        #expect(repository.fetchContent(id: id) == localContent)

        #expect(repository.upsertSyncPayload(newerRemote) == true)
        #expect(repository.fetchHistory(id: id)?.title == "Remote newer")
        #expect(repository.fetchContent(id: id) == PasteboardContent("Remote newer"))
    }

    @Test
    func deleteAll() throws {
        let content = PasteboardContent("First")
        let content2 = PasteboardContent("Second")
        let id = PasteboardHistory.ID(rawValue: content.hash)
        let id2 = PasteboardHistory.ID(rawValue: content2.hash)

        repository.save(id: id, content: content, updateAt: 1)
        repository.save(id: id2, content: content2, updateAt: 2)
        #expect(repository.hasHistories())

        repository.deleteAll()

        #expect(!repository.hasHistories())
    }

    @Test
    func deleteOverflowingHistories() throws {
        let content = PasteboardContent("First")
        let content2 = PasteboardContent("Second")
        let content3 = PasteboardContent("Third")
        let id = PasteboardHistory.ID(rawValue: content.hash)
        let id2 = PasteboardHistory.ID(rawValue: content2.hash)
        let id3 = PasteboardHistory.ID(rawValue: content3.hash)

        repository.save(id: id, content: content, updateAt: 1)
        repository.save(id: id2, content: content2, updateAt: 2)
        repository.save(id: id3, content: content3, updateAt: 3)

        repository.deleteOverflowingHistories(maxHistorySize: 2)
        #expect(
            repository
                .fetchHistoryDetails(ascending: false, includesThumbnailAsset: false, limit: 10)
                .map(\.history.id) == [id3, id2]
        )
        #expect(repository.fetchHistory(id: id) == nil)

        repository.deleteOverflowingHistories(maxHistorySize: 0)
        #expect(!repository.hasHistories())
    }

    @Test
    func retentionSettingsSeparateMenuDisplayFromStoredHistory() throws {
        let settings = HistoryRetentionSettings(menuDisplayLimit: 1, storedHistoryLimit: 2, maxSyncedAssetBytes: 1024)
        let first = PasteboardContent("First")
        let second = PasteboardContent("Second")
        let third = PasteboardContent("Third")
        let firstID = PasteboardHistory.ID(rawValue: first.hash)
        let secondID = PasteboardHistory.ID(rawValue: second.hash)
        let thirdID = PasteboardHistory.ID(rawValue: third.hash)

        repository.save(id: firstID, content: first, updateAt: 1)
        repository.save(id: secondID, content: second, updateAt: 2)
        repository.save(id: thirdID, content: third, updateAt: 3)

        #expect(
            repository
                .fetchHistoryDetails(ascending: false, includesThumbnailAsset: false, limit: settings.menuDisplayLimit)
                .map(\.history.id) == [thirdID]
        )

        repository.pruneHistories(settings: settings)

        #expect(repository.fetchHistory(id: thirdID) != nil)
        #expect(repository.fetchHistory(id: secondID) != nil)
        #expect(repository.fetchHistory(id: firstID) == nil)
    }

    @Test
    func plainSearchIsCaseInsensitiveAndPaginates() throws {
        let first = PasteboardContent("alpha")
        let second = PasteboardContent("Beta")
        let third = PasteboardContent("ALPINE")
        let firstID = PasteboardHistory.ID(rawValue: first.hash)
        let secondID = PasteboardHistory.ID(rawValue: second.hash)
        let thirdID = PasteboardHistory.ID(rawValue: third.hash)

        repository.save(id: firstID, content: first, updateAt: 1)
        repository.save(id: secondID, content: second, updateAt: 2)
        repository.save(id: thirdID, content: third, updateAt: 3)

        let firstPage = try repository.searchHistoryDetails(
            query: HistorySearchQuery(text: "alp", mode: .plain, caseSensitive: false, sortOrder: .newestFirst),
            includesThumbnailAsset: false,
            limit: 1,
            offset: 0
        )
        let secondPage = try repository.searchHistoryDetails(
            query: HistorySearchQuery(text: "alp", mode: .plain, caseSensitive: false, sortOrder: .newestFirst),
            includesThumbnailAsset: false,
            limit: 1,
            offset: 1
        )

        #expect(firstPage.map(\.history.id) == [thirdID])
        #expect(secondPage.map(\.history.id) == [firstID])
        #expect(repository.fetchHistory(id: secondID) != nil)
    }

    @Test
    func regexSearchFiltersByTypeAndReportsInvalidPatterns() throws {
        let text = PasteboardContent("ticket-123")
        let pdf = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .pdf, data: Data("ticket-456".utf8))
            ]
        )
        let textID = PasteboardHistory.ID(rawValue: text.hash)
        let pdfID = PasteboardHistory.ID(rawValue: pdf.hash)

        repository.save(id: textID, content: text, updateAt: 1)
        repository.save(id: pdfID, content: pdf, updateAt: 2)

        let matches = try repository.searchHistoryDetails(
            query: HistorySearchQuery(
                text: #"ticket-\d+"#,
                mode: .regex,
                caseSensitive: true,
                types: [.string],
                sortOrder: .oldestFirst
            ),
            includesThumbnailAsset: false,
            limit: 10,
            offset: 0
        )

        #expect(matches.map(\.history.id) == [textID])

        #expect(throws: HistorySearchError.invalidRegularExpression("["))
        {
            _ = try repository.searchHistoryDetails(
                query: HistorySearchQuery(text: "[", mode: .regex),
                includesThumbnailAsset: false,
                limit: 10,
                offset: 0
            )
        }
    }
}

private extension PasteboardContent {
    init(_ string: String) {
        self.init(
            assets: [
                PasteboardContent.Asset(type: .string, data: string.data(using: .utf8)!)
            ]
        )
    }
}

private func restore(_ value: Any?, forKey key: String, defaults: UserDefaults) {
    if let value {
        defaults.set(value, forKey: key)
    } else {
        defaults.removeObject(forKey: key)
    }
}

private func makeTabEvent(shift: Bool = false) throws -> NSEvent {
    try #require(NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: shift ? [.shift] : [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "\t",
        charactersIgnoringModifiers: "\t",
        isARepeat: false,
        keyCode: 48
    ))
}

private func makeMouseEnteredEvent(windowNumber: Int = 0) throws -> NSEvent {
    try #require(NSEvent.enterExitEvent(
        with: .mouseEntered,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: windowNumber,
        context: nil,
        eventNumber: 0,
        trackingNumber: 0,
        userData: nil
    ))
}

private func makeMouseMovedEvent(windowNumber: Int = 0) throws -> NSEvent {
    try #require(NSEvent.mouseEvent(
        with: .mouseMoved,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: windowNumber,
        context: nil,
        eventNumber: 0,
        clickCount: 0,
        pressure: 0
    ))
}

private func firstResponder(in window: NSWindow, belongsTo view: NSView) -> Bool {
    if window.firstResponder === view {
        return true
    }
    if let control = view as? NSControl,
       control.currentEditor() === window.firstResponder {
        return true
    }
    guard let responderView = window.firstResponder as? NSView else {
        return false
    }
    return responderView === view || responderView.isDescendant(of: view)
}

private func focusedRowAlpha(_ row: HistoryMenuRowView) -> CGFloat? {
    row.layer?.backgroundColor?.alpha
}

@MainActor
private func makeHistoryMenuTestWindow(width: CGFloat, height: CGFloat) -> NSWindow {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: width, height: height),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    window.animationBehavior = .none
    window.isReleasedWhenClosed = false
    return window
}

@MainActor
private func closeHistoryMenuTestWindow(_ window: NSWindow) {
    window.makeFirstResponder(nil)
    let retainedContentView = window.contentView
    window.contentView = nil
    window.orderOut(nil)
    HistoryMenuTestWindowRetainer.retain(window: window, contentView: retainedContentView)
}

private enum HistoryMenuTestWindowRetainer {
    private static var windows = [NSWindow]()
    private static var contentViews = [NSView]()

    static func retain(window: NSWindow, contentView: NSView?) {
        windows.append(window)
        if let contentView { contentViews.append(contentView) }
    }
}

struct HistoryMenuPaginationStateTests {
    @Test
    func queryChangeResetsPageAndNavigationStaysBounded() {
        var state = HistoryMenuPaginationState(pageSize: 10)

        state.goToNextPage(if: true)
        state.goToNextPage(if: true)
        #expect(state.pageIndex == 2)
        #expect(state.offset == 20)

        state.updateQuery("  keyword  ")
        #expect(state.query == "keyword")
        #expect(state.pageIndex == 0)
        #expect(state.offset == 0)

        state.goToPreviousPage()
        #expect(state.pageIndex == 0)

        state.goToNextPage(if: false)
        #expect(state.pageIndex == 0)
    }

    @Test
    func filterChangesResetPageAndExposeQueryOptions() {
        var state = HistoryMenuPaginationState(pageSize: 10)
        state.goToNextPage(if: true)
        state.goToNextPage(if: true)

        state.updateMode(.regex)
        #expect(state.mode == .regex)
        #expect(state.pageIndex == 0)

        state.goToNextPage(if: true)
        state.updateCaseSensitive(true)
        #expect(state.caseSensitive)
        #expect(state.pageIndex == 0)

        state.goToNextPage(if: true)
        state.updateTypeFilter(.images)
        #expect(state.typeFilter == .images)
        #expect(state.selectedTypes == NSPasteboard.PasteboardType.clipyImageTypes)
        #expect(state.pageIndex == 0)
    }

    @Test
    func typeFiltersMatchHistorySearchWindowSemantics() {
        #expect(HistoryMenuTypeFilter.all.pasteboardTypes.isEmpty)
        #expect(HistoryMenuTypeFilter.text.pasteboardTypes == [.string, .deprecatedString])
        #expect(HistoryMenuTypeFilter.images.pasteboardTypes == NSPasteboard.PasteboardType.clipyImageTypes)
        #expect(HistoryMenuTypeFilter.files.pasteboardTypes == [.fileURL])
        #expect(HistoryMenuTypeFilter.pdf.pasteboardTypes == [.pdf, .deprecatedPDF])
    }
}

@Suite(.serialized)
struct HistoryMenuHeaderViewTests {
    @Test @MainActor
    func headerUsesReadableTwoRowLayoutAndKeyViewLoop() throws {
        let headerView = HistoryMenuHeaderView()
        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        let controls = headerView.subviews.compactMap { $0 as? NSControl }
        let tabChainControls = controls.filter { control in
            guard let segmentedControl = control as? NSSegmentedControl else { return control.isEnabled }
            return control.isEnabled && segmentedControl.segmentCount > 1
        }

        #expect(headerView.frame.height == 64)
        #expect(controls.count >= 5)
        #expect(searchField.nextKeyView != nil)
        #expect(tabChainControls.allSatisfy { $0.nextKeyView != nil })
    }

    @Test @MainActor
    func headerFocusesSearchFieldWhenPresented() async throws {
        let window = makeHistoryMenuTestWindow(width: 420, height: 80)
        let headerView = HistoryMenuHeaderView()
        window.contentView = headerView
        window.makeKeyAndOrderFront(nil)
        defer { closeHistoryMenuTestWindow(window) }

        try await Task.sleep(nanoseconds: 50_000_000)

        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        #expect(searchField.currentEditor() != nil)
    }

    @Test @MainActor
    func headerCanExtendTabOrderIntoHistoryRows() {
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        let secondRow = HistoryMenuRowView(title: "2. Second", image: nil) {}

        headerView.connectKeyboardNavigation(to: [firstRow, secondRow])

        #expect(headerView.lastHeaderFocusableView.nextKeyView === firstRow)
        #expect(firstRow.nextKeyView === secondRow)
        #expect(secondRow.nextKeyView === headerView.firstHeaderFocusableView)
    }

    @Test @MainActor
    func headerTabOrderStartsAtRowsThenVisitsPageSearchOptionsAndLoopsBackToRows() throws {
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        let secondRow = HistoryMenuRowView(title: "2. Second", image: nil) {}

        headerView.configure(state: HistoryMenuPaginationState(pageIndex: 1), hasNextPage: true)
        headerView.connectKeyboardNavigation(to: [firstRow, secondRow])

        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        let pageButtons = headerView.subviews.compactMap { $0 as? NSButton }
        let previousButton = try #require(pageButtons.first)
        let nextButton = try #require(pageButtons.dropFirst().first)
        let typeControl = try #require(
            headerView.subviews.compactMap { $0 as? NSSegmentedControl }
                .first { $0.segmentCount == HistoryMenuTypeFilter.allCases.count }
        )

        #expect(firstRow.nextKeyView === secondRow)
        #expect(secondRow.nextKeyView === nextButton)
        #expect(nextButton.nextKeyView === previousButton)
        #expect(previousButton.nextKeyView === searchField)
        #expect(searchField.nextKeyView === typeControl)
        #expect(typeControl.nextKeyView === firstRow)
    }

    @Test @MainActor
    func headerTabOrderSkipsDisabledPreviousPageButton() throws {
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}

        headerView.configure(state: HistoryMenuPaginationState(pageIndex: 0), hasNextPage: true)
        headerView.connectKeyboardNavigation(to: [firstRow])

        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        let pageButtons = headerView.subviews.compactMap { $0 as? NSButton }
        let previousButton = try #require(pageButtons.first)
        let nextButton = try #require(pageButtons.dropFirst().first)
        let typeControl = try #require(
            headerView.subviews.compactMap { $0 as? NSSegmentedControl }
                .first { $0.segmentCount == HistoryMenuTypeFilter.allCases.count }
        )

        #expect(!previousButton.isEnabled)
        #expect(nextButton.isEnabled)
        #expect(firstRow.nextKeyView === nextButton)
        #expect(nextButton.nextKeyView === searchField)
        #expect(searchField.nextKeyView === typeControl)
    }

    @Test @MainActor
    func headerTabOrderLoopsFromLastTypeSegmentToFirstRow() throws {
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}

        headerView.configure(state: HistoryMenuPaginationState(pageIndex: 3), hasNextPage: true)
        headerView.connectKeyboardNavigation(to: [firstRow])

        let segmentedControls = headerView.subviews.compactMap { $0 as? NSSegmentedControl }
        let typeControl = try #require(segmentedControls.first { $0.segmentCount == HistoryMenuTypeFilter.allCases.count })

        #expect(typeControl.nextKeyView === firstRow)
    }

    @Test @MainActor
    func headerFocusesFirstHistoryRowWhenPresented() async throws {
        let window = makeHistoryMenuTestWindow(width: 420, height: 150)
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 150))
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        headerView.frame.origin = NSPoint(x: 0, y: 60)
        firstRow.frame.origin = NSPoint(x: 0, y: 20)
        headerView.connectKeyboardNavigation(to: [firstRow])
        containerView.addSubview(headerView)
        containerView.addSubview(firstRow)
        window.contentView = containerView
        window.makeKeyAndOrderFront(nil)
        defer { closeHistoryMenuTestWindow(window) }

        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(window.firstResponder === firstRow)
    }

    @Test @MainActor
    func pendingInitialFocusDoesNotStealSearchFieldFocus() async throws {
        let window = makeHistoryMenuTestWindow(width: 420, height: 150)
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 150))
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        headerView.frame.origin = NSPoint(x: 0, y: 60)
        firstRow.frame.origin = NSPoint(x: 0, y: 20)
        headerView.connectKeyboardNavigation(to: [firstRow])
        containerView.addSubview(headerView)
        containerView.addSubview(firstRow)
        window.contentView = containerView
        window.makeKeyAndOrderFront(nil)
        defer { closeHistoryMenuTestWindow(window) }

        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        window.makeFirstResponder(searchField)

        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(firstResponder(in: window, belongsTo: searchField))
        #expect(focusedRowAlpha(firstRow) == 0)
    }

    @Test @MainActor
    func headerControlsAdvanceFocusWithTabKeyInsideMenuViews() throws {
        let window = makeHistoryMenuTestWindow(width: 420, height: 150)
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 150))
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        headerView.configure(state: HistoryMenuPaginationState(pageIndex: 1), hasNextPage: true)
        headerView.connectKeyboardNavigation(to: [firstRow])
        containerView.addSubview(headerView)
        containerView.addSubview(firstRow)
        window.contentView = containerView
        window.makeKeyAndOrderFront(nil)
        defer { closeHistoryMenuTestWindow(window) }

        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        let typeControl = try #require(
            headerView.subviews.compactMap { $0 as? NSSegmentedControl }
                .first { $0.segmentCount == HistoryMenuTypeFilter.allCases.count }
        )
        let tabEvent = try makeTabEvent()

        window.makeFirstResponder(searchField)
        #expect(headerView.handleTabKeyFromCurrentResponder(tabEvent))
        #expect(firstResponder(in: window, belongsTo: typeControl))

        for _ in 1..<typeControl.segmentCount {
            #expect(headerView.handleTabKeyFromCurrentResponder(tabEvent))
            #expect(firstResponder(in: window, belongsTo: typeControl))
        }

        #expect(headerView.handleTabKeyFromCurrentResponder(tabEvent))
        #expect(firstResponder(in: window, belongsTo: firstRow))
    }

    @Test @MainActor
    func tabFallsBackToLogicalFocusWhenMenuWindowOwnsFirstResponder() throws {
        let window = makeHistoryMenuTestWindow(width: 420, height: 150)
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 150))
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        headerView.connectKeyboardNavigation(to: [firstRow])
        containerView.addSubview(headerView)
        containerView.addSubview(firstRow)
        window.contentView = containerView
        window.makeKeyAndOrderFront(nil)
        defer { closeHistoryMenuTestWindow(window) }

        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        window.makeFirstResponder(containerView)

        #expect(headerView.handleTabKeyFromCurrentResponder(try makeTabEvent()))
        #expect(firstResponder(in: window, belongsTo: searchField))
    }

    @Test @MainActor
    func tabUsesHoveredHistoryRowWhenMenuWindowOwnsFirstResponder() throws {
        let window = makeHistoryMenuTestWindow(width: 420, height: 170)
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 170))
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        let lastRow = HistoryMenuRowView(title: "0. Last", image: nil) {}
        headerView.connectKeyboardNavigation(to: [firstRow, lastRow])
        containerView.addSubview(headerView)
        containerView.addSubview(firstRow)
        containerView.addSubview(lastRow)
        window.contentView = containerView
        window.makeKeyAndOrderFront(nil)
        defer { closeHistoryMenuTestWindow(window) }

        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        window.makeFirstResponder(containerView)
        lastRow.mouseEntered(with: try makeMouseEnteredEvent(windowNumber: window.windowNumber))

        #expect(headerView.handleTabKeyFromCurrentResponder(try makeTabEvent()))
        #expect(firstResponder(in: window, belongsTo: searchField))
    }

    @Test @MainActor
    func hoveringSearchFieldDoesNotStealFocusedHistoryRow() throws {
        let window = makeHistoryMenuTestWindow(width: 420, height: 150)
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 150))
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        headerView.connectKeyboardNavigation(to: [firstRow])
        containerView.addSubview(headerView)
        containerView.addSubview(firstRow)
        window.contentView = containerView
        window.makeKeyAndOrderFront(nil)
        defer { closeHistoryMenuTestWindow(window) }

        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        window.makeFirstResponder(firstRow)

        searchField.mouseEntered(with: try makeMouseEnteredEvent(windowNumber: window.windowNumber))

        #expect(!firstResponder(in: window, belongsTo: searchField))
        #expect(firstResponder(in: window, belongsTo: firstRow))
        #expect(focusedRowAlpha(firstRow) == 0.9)
    }

    @Test @MainActor
    func hoveringHeaderBackgroundDoesNotStealFocusedHistoryRow() throws {
        let window = makeHistoryMenuTestWindow(width: 420, height: 150)
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 150))
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        headerView.connectKeyboardNavigation(to: [firstRow])
        containerView.addSubview(headerView)
        containerView.addSubview(firstRow)
        window.contentView = containerView
        window.makeKeyAndOrderFront(nil)
        defer { closeHistoryMenuTestWindow(window) }

        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        window.makeFirstResponder(firstRow)

        headerView.mouseEntered(with: try makeMouseEnteredEvent(windowNumber: window.windowNumber))

        #expect(!firstResponder(in: window, belongsTo: searchField))
        #expect(firstResponder(in: window, belongsTo: firstRow))
        #expect(focusedRowAlpha(firstRow) == 0.9)
    }

    @Test @MainActor
    func movingInsideSearchFieldDoesNotStealFocusedHistoryRow() throws {
        let window = makeHistoryMenuTestWindow(width: 420, height: 150)
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 150))
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        headerView.connectKeyboardNavigation(to: [firstRow])
        containerView.addSubview(headerView)
        containerView.addSubview(firstRow)
        window.contentView = containerView
        window.makeKeyAndOrderFront(nil)
        defer { closeHistoryMenuTestWindow(window) }

        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        window.makeFirstResponder(firstRow)

        searchField.mouseMoved(with: try makeMouseMovedEvent(windowNumber: window.windowNumber))

        #expect(!firstResponder(in: window, belongsTo: searchField))
        #expect(firstResponder(in: window, belongsTo: firstRow))
        #expect(focusedRowAlpha(firstRow) == 0.9)
    }

    @Test @MainActor
    func tabMovesBetweenRowsWithoutLeavingPreviousRowsSelected() throws {
        let window = makeHistoryMenuTestWindow(width: 420, height: 110)
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 110))
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        let secondRow = HistoryMenuRowView(title: "2. Second", image: nil) {}
        firstRow.frame.origin = NSPoint(x: 0, y: 40)
        secondRow.frame.origin = NSPoint(x: 0, y: 5)
        firstRow.nextKeyView = secondRow
        containerView.addSubview(firstRow)
        containerView.addSubview(secondRow)
        window.contentView = containerView
        window.makeKeyAndOrderFront(nil)
        defer { closeHistoryMenuTestWindow(window) }

        window.makeFirstResponder(firstRow)
        #expect(focusedRowAlpha(firstRow) == 0.9)

        window.makeFirstResponder(secondRow)

        #expect(focusedRowAlpha(firstRow) == 0)
        #expect(focusedRowAlpha(secondRow) == 0.9)
    }

    @Test @MainActor
    func tabCyclesFromLastRowToSearchOptionsAndBackToFirstRow() throws {
        let window = makeHistoryMenuTestWindow(width: 420, height: 170)
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 170))
        let headerView = HistoryMenuHeaderView()
        let firstRow = HistoryMenuRowView(title: "1. First", image: nil) {}
        let secondRow = HistoryMenuRowView(title: "2. Second", image: nil) {}
        headerView.frame.origin = NSPoint(x: 0, y: 90)
        firstRow.frame.origin = NSPoint(x: 0, y: 55)
        secondRow.frame.origin = NSPoint(x: 0, y: 20)
        headerView.configure(state: HistoryMenuPaginationState(pageIndex: 1), hasNextPage: true)
        headerView.connectKeyboardNavigation(to: [firstRow, secondRow])
        containerView.addSubview(headerView)
        containerView.addSubview(firstRow)
        containerView.addSubview(secondRow)
        window.contentView = containerView
        window.makeKeyAndOrderFront(nil)
        defer { closeHistoryMenuTestWindow(window) }

        let searchField = try #require(headerView.subviews.compactMap { $0 as? NSSearchField }.first)
        let pageButtons = headerView.subviews.compactMap { $0 as? NSButton }
        let previousButton = try #require(pageButtons.first)
        let nextButton = try #require(pageButtons.dropFirst().first)
        let typeControl = try #require(
            headerView.subviews.compactMap { $0 as? NSSegmentedControl }
                .first { $0.segmentCount == HistoryMenuTypeFilter.allCases.count }
        )
        let tabEvent = try makeTabEvent()

        window.makeFirstResponder(firstRow)
        #expect(headerView.handleTabKeyFromCurrentResponder(tabEvent))
        #expect(firstResponder(in: window, belongsTo: secondRow))
        #expect(focusedRowAlpha(firstRow) == 0)
        #expect(focusedRowAlpha(secondRow) == 0.9)

        #expect(headerView.handleTabKeyFromCurrentResponder(tabEvent))
        #expect(firstResponder(in: window, belongsTo: nextButton))
        #expect(focusedRowAlpha(secondRow) == 0)

        #expect(headerView.handleTabKeyFromCurrentResponder(tabEvent))
        #expect(firstResponder(in: window, belongsTo: previousButton))

        #expect(headerView.handleTabKeyFromCurrentResponder(tabEvent))
        #expect(firstResponder(in: window, belongsTo: searchField))

        #expect(headerView.handleTabKeyFromCurrentResponder(tabEvent))
        #expect(firstResponder(in: window, belongsTo: typeControl))
        let selectedTypeSegment = typeControl.selectedSegment

        for _ in 1..<typeControl.segmentCount {
            #expect(headerView.handleTabKeyFromCurrentResponder(tabEvent))
            #expect(firstResponder(in: window, belongsTo: typeControl))
            #expect(typeControl.selectedSegment == selectedTypeSegment)
        }

        #expect(headerView.handleTabKeyFromCurrentResponder(tabEvent))
        #expect(firstResponder(in: window, belongsTo: firstRow))
        #expect(typeControl.selectedSegment == selectedTypeSegment)
    }

    @Test @MainActor
    func historyRowConfirmsWithReturnKey() throws {
        var didConfirm = false
        let row = HistoryMenuRowView(title: "1. Confirm", image: nil) {
            didConfirm = true
        }
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ))

        row.keyDown(with: event)

        #expect(didConfirm)
    }

    @Test @MainActor
    func historyRowUsesCompactImagePreview() throws {
        let image = NSImage(size: NSSize(width: 320, height: 180))
        let row = HistoryMenuRowView(title: "1. Screenshot", image: image) {}

        row.layoutSubtreeIfNeeded()

        let imageView = try #require(row.subviews.compactMap { $0 as? NSImageView }.first)
        #expect(imageView.imageScaling == .scaleProportionallyDown)
        #expect(row.frame.height == 42)
        #expect(imageView.frame.width == 52)
        #expect(imageView.frame.height == 32)
    }

    @Test @MainActor
    func historyRowWithoutImageKeepsCompactHeight() {
        let row = HistoryMenuRowView(title: "1. Text", image: nil) {}

        #expect(row.frame.height == 28)
    }

    @Test @MainActor
    func imagePreviewPanelUsesNonActivatingPreviewWindow() throws {
        let controller = HistoryMenuImagePreviewController()
        let image = NSImage(size: NSSize(width: 640, height: 360))

        controller.show(image: image, relativeTo: NSRect(x: 40, y: 40, width: 48, height: 30), in: nil)

        let panel = try #require(controller.panel)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.level == .popUpMenu)
        #expect(panel.contentView?.frame.size == NSSize(width: 260, height: 180))
        controller.hide()
    }
}

private extension PasteboardHistory {
    init(id: PasteboardHistory.ID, title: String, updateAt: Int) {
        self.init(
            id: id,
            title: title,
            pasteboardTypes: [.string],
            updateAt: updateAt,
            deviceID: CPYUtilities.deviceID
        )
    }
}

private func waitUntil(condition: @escaping @MainActor () async -> Bool) async throws {
    try await confirmation { confirmation in
        while true {
            if await condition() {
                confirmation()
                return
            } else {
                try await Task.sleep(for: .seconds(0.01))
            }
        }
    }
}
