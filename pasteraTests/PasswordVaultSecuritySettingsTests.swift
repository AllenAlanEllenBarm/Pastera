import Foundation
import Testing
@testable import Pastera

@Suite("Password vault security settings")
struct PasswordVaultSecuritySettingsTests {
    @Test("quick unlock defaults on and disabling survives a later password unlock")
    func quickUnlockIntentControlsFutureUnlocks() async throws {
        let fixture = try SecuritySettingsFixture()
        defer { fixture.remove() }

        #expect(fixture.persistedValue(forKey: Constants.UserDefaults.passwordVaultQuickUnlockEnabled) == nil)
        #expect(await fixture.createDatabase().isSuccess)
        #expect(fixture.quickKey.data?.count == 32)

        #expect(await fixture.setQuickUnlock(false).isSuccess)
        #expect(fixture.defaults.bool(forKey: Constants.UserDefaults.passwordVaultQuickUnlockEnabled) == false)
        #expect(fixture.quickKey.data == nil)

        fixture.store.lock()
        #expect(await fixture.unlock().isSuccess)
        #expect(fixture.quickKey.data == nil)
    }

    @Test("local commits are recorded and a successful unlock retries synchronization")
    func localCommitAndUnlockDriveSyncLifecycle() async throws {
        let fixture = try SecuritySettingsFixture()
        defer { fixture.remove() }

        #expect(await fixture.createDatabase().isSuccess)
        #expect(fixture.syncController.commits.map(\.origin) == [.userMutation])

        fixture.syncController.reasons.removeAll()
        fixture.store.lock()
        #expect(await fixture.unlock().isSuccess)
        #expect(fixture.syncController.reasons == [.localChange])
    }

    @Test("quick unlock can only be enabled while the vault is readable")
    func quickUnlockEnableRequiresReadableVault() async throws {
        let fixture = try SecuritySettingsFixture()
        defer { fixture.remove() }
        #expect(await fixture.createDatabase().isSuccess)
        #expect(await fixture.setQuickUnlock(false).isSuccess)
        fixture.store.lock()

        #expect(await fixture.setQuickUnlock(true).failure == .vaultLocked)
        #expect(fixture.defaults.bool(forKey: Constants.UserDefaults.passwordVaultQuickUnlockEnabled) == false)

        #expect(await fixture.unlock().isSuccess)
        #expect(await fixture.setQuickUnlock(true).isSuccess)
        #expect(fixture.quickKey.data?.count == 32)
        #expect(fixture.defaults.bool(forKey: Constants.UserDefaults.passwordVaultQuickUnlockEnabled))
    }

    @Test("automatic lock accepts only supported values and refreshes the readable session")
    func automaticLockValidationAndRefresh() async throws {
        let fixture = ControllerSpyFixture()
        defer { fixture.remove() }

        #expect(await fixture.setAutoLock(120).failure == .invalidAutoLockInterval)
        #expect(fixture.store.refreshAutoLockCallCount == 0)
        #expect(fixture.persistedValue(forKey: Constants.UserDefaults.passwordVaultAutoLockInterval) == nil)

        #expect(await fixture.setAutoLock(900).isSuccess)
        #expect(fixture.defaults.double(forKey: Constants.UserDefaults.passwordVaultAutoLockInterval) == 900)
        #expect(fixture.store.refreshAutoLockCallCount == 1)
    }

    @Test("legacy onChange and removable observers receive the same state notifications")
    func stateObserversCoexist() async throws {
        let fixture = ControllerSpyFixture()
        defer { fixture.remove() }
        let counts = LockedNotificationCounts()
        fixture.controller.onChange = { counts.incrementLegacy() }
        let token = fixture.controller.addStateChangeObserver { counts.incrementObserver() }

        #expect(await fixture.setAutoLock(300).isSuccess)
        let first = counts.snapshot
        #expect(first.legacy >= 2)
        #expect(first.observer >= 2)

        fixture.controller.removeStateChangeObserver(token)
        #expect(await fixture.setAutoLock(900).isSuccess)
        let second = counts.snapshot
        #expect(second.legacy > first.legacy)
        #expect(second.observer == first.observer)
    }

