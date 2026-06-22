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
@Suite
struct HistoryRepositoryBootstrapTests {
    @Test
    func repositoryCreatedBeforeBootstrapUsesBootstrappedDatabaseAtCallTime() throws {
        let repository = PasteboardHistoryRepository()

        try withDependencies {
            try $0.bootstrapDatabase()
        } operation: {
            let content = PasteboardContent("Bootstrap after init")
            let id = PasteboardHistory.ID(rawValue: content.hash)
            let history = PasteboardHistory(id: id, title: "Bootstrap after init", updateAt: 1)

            repository.save(id: id, content: content, updateAt: 1)

            #expect(repository.fetchHistory(id: id) == history)
            #expect(repository.fetchContent(id: id) == content)
        }
    }
}

@MainActor
@Suite
struct ClipServiceCaptureTests {
    @Test
    func emptyPasteboardChangeRetriesUntilTypesAreAvailable() {
        let repository = RecordingPasteboardHistoryRepository()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipServiceCaptureTests.retry.\(UUID().uuidString)"))
        defer { pasteboard.clearContents() }
        pasteboard.clearContents()

        withDependencies {
            $0.pasteboardHistoryRepository = repository
        } operation: {
            let service = ClipService()
            service.setStoreTypesForTesting(["String": NSNumber(value: true)])

            #expect(!service.createForTesting(from: pasteboard))

            let item = NSPasteboardItem()
            item.setString("Ready after clear", forType: .string)
            pasteboard.writeObjects([item])

            #expect(service.createForTesting(from: pasteboard))
        }

        #expect(repository.savedContents.map(\.stringValue) == ["Ready after clear"])
    }
}

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
        let settings = HistoryRetentionSettings(
            menuDisplayLimit: 1,
            storedHistoryLimit: 2,
            maxSyncedHistoryTextBytes: 256 * 1024,
            maxHistorySnapshotTextBudgetBytes: 8 * 1024 * 1024
        )
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

@MainActor
@Suite(
    .dependencies {
        try $0.bootstrapDatabase()
    }
)
struct PasteboardHistorySyncRepositoryTests {
    let repository = PasteboardHistoryRepository()

