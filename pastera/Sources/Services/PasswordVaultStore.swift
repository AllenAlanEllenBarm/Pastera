import CryptoKit
import AppKit
import Foundation
import KDBXKit
import LocalAuthentication
import Security

enum PasswordVaultState: Equatable {
    case notConfigured
    case locked
    case unlocking
    case unlocked
    case readOnlyWarning(String)
    case failed(String)
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

final class VaultSessionController {
    static let allowedTimeouts: [TimeInterval] = [60, 300, 900, 1_800]

    private let timeoutProvider: () -> TimeInterval
    private let lockAction: () -> Void
    private var lockWorkItem: DispatchWorkItem?
    private var observers = [NSObjectProtocol]()

    init(
        timeoutProvider: @escaping () -> TimeInterval = {
            let value = UserDefaults.standard.double(forKey: Constants.UserDefaults.passwordVaultAutoLockInterval)
            return VaultSessionController.allowedTimeouts.contains(value) ? value : 300
        },
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        lockAction: @escaping () -> Void
    ) {
        self.timeoutProvider = timeoutProvider
        self.lockAction = lockAction
        observers = [
            notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                self?.lockNow()
            },
            notificationCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.lockNow()
            },
            NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
                self?.lockNow()
            }
        ]
    }

    deinit {
        lockWorkItem?.cancel()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }

    func touch() {
        lockWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.lockNow() }
        lockWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutProvider(), execute: item)
    }

    func cancel() {
        lockWorkItem?.cancel()
        lockWorkItem = nil
    }

    func lockNow() {
        cancel()
        lockAction()
    }
}

final class VaultFileCoordinator {
    static func vaultURL(for syncRootURL: URL) -> URL {
        syncRootURL
            .appendingPathComponent("PasteraSync", isDirectory: true)
            .appendingPathComponent("vault", isDirectory: true)
            .appendingPathComponent("PasteraVault.kdbx", isDirectory: false)
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func read(from url: URL) throws -> Data {
        guard fileManager.fileExists(atPath: url.path) else { throw PasswordVaultError.databaseNotConfigured }
        return try Data(contentsOf: url)
    }

    func revision(of data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    func write(_ data: Data, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: url.path) {
            let backupURL = url.appendingPathExtension("bak")
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.copyItem(at: url, to: backupURL)
        }
        try data.write(to: url, options: .atomic)
    }

    func conflictFiles(alongside url: URL) throws -> [URL] {
        let directory = url.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter {
            $0 != url && $0.pathExtension.lowercased() == "kdbx"
        }
    }

    func archiveResolvedConflict(_ conflictURL: URL, alongside vaultURL: URL) throws {
        let resolved = vaultURL.deletingLastPathComponent()
            .appendingPathComponent("conflicts", isDirectory: true)
            .appendingPathComponent("resolved", isDirectory: true)
        try fileManager.createDirectory(at: resolved, withIntermediateDirectories: true)
        var destination = resolved.appendingPathComponent(conflictURL.lastPathComponent)
        if fileManager.fileExists(atPath: destination.path) {
            destination = resolved.appendingPathComponent("\(UUID().uuidString)-\(conflictURL.lastPathComponent)")
        }
        try fileManager.moveItem(at: conflictURL, to: destination)
    }
}

struct KDBXVaultMergeResult {
    let content: KDBXContent
    let hasConflictCopies: Bool
}

final class KDBXVaultMerger {
    func merge(local: KDBXContent, remote: KDBXContent) -> KDBXVaultMergeResult {
        var output = remote
        var hasConflicts = false
        output.database.root.group = mergeGroup(
            local.database.root.group,
            remote.database.root.group,
            hasConflicts: &hasConflicts
        )
        let tombstones = (local.database.root.deletedObjects + remote.database.root.deletedObjects).reduce(into: [UUID: KDBX.DeletedObject]()) {
            if ($0[$1.uuid]?.deletionTime ?? .distantPast) < $1.deletionTime { $0[$1.uuid] = $1 }
        }
        output.database.root.deletedObjects = Array(tombstones.values)
        removeDeleted(from: &output.database.root.group, tombstones: tombstones)
        return KDBXVaultMergeResult(content: output, hasConflictCopies: hasConflicts)
    }

    private func mergeGroup(
        _ local: KDBX.Group,
        _ remote: KDBX.Group,
        hasConflicts: inout Bool
    ) -> KDBX.Group {
        var output = newer(local, remote)
        output.entries = mergeEntries(local.entries, remote.entries, hasConflicts: &hasConflicts)
        var groups = Dictionary(uniqueKeysWithValues: remote.groups.map { ($0.uuid, $0) })
        for group in local.groups {
            if let remoteGroup = groups[group.uuid] {
                groups[group.uuid] = mergeGroup(group, remoteGroup, hasConflicts: &hasConflicts)
            } else {
                groups[group.uuid] = group
            }
        }
        output.groups = Array(groups.values)
        return output
    }

