//
//  PasteboardHistorySearchPerformanceTests.swift
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
import DependenciesTestSupport
import SQLiteData
import Testing
@testable import Pastera

@MainActor
@Suite(.dependencies {
    try $0.bootstrapDatabase()
})
struct PasteboardHistorySearchPerformanceTests {
    let repository = PasteboardHistoryRepository()

    @Test
    func matchingHistoryIDsReturnsOnlyRequestedPage() throws {
        let first = PasteboardContent("alpha")
        let second = PasteboardContent("Beta")
        let third = PasteboardContent("ALPINE")
        let firstID = PasteboardHistory.ID(rawValue: first.hash)
        let secondID = PasteboardHistory.ID(rawValue: second.hash)
        let thirdID = PasteboardHistory.ID(rawValue: third.hash)

        repository.save(id: firstID, content: first, updateAt: 1)
        repository.save(id: secondID, content: second, updateAt: 2)
        repository.save(id: thirdID, content: third, updateAt: 3)

        let ids = try repository.matchingHistoryIDs(
            query: HistorySearchQuery(text: "alp", mode: .plain, caseSensitive: false, sortOrder: .newestFirst),
            limit: 1,
            offset: 1
        )

        #expect(ids == [firstID])
        #expect(!ids.contains(secondID))
        #expect(!ids.contains(thirdID))
    }

    @Test
    func fetchHistoryDetailsByIDsPreservesOrderAndLoadsOnlyRequestedThumbnails() throws {
        let colorContent = PasteboardContent("#ff0000")
        let textContent = PasteboardContent("plain")
        let otherColorContent = PasteboardContent("#00ff00")
        let colorID = PasteboardHistory.ID(rawValue: colorContent.hash)
        let textID = PasteboardHistory.ID(rawValue: textContent.hash)
        let otherColorID = PasteboardHistory.ID(rawValue: otherColorContent.hash)

        repository.save(id: colorID, content: colorContent, updateAt: 1)
        repository.save(id: textID, content: textContent, updateAt: 2)
        repository.save(id: otherColorID, content: otherColorContent, updateAt: 3)

        let details = repository.fetchHistoryDetails(
            ids: [textID, colorID],
            includesThumbnailAsset: true
        )

        #expect(details.map(\.history.id) == [textID, colorID])
        #expect(details[0].thumbnailAsset == nil)
        let thumbnail = try #require(details[1].thumbnailAsset)
        #expect(thumbnail.pasteboardHistoryID == colorID)
        #expect(thumbnail.kind == .colorCode)
        #expect(thumbnail.data.starts(with: Data([0x89, 0x50, 0x4E, 0x47])))
        #expect(!details.map(\.history.id).contains(otherColorID))
    }

    @Test(.timeLimit(.minutes(1)))
    func observeHistoryChangesEmitsWithoutReturningHistories() async throws {
        var changeCount = 0
        let cancellable = repository.observeHistoryChanges().sink {
            changeCount += 1
        }
        defer { _ = cancellable }

        try await waitUntil { changeCount >= 1 }

        let content = PasteboardContent("First")
        let id = PasteboardHistory.ID(rawValue: content.hash)
        repository.save(id: id, content: content, updateAt: 1)
        try await waitUntil { changeCount >= 2 }

        repository.deleteHistory(id: id)
        try await waitUntil { changeCount >= 3 }

        repository.deleteAll()
        try await waitUntil { changeCount >= 4 }
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

private func waitUntil(condition: @escaping @MainActor () async -> Bool) async throws {
    let deadline = Date().addingTimeInterval(2)
    while Date() < deadline {
        if await condition() {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    Issue.record("Timed out waiting for condition")
}
