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
    let rootURL: URL?
    let historyUploadEnabled: Bool
    let historyImportEnabled: Bool
    let snippetUploadEnabled: Bool
    let snippetImportEnabled: Bool
    let fileUploadEnabled: Bool
    let fileImportEnabled: Bool
    let fileAssetTypes: Set<PasteboardAvailableType>
    let pollInterval: TimeInterval
    let maxSyncedHistoryTextBytes: Int
    let maxHistorySnapshotTextBudgetBytes: Int
    let historyLimit: Int
    let maxSyncedFileBytes: Int
    let syncedFileLimitPerDevice: Int

    var hasEnabledWork: Bool {
        hasEnabledUploadWork || hasEnabledImportWork
    }

    var hasEnabledUploadWork: Bool {
        historyUploadEnabled
            || snippetUploadEnabled
            || fileUploadEnabled
    }

    var hasEnabledImportWork: Bool {
        historyImportEnabled
            || snippetImportEnabled
            || fileImportEnabled
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
    let warningDescription: String?

    var statusText: String {
        if let errorDescription {
            return errorDescription
        }
        let warningSuffix = warningDescription.map { " \($0)。" } ?? ""
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
                    uploadStatusText + warningSuffix
            }
            if importedCount > 0 {
                return "已导入 \(importedCount) 条。OneDrive 云端上传状态请查看 OneDrive。" + warningSuffix
            }
            if uploadedCount > 0 {
                return "已写入 \(uploadedCount) 条到本地同步文件夹" + uploadStatusText + warningSuffix
            }
            return "没有新数据。OneDrive 云端上传状态请查看 OneDrive。" + warningSuffix
        case .failed:
            return "同步失败"
        }
    }

    static let idle = SyncStatus(
        phase: .idle,
        lastSyncAt: nil,
        uploadedCount: 0,
        importedCount: 0,
        errorDescription: nil,
        warningDescription: nil
    )
}

enum SyncCoordinatorError: LocalizedError {
    case noEnabledWork
    case missingOneDrive
    case folderUnavailable

    var errorDescription: String? {
        switch self {
        case .noEnabledWork:
            return "请先开启至少一个同步开关。"
        case .missingOneDrive:
            return "请先安装并登录 OneDrive。"
        case .folderUnavailable:
            return "所选 OneDrive 文件夹不可用。"
        }
    }
}