    private func mergeEntries(
        _ local: [KDBX.Entry],
        _ remote: [KDBX.Entry],
        hasConflicts: inout Bool
    ) -> [KDBX.Entry] {
        var entries = Dictionary(uniqueKeysWithValues: remote.map { ($0.uuid, $0) })
        for entry in local {
            guard let remoteEntry = entries[entry.uuid] else {
                entries[entry.uuid] = entry
                continue
            }
            guard !sameEntryContent(entry, remoteEntry) else { continue }
            let localTime = entry.times?.lastModificationTime ?? .distantPast
            let remoteTime = remoteEntry.times?.lastModificationTime ?? .distantPast
            if localTime == remoteTime {
                var conflict = entry
                conflict.uuid = UUID()
                setTitle(on: &conflict, title: "\(title(of: entry)) (Conflict)")
                entries[conflict.uuid] = conflict
                hasConflicts = true
            } else {
                var winner = localTime > remoteTime ? entry : remoteEntry
                var loser = localTime > remoteTime ? remoteEntry : entry
                loser.history = []
                winner.history = Array((winner.history + [loser]).suffix(10))
                entries[entry.uuid] = winner
            }
        }
        return Array(entries.values)
    }

    private func sameEntryContent(_ lhs: KDBX.Entry, _ rhs: KDBX.Entry) -> Bool {
        lhs.iconID == rhs.iconID &&
            lhs.customIconUUID == rhs.customIconUUID &&
            lhs.foregroundColor == rhs.foregroundColor &&
            lhs.backgroundColor == rhs.backgroundColor &&
            lhs.overrideURL == rhs.overrideURL &&
            lhs.qualityCheck == rhs.qualityCheck &&
            lhs.tags == rhs.tags &&
            lhs.previousParentGroup == rhs.previousParentGroup &&
            lhs.strings == rhs.strings &&
            lhs.binaries == rhs.binaries &&
            lhs.autoType == rhs.autoType &&
            lhs.customData == rhs.customData
    }

    private func newer(_ local: KDBX.Group, _ remote: KDBX.Group) -> KDBX.Group {
        (local.times?.lastModificationTime ?? .distantPast) > (remote.times?.lastModificationTime ?? .distantPast)
            ? local : remote
    }

    private func removeDeleted(
        from group: inout KDBX.Group,
        tombstones: [UUID: KDBX.DeletedObject]
    ) {
        group.entries.removeAll { entry in
            guard let deletion = tombstones[entry.uuid] else { return false }
            return deletion.deletionTime > (entry.times?.lastModificationTime ?? .distantPast)
        }
        group.groups.removeAll { child in
            guard let deletion = tombstones[child.uuid] else { return false }
            return deletion.deletionTime > (child.times?.lastModificationTime ?? .distantPast)
        }
        for index in group.groups.indices {
            removeDeleted(from: &group.groups[index], tombstones: tombstones)
        }
    }

    private func title(of entry: KDBX.Entry) -> String {
        entry.strings.first(where: { $0.key == "Title" })?.value.revealedString ?? "Password"
    }

    private func setTitle(on entry: inout KDBX.Entry, title: String) {
        if let index = entry.strings.firstIndex(where: { $0.key == "Title" }) {
            entry.strings[index].value = .regular(title)
        } else {
            entry.strings.append(.init(key: "Title", value: .regular(title)))
        }
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
    case unsupportedFormat
    case cloudUnavailable
    case externalConflict
    case saveFailed
}

protocol PasswordVaultStore {
    var state: PasswordVaultState { get }
    var canQuickUnlock: Bool { get }
    var canAutomationUnlock: Bool { get }

    func createDatabase(masterPassword: String, rememberQuickUnlock: Bool) throws
    func unlock(masterPassword: String, rememberQuickUnlock: Bool) throws
    func unlockWithQuickKey(reason: String) throws
    func enableAutomationUnlock() throws
    func unlockForAutomation() throws
    func disableAutomationUnlock() throws
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
    func createDatabase(masterPassword: String, rememberQuickUnlock: Bool) throws { throw PasswordVaultError.unsupportedFormat }
    func unlock(masterPassword: String, rememberQuickUnlock: Bool) throws { throw PasswordVaultError.unsupportedFormat }
    func unlockWithQuickKey(reason: String) throws { throw PasswordVaultError.keychainUnavailable }
    func enableAutomationUnlock() throws { throw PasswordVaultError.keychainUnavailable }
    func unlockForAutomation() throws { throw PasswordVaultError.keychainUnavailable }
    func disableAutomationUnlock() throws {}
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
    func delete() throws
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

    func load(reason: String) throws -> Data {
        let context = LAContext()
        context.localizedReason = reason
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecAttrSynchronizable as String: false,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]
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
