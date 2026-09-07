import AppKit
import Foundation
import KDBXKit
import LocalAuthentication
import Security

enum PasswordVaultState: Equatable {
    case notConfigured
    case preparingLocalCopy
    case localCopyUnavailable(PasswordVaultLocalPreparationFailure)
    case locked
    case unlocking
    case unlocked
    case readOnlyWarning(String)
    case recoveryRequired(String)
    case failed(String)
}

private enum VaultSessionLockRequestKind {
    case timer(UInt64)
    case mandatory
}

final class VaultSessionLockRequest {
    private weak var controller: VaultSessionController?
    private let kind: VaultSessionLockRequestKind
    private let stateLock = NSLock()
    private var wasConsumed = false

    fileprivate init(controller: VaultSessionController, kind: VaultSessionLockRequestKind) {
        self.controller = controller
        self.kind = kind
    }

    func consume() -> Bool {
        stateLock.lock()
        guard !wasConsumed else {
            stateLock.unlock()
            return false
        }
        wasConsumed = true
        stateLock.unlock()
        return controller?.consumeLockRequest(kind) == true
    }
}
final class VaultSessionController {
    typealias TimerScheduler = (TimeInterval, @escaping () -> Void) -> (() -> Void)

    static let allowedTimeouts: [TimeInterval] = [60, 300, 900, 1_800]

    private let timeoutProvider: () -> TimeInterval
    private let timerScheduler: TimerScheduler
    private let lockRequestAction: (VaultSessionLockRequest) -> Void
    private let stateLock = NSLock()
    private var generation: UInt64 = 0
    private var pendingLockGeneration: UInt64?
    private var cancelScheduledTimer: (() -> Void)?
    private var observers = [(NotificationCenter, NSObjectProtocol)]()

    convenience init(
        timeoutProvider: @escaping () -> TimeInterval = VaultSessionController.defaultTimeout,
        notificationCenter: NotificationCenter? = nil,
        timerScheduler: @escaping TimerScheduler = VaultSessionController.scheduleOnMain,
        lockAction: @escaping () -> Void
    ) {
        self.init(
            timeoutProvider: timeoutProvider,
            notificationCenter: notificationCenter,
            timerScheduler: timerScheduler,
            lockRequestAction: { request in
                guard request.consume() else { return }
                lockAction()
            }
        )
    }
    init(
        timeoutProvider: @escaping () -> TimeInterval = VaultSessionController.defaultTimeout,
        notificationCenter: NotificationCenter? = nil,
        timerScheduler: @escaping TimerScheduler = VaultSessionController.scheduleOnMain,
        lockRequestAction: @escaping (VaultSessionLockRequest) -> Void
    ) {
        self.timeoutProvider = timeoutProvider
        self.timerScheduler = timerScheduler
        self.lockRequestAction = lockRequestAction
        let workspaceCenter = notificationCenter ?? NSWorkspace.shared.notificationCenter
        func observe(_ center: NotificationCenter, _ name: Notification.Name) -> (NotificationCenter, NSObjectProtocol) {
            (center, center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.lockNow() })
        }
        observers = [
            observe(workspaceCenter, NSWorkspace.willSleepNotification),
            observe(workspaceCenter, NSWorkspace.sessionDidResignActiveNotification),
            observe(NotificationCenter.default, NSApplication.willTerminateNotification)
        ]
    }
    deinit {
        cancel()
        observers.forEach { center, observer in center.removeObserver(observer) }
    }
    func touch() {
        let token: UInt64
        let previousCancellation: (() -> Void)?
        stateLock.lock()
        generation &+= 1
        token = generation
        pendingLockGeneration = nil
        previousCancellation = cancelScheduledTimer
        cancelScheduledTimer = nil
        stateLock.unlock()
        previousCancellation?()
        let cancellation = timerScheduler(timeoutProvider()) { [weak self] in
            self?.emitTimerLockRequest(generation: token)
        }
        stateLock.lock()
        let shouldKeepTimer = generation == token && pendingLockGeneration == nil
        if shouldKeepTimer { cancelScheduledTimer = cancellation }
        stateLock.unlock()
        if !shouldKeepTimer { cancellation() }
    }
    func cancel() {
        let cancellation: (() -> Void)?
        stateLock.lock()
        generation &+= 1
        pendingLockGeneration = nil
        cancellation = cancelScheduledTimer
        cancelScheduledTimer = nil
        stateLock.unlock()
        cancellation?()
    }
    func lockNow() {
        let cancellation: (() -> Void)?
        stateLock.lock()
        generation &+= 1
        pendingLockGeneration = nil
        cancellation = cancelScheduledTimer
        cancelScheduledTimer = nil
        stateLock.unlock()
        cancellation?()
        lockRequestAction(VaultSessionLockRequest(controller: self, kind: .mandatory))
    }
    private func emitTimerLockRequest(generation requestedGeneration: UInt64) {
        let cancellation: (() -> Void)?
        stateLock.lock()
        guard generation == requestedGeneration, pendingLockGeneration == nil else {
            stateLock.unlock()
            return
        }
        pendingLockGeneration = requestedGeneration
        cancellation = cancelScheduledTimer
        cancelScheduledTimer = nil
        stateLock.unlock()
        cancellation?()
        lockRequestAction(VaultSessionLockRequest(controller: self, kind: .timer(requestedGeneration)))
    }
    fileprivate func consumeLockRequest(_ kind: VaultSessionLockRequestKind) -> Bool {
        guard case let .timer(requestedGeneration) = kind else { return true }
        let cancellation: (() -> Void)?
        stateLock.lock()
        guard generation == requestedGeneration, pendingLockGeneration == requestedGeneration else {
            stateLock.unlock()
            return false
        }
        generation &+= 1
        pendingLockGeneration = nil
        cancellation = cancelScheduledTimer
        cancelScheduledTimer = nil
        stateLock.unlock()
        cancellation?()
        return true
    }
    static func resolvedTimeout(defaults: UserDefaults) -> TimeInterval {
        let value = defaults.double(forKey: Constants.UserDefaults.passwordVaultAutoLockInterval)
        return allowedTimeouts.contains(value) ? value : 300
    }
    private static func defaultTimeout() -> TimeInterval {
        resolvedTimeout(defaults: .standard)
    }
    private static func scheduleOnMain(timeout: TimeInterval, action: @escaping () -> Void) -> () -> Void {
        let item = DispatchWorkItem(block: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: item)
        return { item.cancel() }
    }
}