final class UserDefaultsSyncSettingsStore {
    static let didChangeNotification = Notification.Name("PasteraSyncSettingsDidChange")
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppEnvironment.current.defaults) {
        self.defaults = defaults
    }

    func settings() -> SyncSettings {
        let rootPath = defaults.string(forKey: Constants.UserDefaults.syncRootPath)
        let pollInterval = defaults.double(forKey: Constants.UserDefaults.syncPollInterval)
        let retentionSettings = HistoryRetentionSettings.current(defaults: defaults)
        let fileAssetTypes = fileAssetTypes()
        return SyncSettings(
            rootURL: rootPath.map { URL(fileURLWithPath: $0, isDirectory: true) },
            historyUploadEnabled: defaults.bool(forKey: Constants.UserDefaults.syncHistoryUploadEnabled),
            historyImportEnabled: defaults.bool(forKey: Constants.UserDefaults.syncHistoryImportEnabled),
            snippetUploadEnabled: defaults.bool(forKey: Constants.UserDefaults.syncSnippetUploadEnabled),
            snippetImportEnabled: defaults.bool(forKey: Constants.UserDefaults.syncSnippetImportEnabled),
            fileUploadEnabled: !fileAssetTypes.isEmpty && defaults.bool(forKey: Constants.UserDefaults.syncFileUploadEnabled),
            fileImportEnabled: !fileAssetTypes.isEmpty && defaults.bool(forKey: Constants.UserDefaults.syncFileImportEnabled),
            fileAssetTypes: fileAssetTypes,
            pollInterval: pollInterval > 0 ? pollInterval : 300,
            maxSyncedHistoryTextBytes: retentionSettings.maxSyncedHistoryTextBytes,
            maxHistorySnapshotTextBudgetBytes: retentionSettings.maxHistorySnapshotTextBudgetBytes,
            historyLimit: min(retentionSettings.storedHistoryLimit, HistoryRetentionSettings.defaultStoredHistoryLimit),
            maxSyncedFileBytes: maxSyncedFileBytes(),
            syncedFileLimitPerDevice: syncedFileLimitPerDevice()
        )
    }

    func setRootURL(_ url: URL?) {
        if let url {
            defaults.set(url.standardizedFileURL.path, forKey: Constants.UserDefaults.syncRootPath)
        } else {
            defaults.removeObject(forKey: Constants.UserDefaults.syncRootPath)
        }
        notifyChange()
    }

    func setHistoryUploadEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Constants.UserDefaults.syncHistoryUploadEnabled)
        updateDerivedFileScopes()
        notifyChange()
    }

    func setSnippetUploadEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Constants.UserDefaults.syncSnippetUploadEnabled)
        notifyChange()
    }

    func setFileUploadEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Constants.UserDefaults.syncFileUploadEnabled)
        notifyChange()
    }

    func setHistoryImportEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Constants.UserDefaults.syncHistoryImportEnabled)
        updateDerivedFileScopes()
        notifyChange()
    }

    func setSnippetImportEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Constants.UserDefaults.syncSnippetImportEnabled)
        notifyChange()
    }

    func setFileImportEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Constants.UserDefaults.syncFileImportEnabled)
        notifyChange()
    }

    func setFileTypeEnabled(_ type: PasteboardAvailableType, enabled: Bool) {
        var states = fileTypeStates()
        states[type.rawValue] = NSNumber(value: enabled)
        defaults.set(states, forKey: Constants.UserDefaults.syncFileTypes)
        updateDerivedFileScopes()
        notifyChange()
    }

    private func maxSyncedFileBytes() -> Int {
        let value = defaults.integer(forKey: Constants.UserDefaults.maxSyncedFileBytes)
        let maximum = 25 * 1024 * 1024
        return value > 0 ? min(value, maximum) : maximum
    }

    private func syncedFileLimitPerDevice() -> Int {
        let value = defaults.integer(forKey: Constants.UserDefaults.syncedFileLimitPerDevice)
        return value > 0 ? min(value, 10) : 10
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: defaults)
    }

    private func fileAssetTypes() -> Set<PasteboardAvailableType> {
        Set(fileTypeStates().compactMap { key, value in
            guard value.boolValue else { return nil }
            return PasteboardAvailableType(rawValue: key)
        })
    }

    private func fileTypeStates() -> [String: NSNumber] {
        let values = defaults.object(forKey: Constants.UserDefaults.syncFileTypes) as? [String: Any] ?? [:]
        return PasteboardAvailableType.syncFileTypes.reduce(into: [String: NSNumber]()) { result, type in
            if let number = values[type.rawValue] as? NSNumber {
                result[type.rawValue] = number
            } else if let bool = values[type.rawValue] as? Bool {
                result[type.rawValue] = NSNumber(value: bool)
            } else {
                result[type.rawValue] = NSNumber(value: false)
            }
        }
    }

    private func updateDerivedFileScopes() {
        let hasFileTypes = !fileAssetTypes().isEmpty
        defaults.set(
            hasFileTypes && defaults.bool(forKey: Constants.UserDefaults.syncHistoryUploadEnabled),
            forKey: Constants.UserDefaults.syncFileUploadEnabled
        )
        defaults.set(
            hasFileTypes && defaults.bool(forKey: Constants.UserDefaults.syncHistoryImportEnabled),
            forKey: Constants.UserDefaults.syncFileImportEnabled
        )
        defaults.synchronize()
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
    private struct ActivationSignature: Equatable {
        let rootPath: String?
        let rootAvailable: Bool
        let pollInterval: TimeInterval
        let historyObservationEnabled: Bool
        let snippetObservationEnabled: Bool
        let hasEnabledWork: Bool
        let vaultCanSync: Bool
    }
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
    private let passwordVaultStoreProvider: () -> PasswordVaultStore
    private let queue: DispatchQueue
    private var timer: DispatchSourceTimer?
    private var historyObservation: AnyCancellable?
    private var snippetObservation: AnyCancellable?
    private var configurationObservation: AnyCancellable?
    private var activationSignature: ActivationSignature?
    private var lastHistoryExportSignature: HistoryWindowSignature?
    private var importedHistorySnapshotStates = [String: HistoryRemoteSnapshotState]()

    private struct DirectionPlan {
        let upload: Bool
        let importRemote: Bool
    }

    private struct SyncRunResult {
        var uploaded = 0
        var imported = 0
        var warnings = [String]()

        var isNoOp: Bool {
            uploaded == 0 && imported == 0 && warnings.isEmpty
        }

        var warningDescription: String? {
            warnings.isEmpty ? nil : warnings.joined(separator: "；")
        }
    }

    init(
        settingsProvider: @escaping () -> SyncSettings = { UserDefaultsSyncSettingsStore().settings() },
        providerFactory: @escaping (URL) -> OneDriveFolderSyncProvider = { OneDriveFolderSyncProvider(rootURL: $0) },
        historyRepository: PasteboardHistoryRepositoryProtocol = PasteboardHistoryRepository(),
        snippetRepository: SnippetRepositoryProtocol = SnippetRepository(),
        passwordVaultStoreProvider: @escaping () -> PasswordVaultStore = { AppEnvironment.current.passwordVaultStore },
        queue: DispatchQueue = DispatchQueue(label: "com.pastera.sync.coordinator", qos: .utility)
    ) {
        self.settingsProvider = settingsProvider
        self.providerFactory = providerFactory
        self.historyRepository = historyRepository
        self.snippetRepository = snippetRepository
        self.passwordVaultStoreProvider = passwordVaultStoreProvider
        self.queue = queue
    }

    func start() {
        configurationObservation = NotificationCenter.default.publisher(
            for: UserDefaultsSyncSettingsStore.didChangeNotification
        )
        .sink { [weak self] _ in self?.reloadConfiguration() }
        reloadConfiguration()
        syncNow(reason: .startup)
    }

    func stop() {
        timer?.cancel()
        timer = nil
        historyObservation = nil
        snippetObservation = nil
        configurationObservation = nil
        activationSignature = nil
    }

    func reloadConfiguration() {
        queue.async { [weak self] in self?.applyConfiguration() }
    }

    private func applyConfiguration() {
        let settings = settingsProvider()
        let rootAvailable = settings.rootURL.map { FileManager.default.fileExists(atPath: $0.path) } == true
        let vaultStore = passwordVaultStoreProvider()
        let vaultCanSync = vaultStore.state == .unlocked
            || { if case .readOnlyWarning = vaultStore.state { return true }; return false }()
        let signature = ActivationSignature(
            rootPath: settings.rootURL?.standardizedFileURL.path,
            rootAvailable: rootAvailable,
            pollInterval: settings.pollInterval,
            historyObservationEnabled: settings.historyUploadEnabled || settings.fileUploadEnabled,
            snippetObservationEnabled: settings.snippetUploadEnabled,
            hasEnabledWork: settings.hasEnabledWork,
            vaultCanSync: vaultCanSync
        )
        guard signature != activationSignature else { return }
        activationSignature = signature
        guard rootAvailable, settings.hasEnabledWork || vaultCanSync else {
            timer?.cancel()
            timer = nil
            historyObservation = nil
            snippetObservation = nil
            return
        }
        installTimer()
        observeLocalChanges(settings: settings)
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

    private func observeLocalChanges(settings: SyncSettings) {
        historyObservation = nil
        if settings.historyUploadEnabled || settings.fileUploadEnabled {
            let publisher = settings.fileUploadEnabled
                ? historyRepository.observeHistoryChanges()
                : historyRepository.observeTextSyncCandidateChanges(currentDeviceID: currentDeviceID)
            historyObservation = publisher
                .dropFirst()
                .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
                .sink { [weak self] _ in self?.syncNow(reason: .localChange) }
        }

        snippetObservation = nil
        if settings.snippetUploadEnabled {
            snippetObservation = snippetRepository.observeFolderDetails()
                .dropFirst()
                .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
                .sink { [weak self] _ in self?.syncNow(reason: .localChange) }
        }
    }

    private func performSync(reason: Reason) {
        let settings = settingsProvider()
        guard let rootURL = settings.rootURL else {
            setSkipped(error: SyncCoordinatorError.missingOneDrive)
            return
        }
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            setSkipped(error: SyncCoordinatorError.folderUnavailable)
            return
        }
        let vaultStore = passwordVaultStoreProvider()
        let vaultCanSync = vaultStore.state == .unlocked
            || { if case .readOnlyWarning = vaultStore.state { return true }; return false }()
        guard settings.hasEnabledWork || vaultCanSync else {
            setSkipped(error: SyncCoordinatorError.noEnabledWork)
            return
        }
        let directionPlan = directionPlan(reason: reason, settings: settings)

        if reason == .manual {
            setStatus(SyncStatus(
                phase: .syncing,
                lastSyncAt: status.lastSyncAt,
                uploadedCount: status.uploadedCount,
                importedCount: status.importedCount,
                errorDescription: nil,
                warningDescription: nil
            ))
        }

        do {
            if vaultCanSync {
                try vaultStore.reloadAndMerge()
            }
            let result: SyncRunResult
            if settings.hasEnabledWork {
                let provider = providerFactory(rootURL)
                result = try sync(settings: settings, provider: provider, directionPlan: directionPlan)
            } else {
                result = SyncRunResult()
            }
            guard reason == .manual || !result.isNoOp else { return }
            setStatus(SyncStatus(
                phase: .succeeded,
                lastSyncAt: Date(),
                uploadedCount: result.uploaded,
                importedCount: result.imported,
                errorDescription: nil,
                warningDescription: result.warningDescription
            ))
        } catch {
            setStatus(SyncStatus(
                phase: .failed,
                lastSyncAt: status.lastSyncAt,
                uploadedCount: status.uploadedCount,
                importedCount: status.importedCount,
                errorDescription: error.localizedDescription,
                warningDescription: nil
            ))
        }
    }

    private func sync(
        settings: SyncSettings,
        provider: OneDriveFolderSyncProvider,
        directionPlan: DirectionPlan
    ) throws -> SyncRunResult {
        var result = SyncRunResult()

        if directionPlan.importRemote, settings.historyImportEnabled {
            result.imported += try importHistories(provider: provider)
        }
        if directionPlan.importRemote, settings.snippetImportEnabled {
            result.imported += try importSnippets(provider: provider)
        }
        if directionPlan.importRemote, settings.fileImportEnabled {
            do {
                let fileResult = try importFiles(settings: settings, provider: provider)
                result.imported += fileResult.imported
                if let warning = fileResult.warning {
                    result.warnings.append(warning)
                }
            } catch {
                result.warnings.append("文件同步失败：\(error.localizedDescription)")
            }
        }
        if directionPlan.upload, settings.historyUploadEnabled {
            result.uploaded += try exportHistories(settings: settings, provider: provider)
        }
        if directionPlan.upload, settings.snippetUploadEnabled {
            result.uploaded += try exportSnippets(provider: provider)
        }
        if directionPlan.upload, settings.fileUploadEnabled {
            do {
                let fileResult = try exportFiles(settings: settings, provider: provider)
                result.uploaded += fileResult.uploaded
                if let warning = fileResult.warning {
                    result.warnings.append(warning)
                }
            } catch {
                result.warnings.append("文件同步失败：\(error.localizedDescription)")
            }
        }
        return result
    }

    private func importHistories(provider: OneDriveFolderSyncProvider) throws -> Int {
        let states = try provider.historySnapshotFileStates(excludingDeviceID: currentDeviceID)
        let changedStates = states.filter {
            importedHistorySnapshotStates[$0.cacheKey] != $0
        }
        guard !changedStates.isEmpty else { return 0 }
        let payloads = try provider.loadHistorySnapshots(from: changedStates, excludingDeviceID: currentDeviceID)
            .flatMap(\.payloads)
        let imported = payloads.reduce(0) { importedCount, payload in
            importedCount + (historyRepository.upsertSyncPayload(payload) ? 1 : 0)
        }
        for state in changedStates {
            importedHistorySnapshotStates[state.cacheKey] = state
        }
        return imported
    }

    private func importSnippets(provider: OneDriveFolderSyncProvider) throws -> Int {
        _ = snippetRepository.removeDuplicateFoldersAndSnippets()
        return try provider.loadSnippetSnapshots(excludingDeviceID: currentDeviceID).reduce(0) { importedCount, snapshot in
            importedCount + snippetRepository.upsertSyncSnapshot(snapshot.snapshot)
        }
    }

    private func importFiles(
        settings: SyncSettings,
        provider: OneDriveFolderSyncProvider
    ) throws -> (imported: Int, warning: String?) {
        let loadResult = try provider.loadFileSnapshotResult(
            excludingDeviceID: currentDeviceID,
            includedFileTypes: settings.fileAssetTypes,
            maxFileBytes: settings.maxSyncedFileBytes,
            maxAssetsPerDevice: settings.syncedFileLimitPerDevice,
            shouldImportHistory: { [historyRepository] historyID, updatedAt in
                historyRepository.shouldImportFileSyncHistory(historyID: historyID, updatedAt: updatedAt)
            }
        )
        let imported = loadResult.snapshots.reduce(0) { importedCount, snapshot in
            importedCount + snapshot.histories.reduce(0) { historyImportedCount, payload in
                guard payload.assets.allSatisfy({
                    guard let fileType = PasteboardAvailableType.syncFileType(for: $0.pasteboardType) else {
                        return false
                    }
                    return settings.fileAssetTypes.contains(fileType)
                }) else {
                    return historyImportedCount
                }
                return historyImportedCount + (historyRepository.upsertFileSyncHistory(payload) ? 1 : 0)
            }
        }
        var warnings = [String]()
        if loadResult.skippedAssetCount > 0 {
            warnings.append("已跳过 \(loadResult.skippedAssetCount) 个文件（缺失、超限或校验失败）")
        }
        if loadResult.skippedManifestCount > 0 {
            warnings.append("已跳过 \(loadResult.skippedManifestCount) 个文件同步清单（无法读取）")
        }
        return (imported, warnings.isEmpty ? nil : warnings.joined(separator: "。"))
    }

    private func exportHistories(settings: SyncSettings, provider: OneDriveFolderSyncProvider) throws -> Int {
        let historyLimit = max(0, min(settings.historyLimit, HistoryRetentionSettings.defaultStoredHistoryLimit))
        let payloads = historyRepository.fetchSyncPayloads(
            currentDeviceID: currentDeviceID,
            limit: historyLimit,
            maxTextBytes: settings.maxSyncedHistoryTextBytes,
            snapshotTextBudgetBytes: settings.maxHistorySnapshotTextBudgetBytes
        )
        let signature = HistoryWindowSignature.make(
            payloads: payloads,
            limit: historyLimit,
            maxTextBytes: settings.maxSyncedHistoryTextBytes,
            snapshotTextBudgetBytes: settings.maxHistorySnapshotTextBudgetBytes
        )
        if lastHistoryExportSignature == signature,
           provider.historySnapshotExists(deviceID: currentDeviceID) {
            return 0
        }
        try provider.saveHistorySnapshot(
            payloads,
            deviceID: currentDeviceID,
            limit: historyLimit,
            maxTextBytes: settings.maxSyncedHistoryTextBytes,
            snapshotTextBudgetBytes: settings.maxHistorySnapshotTextBudgetBytes
        )
        lastHistoryExportSignature = signature
        return payloads.count
    }

    private func exportSnippets(provider: OneDriveFolderSyncProvider) throws -> Int {
        _ = snippetRepository.removeDuplicateFoldersAndSnippets()
        let snapshot = snippetRepository.fetchSyncSnapshot()
        try provider.saveSnippetSnapshot(snapshot, deviceID: currentDeviceID)
        return snapshot.folders.count + snapshot.snippets.count
    }

    private func exportFiles(
        settings: SyncSettings,
        provider: OneDriveFolderSyncProvider
    ) throws -> (uploaded: Int, warning: String?) {
        let snapshot = historyRepository.fetchFileSyncSnapshot(
            currentDeviceID: currentDeviceID,
            limit: settings.syncedFileLimitPerDevice,
            maxFileBytes: settings.maxSyncedFileBytes,
            includedFileTypes: settings.fileAssetTypes
        )
        try provider.saveFileSnapshot(snapshot, deviceID: currentDeviceID)
        let warning = snapshot.skippedAssetCount > 0
            ? "已跳过 \(snapshot.skippedAssetCount) 个文件（超过大小限制或无法同步）"
            : nil
        return (snapshot.assetCount, warning)
    }

    private func setSkipped(error: Error? = nil) {
        setStatus(SyncStatus(
            phase: .skipped,
            lastSyncAt: status.lastSyncAt,
            uploadedCount: status.uploadedCount,
            importedCount: status.importedCount,
            errorDescription: error?.localizedDescription,
            warningDescription: status.warningDescription
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

    private func directionPlan(reason: Reason, settings: SyncSettings) -> DirectionPlan {
        DirectionPlan(
            upload: settings.hasEnabledUploadWork,
            importRemote: reason == .localChange ? false : settings.hasEnabledImportWork
        )
    }
}
