import Foundation
import LocalAuthentication
import Security
import Testing
@testable import Pastera

@Suite("Password vault store")
struct PasswordVaultStoreTests {
    @Test("KDBX vault lives under the configured Pastera sync root")
    func kdbxVaultUsesDedicatedSyncLocation() {
        let root = URL(fileURLWithPath: "/tmp/OneDrive", isDirectory: true)

        #expect(VaultFileCoordinator.vaultURL(for: root).path == "/tmp/OneDrive/PasteraSync/vault/PasteraVault.kdbx")
    }

    @Test("password vault lifecycle exposes locked and recovery states")
    func passwordVaultLifecycleStatesAreStable() {
        let states: [PasswordVaultState] = [
            .notConfigured,
            .locked,
            .unlocking,
            .unlocked,
            .readOnlyWarning("conflict"),
            .failed("corrupted")
        ]

        #expect(states.count == 6)
        #expect(states[3] == .unlocked)
    }

    @Test("KDBX vault creates, locks, unlocks, and persists credentials")
    func kdbxVaultLifecycleRoundTrips() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = KDBXPasswordVaultStore(syncRootProvider: { root })

        try store.createDatabase(masterPassword: "correct horse battery staple", rememberQuickUnlock: false)
        let folder = try store.createFolder(name: "Work")
        let entry = try store.create(PasswordVaultDraft(
            folderID: folder.id,
            title: "Mail",
            website: "https://mail.example.com",
            username: "alice",
            note: "Primary",
            password: "secret-value"
        ))
        #expect(try store.revealPassword(id: entry.id, reason: "test") == "secret-value")

        store.lock()
        #expect(store.state == .locked)
        #expect(throws: PasswordVaultError.vaultLocked) { try store.listEntries() }

