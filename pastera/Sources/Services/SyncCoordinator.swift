//
//  SyncCoordinator.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Codex on 2026/06/16.
//
//  Copyright © 2015-2026 Clipy Project.
//

import Combine
import Foundation

struct SyncSettings: Equatable {
    let automaticSyncEnabled: Bool
    let rootURL: URL?
    let historyUploadEnabled: Bool
    let historyImportEnabled: Bool
    let snippetUploadEnabled: Bool
    let snippetImportEnabled: Bool
    let historyUploadEnabledAt: Int
    let snippetUploadEnabledAt: Int
    let pollInterval: TimeInterval
    let maxSyncedAssetBytes: Int

    var hasEnabledWork: Bool {
        historyUploadEnabled
            || historyImportEnabled
            || snippetUploadEnabled
            || snippetImportEnabled
    }
}

struct SyncStatus: Equatable {
    enum Phase: Equatable {
        case idle
        case skipped
        case syncing
        case succeeded
        case failed
    }

    let phase: Phase
    let lastSyncAt: Date?
    let uploadedCount: Int
    let importedCount: Int
    let errorDescription: String?

    var statusText: String {
        if let errorDescription {
            return errorDescription
        }
        switch phase {
        case .idle:
            return "未同步"
        case .skipped:
            return "已跳过"
        case .syncing:
            return "同步中..."
        case .succeeded:
            let uploadStatusText = "，等待 OneDrive 客户端上传；" +
                "Pastera 不知道云端是否已完成。"
            if importedCount > 0, uploadedCount > 0 {
                return "已导入 \(importedCount) 条，已写入 \(uploadedCount) 条到本地同步文件夹" +
                    uploadStatusText
            }
            if importedCount > 0 {
                return "已导入 \(importedCount) 条。OneDrive 云端上传状态请查看 OneDrive。"
            }
            if uploadedCount > 0 {
                return "已写入 \(uploadedCount) 条到本地同步文件夹" + uploadStatusText
            }
            return "没有新数据。OneDrive 云端上传状态请查看 OneDrive。"
        case .failed:
            return "同步失败"
        }
    }

    static let idle = SyncStatus(
        phase: .idle,
        lastSyncAt: nil,
        uploadedCount: 0,
        importedCount: 0,
        errorDescription: nil
    )
}

enum SyncCoordinatorError: LocalizedError {
    case noEnabledWork
    case missingOneDrive
    case folderUnavailable
    case automaticSyncDisabled

    var errorDescription: String? {
        switch self {
        case .noEnabledWork:
            return "请先开启至少一个同步开关。"
        case .missingOneDrive:
            return "请先安装并登录 OneDrive。"
        case .folderUnavailable:
            return "所选 OneDrive 文件夹不可用。"
        case .automaticSyncDisabled:
            return "自动同步未开启。"
        }
    }
}

final class UserDefaultsSyncSettingsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppEnvironment.current.defaults) {
        self.defaults = defaults
    }

    func settings() -> SyncSettings {
        let rootPath = defaults.string(forKey: Constants.UserDefaults.syncRootPath)
        let pollInterval = defaults.double(forKey: Constants.UserDefaults.syncPollInterval)
        return SyncSettings(
            automaticSyncEnabled: defaults.bool(forKey: Constants.UserDefaults.syncAutomaticEnabled),
            rootURL: rootPath.map { URL(fileURLWithPath: $0, isDirectory: true) },
            historyUploadEnabled: defaults.bool(forKey: Constants.UserDefaults.syncHistoryUploadEnabled),
            historyImportEnabled: defaults.bool(forKey: Constants.UserDefaults.syncHistoryImportEnabled),
            snippetUploadEnabled: defaults.bool(forKey: Constants.UserDefaults.syncSnippetUploadEnabled),
            snippetImportEnabled: defaults.bool(forKey: Constants.UserDefaults.syncSnippetImportEnabled),
            historyUploadEnabledAt: defaults.integer(forKey: Constants.UserDefaults.syncHistoryUploadEnabledAt),
            snippetUploadEnabledAt: defaults.integer(forKey: Constants.UserDefaults.syncSnippetUploadEnabledAt),
            pollInterval: pollInterval > 0 ? pollInterval : 300,
            maxSyncedAssetBytes: HistoryRetentionSettings.current(defaults: defaults).maxSyncedAssetBytes
        )
    }

    func setAutomaticSyncEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Constants.UserDefaults.syncAutomaticEnabled)
    }

    func setRootURL(_ url: URL?) {
        if let url {
            defaults.set(url.standardizedFileURL.path, forKey: Constants.UserDefaults.syncRootPath)
        } else {
            defaults.removeObject(forKey: Constants.UserDefaults.syncRootPath)
        }
    }

    func setHistoryUploadEnabled(_ enabled: Bool) {
        setUploadEnabled(
            enabled,
            enabledKey: Constants.UserDefaults.syncHistoryUploadEnabled,
            enabledAtKey: Constants.UserDefaults.syncHistoryUploadEnabledAt
        )
    }

    func setSnippetUploadEnabled(_ enabled: Bool) {
        setUploadEnabled(
            enabled,
            enabledKey: Constants.UserDefaults.syncSnippetUploadEnabled,
            enabledAtKey: Constants.UserDefaults.syncSnippetUploadEnabledAt
        )
    }

    func setHistoryImportEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Constants.UserDefaults.syncHistoryImportEnabled)
    }

    func setSnippetImportEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Constants.UserDefaults.syncSnippetImportEnabled)
    }

    func enableAllSyncScopesIfNeeded() {
        let settings = settings()
        guard !settings.hasEnabledWork else { return }
        setHistoryUploadEnabled(true)
        setHistoryImportEnabled(true)
        setSnippetUploadEnabled(true)
        setSnippetImportEnabled(true)
    }

    private func setUploadEnabled(_ enabled: Bool, enabledKey: String, enabledAtKey: String) {
        let wasEnabled = defaults.bool(forKey: enabledKey)
        defaults.set(enabled, forKey: enabledKey)
        if enabled, !wasEnabled {
            defaults.set(Int(Date().timeIntervalSince1970), forKey: enabledAtKey)
        }
    }
}

struct SyncDefaultFolderCandidate: Equatable {
    let oneDriveRootURL: URL
    let syncRootURL: URL
    let displayName: String
    let isOneDriveBacked: Bool
}

enum SyncDefaultFolderResolution: Equatable {
    case found(SyncDefaultFolderCandidate)
    case notFound
    case multiple([SyncDefaultFolderCandidate])
}

