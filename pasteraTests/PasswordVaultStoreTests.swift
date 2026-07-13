import Foundation
import Security
import Testing
@testable import Pastera

@Suite("Password vault store")
struct PasswordVaultStoreTests {
    @Test("legacy entries migrate into the unfiled folder")
    func legacyEntriesMigrateIntoUnfiledFolder() throws {
        let client = InMemoryPasswordVaultKeychainClient()
        let legacyID = UUID()
        client.metadata = try JSONEncoder().encode([
            LegacyPasswordVaultEntryFixture(
                id: legacyID,
                title: "Mail",
                website: "mail.example.com",
                username: "alice",
                note: "",
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 20)
            )
        ])
        let store = KeychainPasswordVaultStore(client: client)

        let folders = try store.listFolders()
        let entries = try store.listEntries()

        #expect(folders.count == 1)
        #expect(folders[0].name == "Unfiled")
        #expect(entries.count == 1)
        #expect(entries[0].id == legacyID)
        #expect(entries[0].folderID == folders[0].id)
        let savedMetadata = try #require(client.metadata)
        #expect(try JSONDecoder().decode(PasswordVaultMetadata.self, from: savedMetadata).version == 2)
    }

    @Test("folders are single-level and non-empty folders cannot be deleted")
    func folderLifecycleProtectsContainedPasswords() throws {
        let client = InMemoryPasswordVaultKeychainClient()
        let store = KeychainPasswordVaultStore(client: client)
        let folder = try store.createFolder(name: "Work")
        _ = try store.create(PasswordVaultDraft(
            folderID: folder.id,
            title: "Mail",
            website: "",
            username: "alice",
            note: "",
            password: "secret-value"
        ))

        #expect(throws: PasswordVaultError.folderNotEmpty) {
            try store.deleteFolder(id: folder.id)
        }
        let archive = try store.createFolder(name: "Archive")
        let entry = try #require(store.listEntries().first)
        try store.moveEntry(id: entry.id, to: archive.id)
        try store.deleteFolder(id: folder.id)

        #expect(try store.listFolders().map(\.name) == ["Archive"])
    }

    @Test("metadata search excludes secrets")
    func metadataSearchExcludesSecrets() throws {
        let entry = PasswordVaultEntry(
            id: UUID(),
            folderID: UUID(),
            title: "Production",
            website: "https://example.com",
            username: "alice",
            note: "Primary account",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        #expect(entry.matches("example"))
        #expect(entry.matches("ALICE"))
        #expect(!entry.matches("secret-value"))
    }

    @Test("secret query is local-only and requires user presence")
    func secretQueryUsesProtectedLocalKeychainItem() throws {
        let id = UUID()
        let query = try KeychainPasswordVaultStore.secretAddQuery(
            id: id,
            secret: Data("secret-value".utf8)
        )

        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String == KeychainPasswordVaultStore.secretService)
        #expect(query[kSecAttrAccount as String] as? String == id.uuidString)
        #expect(query[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(query[kSecValueData as String] as? Data == Data("secret-value".utf8))
        #expect(query[kSecAttrAccessControl as String] != nil)
    }

    @Test("metadata round-trips without a database")
    func metadataRoundTripsThroughKeychainClient() throws {
        let client = InMemoryPasswordVaultKeychainClient()
        let store = KeychainPasswordVaultStore(client: client, now: { Date(timeIntervalSince1970: 100) })
        let draft = PasswordVaultDraft(
            folderID: nil,
            title: "Mail",
            website: "https://mail.example.com",
            username: "alice",
            note: "Work",
            password: "secret-value"
        )

        let created = try store.create(draft)
        let listed = try store.listEntries()

        #expect(listed == [created])
        #expect(client.secret(for: created.id) == "secret-value")
    }

    @Test("failed secret creation does not leave metadata")
    func failedSecretCreationRollsBackMetadata() throws {
        let client = InMemoryPasswordVaultKeychainClient()
        client.nextSecretWriteError = PasswordVaultError.keychainUnavailable
        let store = KeychainPasswordVaultStore(client: client)

        #expect(throws: PasswordVaultError.keychainUnavailable) {
            try store.create(PasswordVaultDraft(
                folderID: nil,
                title: "Mail",
                website: "",
                username: "alice",
                note: "",
                password: "secret-value"
            ))
        }
        #expect(try store.listEntries().isEmpty)
    }
}

private struct LegacyPasswordVaultEntryFixture: Codable {
    let id: UUID
    let title: String
    let website: String
    let username: String
    let note: String
    let createdAt: Date
    let updatedAt: Date
}

private final class InMemoryPasswordVaultKeychainClient: PasswordVaultKeychainClient {
    var metadata: Data?
    private var secrets = [UUID: Data]()
    var nextSecretWriteError: Error?

    func readMetadata() throws -> Data? { metadata }
    func writeMetadata(_ data: Data) throws { metadata = data }

    func readSecret(id: UUID, reason: String) throws -> Data {
        guard let data = secrets[id] else { throw PasswordVaultError.entryNotFound }
        return data
    }

    func writeSecret(id: UUID, data: Data) throws {
        if let nextSecretWriteError {
            self.nextSecretWriteError = nil
            throw nextSecretWriteError
        }
        secrets[id] = data
    }

    func deleteSecret(id: UUID, reason: String?) throws {
        secrets[id] = nil
    }

    func secret(for id: UUID) -> String? {
        secrets[id].flatMap { String(data: $0, encoding: .utf8) }
    }
}