struct PasswordVaultViewState: Equatable {
    var state: PasswordVaultState
    var folders: [PasswordVaultFolder]
    var entries: [PasswordVaultEntry]
    var isBusy: Bool
    var error: PasswordVaultError?

    init(
        state: PasswordVaultState,
        folders: [PasswordVaultFolder] = [],
        entries: [PasswordVaultEntry] = [],
        isBusy: Bool = false,
        error: PasswordVaultError? = nil
    ) {
        self.state = state
        self.folders = folders
        self.entries = entries
        self.isBusy = isBusy
        self.error = error
    }
}

struct PasswordVaultEntry: Codable, Equatable, Identifiable {
    let id: UUID
    var folderID: UUID
    var title: String
    var website: String
    var username: String
    var note: String
    let createdAt: Date
    var updatedAt: Date

    func matches(_ query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(normalized)
            || website.localizedCaseInsensitiveContains(normalized)
            || username.localizedCaseInsensitiveContains(normalized)
    }
}

struct PasswordVaultDraft: Equatable {
    var folderID: UUID?
    var title: String
    var website: String
    var username: String
    var note: String
    var password: String

    init(
        folderID: UUID? = nil,
        title: String,
        website: String,
        username: String,
        note: String,
        password: String
    ) {
        self.folderID = folderID
        self.title = title
        self.website = website
        self.username = username
        self.note = note
        self.password = password
    }
}

struct PasswordVaultFolder: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    let createdAt: Date
    var updatedAt: Date
}

struct PasswordVaultMetadata: Codable, Equatable {
    static let currentVersion = 2
    var version: Int
    var folders: [PasswordVaultFolder]
    var entries: [PasswordVaultEntry]
}

enum PasswordVaultError: Error, Equatable {
    case invalidTitle
    case invalidUsername
    case invalidPassword
    case entryNotFound
    case userCancelled
    case authenticationFailed
    case corruptedData
    case duplicateEntry
    case duplicateFolder
    case folderNotFound
    case folderNotEmpty
    case keychainUnavailable
    case databaseNotConfigured
    case vaultLocked
    case wrongMasterPassword
    case resetRequiresForcedReset
    case recoveryRequired
    case unsupportedFormat
    case cloudUnavailable
    case externalConflict
    case saveFailed
    case invalidAutoLockInterval
}

