import Foundation
import Security

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
}

protocol PasswordVaultStore {
    func listFolders() throws -> [PasswordVaultFolder]
    func listEntries() throws -> [PasswordVaultEntry]
    func createFolder(name: String) throws -> PasswordVaultFolder
    func renameFolder(id: UUID, name: String) throws -> PasswordVaultFolder
    func deleteFolder(id: UUID) throws
    func moveEntry(id: UUID, to folderID: UUID) throws
    func create(_ draft: PasswordVaultDraft) throws -> PasswordVaultEntry
    func update(id: UUID, draft: PasswordVaultDraft) throws -> PasswordVaultEntry
    func revealPassword(id: UUID, reason: String) throws -> String
    func delete(id: UUID, reason: String) throws
}

protocol PasswordVaultKeychainClient {
    func readMetadata() throws -> Data?
    func writeMetadata(_ data: Data) throws
    func readSecret(id: UUID, reason: String) throws -> Data
    func writeSecret(id: UUID, data: Data) throws
    func deleteSecret(id: UUID, reason: String?) throws
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
        try loadMetadata().entries.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    func listFolders() throws -> [PasswordVaultFolder] {
        try loadMetadata().folders.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
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

    func moveEntry(id: UUID, to folderID: UUID) throws {
        var metadata = try loadMetadata()
        guard metadata.folders.contains(where: { $0.id == folderID }) else {
            throw PasswordVaultError.folderNotFound
        }
        guard let index = metadata.entries.firstIndex(where: { $0.id == id }) else {
            throw PasswordVaultError.entryNotFound
        }
        metadata.entries[index].folderID = folderID
        metadata.entries[index].updatedAt = now()
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
