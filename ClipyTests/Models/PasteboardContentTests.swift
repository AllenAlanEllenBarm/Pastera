//
//  PasteboardContentTests.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Shunsuke Furubayashi on 2026/05/28.
//
//  Copyright © 2015-2026 Clipy Project.
//

import AppKit
import Testing
@testable import Clipy

@MainActor
@Suite
struct PasteboardContentTests {
    @Test
    func typesAreDerivedFromAssetsInOrder() {
        let content = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .rtf, data: Data("rtf".utf8)),
                PasteboardContent.Asset(type: .string, data: Data("Hello".utf8)),
                PasteboardContent.Asset(type: .pdf, data: Data("pdf".utf8))
            ]
        )
        #expect(content.types == [.rtf, .string, .pdf])
    }

    @Test
    func imageInitializerStoresTiffAsset() throws {
        let image = NSImage.create(with: .red, size: NSSize(width: 10, height: 10))
        let content = try #require(PasteboardContent(image: image))

        #expect(content.types == [.tiff])
        #expect(content.assets.count == 1)
        #expect(content.assets.first?.type == .tiff)
        #expect(content.assets.first?.data.isEmpty == false)
    }

    @Test
    func stringPropertiesUseModernAndDeprecatedStringData() {
        let modernContent = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .string, data: Data("Hello".utf8))
            ]
        )
        let deprecatedContent = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .deprecatedString, data: Data("Legacy".utf8))
            ]
        )
        let mixedContent = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .string, data: Data("Hello".utf8)),
                PasteboardContent.Asset(type: .rtf, data: Data("rtf".utf8))
            ]
        )

        #expect(modernContent.isOnlyStringType)
        #expect(modernContent.stringValue == "Hello")
        #expect(deprecatedContent.isOnlyStringType)
        #expect(deprecatedContent.stringValue == "Legacy")
        #expect(!mixedContent.isOnlyStringType)
        #expect(mixedContent.stringValue == "Hello")
    }

    @Test
    func colorCodeImageIsCreatedFromHexString() {
        let colorContent = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .string, data: Data("#ff0000".utf8))
            ]
        )
        let invalidContent = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .string, data: Data("not a color".utf8))
            ]
        )

        #expect(colorContent.colorCodeImage?.size == NSSize(width: 20, height: 20))
        #expect(invalidContent.colorCodeImage == nil)
    }

    @Test
    func thumbnailImageIsCreatedFromStoredTiffData() {
        let defaults = UserDefaults.standard
        let previousWidth = defaults.object(forKey: Constants.UserDefaults.thumbnailWidth)
        let previousHeight = defaults.object(forKey: Constants.UserDefaults.thumbnailHeight)
        defer {
            if let previousWidth {
                defaults.set(previousWidth, forKey: Constants.UserDefaults.thumbnailWidth)
            } else {
                defaults.removeObject(forKey: Constants.UserDefaults.thumbnailWidth)
            }
            if let previousHeight {
                defaults.set(previousHeight, forKey: Constants.UserDefaults.thumbnailHeight)
            } else {
                defaults.removeObject(forKey: Constants.UserDefaults.thumbnailHeight)
            }
        }
        defaults.set(8, forKey: Constants.UserDefaults.thumbnailWidth)
        defaults.set(6, forKey: Constants.UserDefaults.thumbnailHeight)

        let image = NSImage.create(with: .blue, size: NSSize(width: 20, height: 10))
        let content = PasteboardContent(image: image)

        #expect(content?.thumbnailImage?.size == NSSize(width: 8, height: 4))
    }

    @Test
    func contentHashIsStableAndContentBased() {
        let content = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .string, data: Data("Hello".utf8)),
                PasteboardContent.Asset(type: .rtf, data: Data("rtf".utf8))
            ]
        )
        let equivalentContent = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .string, data: Data("Hello".utf8)),
                PasteboardContent.Asset(type: .rtf, data: Data("rtf".utf8))
            ]
        )
        let changedDataContent = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .string, data: Data("Hello!".utf8)),
                PasteboardContent.Asset(type: .rtf, data: Data("rtf".utf8))
            ]
        )
        let changedOrderContent = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .rtf, data: Data("rtf".utf8)),
                PasteboardContent.Asset(type: .string, data: Data("Hello".utf8))
            ]
        )

        #expect(content.hash == "4c6a4ba3cd6a6aad6a2c6620542b11c94edf2af3297611aeba21a86e79dbeb20")
        #expect(content.hash == equivalentContent.hash)
        #expect(content.hash != changedDataContent.hash)
        #expect(content.hash != changedOrderContent.hash)
    }

    @Test
    func pasteboardInitializerPreservesMultipleImageItems() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PasteboardContentTests.images"))
        pasteboard.clearContents()
        let firstImage = try #require(NSImage.create(with: .red, size: NSSize(width: 10, height: 10)).tiffRepresentation)
        let secondImage = try #require(NSImage.create(with: .blue, size: NSSize(width: 20, height: 20)).tiffRepresentation)
        let firstItem = NSPasteboardItem()
        firstItem.setData(firstImage, forType: .tiff)
        let secondItem = NSPasteboardItem()
        secondItem.setData(secondImage, forType: .tiff)
        pasteboard.writeObjects([firstItem, secondItem])

        let content = try #require(PasteboardContent(pasteboard: pasteboard, types: [.tiff]))

        #expect(content.assets.map(\.type) == [.tiff, .tiff])
        #expect(content.assets.map(\.data) == [firstImage, secondImage])
    }

    @Test
    func syncRecordJSONRoundTripsEncryptedPayload() throws {
        let payload = Data("history payload".utf8)
        let sealedPayload = try SyncPayloadCipher.seal(payload, passphrase: "sync-passphrase", salt: Data("salt".utf8))
        let record = SyncRecord(
            id: "history-1",
            kind: .history,
            deviceID: "device-a",
            updatedAt: 10,
            deletedAt: nil,
            payload: sealedPayload,
            schemaVersion: 1
        )

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(SyncRecord.self, from: data)

        #expect(decoded == record)
        #expect(try SyncPayloadCipher.open(decoded.payload, passphrase: "sync-passphrase", salt: Data("salt".utf8)) == payload)
        #expect(throws: Error.self) {
            _ = try SyncPayloadCipher.open(decoded.payload, passphrase: "wrong", salt: Data("salt".utf8))
        }
    }

    @Test
    func syncConflictPolicyChoosesNewestRecordAndDeleteTombstones() {
        let oldRecord = SyncRecord.plaintextFixture(id: "history-1", updatedAt: 1, deletedAt: nil)
        let newRecord = SyncRecord.plaintextFixture(id: "history-1", updatedAt: 2, deletedAt: nil)
        let deleteRecord = SyncRecord.plaintextFixture(id: "history-1", updatedAt: 3, deletedAt: 3)

        #expect(SyncConflictPolicy.lastWriteWins.resolve(local: oldRecord, remote: newRecord) == newRecord)
        #expect(SyncConflictPolicy.lastWriteWins.resolve(local: newRecord, remote: deleteRecord) == deleteRecord)
    }

    @Test
    func syncManifestJSONRoundTripsRecordMetadata() throws {
        let manifest = SyncManifest(
            schemaVersion: 1,
            deviceID: "device-a",
            updatedAt: 10,
            records: [
                SyncManifestRecord(id: "history-1", kind: .history, updatedAt: 8, deletedAt: nil),
                SyncManifestRecord(id: "snippet-1", kind: .snippet, updatedAt: 9, deletedAt: 9)
            ]
        )

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(SyncManifest.self, from: data)

        #expect(decoded == manifest)
    }

    @Test
    func syncServiceMergesRecordsAndPersistsWinners() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let service = SyncService(provider: provider)
        let local = SyncRecord.plaintextFixture(id: "history-1", kind: .history, updatedAt: 1, deletedAt: nil)
        let remote = SyncRecord.plaintextFixture(id: "history-1", kind: .history, updatedAt: 2, deletedAt: nil)
        let snippet = SyncRecord.plaintextFixture(id: "snippet-1", kind: .snippet, updatedAt: 1, deletedAt: nil)

        let merged = service.merge(local: [local, snippet], remote: [remote])
        try service.push(merged)

        #expect(merged == [remote, snippet])
        #expect(try service.pull(kind: .history) == [remote])
        #expect(try service.pull(kind: .snippet) == [snippet])
    }

    @Test
    func oneDriveFolderSyncProviderWritesRecordsAtomically() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let history = SyncRecord.plaintextFixture(id: "history-1", kind: .history, updatedAt: 1, deletedAt: nil)
        let snippet = SyncRecord.plaintextFixture(id: "snippet-1", kind: .snippet, updatedAt: 2, deletedAt: nil)

        try provider.save(history)
        try provider.save(snippet)

        #expect(try provider.loadRecords(kind: .history) == [history])
        #expect(try provider.loadRecords(kind: .snippet) == [snippet])
    }
}

private extension SyncRecord {
    static func plaintextFixture(
        id: String,
        kind: SyncRecord.Kind = .history,
        updatedAt: Int,
        deletedAt: Int?
    ) -> SyncRecord {
        SyncRecord(
            id: id,
            kind: kind,
            deviceID: "device",
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            payload: EncryptedSyncPayload(nonce: Data(), ciphertext: Data("payload".utf8), tag: Data()),
            schemaVersion: 1
        )
    }
}
