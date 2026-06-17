//
//  SyncCoordinatorTests.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Codex on 2026/06/16.
//
//  Copyright © 2015-2026 Clipy Project.
//

import AppKit
import DependenciesTestSupport
import Foundation
import Testing
@testable import Pastera

@MainActor
@Suite(
    .dependencies {
        try $0.bootstrapDatabase()
    }
)
struct SyncCoordinatorTests {
    private let historyRepository = PasteboardHistoryRepository()
    private let snippetRepository = SnippetRepository()

    @Test
    func coordinatorErrorsUseChineseStatusText() {
        #expect(SyncCoordinatorError.noEnabledWork.localizedDescription == "请先开启至少一个同步开关。")
        #expect(SyncCoordinatorError.missingOneDrive.localizedDescription == "请先安装并登录 OneDrive。")
        #expect(SyncCoordinatorError.folderUnavailable.localizedDescription == "所选 OneDrive 文件夹不可用。")
        #expect(SyncCoordinatorError.automaticSyncDisabled.localizedDescription == "自动同步未开启。")
    }

    @Test
    func defaultFolderResolverCreatesRecommendedCloudStorageOneDriveFolder() throws {
        let homeURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: homeURL) }
        let oneDriveRootURL = oneDriveRootURL(homeURL: homeURL, name: "OneDrive")
        try FileManager.default.createDirectory(at: oneDriveRootURL, withIntermediateDirectories: true)
        let expectedURL = oneDriveRootURL
            .appendingPathComponent("Pastera", isDirectory: true)
            .appendingPathComponent("sync", isDirectory: true)

        let resolution = SyncDefaultFolderResolver(fileManager: .default).resolve(homeDirectory: homeURL)

        guard case .found(let candidate) = resolution else {
            #expect(Bool(false), "Expected a single recommended OneDrive sync location, got \(resolution)")
            return
        }
        #expect(candidate.displayName == "OneDrive")
        #expect(candidate.oneDriveRootURL == oneDriveRootURL.resolvingSymlinksInPath().standardizedFileURL)
        #expect(candidate.syncRootURL == expectedURL.resolvingSymlinksInPath().standardizedFileURL)
        #expect(candidate.isOneDriveBacked)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: expectedURL.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test
    func defaultFolderResolverChoosesPersonalOneDriveWhenMultipleAccountsExist() throws {
        let homeURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: homeURL) }
        let personalURL = oneDriveRootURL(homeURL: homeURL, name: "OneDrive")
        let workURL = oneDriveRootURL(homeURL: homeURL, name: "OneDrive - Work")
        try FileManager.default.createDirectory(at: personalURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workURL, withIntermediateDirectories: true)

        let resolution = SyncDefaultFolderResolver(fileManager: .default).resolve(homeDirectory: homeURL)

        guard case .found(let candidate) = resolution else {
            #expect(Bool(false), "Expected the personal OneDrive candidate, got \(resolution)")
            return
        }
        #expect(candidate.displayName == "OneDrive")
        #expect(FileManager.default.fileExists(atPath: syncRootURL(oneDriveRootURL: personalURL).path))
        #expect(!FileManager.default.fileExists(atPath: syncRootURL(oneDriveRootURL: workURL).path))
    }

    @Test
    func defaultFolderResolverDoesNotFallbackToDocumentsFolder() throws {
        let homeURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: homeURL) }
        let documentsOneDriveURL = homeURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("oneDrive", isDirectory: true)
        try FileManager.default.createDirectory(at: documentsOneDriveURL, withIntermediateDirectories: true)

        let resolution = SyncDefaultFolderResolver(fileManager: .default).resolve(homeDirectory: homeURL)

        #expect(resolution == .notFound)
        #expect(!FileManager.default.fileExists(
            atPath: syncRootURL(oneDriveRootURL: documentsOneDriveURL).path
        ))
    }

    @Test
    func defaultFolderResolverDeduplicatesCanonicalOneDriveRoots() throws {
        let homeURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: homeURL) }
        let oneDriveURL = oneDriveRootURL(homeURL: homeURL, name: "OneDrive")
        let aliasURL = oneDriveRootURL(homeURL: homeURL, name: "OneDrive - Alias")
        try FileManager.default.createDirectory(at: oneDriveURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: aliasURL, withDestinationURL: oneDriveURL)

        let resolution = SyncDefaultFolderResolver(fileManager: .default).resolve(homeDirectory: homeURL)

        guard case .found(let candidate) = resolution else {
            #expect(Bool(false), "Expected duplicate canonical OneDrive roots to collapse to one candidate")
            return
        }
        #expect(candidate.oneDriveRootURL == oneDriveURL.resolvingSymlinksInPath().standardizedFileURL)
    }

    @Test
    func defaultFolderResolverIgnoresSharedLibraryAndCloudTempDirectories() throws {
        let homeURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: homeURL) }
        let sharedLibraryURL = oneDriveRootURL(homeURL: homeURL, name: "OneDrive - Shared Libraries - Work")
        let cloudTempURL = oneDriveRootURL(homeURL: homeURL, name: "OneDriveCloudTemp")
        try FileManager.default.createDirectory(at: sharedLibraryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cloudTempURL, withIntermediateDirectories: true)

        let resolution = SyncDefaultFolderResolver(fileManager: .default).resolve(homeDirectory: homeURL)

        #expect(resolution == .notFound)
    }

    @Test
    func coordinatorHonorsIndependentUploadSwitches() throws {
        let rootURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let content = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .string, data: Data("Synced history".utf8))
            ]
        )
        historyRepository.save(id: PasteboardHistory.ID(rawValue: content.hash), content: content, updateAt: 10)
        let folder = try #require(snippetRepository.insertFolder())
        _ = try #require(snippetRepository.insertSnippet(to: folder.id))

        var settings = makeSettings(rootURL: rootURL, historyUpload: true, snippetUpload: false)
        let coordinator = SyncCoordinator(
            settingsProvider: { settings },
            providerFactory: { _ in provider },
            historyRepository: historyRepository,
            snippetRepository: snippetRepository
        )

        coordinator.syncNow(reason: .manual, wait: true)

        #expect(try provider.loadRecords(kind: .history).count == 1)
        #expect(try provider.loadRecords(kind: .snippet).isEmpty)
        #expect(try provider.loadRecords(kind: .snippetFolder).isEmpty)

        settings = makeSettings(rootURL: rootURL, historyUpload: false, snippetUpload: true)
        coordinator.syncNow(reason: .manual, wait: true)

        #expect(try provider.loadRecords(kind: .history).count == 1)
        #expect(try provider.loadRecords(kind: .snippet).count == 1)
        #expect(try provider.loadRecords(kind: .snippetFolder).count == 1)
    }

    @Test
    func coordinatorSkipsBackgroundSyncWhenAutomaticSyncIsOffButAllowsManualSync() throws {
        let rootURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let content = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .string, data: Data("Background gated".utf8))
            ]
        )
        historyRepository.save(id: PasteboardHistory.ID(rawValue: content.hash), content: content, updateAt: 10)
        let settings = makeSettings(rootURL: rootURL, automaticSync: false, historyUpload: true)
        let coordinator = SyncCoordinator(
            settingsProvider: { settings },
            providerFactory: { _ in provider },
            historyRepository: historyRepository,
            snippetRepository: snippetRepository
        )

        coordinator.syncNow(reason: .timer, wait: true)

        #expect(coordinator.status.phase == .skipped)
        #expect(coordinator.status.statusText == "自动同步未开启。")
        #expect(try provider.loadRecords(kind: .history).isEmpty)

        coordinator.syncNow(reason: .manual, wait: true)

        #expect(coordinator.status.phase == .succeeded)
        #expect(try provider.loadRecords(kind: .history).count == 1)
    }

    @Test
    func coordinatorSkipsLegacyEncryptedRecordsWithoutRequiringAKey() throws {
        let rootURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let remoteID = PasteboardHistory.ID(rawValue: "remote-history")
        let historyDirectory = rootURL.appendingPathComponent("histories", isDirectory: true)
        try FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        try Data("""
        {
          "id": "remote-history",
          "kind": "history",
          "deviceID": "remote-device",
          "updatedAt": 20,
          "deletedAt": null,
          "payload": {
            "nonce": "",
            "ciphertext": "cGF5bG9hZA==",
            "tag": ""
          },
          "schemaVersion": 1
        }
        """.utf8).write(to: historyDirectory.appendingPathComponent("remote-history.json"))
        let coordinator = SyncCoordinator(
            settingsProvider: { makeSettings(rootURL: rootURL, historyImport: true) },
            providerFactory: { _ in provider },
            historyRepository: historyRepository,
            snippetRepository: snippetRepository
        )

        coordinator.syncNow(reason: .manual, wait: true)

        #expect(historyRepository.fetchHistory(id: remoteID) == nil)
        #expect(coordinator.status.phase == .succeeded)
        #expect(coordinator.status.importedCount == 0)
    }

    @Test
    func coordinatorCountsOnlyActualImportsWhenRemoteRecordIsSkippedByLWW() throws {
        let rootURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let localContent = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .string, data: Data("Local newer".utf8))
            ]
        )
        let sharedID = PasteboardHistory.ID(rawValue: "shared-history")
        historyRepository.save(id: sharedID, content: localContent, updateAt: 30)
        let remotePayload = PasteboardHistorySyncPayload(
            id: sharedID.rawValue,
            title: "Remote older",
            pasteboardTypes: [.string],
            updateAt: 20,
            deviceID: "remote-device",
            assets: [PasteboardHistorySyncPayload.Asset(type: .string, data: Data("Remote older".utf8))],
            thumbnail: nil
        )
        try provider.save(makePlaintextRecord(payload: remotePayload, kind: .history))
        let coordinator = SyncCoordinator(
            settingsProvider: { makeSettings(rootURL: rootURL, historyImport: true) },
            providerFactory: { _ in provider },
            historyRepository: historyRepository,
            snippetRepository: snippetRepository
        )

        coordinator.syncNow(reason: .manual, wait: true)

        #expect(coordinator.status.phase == .succeeded)
        #expect(coordinator.status.importedCount == 0)
        #expect(coordinator.status.statusText == "没有新数据。OneDrive 云端上传状态请查看 OneDrive。")
        #expect(historyRepository.fetchHistory(id: sharedID)?.title == "Local newer")
    }

    @Test
    func coordinatorUploadsBusinessTimestampWithoutFallback() throws {
        let rootURL = try makeRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let provider = OneDriveFolderSyncProvider(rootURL: rootURL)
        let content = PasteboardContent(
            assets: [
                PasteboardContent.Asset(type: .string, data: Data("Zero timestamp".utf8))
            ]
        )
        historyRepository.save(id: PasteboardHistory.ID(rawValue: content.hash), content: content, updateAt: 0)
        let coordinator = SyncCoordinator(
            settingsProvider: { makeSettings(rootURL: rootURL, historyUpload: true) },
            providerFactory: { _ in provider },
            historyRepository: historyRepository,
            snippetRepository: snippetRepository
        )

        coordinator.syncNow(reason: .manual, wait: true)

        let record = try #require(provider.loadRecords(kind: .history).first)
        #expect(record.updatedAt == 0)
        #expect(record.payload != .object([:]))
        #expect(coordinator.status.statusText == "已写入 1 条到本地同步文件夹，等待 OneDrive 客户端上传；Pastera 不知道云端是否已完成。")
    }

    private func makeRootURL() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    private func oneDriveRootURL(homeURL: URL, name: String) -> URL {
        homeURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("CloudStorage", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    private func syncRootURL(oneDriveRootURL: URL) -> URL {
        oneDriveRootURL
            .appendingPathComponent("Pastera", isDirectory: true)
            .appendingPathComponent("sync", isDirectory: true)
    }

    private func makePlaintextRecord<T: Encodable>(
        payload: T,
        kind: SyncRecord.Kind
    ) throws -> SyncRecord {
        let recordID: String
        let updatedAt: Int
        switch payload {
        case let history as PasteboardHistorySyncPayload:
            recordID = history.id
            updatedAt = history.updateAt
        case let folder as SnippetFolderSyncPayload:
            recordID = folder.id
            updatedAt = folder.updatedAt
        case let snippet as SnippetSyncPayload:
            recordID = snippet.id
            updatedAt = snippet.updatedAt
        default:
            throw NSError(domain: "SyncCoordinatorTests", code: 1, userInfo: nil)
        }
        return SyncRecord(
            id: recordID,
            kind: kind,
            deviceID: "remote-device",
            updatedAt: updatedAt,
            deletedAt: nil,
            payload: try SyncJSONValue(payload),
            schemaVersion: 1
        )
    }

    private func makeSettings(
        rootURL: URL,
        automaticSync: Bool = true,
        historyUpload: Bool = false,
        historyImport: Bool = false,
        snippetUpload: Bool = false,
        snippetImport: Bool = false
    ) -> SyncSettings {
        SyncSettings(
            automaticSyncEnabled: automaticSync,
            rootURL: rootURL,
            historyUploadEnabled: historyUpload,
            historyImportEnabled: historyImport,
            snippetUploadEnabled: snippetUpload,
            snippetImportEnabled: snippetImport,
            historyUploadEnabledAt: 0,
            snippetUploadEnabledAt: 0,
            pollInterval: 300,
            maxSyncedAssetBytes: 1024
        )
    }

    private var currentDeviceID: String {
        CPYUtilities.deviceID ?? ProcessInfo.processInfo.hostName
    }
}