struct PasswordVaultAuthorizationContext {
    let localAuthenticationContext: LAContext?
}

enum PasswordVaultMasterPasswordResetCapability: Equatable {
    case preservesData
    case requiresForcedReset
    case unavailable
}

enum PasswordVaultMasterPasswordResetWarning: String, Hashable {
    case systemUnlockDisabled
    case automationUnlockDisabled
    case credentialCleanupFailed
    case conflictArchivePending
    case rekeyArtifactCleanupPending
}

struct PasswordVaultMasterPasswordResetResult: Equatable {
    let warnings: [PasswordVaultMasterPasswordResetWarning]
}

enum PasswordVaultForcedResetWarning: String, Hashable {
    case systemUnlockDisabled
    case credentialCleanupFailed
    case resetArtifactCleanupPending
}

struct PasswordVaultForcedResetResult: Equatable {
    let encryptedSnapshot: PasswordVaultEncryptedSnapshot
    let localArchiveDigest: String
    let warnings: [PasswordVaultForcedResetWarning]
}

enum PasswordVaultForcedResetError: Error, Equatable {
    case recoveryRequired
}

enum PasswordVaultForcedResetRecoveryResult: Equatable {
    case rolledBack(oldDigest: String)
    case committed(newDigest: String)
}

protocol PasswordVaultStore {
    var state: PasswordVaultState { get }
    var canQuickUnlock: Bool { get }
    var canAutomationUnlock: Bool { get }
    var masterPasswordResetCapability: PasswordVaultMasterPasswordResetCapability { get }

    func createDatabase(masterPassword: String, rememberQuickUnlock: Bool) throws
    func unlock(masterPassword: String, rememberQuickUnlock: Bool) throws
    func unlockWithQuickKey(reason: String) throws
    func enableQuickUnlock() throws
    func disableQuickUnlock() throws
    func refreshAutoLockSchedule()
    func resetMasterPassword(
        newPassword: String,
        keepSystemUnlockEnabled: Bool,
        authorization: PasswordVaultAuthorizationContext
    ) throws -> PasswordVaultMasterPasswordResetResult
    func forceReset(
        newPassword: String,
        rememberSystemUnlock: Bool
    ) throws -> PasswordVaultForcedResetResult
    func retryForcedResetRecovery() throws -> PasswordVaultForcedResetRecoveryResult
    func enableAutomationUnlock() throws
    func unlockForAutomation() throws
    func disableAutomationUnlock() throws
    func prepareLocalCopy(using migrator: PasswordVaultMigrating)
    func bindSessionExecutor(_ executor: VaultAgentSerialExecutor, onStateChange: @escaping () -> Void)
    func lock()
    func reloadAndMerge() throws
    func listFolders() throws -> [PasswordVaultFolder]
    func listEntries() throws -> [PasswordVaultEntry]
    func createFolder(name: String) throws -> PasswordVaultFolder
    func renameFolder(id: UUID, name: String) throws -> PasswordVaultFolder
    func deleteFolder(id: UUID) throws
    func reorderFolders(_ folderIDs: [UUID]) throws
    func moveEntry(id: UUID, to folderID: UUID) throws
    func moveEntry(id: UUID, to folderID: UUID, orderedEntryIDsByFolder: [UUID: [UUID]]) throws
    func create(_ draft: PasswordVaultDraft) throws -> PasswordVaultEntry
    func update(id: UUID, draft: PasswordVaultDraft) throws -> PasswordVaultEntry
    func revealPassword(id: UUID, reason: String) throws -> String
    func delete(id: UUID, reason: String) throws
}