    @Test
    func fileSyncSnapshotExportsSupportedNonTextAssetsWithoutAffectingTextHistory() throws {
        let text = PasteboardContent("Text only")
        let webURL = try #require(URL(string: "https://pastera.example"))
        let urlContent = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .URL, data: webURL.dataRepresentation)]
        )
        let image = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .png, data: Data([0x89, 0x50, 0x4E, 0x47]))]
        )
        let pdf = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .pdf, data: Data("%PDF-1.7".utf8))]
        )
        let rtf = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .rtf, data: Data("{\\rtf1 file}".utf8))]
        )
        let fileURL = try writeTemporaryFile(name: "report.txt", data: Data("report".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let file = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .fileURL, data: fileURL.dataRepresentation)]
        )
        let tooLarge = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .pdf, data: Data(repeating: 1, count: 13))]
        )
        let folderURL = try writeTemporaryFolder(name: "folder")
        defer { try? FileManager.default.removeItem(at: folderURL.deletingLastPathComponent()) }
        let folder = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .fileURL, data: folderURL.dataRepresentation)]
        )

        repository.save(id: PasteboardHistory.ID(rawValue: text.hash), content: text, updateAt: 80)
        repository.save(id: PasteboardHistory.ID(rawValue: urlContent.hash), content: urlContent, updateAt: 70)
        repository.save(id: PasteboardHistory.ID(rawValue: image.hash), content: image, updateAt: 60)
        repository.save(id: PasteboardHistory.ID(rawValue: pdf.hash), content: pdf, updateAt: 50)
        repository.save(id: PasteboardHistory.ID(rawValue: rtf.hash), content: rtf, updateAt: 40)
        repository.save(id: PasteboardHistory.ID(rawValue: file.hash), content: file, updateAt: 30)
        repository.save(id: PasteboardHistory.ID(rawValue: tooLarge.hash), content: tooLarge, updateAt: 20)
        repository.save(id: PasteboardHistory.ID(rawValue: folder.hash), content: folder, updateAt: 10)

        let snapshot = repository.fetchFileSyncSnapshot(
            currentDeviceID: CPYUtilities.deviceID,
            limit: 10,
            maxFileBytes: 12
        )

        #expect(snapshot.histories.map(\.historyID) == [
            image.hash,
            pdf.hash,
            rtf.hash
        ])
        #expect(snapshot.assetCount == 3)
        #expect(snapshot.skippedAssetCount == 1)
        #expect(snapshot.histories.flatMap(\.assets).map(\.pasteboardType) == [.png, .pdf, .rtf])
    }

    @Test
    func fileSyncSnapshotIncludesOnlySelectedFileTypes() throws {
        let image = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .png, data: Data([0x89, 0x50, 0x4E, 0x47]))]
        )
        let pdf = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .pdf, data: Data("%PDF-1.7".utf8))]
        )
        let rtf = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .rtf, data: Data("{\\rtf1 file}".utf8))]
        )
        let fileURL = try writeTemporaryFile(name: "report.txt", data: Data("report".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let file = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .fileURL, data: fileURL.dataRepresentation)]
        )
        let tooLarge = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .pdf, data: Data(repeating: 1, count: 13))]
        )

        repository.save(id: PasteboardHistory.ID(rawValue: image.hash), content: image, updateAt: 50)
        repository.save(id: PasteboardHistory.ID(rawValue: pdf.hash), content: pdf, updateAt: 40)
        repository.save(id: PasteboardHistory.ID(rawValue: rtf.hash), content: rtf, updateAt: 30)
        repository.save(id: PasteboardHistory.ID(rawValue: file.hash), content: file, updateAt: 20)
        repository.save(id: PasteboardHistory.ID(rawValue: tooLarge.hash), content: tooLarge, updateAt: 10)

        let snapshot = repository.fetchFileSyncSnapshot(
            currentDeviceID: CPYUtilities.deviceID,
            limit: 10,
            maxFileBytes: 12,
            includedFileTypes: [.pdf]
        )

        #expect(snapshot.histories.map(\.historyID) == [pdf.hash])
        #expect(snapshot.assetCount == 1)
        #expect(snapshot.skippedAssetCount == 1)
        #expect(snapshot.histories.flatMap(\.assets).map(\.pasteboardType) == [.pdf])
    }

    @Test
    func fileSyncSnapshotIgnoresFinderFilesEvenWhenLegacyPreferenceContainsFilenames() throws {
        let fileURL = try writeTemporaryFile(name: "report.txt", data: Data("report".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let file = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .fileURL, data: fileURL.dataRepresentation)]
        )

        repository.save(id: PasteboardHistory.ID(rawValue: file.hash), content: file, updateAt: 20)

        let snapshot = repository.fetchFileSyncSnapshot(
            currentDeviceID: CPYUtilities.deviceID,
            limit: 10,
            maxFileBytes: 25 * 1024 * 1024,
            includedFileTypes: [.filenames]
        )

        #expect(snapshot.histories.isEmpty)
        #expect(snapshot.assetCount == 0)
        #expect(snapshot.skippedAssetCount == 0)
    }

    @Test
    func fileSyncSnapshotKeepsMultiAssetHistoriesWholeWhenLimitWouldBeExceeded() throws {
        let newest = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .pdf, data: Data("a".utf8)),
                PasteboardContent.Asset(type: .pdf, data: Data("b".utf8))
            ]
        )
        let older = PasteboardContent(
            assets: (0..<9).map { index in
                PasteboardContent.Asset(type: .pdf, data: Data("older-\(index)".utf8))
            }
        )

        repository.save(id: PasteboardHistory.ID(rawValue: newest.hash), content: newest, updateAt: 2)
        repository.save(id: PasteboardHistory.ID(rawValue: older.hash), content: older, updateAt: 1)

        let snapshot = repository.fetchFileSyncSnapshot(
            currentDeviceID: CPYUtilities.deviceID,
            limit: 10,
            maxFileBytes: 25 * 1024 * 1024
        )

        #expect(snapshot.histories.map(\.historyID) == [newest.hash])
        #expect(snapshot.assetCount == 2)
        #expect(snapshot.skippedAssetCount == 9)
    }

    @Test
    func fileSyncImportRestoresBinaryAssetsAndRejectsFinderFiles() throws {
        let binaryPayload = FileSyncHistoryPayload(
            deviceID: "remote-device",
            historyID: "remote-pdf",
            updatedAt: 20,
            assets: [
                FileSyncAssetPayload(
                    assetIndex: 0,
                    pasteboardType: .pdf,
                    data: Data("%PDF".utf8),
                    originalFilename: nil
                )
            ]
        )
        let finderPayload = FileSyncHistoryPayload(
            deviceID: "remote-device",
            historyID: "remote-file",
            updatedAt: 30,
            assets: [
                FileSyncAssetPayload(
                    assetIndex: 0,
                    pasteboardType: .fileURL,
                    data: Data("cached bytes".utf8),
                    originalFilename: "remote.txt"
                )
            ]
        )

        #expect(repository.upsertFileSyncHistory(binaryPayload))
        #expect(!repository.upsertFileSyncHistory(finderPayload))

        let pdfContent = try #require(repository.fetchContent(id: PasteboardHistory.ID(rawValue: "remote-pdf")))
        #expect(pdfContent.assets == [
            PasteboardContent.Asset(type: .pdf, data: Data("%PDF".utf8))
        ])
        #expect(repository.fetchContent(id: PasteboardHistory.ID(rawValue: "remote-file")) == nil)
    }

    @Test
    func syncPayloadsExportNewestCurrentDeviceTextAndURLWindowOnly() throws {
        let current = PasteboardContent("Current")
        let old = PasteboardContent("Old")
        let remote = PasteboardContent("Remote")
        let webURL = try #require(URL(string: "https://e.co"))
        let urlContent = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .URL, data: webURL.dataRepresentation)]
        )
        let image = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .tiff, data: Data(repeating: 1, count: 8))]
        )
        let file = PasteboardContent(
            assets: [
                PasteboardContent.Asset(
                    type: .fileURL,
                    data: URL(fileURLWithPath: "/tmp/pastera.txt").dataRepresentation
                )
            ]
        )
        let rtf = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .rtf, data: Data("{\\rtf1 Remote}".utf8))]
        )
        let html = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .html, data: Data("<strong>Remote</strong>".utf8))]
        )
        let large = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .string, data: Data(String(repeating: "A", count: 17).utf8))]
        )
        let currentID = PasteboardHistory.ID(rawValue: current.hash)
        let oldID = PasteboardHistory.ID(rawValue: old.hash)
        let remoteID = PasteboardHistory.ID(rawValue: remote.hash)
        let urlID = PasteboardHistory.ID(rawValue: urlContent.hash)

        repository.save(id: currentID, content: current, updateAt: 10)
        repository.save(id: oldID, content: old, updateAt: 4)
        repository.upsertSyncPayload(PasteboardHistorySyncPayload(
            id: remoteID.rawValue,
            text: "Remote",
            updateAt: 12,
            deviceID: "remote-device",
            sourceKind: .plainText
        ))
        repository.save(id: urlID, content: urlContent, updateAt: 12)
        repository.save(id: PasteboardHistory.ID(rawValue: image.hash), content: image, updateAt: 16)
        repository.save(id: PasteboardHistory.ID(rawValue: file.hash), content: file, updateAt: 15)
        repository.save(id: PasteboardHistory.ID(rawValue: rtf.hash), content: rtf, updateAt: 14)
        repository.save(id: PasteboardHistory.ID(rawValue: html.hash), content: html, updateAt: 13)
        repository.save(id: PasteboardHistory.ID(rawValue: large.hash), content: large, updateAt: 13)

        let payloads = repository.fetchSyncPayloads(
            currentDeviceID: CPYUtilities.deviceID,
            limit: 3,
            maxTextBytes: 16,
            snapshotTextBudgetBytes: 128
        )

        #expect(payloads.map(\.id) == [urlID.rawValue, currentID.rawValue, oldID.rawValue])
        #expect(payloads.map(\.sourceKind) == [.url, .plainText, .plainText])
        #expect(payloads.first?.text == "https://e.co")
        #expect(payloads.first?.deviceID == CPYUtilities.deviceID)
    }

    @Test
    func syncPayloadExportStopsAtSnapshotTextBudget() throws {
        let newest = PasteboardContent("First")
        let older = PasteboardContent("Second")
        let newestID = PasteboardHistory.ID(rawValue: newest.hash)
        repository.save(id: newestID, content: newest, updateAt: 2)
        repository.save(id: PasteboardHistory.ID(rawValue: older.hash), content: older, updateAt: 1)

        let payloads = repository.fetchSyncPayloads(
            currentDeviceID: CPYUtilities.deviceID,
            limit: 2000,
            maxTextBytes: 256 * 1024,
            snapshotTextBudgetBytes: 6
        )

        #expect(payloads.map(\.id) == [newestID.rawValue])
    }

    @Test(.timeLimit(.minutes(1)))
    func observeTextSyncCandidateChangesIgnoresRemoteAndNonTextHistories() async throws {
        var changeCount = 0
        let cancellable = repository
            .observeTextSyncCandidateChanges(currentDeviceID: CPYUtilities.deviceID)
            .sink {
                changeCount += 1
            }
        defer { _ = cancellable }

        try await waitUntil { changeCount >= 1 }

        repository.upsertSyncPayload(PasteboardHistorySyncPayload(
            id: "remote-history",
            text: "Remote",
            updateAt: 10,
            deviceID: "remote-device",
            sourceKind: .plainText
        ))
        try await Task.sleep(for: .seconds(0.05))
        #expect(changeCount == 1)

        let image = PasteboardContent(
            assets: [PasteboardContent.Asset(type: .png, data: Data([0x89, 0x50, 0x4E, 0x47]))]
        )
        repository.save(id: PasteboardHistory.ID(rawValue: image.hash), content: image, updateAt: 11)
        try await Task.sleep(for: .seconds(0.05))
        #expect(changeCount == 1)

        let text = PasteboardContent("Local text")
        repository.save(id: PasteboardHistory.ID(rawValue: text.hash), content: text, updateAt: 12)
        try await waitUntil { changeCount >= 2 }
    }

    @Test
    func syncImportDoesNotReuploadRemoteHistoryAndLocalSuppressionPreventsReimport() throws {
        let id = PasteboardHistory.ID(rawValue: "remote-history")
        let payload = PasteboardHistorySyncPayload(
            id: id.rawValue,
            text: "Remote history",
            updateAt: 20,
            deviceID: "remote-device",
            sourceKind: .plainText
        )

        repository.upsertSyncPayload(payload)
        #expect(repository.fetchHistory(id: id)?.deviceID == "remote-device")
        #expect(repository.fetchSyncPayloads(
            currentDeviceID: CPYUtilities.deviceID,
            limit: 2000,
            maxTextBytes: 256 * 1024,
            snapshotTextBudgetBytes: 8 * 1024 * 1024
        ).isEmpty)

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
            text: "Remote older",
            updateAt: 20,
            deviceID: "remote-device",
            sourceKind: .plainText
        )
        let newerRemote = PasteboardHistorySyncPayload(
            id: id.rawValue,
            text: "Remote newer",
            updateAt: 40,
            deviceID: "remote-device",
            sourceKind: .url
        )

        #expect(repository.upsertSyncPayload(olderRemote) == false)
        #expect(repository.fetchHistory(id: id)?.title == "Local newer")
        #expect(repository.fetchContent(id: id) == localContent)

        #expect(repository.upsertSyncPayload(newerRemote) == true)
        #expect(repository.fetchHistory(id: id)?.title == "Remote newer")
        #expect(repository.fetchContent(id: id) == PasteboardContent("Remote newer"))
        #expect(repository.fetchHistory(id: id)?.pasteboardTypes == [.string])
        #expect(
            repository
                .fetchHistoryDetails(ascending: false, includesThumbnailAsset: true, limit: 1)
                .first?
                .thumbnailAsset == nil
        )
    }
}

private final class RecordingPasteboardHistoryRepository: PasteboardHistoryRepositoryProtocol {
    private(set) var savedContents = [PasteboardContent]()

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
        []
    }

    func searchHistoryDetails(
        query: HistorySearchQuery,
        includesThumbnailAsset: Bool,
        limit: Int,
        offset: Int
    ) throws -> [PasteboardHistoryDetail] {
        []
    }

    func fetchHistory(id: PasteboardHistory.ID) -> PasteboardHistory? { nil }
    func fetchContent(id: PasteboardHistory.ID) -> PasteboardContent? { nil }

    func save(id: PasteboardHistory.ID, content: PasteboardContent, updateAt: Int) {
        savedContents.append(content)
    }

    func deleteHistory(id: PasteboardHistory.ID) {}
    func deleteAll() {}
    func deleteOverflowingHistories(maxHistorySize: Int) {}
    func pruneHistories(settings: HistoryRetentionSettings) {}
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

private func writeTemporaryFile(name: String, data: Data) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name)
    try data.write(to: url)
    return url
}

private func writeTemporaryFolder(name: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let folderURL = directory.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
    return folderURL
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