    @Test("master password change shares the agent executor and disables failed quick unlock intent")
    func passwordChangeSerializesWithAgentWork() async throws {
        let fixture = ControllerSpyFixture()
        defer { fixture.remove() }
        fixture.defaults.set(true, forKey: Constants.UserDefaults.passwordVaultQuickUnlockEnabled)
        fixture.store.changeResult = .init(warnings: [.quickUnlockDisabled])
        fixture.store.blockMetadataRead = true

        let agentTask = Task {
            await result { fixture.controller.agentMetadata(completion: $0) }
        }
        #expect(await wait(for: fixture.store.metadataStarted) == .success)

        let changeTask = Task {
            await result {
                fixture.controller.changeMasterPassword(
                    currentPassword: "current fixture value",
                    newPassword: "new fixture value",
                    completion: $0
                )
            }
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(fixture.store.passwordChangeCallCount == 0)

        fixture.store.metadataRelease.signal()
        #expect(await agentTask.value.isSuccess)
        #expect(await changeTask.value.isSuccess)
        #expect(fixture.store.passwordChangeCallCount == 1)
        #expect(!fixture.defaults.bool(forKey: Constants.UserDefaults.passwordVaultQuickUnlockEnabled))
    }

    @Test("security settings snapshot uses the injected defaults and store state")
    func securitySettingsSnapshotIsConsistent() async {
        let fixture = ControllerSpyFixture()
        defer { fixture.remove() }
        fixture.defaults.set(1_800, forKey: Constants.UserDefaults.passwordVaultAutoLockInterval)
        fixture.defaults.set(false, forKey: Constants.UserDefaults.passwordVaultQuickUnlockEnabled)
        fixture.store.quickUnlockAvailable = true

        let state = await withCheckedContinuation { continuation in
            fixture.controller.loadSecuritySettings { continuation.resume(returning: $0) }
        }

        #expect(state.vaultState == .unlocked)
        #expect(state.autoLockInterval == 1_800)
        #expect(!state.quickUnlockEnabled)
        #expect(state.quickUnlockAvailable)
        #expect(!state.isBusy)
    }
}

private final class SecuritySettingsFixture {
    let root: URL
    let defaults: UserDefaults
    let quickKey = SecuritySettingsQuickKeyStore()
    let store: KDBXPasswordVaultStore
    let syncController = SecuritySettingsSyncController()
    let controller: PasswordVaultUIController
    private let suiteName: String
    private let password = "security settings fixture password"

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "PasswordVaultSecuritySettingsTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        store = KDBXPasswordVaultStore(
            localStorage: makeSecuritySettingsLocalStorage(at: root),
            unlockKeyStore: quickKey,
            automationUnlockKeyStore: SecuritySettingsAutomationKeyStore()
        )
        controller = PasswordVaultUIController(
            store: store,
            syncController: syncController,
            defaults: defaults
        )
    }

    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }

    func persistedValue(forKey key: String) -> Any? {
        defaults.persistentDomain(forName: suiteName)?[key]
    }

    func createDatabase() async -> Result<Void, PasswordVaultError> {
        await result { controller.createDatabase(masterPassword: password, completion: $0) }
    }

    func unlock() async -> Result<Void, PasswordVaultError> {
        await result { controller.unlock(masterPassword: password, completion: $0) }
    }

    func setQuickUnlock(_ enabled: Bool) async -> Result<Void, PasswordVaultError> {
        await result { controller.setQuickUnlockEnabled(enabled, completion: $0) }
    }
}

private final class SecuritySettingsSyncController: PasswordVaultSyncControlling {
    var snapshot = PasswordVaultSyncSnapshot(
        mode: .localOnly,
        phase: .disabled,
        localVaultAvailable: true,
        remoteVaultAvailable: nil,
        pendingChangeCount: 0,
        conflictCopyCount: 0,
        lastSyncAt: nil
    )
    var commits = [PasswordVaultCommit]()
    var reasons = [SyncCoordinator.Reason]()

    func addObserver(_ observer: @escaping (PasswordVaultSyncSnapshot) -> Void) -> UUID {
        let identifier = UUID()
        observer(snapshot)
        return identifier
    }

    func removeObserver(_ identifier: UUID) {}
    func record(_ commit: PasswordVaultCommit) { commits.append(commit) }
    func synchronize(reason: SyncCoordinator.Reason) { reasons.append(reason) }
    func enableOneDrive(
        rootURL: URL,
        remoteMasterPassword: String?, // swiftlint:disable:this inclusive_language
        completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) { completion(.success(())) }
    func switchToLocalOnly(
        completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) { completion(.success(())) }
    func deleteRemoteReplica(
        completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) { completion(.success(())) }
}

private func makeSecuritySettingsLocalStorage(at root: URL) -> FilePasswordVaultLocalStorage {
    let directory = root.appendingPathComponent("PasswordVault", isDirectory: true)
    return FilePasswordVaultLocalStorage(paths: PasswordVaultLocalPaths(
        directoryURL: directory,
        vaultURL: directory.appendingPathComponent("PasteraVault.kdbx"),
        backupURL: directory.appendingPathComponent("PasteraVault.kdbx.bak"),
        metadataURL: directory.appendingPathComponent("PasswordVaultSyncMetadata.json")
    ))
}

private final class ControllerSpyFixture {
    let defaults: UserDefaults
    let store = SecuritySettingsStoreSpy()
    let controller: PasswordVaultUIController
    private let suiteName: String

    init() {
        suiteName = "PasswordVaultSecuritySettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
        controller = PasswordVaultUIController(store: store, defaults: defaults)
    }

    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func persistedValue(forKey key: String) -> Any? {
        defaults.persistentDomain(forName: suiteName)?[key]
    }