extension PasswordVaultStore {
    var state: PasswordVaultState { .unlocked }
    var canQuickUnlock: Bool { false }
    var canAutomationUnlock: Bool { false }
    var masterPasswordResetCapability: PasswordVaultMasterPasswordResetCapability { .unavailable }
    func createDatabase(masterPassword: String, rememberQuickUnlock: Bool) throws { throw PasswordVaultError.unsupportedFormat }
    func unlock(masterPassword: String, rememberQuickUnlock: Bool) throws { throw PasswordVaultError.unsupportedFormat }
    func unlockWithQuickKey(reason: String) throws { throw PasswordVaultError.keychainUnavailable }
    func enableQuickUnlock() throws { throw PasswordVaultError.keychainUnavailable }
    func disableQuickUnlock() throws {}
    func refreshAutoLockSchedule() {}
    func resetMasterPassword(
        newPassword: String,
        keepSystemUnlockEnabled: Bool,
        authorization: PasswordVaultAuthorizationContext
    ) throws -> PasswordVaultMasterPasswordResetResult {
        throw PasswordVaultError.unsupportedFormat
    }
    func forceReset(
        newPassword: String,
        rememberSystemUnlock: Bool
    ) throws -> PasswordVaultForcedResetResult {
        throw PasswordVaultError.unsupportedFormat
    }
    func retryForcedResetRecovery() throws -> PasswordVaultForcedResetRecoveryResult {
        throw PasswordVaultForcedResetError.recoveryRequired
    }
    func enableAutomationUnlock() throws { throw PasswordVaultError.keychainUnavailable }
    func unlockForAutomation() throws { throw PasswordVaultError.keychainUnavailable }
    func disableAutomationUnlock() throws {}
    func prepareLocalCopy(using migrator: PasswordVaultMigrating) {}
    func bindSessionExecutor(_ executor: VaultAgentSerialExecutor, onStateChange: @escaping () -> Void) {}
    func lock() {}
    func reloadAndMerge() throws {}
}

protocol PasswordVaultKeychainClient {
    func readMetadata() throws -> Data?
    func writeMetadata(_ data: Data) throws
    func readSecret(id: UUID, reason: String) throws -> Data
    func writeSecret(id: UUID, data: Data) throws
    func deleteSecret(id: UUID, reason: String?) throws
}

protocol VaultUnlockKeyStoring {
    var containsKey: Bool { get }
    func save(_ data: Data) throws
    func load(reason: String) throws -> Data
    func load(reason: String, authenticationContext: LAContext?) throws -> Data
    func delete() throws
}

extension VaultUnlockKeyStoring {
    func load(reason: String, authenticationContext: LAContext?) throws -> Data {
        try load(reason: reason)
    }
}

final class VaultUnlockKeyStore: VaultUnlockKeyStoring {
    static let service = "com.pastera-app.Pastera.password-vault.kdbx-unlock"
    private static let account = "PasteraVault"

    static var availabilityQuery: [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]
    }

    var containsKey: Bool {
        SecItemCopyMatching(Self.availabilityQuery as CFDictionary, nil) == errSecSuccess
    }

    func save(_ data: Data) throws {
        guard data.count == 32 else { throw PasswordVaultError.keychainUnavailable }
        try? delete()
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            &error
        ) else { throw PasswordVaultError.keychainUnavailable }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecAttrSynchronizable as String: false,
            kSecAttrAccessControl as String: access,
            kSecValueData as String: data
        ]
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else {
            throw PasswordVaultError.keychainUnavailable
        }
    }

    private static var baseLoadQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
    }

    func load(reason: String) throws -> Data {
        try load(reason: reason, authenticationContext: nil)
    }

    func load(reason: String, authenticationContext: LAContext?) throws -> Data {
        let context = authenticationContext ?? LAContext()
        context.localizedReason = reason
        var query = Self.baseLoadQuery
        query[kSecUseAuthenticationContext as String] = context
        return try copyUnlockKey(using: query)
    }

    private func copyUnlockKey(using query: [String: Any]) throws -> Data {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, data.count == 32 else {
            if status == errSecUserCanceled { throw PasswordVaultError.userCancelled }
            if status == errSecAuthFailed || status == errSecInteractionNotAllowed {
                throw PasswordVaultError.authenticationFailed
            }
            throw PasswordVaultError.keychainUnavailable
        }
        return data
    }

    func delete() throws {
        let status = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecAttrSynchronizable as String: false
        ] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PasswordVaultError.keychainUnavailable
        }
    }
}

final class KeychainPasswordVaultStore: PasswordVaultStore {
    static let metadataService = "com.pastera-app.Pastera.password-vault.metadata"
    static let secretService = "com.pastera-app.Pastera.password-vault.secret"

    private let client: PasswordVaultKeychainClient
    private let now: () -> Date
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(client: PasswordVaultKeychainClient = SystemPasswordVaultKeychainClient(), now: @escaping () -> Date = Date.init) {
        self.client = client
        self.now = now
    }

    func listEntries() throws -> [PasswordVaultEntry] {
        try loadMetadata().entries
    }

    func listFolders() throws -> [PasswordVaultFolder] {
        try loadMetadata().folders
    }