struct SyncDefaultFolderResolver {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func resolve(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> SyncDefaultFolderResolution {
        let candidates = oneDriveCandidates(homeDirectory: homeDirectory)
        guard let candidate = preferredCandidate(from: candidates) else {
            return .notFound
        }
        guard let preparedCandidate = prepare(candidate) else {
            return .notFound
        }
        return .found(preparedCandidate)
    }

    func preferredCandidate(from candidates: [SyncDefaultFolderCandidate]) -> SyncDefaultFolderCandidate? {
        let sortedCandidates = candidates.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        return sortedCandidates.first { $0.displayName.compare("OneDrive", options: [.caseInsensitive]) == .orderedSame }
            ?? sortedCandidates.first
    }

    func prepare(_ candidate: SyncDefaultFolderCandidate) -> SyncDefaultFolderCandidate? {
        do {
            try fileManager.createDirectory(at: candidate.syncRootURL, withIntermediateDirectories: true)
            return SyncDefaultFolderCandidate(
                oneDriveRootURL: canonicalURL(candidate.oneDriveRootURL),
                syncRootURL: canonicalURL(candidate.syncRootURL),
                displayName: candidate.displayName,
                isOneDriveBacked: candidate.isOneDriveBacked
            )
        } catch {
            return nil
        }
    }

    func oneDriveCandidates(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [SyncDefaultFolderCandidate] {
        let cloudStorageURL = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("CloudStorage", isDirectory: true)
        guard let contents = try? fileManager.contentsOfDirectory(
            at: cloudStorageURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return contents
            .filter(isUsableOneDriveRoot)
            .reduce(into: [String: SyncDefaultFolderCandidate]()) { uniqueCandidates, url in
                let oneDriveRootURL = canonicalURL(url)
                uniqueCandidates[oneDriveRootURL.path] = SyncDefaultFolderCandidate(
                    oneDriveRootURL: oneDriveRootURL,
                    syncRootURL: Self.defaultFolderURL(oneDriveRootURL: oneDriveRootURL),
                    displayName: url.lastPathComponent,
                    isOneDriveBacked: true
                )
            }
            .values
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    func oneDriveCandidate(
        containing url: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> SyncDefaultFolderCandidate? {
        let targetURL = canonicalURL(url)
        return oneDriveCandidates(homeDirectory: homeDirectory)
            .first { candidate in
                targetURL.path == candidate.oneDriveRootURL.path
                    || targetURL.path.hasPrefix(candidate.oneDriveRootURL.path + "/")
            }
    }

    static func defaultFolderURL(oneDriveRootURL: URL) -> URL {
        oneDriveRootURL
            .appendingPathComponent("Pastera", isDirectory: true)
            .appendingPathComponent("sync", isDirectory: true)
    }

    static func defaultFolderURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("CloudStorage", isDirectory: true)
            .appendingPathComponent("OneDrive", isDirectory: true)
            .appendingPathComponent("Pastera", isDirectory: true)
            .appendingPathComponent("sync", isDirectory: true)
    }

    private func isUsableOneDriveRoot(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        guard name.range(of: "OneDrive", options: [.anchored, .caseInsensitive]) != nil else {
            return false
        }
        guard name.range(of: "Shared Libraries", options: [.caseInsensitive]) == nil,
              name.range(of: "CloudTemp", options: [.caseInsensitive]) == nil else {
            return false
        }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return values?.isDirectory == true
    }

    private func canonicalURL(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }
}

final class SyncCoordinator {
    enum Reason {
        case startup
        case timer
        case localChange
        case manual
    }

    static let shared = SyncCoordinator()
    static let statusDidChangeNotification = Notification.Name("PasteraSyncStatusDidChange")

    @Published private(set) var status = SyncStatus.idle

    private let settingsProvider: () -> SyncSettings
    private let providerFactory: (URL) -> OneDriveFolderSyncProvider
    private let historyRepository: PasteboardHistoryRepositoryProtocol
    private let snippetRepository: SnippetRepositoryProtocol
    private let queue: DispatchQueue
    private var timer: DispatchSourceTimer?
    private var cancellables = Set<AnyCancellable>()

    init(
        settingsProvider: @escaping () -> SyncSettings = { UserDefaultsSyncSettingsStore().settings() },
        providerFactory: @escaping (URL) -> OneDriveFolderSyncProvider = { OneDriveFolderSyncProvider(rootURL: $0) },
        historyRepository: PasteboardHistoryRepositoryProtocol = PasteboardHistoryRepository(),
        snippetRepository: SnippetRepositoryProtocol = SnippetRepository(),
        queue: DispatchQueue = DispatchQueue(label: "com.pastera.sync.coordinator", qos: .utility)
    ) {
        self.settingsProvider = settingsProvider
        self.providerFactory = providerFactory
        self.historyRepository = historyRepository
        self.snippetRepository = snippetRepository
        self.queue = queue
    }

    func start() {
        syncNow(reason: .startup)
        installTimer()
        observeLocalChanges()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        cancellables.removeAll()
    }

    func syncNow(reason: Reason, wait: Bool = false) {
        let work = { [weak self] in
            self?.performSync(reason: reason)
        }
        if wait {
            queue.sync {
                work()
            }
        } else {
            queue.async {
                work()
            }
        }
    }

    private func installTimer() {
        timer?.cancel()
        let interval = max(30, settingsProvider().pollInterval)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.performSync(reason: .timer)
        }
        timer.resume()
        self.timer = timer
    }

    private func observeLocalChanges() {
        historyRepository.observeHistoryChanges()
            .dropFirst()
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncNow(reason: .localChange)
            }
            .store(in: &cancellables)

        snippetRepository.observeFolderDetails()
            .dropFirst()
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncNow(reason: .localChange)
            }
            .store(in: &cancellables)
    }

    private func performSync(reason: Reason) {
        let settings = settingsProvider()
        guard reason == .manual || settings.automaticSyncEnabled else {
            setSkipped(error: SyncCoordinatorError.automaticSyncDisabled)
            return
        }
        guard let rootURL = settings.rootURL else {
            setSkipped(error: SyncCoordinatorError.missingOneDrive)
            return
        }
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            setSkipped(error: SyncCoordinatorError.folderUnavailable)
            return
        }
        guard settings.hasEnabledWork else {
            setSkipped(error: SyncCoordinatorError.noEnabledWork)
            return
        }

        setStatus(SyncStatus(
            phase: .syncing,
            lastSyncAt: status.lastSyncAt,
            uploadedCount: status.uploadedCount,
            importedCount: status.importedCount,
            errorDescription: nil
        ))

        do {
            let provider = providerFactory(rootURL)
            let manifest = try provider.loadOrCreateManifest(deviceID: currentDeviceID)
            let result = try sync(settings: settings, provider: provider, manifest: manifest)
            _ = reason
            setStatus(SyncStatus(
                phase: .succeeded,
                lastSyncAt: Date(),
                uploadedCount: result.uploaded,
                importedCount: result.imported,
                errorDescription: nil
            ))
        } catch {
            setStatus(SyncStatus(
                phase: .failed,
                lastSyncAt: status.lastSyncAt,
                uploadedCount: status.uploadedCount,
                importedCount: status.importedCount,
                errorDescription: error.localizedDescription
            ))
        }
    }