    func setAutoLock(_ interval: TimeInterval) async -> Result<Void, PasswordVaultError> {
        await result { controller.setAutoLockInterval(interval, completion: $0) }
    }
}

private func result<T>(
    _ start: (@escaping (Result<T, PasswordVaultError>) -> Void) -> Void
) async -> Result<T, PasswordVaultError> {
    await withCheckedContinuation { continuation in
        start { continuation.resume(returning: $0) }
    }
}

private func wait(for semaphore: DispatchSemaphore) async -> DispatchTimeoutResult {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
            continuation.resume(returning: semaphore.wait(timeout: .now() + 1))
        }
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var failure: Failure? {
        if case let .failure(error) = self { return error }
        return nil
    }
}

private final class LockedNotificationCounts {
    private let lock = NSLock()
    private var legacy = 0
    private var observer = 0

    var snapshot: (legacy: Int, observer: Int) {
        lock.withLock { (legacy, observer) }
    }

    func incrementLegacy() {
        lock.withLock { legacy += 1 }
    }

    func incrementObserver() {
        lock.withLock { observer += 1 }
    }
}

private final class SecuritySettingsQuickKeyStore: VaultUnlockKeyStoring {
    var data: Data?
    var containsKey: Bool { data != nil }

    func save(_ data: Data) throws { self.data = data }
    func load(reason: String) throws -> Data { try #require(data) }
    func delete() throws { data = nil }
}

private final class SecuritySettingsAutomationKeyStore: VaultAutomationUnlockKeyStoring {
    var data: Data?
    var containsKey: Bool { data != nil }

    func save(_ data: Data) throws { self.data = data }
    func load() throws -> Data { try #require(data) }
    func delete() throws { data = nil }
}

private final class SecuritySettingsStoreSpy: PasswordVaultStore {
    var state: PasswordVaultState = .unlocked
    var quickUnlockAvailable = false
    var canQuickUnlock: Bool { quickUnlockAvailable }
    var canAutomationUnlock: Bool { false }
    var refreshAutoLockCallCount = 0
    var passwordChangeCallCount = 0
    var changeResult = PasswordVaultMasterPasswordChangeResult(warnings: [])
    var blockMetadataRead = false
    let metadataStarted = DispatchSemaphore(value: 0)
    let metadataRelease = DispatchSemaphore(value: 0)

    func createDatabase(
        masterPassword: String, // swiftlint:disable:this inclusive_language
        rememberQuickUnlock: Bool
    ) throws {}
    func unlock(
        masterPassword: String, // swiftlint:disable:this inclusive_language
        rememberQuickUnlock: Bool
    ) throws {}
    func unlockWithQuickKey(reason: String) throws {}
    func enableQuickUnlock() throws {
        guard state == .unlocked else { throw PasswordVaultError.vaultLocked }
        quickUnlockAvailable = true
    }
    func disableQuickUnlock() throws { quickUnlockAvailable = false }
    func refreshAutoLockSchedule() { refreshAutoLockCallCount += 1 }
    // swiftlint:disable:next inclusive_language
    func changeMasterPassword(
        currentPassword: String,
        newPassword: String,
        keepQuickUnlockEnabled: Bool
    ) throws -> PasswordVaultMasterPasswordChangeResult {
        passwordChangeCallCount += 1
        return changeResult
    }
    func lock() { state = .locked }
    func listFolders() throws -> [PasswordVaultFolder] {
        if blockMetadataRead {
            metadataStarted.signal()
            _ = metadataRelease.wait(timeout: .now() + 2)
        }
        return []
    }
    func listEntries() throws -> [PasswordVaultEntry] { [] }
    func createFolder(name: String) throws -> PasswordVaultFolder { throw PasswordVaultError.unsupportedFormat }
    func renameFolder(id: UUID, name: String) throws -> PasswordVaultFolder { throw PasswordVaultError.unsupportedFormat }
    func deleteFolder(id: UUID) throws { throw PasswordVaultError.unsupportedFormat }
    func reorderFolders(_ folderIDs: [UUID]) throws { throw PasswordVaultError.unsupportedFormat }
    func moveEntry(id: UUID, to folderID: UUID) throws { throw PasswordVaultError.unsupportedFormat }
    func moveEntry(id: UUID, to folderID: UUID, orderedEntryIDsByFolder: [UUID: [UUID]]) throws {
        throw PasswordVaultError.unsupportedFormat
    }
    func create(_ draft: PasswordVaultDraft) throws -> PasswordVaultEntry { throw PasswordVaultError.unsupportedFormat }
    func update(id: UUID, draft: PasswordVaultDraft) throws -> PasswordVaultEntry { throw PasswordVaultError.unsupportedFormat }
    func revealPassword(id: UUID, reason: String) throws -> String { throw PasswordVaultError.unsupportedFormat }
    func delete(id: UUID, reason: String) throws { throw PasswordVaultError.unsupportedFormat }
}