    func createFolder(name: String) throws -> PasswordVaultFolder {
        let normalizedName = try normalizedFolderName(name)
        var metadata = try loadMetadata()
        guard !metadata.folders.contains(where: { $0.name == normalizedName }) else {
            throw PasswordVaultError.duplicateFolder
        }
        let timestamp = now()
        let folder = PasswordVaultFolder(id: UUID(), name: normalizedName, createdAt: timestamp, updatedAt: timestamp)
        metadata.folders.append(folder)
        try saveMetadata(metadata)
        return folder
    }

    func renameFolder(id: UUID, name: String) throws -> PasswordVaultFolder {
        let normalizedName = try normalizedFolderName(name)
        var metadata = try loadMetadata()
        guard let index = metadata.folders.firstIndex(where: { $0.id == id }) else {
            throw PasswordVaultError.folderNotFound
        }
        guard !metadata.folders.contains(where: { $0.id != id && $0.name == normalizedName }) else {
            throw PasswordVaultError.duplicateFolder
        }
        metadata.folders[index].name = normalizedName
        metadata.folders[index].updatedAt = now()
        try saveMetadata(metadata)
        return metadata.folders[index]
    }

    func deleteFolder(id: UUID) throws {
        var metadata = try loadMetadata()
        guard metadata.folders.contains(where: { $0.id == id }) else {
            throw PasswordVaultError.folderNotFound
        }
        guard !metadata.entries.contains(where: { $0.folderID == id }) else {
            throw PasswordVaultError.folderNotEmpty
        }
        metadata.folders.removeAll { $0.id == id }
        try saveMetadata(metadata)
    }

    func reorderFolders(_ folderIDs: [UUID]) throws {
        var metadata = try loadMetadata()
        guard folderIDs.count == metadata.folders.count,
              Set(folderIDs) == Set(metadata.folders.map(\.id)) else {
            throw PasswordVaultError.folderNotFound
        }
        let foldersByID = Dictionary(uniqueKeysWithValues: metadata.folders.map { ($0.id, $0) })
        metadata.folders = try folderIDs.map { id in
            guard let folder = foldersByID[id] else { throw PasswordVaultError.folderNotFound }
            return folder
        }
        try saveMetadata(metadata)
    }

    func moveEntry(id: UUID, to folderID: UUID) throws {
        let metadata = try loadMetadata()
        guard let entry = metadata.entries.first(where: { $0.id == id }) else {
            throw PasswordVaultError.entryNotFound
        }
        var ordered = [UUID: [UUID]]()
        ordered[entry.folderID] = metadata.entries.filter { $0.folderID == entry.folderID && $0.id != id }.map(\.id)
        ordered[folderID] = metadata.entries.filter { $0.folderID == folderID && $0.id != id }.map(\.id) + [id]
        try moveEntry(id: id, to: folderID, orderedEntryIDsByFolder: ordered)
    }

    func moveEntry(id: UUID, to folderID: UUID, orderedEntryIDsByFolder: [UUID: [UUID]]) throws {
        var metadata = try loadMetadata()
        guard metadata.folders.contains(where: { $0.id == folderID }) else {
            throw PasswordVaultError.folderNotFound
        }
        guard let index = metadata.entries.firstIndex(where: { $0.id == id }) else {
            throw PasswordVaultError.entryNotFound
        }
        let sourceFolderID = metadata.entries[index].folderID
        let affectedFolderIDs: Set<UUID> = [sourceFolderID, folderID]
        guard Set(orderedEntryIDsByFolder.keys) == affectedFolderIDs else {
            throw PasswordVaultError.entryNotFound
        }
        let entriesByID = Dictionary(uniqueKeysWithValues: metadata.entries.map { ($0.id, $0) })
        for affectedFolderID in affectedFolderIDs {
            guard let orderedIDs = orderedEntryIDsByFolder[affectedFolderID],
                  orderedIDs.count == Set(orderedIDs).count else {
                throw PasswordVaultError.entryNotFound
            }
            var expectedIDs = Set(metadata.entries.filter { $0.folderID == affectedFolderID }.map(\.id))
            if sourceFolderID == affectedFolderID { expectedIDs.remove(id) }
            if folderID == affectedFolderID { expectedIDs.insert(id) }
            guard Set(orderedIDs) == expectedIDs else { throw PasswordVaultError.entryNotFound }
        }
        metadata.entries[index].folderID = folderID
        metadata.entries[index].updatedAt = now()
        let updatedEntriesByID = Dictionary(uniqueKeysWithValues: metadata.entries.map { ($0.id, $0) })
        metadata.entries = try metadata.folders.flatMap { folder in
            if let orderedIDs = orderedEntryIDsByFolder[folder.id] {
                return try orderedIDs.map { entryID in
                    guard let entry = updatedEntriesByID[entryID] else { throw PasswordVaultError.entryNotFound }
                    return entry
                }
            }
            return metadata.entries.filter { $0.folderID == folder.id }
        }
        guard entriesByID.count == metadata.entries.count else { throw PasswordVaultError.entryNotFound }
        try saveMetadata(metadata)
    }