    private func sync(
        settings: SyncSettings,
        provider: OneDriveFolderSyncProvider,
        manifest: SyncManifest
    ) throws -> (uploaded: Int, imported: Int) {
        var uploadedRecords = [SyncRecord]()
        var imported = 0

        if settings.historyImportEnabled {
            imported += try importHistories(provider: provider)
        }
        if settings.snippetImportEnabled {
            imported += try importSnippets(provider: provider)
        }
        if settings.historyUploadEnabled {
            let records = try exportHistories(settings: settings, manifest: manifest)
            try records.forEach(provider.save)
            uploadedRecords.append(contentsOf: records)
        }
        if settings.snippetUploadEnabled {
            let records = try exportSnippets(settings: settings, manifest: manifest)
            try records.forEach(provider.save)
            uploadedRecords.append(contentsOf: records)
        }
        if !uploadedRecords.isEmpty {
            try provider.saveManifest(manifest.merging(records: uploadedRecords))
        }
        return (uploadedRecords.count, imported)
    }

    private func importHistories(provider: OneDriveFolderSyncProvider) throws -> Int {
        let records = try provider.loadRecords(kind: .history)
            .filter { $0.deletedAt == nil && $0.deviceID != currentDeviceID }
        let payloads = records.compactMap { record in
            try? decodePayload(PasteboardHistorySyncPayload.self, from: record)
        }
        return payloads.reduce(0) { importedCount, payload in
            importedCount + (historyRepository.upsertSyncPayload(payload) ? 1 : 0)
        }
    }