        try store.unlock(masterPassword: "correct horse battery staple", rememberQuickUnlock: false)
        #expect(try store.listEntries().map(\.title) == ["Mail"])
        #expect(try store.revealPassword(id: entry.id, reason: "test") == "secret-value")
    }

    @Test("quick unlock stores only the 32 byte KDBX pre-hash")
    func quickUnlockStoresPreHash() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let keys = InMemoryVaultUnlockKeyStore()
        let store = KDBXPasswordVaultStore(syncRootProvider: { root }, unlockKeyStore: keys)

        try store.createDatabase(masterPassword: "correct horse battery staple", rememberQuickUnlock: true)
        #expect(keys.data?.count == 32)
        #expect(keys.data != Data("correct horse battery staple".utf8))

        store.lock()
        try store.unlockWithQuickKey(reason: "test")
        #expect(store.state == .unlocked)
    }

    @Test("automation key restores a locked KDBX without reading the interactive key")
    func automationKeyRestoresLockedStore() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let interactive = InMemoryVaultUnlockKeyStore()
        let automation = InMemoryVaultAutomationUnlockKeyStore()
        let store = KDBXPasswordVaultStore(
            syncRootProvider: { root },
            unlockKeyStore: interactive,
            automationUnlockKeyStore: automation
        )

        try store.createDatabase(masterPassword: "master", rememberQuickUnlock: true)
        try store.enableAutomationUnlock()
        store.lock()
        try store.unlockForAutomation()

        #expect(store.state == .unlocked)
        #expect(interactive.loadCallCount == 0)
        #expect(automation.loadCallCount == 1)
    }

    @Test("malformed automation key fails safely while the vault stays locked")
    func malformedAutomationKeyFailsSafely() throws {
        let fixture = try makeAutomationVault()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.automation.data = Data(repeating: 0x11, count: 31)
        fixture.store.lock()

        #expect(throws: PasswordVaultError.keychainUnavailable) {
            try fixture.store.unlockForAutomation()
        }
        #expect(fixture.store.state == .locked)
    }

    @Test("automation key is validated before reading a missing database")
    func automationKeyIsValidatedFirst() throws {
        let fixture = try makeAutomationVault()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.automation.data = Data(repeating: 0x11, count: 31)
        try FileManager.default.removeItem(at: VaultFileCoordinator.vaultURL(for: fixture.root))
        fixture.store.lock()

        #expect(throws: PasswordVaultError.keychainUnavailable) {
            try fixture.store.unlockForAutomation()
        }
        #expect(fixture.store.state == .locked)
    }

    @Test("a missing automation key fails safely while the vault stays locked")
    func missingAutomationKeyFailsSafely() throws {
        let fixture = try makeAutomationVault()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.automation.data = nil
        fixture.store.lock()

        #expect(throws: PasswordVaultError.keychainUnavailable) {
            try fixture.store.unlockForAutomation()
        }
        #expect(fixture.store.state == .locked)
        #expect(!fixture.store.canAutomationUnlock)
    }

    @Test("wrong automation credential maps to unavailable and stays locked")
    func wrongAutomationCredentialFailsSafely() throws {
        let fixture = try makeAutomationVault()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.automation.data = Data(repeating: 0x7F, count: 32)
        fixture.store.lock()

        #expect(throws: PasswordVaultError.keychainUnavailable) {
            try fixture.store.unlockForAutomation()
        }
        #expect(fixture.store.state == .locked)
    }

    @Test("disabling automation unlock preserves interactive quick unlock and current state")
    func disablingAutomationUnlockIsIsolated() throws {
        let fixture = try makeAutomationVault(rememberQuickUnlock: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        try fixture.store.disableAutomationUnlock()

        #expect(fixture.store.state == .unlocked)
        #expect(fixture.interactive.containsKey)
        #expect(!fixture.automation.containsKey)
        #expect(fixture.automation.deleteCallCount == 1)
    }

    @Test("automation unlock preserves not-configured and corrupted database errors")
    func automationUnlockPreservesDatabaseErrors() throws {
        let emptyRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: emptyRoot) }
        try FileManager.default.createDirectory(at: emptyRoot, withIntermediateDirectories: true)
        let absent = KDBXPasswordVaultStore(
            syncRootProvider: { emptyRoot },
            automationUnlockKeyStore: InMemoryVaultAutomationUnlockKeyStore(data: Data(repeating: 1, count: 32))
        )
        #expect(throws: PasswordVaultError.databaseNotConfigured) {
            try absent.unlockForAutomation()
        }
        #expect(absent.state == .notConfigured)

        let fixture = try makeAutomationVault()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try Data("not-a-kdbx".utf8).write(to: VaultFileCoordinator.vaultURL(for: fixture.root), options: .atomic)
        fixture.store.lock()
        #expect(throws: PasswordVaultError.corruptedData) {
            try fixture.store.unlockForAutomation()
        }
        #expect(fixture.store.state == .failed("corrupted"))
    }

    @Test("quick-unlock availability lookup cannot present authentication UI")
    func quickUnlockAvailabilityQuerySuppressesAuthenticationUI() {
        let query = VaultUnlockKeyStore.availabilityQuery

        let context = query[kSecUseAuthenticationContext as String] as? LAContext
        #expect(context?.interactionNotAllowed == true)
        #expect(query[kSecReturnData as String] == nil)
    }

    @Test("a local quick-unlock Keychain failure does not block the KDBX database")
    func quickUnlockFailureDoesNotBlockDatabase() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = KDBXPasswordVaultStore(
            syncRootProvider: { root },
            unlockKeyStore: FailingVaultUnlockKeyStore()
        )

        try store.createDatabase(masterPassword: "correct horse battery staple", rememberQuickUnlock: true)

        #expect(store.state == .unlocked)
        #expect(FileManager.default.fileExists(atPath: VaultFileCoordinator.vaultURL(for: root).path))
        #expect(try store.listEntries().isEmpty)
    }

    @Test("concurrent KDBX writers merge entries instead of overwriting")
    func concurrentVaultWritersMerge() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let first = KDBXPasswordVaultStore(syncRootProvider: { root })
        let second = KDBXPasswordVaultStore(syncRootProvider: { root })
        try first.createDatabase(masterPassword: "shared password", rememberQuickUnlock: false)
        try second.unlock(masterPassword: "shared password", rememberQuickUnlock: false)

        let firstFolder = try first.createFolder(name: "First")
        _ = try first.create(.init(
            folderID: firstFolder.id, title: "First Entry", website: "", username: "", note: "", password: "one"
        ))
        let secondFolder = try second.createFolder(name: "Second")
        _ = try second.create(.init(
            folderID: secondFolder.id, title: "Second Entry", website: "", username: "", note: "", password: "two"
        ))

        try first.reloadAndMerge()
        let titles = Set(try first.listEntries().map(\.title))
        #expect(titles == ["First Entry", "Second Entry"], "Merged titles: \(titles)")
    }

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

    @Test("manual folder and entry order persists in Keychain metadata")
    func keychainStorePersistsManualOrder() throws {
        let store = KeychainPasswordVaultStore(client: InMemoryPasswordVaultKeychainClient())
        try assertManualOrderPersists(in: store)
    }

    @Test("manual folder and entry order persists in KDBX")
    func kdbxStorePersistsManualOrder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = KDBXPasswordVaultStore(syncRootProvider: { root })
        try store.createDatabase(masterPassword: "shared password", rememberQuickUnlock: false)

        try assertManualOrderPersists(in: store)
    }

    private func assertManualOrderPersists(in store: PasswordVaultStore) throws {
        let work = try store.createFolder(name: "Work")
        let archive = try store.createFolder(name: "Archive")
        let first = try store.create(.init(
            folderID: work.id, title: "First", website: "", username: "a", note: "", password: "1"
        ))
        let second = try store.create(.init(
            folderID: work.id, title: "Second", website: "", username: "b", note: "", password: "2"
        ))
        let archived = try store.create(.init(
            folderID: archive.id, title: "Archived", website: "", username: "c", note: "", password: "3"
        ))

        try store.reorderFolders([archive.id, work.id])
        #expect(try store.listFolders().map(\.id) == [archive.id, work.id])

        try store.moveEntry(
            id: second.id,
            to: archive.id,
            orderedEntryIDsByFolder: [
                work.id: [first.id],
                archive.id: [second.id, archived.id]
            ]
        )
        #expect(try store.listEntries().filter { $0.folderID == work.id }.map(\.id) == [first.id])
        #expect(try store.listEntries().filter { $0.folderID == archive.id }.map(\.id) == [second.id, archived.id])
    }

    private func makeAutomationVault(
        rememberQuickUnlock: Bool = false
    ) throws -> AutomationVaultFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let interactive = InMemoryVaultUnlockKeyStore()
        let automation = InMemoryVaultAutomationUnlockKeyStore()
        let store = KDBXPasswordVaultStore(
            syncRootProvider: { root },
            unlockKeyStore: interactive,
            automationUnlockKeyStore: automation
        )
        try store.createDatabase(masterPassword: "master", rememberQuickUnlock: rememberQuickUnlock)
        try store.enableAutomationUnlock()
        return AutomationVaultFixture(
            root: root,
            store: store,
            interactive: interactive,
            automation: automation
        )
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