    func create(_ draft: PasswordVaultDraft) throws -> PasswordVaultEntry {
        let normalized = try normalizedDraft(draft)
        var metadata = try loadMetadata()
        let folderID: UUID
        if let requestedFolderID = normalized.folderID {
            guard metadata.folders.contains(where: { $0.id == requestedFolderID }) else {
                throw PasswordVaultError.folderNotFound
            }
            folderID = requestedFolderID
        } else if let existingFolder = metadata.folders.first {
            folderID = existingFolder.id
        } else {
            let folder = makeUnfiledFolder()
            metadata.folders.append(folder)
            folderID = folder.id
        }
        let timestamp = now()
        let entry = PasswordVaultEntry(
            id: UUID(),
            folderID: folderID,
            title: normalized.title,
            website: normalized.website,
            username: normalized.username,
            note: normalized.note,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        metadata.entries.append(entry)
        try saveMetadata(metadata)
        do {
            try client.writeSecret(id: entry.id, data: Data(normalized.password.utf8))
        } catch {
            metadata.entries.removeAll { $0.id == entry.id }
            try? saveMetadata(metadata)
            throw error
        }
        return entry
    }

    func update(id: UUID, draft: PasswordVaultDraft) throws -> PasswordVaultEntry {
        let normalized = try normalizedDraft(draft)
        var metadata = try loadMetadata()
        guard let index = metadata.entries.firstIndex(where: { $0.id == id }) else {
            throw PasswordVaultError.entryNotFound
        }
        let originalSecret = try client.readSecret(id: id, reason: String(localized: "Authenticate to update this password."))
        let originalEntry = metadata.entries[index]
        var updated = originalEntry
        updated.title = normalized.title
        updated.website = normalized.website
        updated.username = normalized.username
        updated.note = normalized.note
        if let folderID = normalized.folderID {
            guard metadata.folders.contains(where: { $0.id == folderID }) else {
                throw PasswordVaultError.folderNotFound
            }
            updated.folderID = folderID
        }
        updated.updatedAt = now()

        try client.writeSecret(id: id, data: Data(normalized.password.utf8))
        metadata.entries[index] = updated
        do {
            try saveMetadata(metadata)
        } catch {
            try? client.writeSecret(id: id, data: originalSecret)
            throw error
        }
        return updated
    }

    func revealPassword(id: UUID, reason: String) throws -> String {
        guard try loadMetadata().entries.contains(where: { $0.id == id }) else {
            throw PasswordVaultError.entryNotFound
        }
        let data = try client.readSecret(id: id, reason: reason)
        guard let password = String(data: data, encoding: .utf8) else {
            throw PasswordVaultError.corruptedData
        }
        return password
    }

    func delete(id: UUID, reason: String) throws {
        var metadata = try loadMetadata()
        guard let index = metadata.entries.firstIndex(where: { $0.id == id }) else {
            throw PasswordVaultError.entryNotFound
        }
        _ = try client.readSecret(id: id, reason: reason)
        let originalMetadata = metadata
        metadata.entries.remove(at: index)
        try saveMetadata(metadata)
        do {
            try client.deleteSecret(id: id, reason: nil)
        } catch {
            try? saveMetadata(originalMetadata)
            throw error
        }
    }

    static func secretAddQuery(id: UUID, secret: Data) throws -> [String: Any] {
        var error: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            &error
        ) else {
            throw PasswordVaultError.keychainUnavailable
        }
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: secretService,
            kSecAttrAccount as String: id.uuidString,
            kSecAttrSynchronizable as String: false,
            kSecAttrAccessControl as String: accessControl,
            kSecValueData as String: secret
        ]
    }

    private func loadMetadata() throws -> PasswordVaultMetadata {
        guard let data = try client.readMetadata() else {
            return PasswordVaultMetadata(version: PasswordVaultMetadata.currentVersion, folders: [], entries: [])
        }
        do {
            return try decoder.decode(PasswordVaultMetadata.self, from: data)
        } catch {
            do {
                let legacyEntries = try decoder.decode([LegacyPasswordVaultEntry].self, from: data)
                let folder = makeUnfiledFolder()
                let metadata = PasswordVaultMetadata(
                    version: PasswordVaultMetadata.currentVersion,
                    folders: [folder],
                    entries: legacyEntries.map {
                        PasswordVaultEntry(
                            id: $0.id,
                            folderID: folder.id,
                            title: $0.title,
                            website: $0.website,
                            username: $0.username,
                            note: $0.note,
                            createdAt: $0.createdAt,
                            updatedAt: $0.updatedAt
                        )
                    }
                )
                try saveMetadata(metadata)
                return metadata
            } catch let error as PasswordVaultError {
                throw error
            } catch {
                throw PasswordVaultError.corruptedData
            }
        }
    }

    private func saveMetadata(_ metadata: PasswordVaultMetadata) throws {
        do {
            try client.writeMetadata(encoder.encode(metadata))
        } catch let error as PasswordVaultError {
            throw error
        } catch {
            throw PasswordVaultError.keychainUnavailable
        }
    }

    private func normalizedDraft(_ draft: PasswordVaultDraft) throws -> PasswordVaultDraft {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw PasswordVaultError.invalidTitle }
        guard !draft.password.isEmpty else { throw PasswordVaultError.invalidPassword }
        return PasswordVaultDraft(
            folderID: draft.folderID,
            title: title,
            website: draft.website.trimmingCharacters(in: .whitespacesAndNewlines),
            username: draft.username.trimmingCharacters(in: .whitespacesAndNewlines),
            note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines),
            password: draft.password
        )
    }

    private func normalizedFolderName(_ name: String) throws -> String {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw PasswordVaultError.invalidTitle }
        return normalized
    }

    private func makeUnfiledFolder() -> PasswordVaultFolder {
        let timestamp = now()
        return PasswordVaultFolder(id: UUID(), name: "Unfiled", createdAt: timestamp, updatedAt: timestamp)
    }
}