    private func importSnippets(provider: OneDriveFolderSyncProvider) throws -> Int {
        let folderRecords = try provider.loadRecords(kind: .snippetFolder)
            .filter { $0.deletedAt == nil && $0.deviceID != currentDeviceID }
        let snippetRecords = try provider.loadRecords(kind: .snippet)
            .filter { $0.deletedAt == nil && $0.deviceID != currentDeviceID }
        let folders = folderRecords.compactMap {
            try? decodePayload(SnippetFolderSyncPayload.self, from: $0)
        }
        let snippets = snippetRecords.compactMap {
            try? decodePayload(SnippetSyncPayload.self, from: $0)
        }
        return snippetRepository.upsertSyncSnapshot(SnippetSyncSnapshot(folders: folders, snippets: snippets))
    }

    private func exportHistories(settings: SyncSettings, manifest: SyncManifest) throws -> [SyncRecord] {
        let payloads = historyRepository.fetchSyncPayloads(
            currentDeviceID: currentDeviceID,
            updatedAtOrAfter: settings.historyUploadEnabledAt,
            maxAssetBytes: settings.maxSyncedAssetBytes
        )
        return try payloads.map {
            try makeRecord(id: $0.id, kind: .history, updatedAt: $0.updateAt, payload: $0)
        }
    }

    private func exportSnippets(settings: SyncSettings, manifest: SyncManifest) throws -> [SyncRecord] {
        let snapshot = snippetRepository.fetchSyncSnapshot(
            currentDeviceID: currentDeviceID,
            updatedAtOrAfter: settings.snippetUploadEnabledAt
        )
        let folderRecords = try snapshot.folders.map {
            try makeRecord(id: $0.id, kind: .snippetFolder, updatedAt: $0.updatedAt, payload: $0)
        }
        let snippetRecords = try snapshot.snippets.map {
            try makeRecord(id: $0.id, kind: .snippet, updatedAt: $0.updatedAt, payload: $0)
        }
        _ = manifest
        return folderRecords + snippetRecords
    }

    private func makeRecord<T: Encodable>(
        id: String,
        kind: SyncRecord.Kind,
        updatedAt: Int,
        payload: T
    ) throws -> SyncRecord {
        return SyncRecord(
            id: id,
            kind: kind,
            deviceID: currentDeviceID,
            updatedAt: updatedAt,
            deletedAt: nil,
            payload: try SyncJSONValue(payload),
            schemaVersion: 1
        )
    }

    private func decodePayload<T: Decodable>(_ type: T.Type, from record: SyncRecord) throws -> T {
        try record.payload.decode(type)
    }

    private func setSkipped(error: Error? = nil) {
        setStatus(SyncStatus(
            phase: .skipped,
            lastSyncAt: status.lastSyncAt,
            uploadedCount: status.uploadedCount,
            importedCount: status.importedCount,
            errorDescription: error?.localizedDescription
        ))
    }

    private func setStatus(_ status: SyncStatus) {
        self.status = status
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.statusDidChangeNotification, object: self)
        }
    }

    private var currentDeviceID: String {
        CPYUtilities.deviceID ?? ProcessInfo.processInfo.hostName
    }
}

private extension SyncManifest {
    func merging(records newRecords: [SyncRecord]) -> SyncManifest {
        var mergedRecords = Dictionary(uniqueKeysWithValues: records.map { ("\($0.kind.rawValue):\($0.id)", $0) })
        newRecords.forEach { record in
            mergedRecords["\(record.kind.rawValue):\(record.id)"] = SyncManifestRecord(
                id: record.id,
                kind: record.kind,
                updatedAt: record.updatedAt,
                deletedAt: record.deletedAt
            )
        }
        return SyncManifest(
            schemaVersion: schemaVersion,
            deviceID: deviceID,
            updatedAt: Int(Date().timeIntervalSince1970),
            records: mergedRecords.values.sorted { lhs, rhs in
                if lhs.kind.rawValue == rhs.kind.rawValue {
                    return lhs.id < rhs.id
                }
                return lhs.kind.rawValue < rhs.kind.rawValue
            }
        )
    }
}