private struct AutomationVaultFixture {
    let root: URL
    let store: KDBXPasswordVaultStore
    let interactive: InMemoryVaultUnlockKeyStore
    let automation: InMemoryVaultAutomationUnlockKeyStore
}

private final class InMemoryVaultUnlockKeyStore: VaultUnlockKeyStoring {
    var data: Data?
    private(set) var loadCallCount = 0
    var containsKey: Bool { data != nil }

    func save(_ data: Data) throws { self.data = data }
    func load(reason: String) throws -> Data {
        loadCallCount += 1
        return try #require(data)
    }
    func delete() throws { data = nil }
}

private final class InMemoryVaultAutomationUnlockKeyStore: VaultAutomationUnlockKeyStoring {
    var data: Data?
    private(set) var loadCallCount = 0
    private(set) var deleteCallCount = 0
    var containsKey: Bool { data != nil }

    init(data: Data? = nil) {
        self.data = data
    }

    func save(_ data: Data) throws { self.data = data }
    func load() throws -> Data {
        loadCallCount += 1
        guard let data else { throw PasswordVaultError.keychainUnavailable }
        return data
    }
    func delete() throws {
        deleteCallCount += 1
        data = nil
    }
}

private final class FailingVaultUnlockKeyStore: VaultUnlockKeyStoring {
    var containsKey: Bool { false }

    func save(_ data: Data) throws { throw PasswordVaultError.keychainUnavailable }
    func load(reason: String) throws -> Data { throw PasswordVaultError.keychainUnavailable }
    func delete() throws {}
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