private struct LegacyPasswordVaultEntry: Codable {
    let id: UUID
    let title: String
    let website: String
    let username: String
    let note: String
    let createdAt: Date
    let updatedAt: Date
}

final class SystemPasswordVaultKeychainClient: PasswordVaultKeychainClient {
    private static let metadataAccount = "index"

    func readMetadata() throws -> Data? {
        var query = metadataBaseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw mapStatus(status)
        }
        return data
    }

    func writeMetadata(_ data: Data) throws {
        let query = metadataBaseQuery()
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw mapStatus(updateStatus) }
        var addQuery = query
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw mapStatus(addStatus) }
    }

    func readSecret(id: UUID, reason: String) throws -> Data {
        var query = secretBaseQuery(id: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseOperationPrompt as String] = reason
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw mapStatus(status)
        }
        return data
    }

    func writeSecret(id: UUID, data: Data) throws {
        let query = secretBaseQuery(id: id)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw mapStatus(updateStatus) }
        let addStatus = SecItemAdd(try KeychainPasswordVaultStore.secretAddQuery(id: id, secret: data) as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw mapStatus(addStatus) }
    }

    func deleteSecret(id: UUID, reason: String?) throws {
        let status = SecItemDelete(secretBaseQuery(id: id) as CFDictionary)
        guard status == errSecSuccess else { throw mapStatus(status) }
    }

    private func metadataBaseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainPasswordVaultStore.metadataService,
            kSecAttrAccount as String: Self.metadataAccount,
            kSecAttrSynchronizable as String: false
        ]
    }

    private func secretBaseQuery(id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainPasswordVaultStore.secretService,
            kSecAttrAccount as String: id.uuidString,
            kSecAttrSynchronizable as String: false
        ]
    }

    private func mapStatus(_ status: OSStatus) -> PasswordVaultError {
        switch status {
        case errSecItemNotFound:
            return .entryNotFound
        case errSecUserCanceled:
            return .userCancelled
        case errSecAuthFailed, errSecInteractionNotAllowed:
            return .authenticationFailed
        case errSecDuplicateItem:
            return .duplicateEntry
        default:
            return .keychainUnavailable
        }
    }
}
