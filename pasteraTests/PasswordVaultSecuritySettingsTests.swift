import Foundation
import LocalAuthentication
import PasteraAgentProtocol
import Testing
@testable import Pastera

// The suite keeps controller security-state and reset orchestration assertions together.
// swiftlint:disable type_body_length
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

    @Test("normal reset authorizes once and reuses the same context without forced fallback")
    func normalResetReusesAuthorizationContext() async {
        let fixture = ResetControllerFixture()
        defer { fixture.remove() }
        fixture.defaults.set(false, forKey: Constants.UserDefaults.passwordVaultQuickUnlockEnabled)
        fixture.store.resetResult = .init(warnings: [])

        let outcome = await fixture.resetMasterPassword()

        #expect(outcome == .success(.init(warnings: [])))
        #expect(fixture.authorizer.callCount == 1)
        #expect(fixture.store.resetCallCount == 1)
        #expect(fixture.store.forceResetCallCount == 0)
        #expect(fixture.store.resetAuthorization?.localAuthenticationContext === fixture.authorizer.context)
        #expect(fixture.store.resetKeepSystemUnlock == false)
        #expect(fixture.store.allOperationsUsedBoundExecutor)
    }

    @Test("normal reset reports forced-reset-required without invoking forced reset")
    func normalResetNeverFallsBackToForcedReset() async {
        let fixture = ResetControllerFixture()
        defer { fixture.remove() }
        fixture.store.resetError = .resetRequiresForcedReset

        let outcome = await fixture.resetMasterPassword()

        #expect(outcome.failure == .resetRequiresForcedReset)
        #expect(fixture.authorizer.callCount == 1)
        #expect(fixture.store.resetCallCount == 1)
        #expect(fixture.store.forceResetCallCount == 0)
        #expect(fixture.agentResetter.callCount == 0)
    }

    @Test("forced reset serializes authorization revocation preparation local reset and sync")
    func forcedResetUsesExactSecurityOrdering() async {
        let fixture = ResetControllerFixture(syncMode: .oneDrive)
        defer { fixture.remove() }
        fixture.store.forceResetResult = .init(
            encryptedSnapshot: .init(data: Data("new vault".utf8), digest: "new-digest"),
            localArchiveDigest: "archive-digest",
            warnings: [.systemUnlockDisabled]
        )
        fixture.syncController.pendingAfterSynchronization = true

        let outcome = await fixture.forceReset()

        #expect(fixture.events.values == [
            .systemAuthorized,
            .agentGrantsRevoked,
            .syncResetPrepared,
            .localVaultReset,
            .syncRequested
        ])
        #expect(outcome == .success(.init(
            localArchiveDigest: "archive-digest",
            oneDriveReplacementPending: true,
            warnings: [.systemUnlockDisabled]
        )))
        #expect(fixture.store.allOperationsUsedBoundExecutor)
        #expect(fixture.agentResetter.allOperationsUsedBoundExecutor)
        #expect(fixture.syncController.allOperationsUsedBoundExecutor)
        #expect(!fixture.defaults.bool(forKey: Constants.UserDefaults.passwordVaultQuickUnlockEnabled))
    }

    @Test("local-only forced reset reports no remote replacement pending")
    func localOnlyForcedResetCompletesLocally() async {
        let fixture = ResetControllerFixture(syncMode: .localOnly)
        defer { fixture.remove() }

        let outcome = await fixture.forceReset()

        #expect(outcome.success?.oneDriveReplacementPending == false)
        #expect(fixture.syncController.preparedDigests == ["old-digest"])
        #expect(fixture.syncController.reasons == [.localChange])
    }

    @Test("forced reset authentication cancellation has no side effects")
    func forcedResetCancellationStopsBeforeRevocation() async {
        let fixture = ResetControllerFixture()
        defer { fixture.remove() }
        fixture.authorizer.result = .failure(.userCancelled)

        let outcome = await fixture.forceReset()

        #expect(outcome.failure == .userCancelled)
        #expect(fixture.events.values.isEmpty)
        #expect(fixture.agentResetter.callCount == 0)
        #expect(fixture.store.forceResetCallCount == 0)
    }

    @Test("Agent revocation failure propagates and prevents preparation and local reset")
    func agentRevocationFailureStopsForcedReset() async {
        let fixture = ResetControllerFixture()
        defer { fixture.remove() }
        fixture.agentResetter.error = VaultAgentErrorCode.automationUnlockUnavailable

        let outcome = await fixture.forceReset()

        #expect(outcome.failure == .keychainUnavailable)
        #expect(fixture.agentResetter.callCount == 1)
        #expect(fixture.syncController.preparedDigests.isEmpty)
        #expect(fixture.store.forceResetCallCount == 0)
    }

    @Test("sync preparation failure propagates and prevents the local transaction")
    func syncPreparationFailureStopsForcedReset() async {
        let fixture = ResetControllerFixture(syncMode: .oneDrive)
        defer { fixture.remove() }
        fixture.syncController.prepareError = PasswordVaultSyncFailure.remoteWriteFailed

        let outcome = await fixture.forceReset()

        #expect(outcome.failure == .cloudUnavailable)
        #expect(fixture.syncController.preparedDigests == ["old-digest"])
        #expect(fixture.store.forceResetCallCount == 0)
        #expect(fixture.syncController.cancelledDigests.isEmpty)
    }

    @Test("local transaction failure cancels only its matching preparation")
    func localFailureCancelsMatchingPreparation() async {
        let fixture = ResetControllerFixture(syncMode: .oneDrive)
        defer { fixture.remove() }
        fixture.store.forceResetError = PasswordVaultError.saveFailed

        let outcome = await fixture.forceReset()

        #expect(outcome.failure == .saveFailed)
        #expect(fixture.syncController.cancelledDigests == ["old-digest"])
        #expect(fixture.syncController.snapshot.phase == .synced)
        #expect(fixture.syncController.reasons.isEmpty)
    }

    @Test("post-commit recovery failure keeps replacement pending while reporting recovery")
    func committedRecoveryFailureKeepsPendingReplacement() async {
        let fixture = ResetControllerFixture(syncMode: .oneDrive)
        defer { fixture.remove() }
        fixture.store.forceResetError = PasswordVaultForcedResetError.recoveryRequired
        fixture.store.publishForcedResetCommitBeforeError = true

        let outcome = await fixture.forceReset()

        #expect(outcome.failure == .recoveryRequired)
        #expect(fixture.syncController.cancelledDigests.isEmpty)
        #expect(fixture.syncController.snapshot.phase == .pendingForcedReset(nil))
        #expect(fixture.syncController.reasons.isEmpty)
    }

    @Test("post-commit metadata failure keeps the real sync preparation recoverable")
    func committedRecoveryDoesNotCancelRealSyncPreparation() async throws {
        let queue = DispatchQueue(label: "PasswordVaultResetControllerTests.real-sync")
        let queueKey = DispatchSpecificKey<String>()
        queue.setSpecific(key: queueKey, value: "vault")
        let events = ResetControllerEventRecorder()
        let store = ResetStoreSpy(events: events, queueKey: queueKey)
        store.forceResetResult = .init(
            encryptedSnapshot: .init(data: Data("replacement vault".utf8), digest: "new-digest"),
            localArchiveDigest: "archive-digest",
            warnings: []
        )
        store.forceResetError = PasswordVaultForcedResetError.recoveryRequired
        store.publishForcedResetCommitBeforeError = true
        var initialMetadata = PasswordVaultSyncMetadata.defaultLocalOnly
        initialMetadata.mode = .oneDrive
        let metadata = FakePasswordVaultSyncMetadataStore(value: initialMetadata)
        var didFailReplacementSave = false
        metadata.saveFailurePredicate = { value in
            guard !didFailReplacementSave,
                  value.pendingForcedReset?.replacementLocalDigest != nil else { return false }
            didFailReplacementSave = true
            return true
        }
        let cloud = FakePasswordVaultCloudReplica()
        let processStatus = FakeOneDriveProcessStatusService()
        let root = URL(fileURLWithPath: "/tmp/pastera-reset-controller-real-sync")
        let syncController = try PasswordVaultSyncService(
            access: store,
            metadataStore: metadata,
            cloudReplica: cloud,
            processStatus: processStatus,
            rootURLProvider: { root },
            rootURLSetter: { _ in },
            rootValidator: { _ in nil },
            queue: queue,
            callbackDispatcher: { $0() }
        )
        let controller = PasswordVaultUIController(
            store: store,
            syncController: syncController,
            authorizer: ResetAuthorizerSpy(events: events),
            defaults: UserDefaults.standard,
            agentAuthorizationResetter: ResetAgentAuthorizationSpy(events: events, queueKey: queueKey),
            storeQueue: queue
        )

        let outcome = await result {
            controller.forceResetPasswordVault(newPassword: "replacement password", completion: $0)
        }

        #expect(outcome.failure == .recoveryRequired)
        #expect(didFailReplacementSave)
        #expect(metadata.value.pendingForcedReset?.previousLocalDigest == "old-digest")
        #expect(metadata.value.pendingForcedReset?.replacementLocalDigest == nil)

        _ = try PasswordVaultSyncService(
            access: store,
            metadataStore: metadata,
            cloudReplica: cloud,
            processStatus: processStatus,
            rootURLProvider: { root },
            rootURLSetter: { _ in },
            rootValidator: { _ in nil },
            queue: queue,
            callbackDispatcher: { $0() }
        )

        #expect(metadata.value.pendingForcedReset?.previousLocalDigest == "old-digest")
        #expect(metadata.value.pendingForcedReset?.replacementLocalDigest == "new-digest")
    }

    @Test("missing explicit Agent resetter never silently permits forced reset")
    func missingAgentResetterFailsClosed() async {
        let fixture = ResetControllerFixture(bindAgentResetter: false)
        defer { fixture.remove() }

        let outcome = await fixture.forceReset()

        #expect(outcome.failure == .keychainUnavailable)
        #expect(fixture.store.forceResetCallCount == 0)
    }

    @Test("custom Agent runtime leaves a default Environment controller fail-closed")
    func customRuntimeDoesNotBindUnusedResetCoordinator() async {
        let events = ResetControllerEventRecorder()
        let queueKey = DispatchSpecificKey<String>()
        let store = ResetStoreSpy(events: events, queueKey: queueKey)
        let authorizer = ResetAuthorizerSpy(events: events)
        var coordinatorBuildCount = 0
        let environment = Environment(
            passwordVaultStore: store,
            passwordVaultSyncService: LocalOnlyPasswordVaultSyncController(localVaultAvailable: true),
            passwordVaultAuthorizer: authorizer,
            vaultAgentApplicationRuntime: UnavailableVaultAgentApplicationRuntime(),
            vaultAgentResetCoordinatorFactory: { executor in
                coordinatorBuildCount += 1
                return VaultAgentAuthorizationResetCoordinator(
                    executor: executor,
                    storeFactory: { InMemoryEnvironmentGrantStore() }
                )
            }
        )

        let outcome = await result {
            environment.passwordVaultUIController.forceResetPasswordVault(
                newPassword: "replacement password",
                completion: $0
            )
        }

        #expect(coordinatorBuildCount == 0)
        #expect(outcome.failure == .keychainUnavailable)
        #expect(store.forceResetCallCount == 0)
    }

    @Test("security settings follow pending forced reset snapshot updates")
    func securitySettingsObserveForcedResetPendingState() async {
        let fixture = ResetControllerFixture(syncMode: .oneDrive)
        defer { fixture.remove() }
        fixture.store.resetCapability = .requiresForcedReset

        fixture.syncController.publish(phase: .pendingForcedReset(.oneDriveNotRunning))
        let pending = await fixture.securitySettings()
        #expect(pending.masterPasswordResetCapability == .requiresForcedReset)
        #expect(pending.forcedResetPending)
        #expect(pending.forcedResetPendingFailure == .oneDriveNotRunning)

        fixture.syncController.publish(phase: .synced)
        let completed = await fixture.securitySettings()
        #expect(!completed.forcedResetPending)
        #expect(completed.forcedResetPendingFailure == nil)
    }

    @Test("retry forwards exactly once and completes on the main thread after state refresh")
    func retryForcedResetForwardsOnceOnMain() async {
        let fixture = ResetControllerFixture(syncMode: .oneDrive)
        defer { fixture.remove() }
        fixture.syncController.publish(phase: .pendingForcedReset(.remoteVerificationFailed))

        let result: Result<Void, PasswordVaultSyncFailure> = await withCheckedContinuation { continuation in
            fixture.controller.retryForcedReset { result in
                #expect(Thread.isMainThread)
                continuation.resume(returning: result)
            }
        }

        #expect(result.isSuccess)
        #expect(fixture.syncController.retryForcedResetCallCount == 1)
        let state = await fixture.securitySettings()
        #expect(!state.forcedResetPending)
        #expect(state.forcedResetPendingFailure == nil)
    }

    @MainActor
    @Test("equal initial sync snapshot does not report a state change")
    func equalInitialSyncSnapshotRemainsSilent() async {
        let snapshot = makeRegistrationSyncSnapshot(mode: .localOnly, phase: .disabled)
        let syncController = RegistrationWindowSyncController(
            getterSnapshot: snapshot,
            registrationSnapshot: snapshot
        )
        let controller = PasswordVaultUIController(
            store: SecuritySettingsStoreSpy(),
            syncController: syncController
        )
        var changeCount = 0
        controller.onChange = { changeCount += 1 }

        await drainSecuritySettingsMainQueue()

        #expect(changeCount == 0)
    }

    @MainActor
    @Test("new sync snapshot captured during observer registration reports one change")
    func registrationWindowSyncChangeIsObserved() async {
        let initial = makeRegistrationSyncSnapshot(mode: .oneDrive, phase: .synced)
        let registered = makeRegistrationSyncSnapshot(
            mode: .oneDrive,
            phase: .pendingForcedReset(.remoteVerificationFailed)
        )
        let syncController = RegistrationWindowSyncController(
            getterSnapshot: initial,
            registrationSnapshot: registered
        )
        let controller = PasswordVaultUIController(
            store: SecuritySettingsStoreSpy(),
            syncController: syncController
        )
        var changeCount = 0
        controller.onChange = { changeCount += 1 }

        await drainSecuritySettingsMainQueue()
        let settings = await withCheckedContinuation { continuation in
            controller.loadSecuritySettings { continuation.resume(returning: $0) }
        }

        #expect(changeCount == 1)
        #expect(settings.forcedResetPending)
        #expect(settings.forcedResetPendingFailure == .remoteVerificationFailed)
    }
}
// swiftlint:enable type_body_length

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
}

private final class RegistrationWindowSyncController: PasswordVaultSyncControlling {
    private let getterSnapshot: PasswordVaultSyncSnapshot
    private let registrationSnapshot: PasswordVaultSyncSnapshot

    init(
        getterSnapshot: PasswordVaultSyncSnapshot,
        registrationSnapshot: PasswordVaultSyncSnapshot
    ) {
        self.getterSnapshot = getterSnapshot
        self.registrationSnapshot = registrationSnapshot
    }

    var snapshot: PasswordVaultSyncSnapshot { getterSnapshot }

    func addObserver(_ observer: @escaping (PasswordVaultSyncSnapshot) -> Void) -> UUID {
        let identifier = UUID()
        DispatchQueue.main.async { [registrationSnapshot] in observer(registrationSnapshot) }
        return identifier
    }

    func removeObserver(_ identifier: UUID) {}
    func record(_ commit: PasswordVaultCommit) {}
    func synchronize(reason: SyncCoordinator.Reason) {}
    func enableOneDrive(
        rootURL: URL,
        remoteMasterPassword: String?, // swiftlint:disable:this inclusive_language
        completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) { completion(.success(())) }
}

private func makeRegistrationSyncSnapshot(
    mode: PasswordVaultSyncMode,
    phase: PasswordVaultSyncPhase
) -> PasswordVaultSyncSnapshot {
    PasswordVaultSyncSnapshot(
        mode: mode,
        phase: phase,
        localVaultAvailable: true,
        remoteVaultAvailable: mode == .oneDrive,
        pendingChangeCount: 0,
        conflictCopyCount: 0,
        lastSyncAt: nil
    )
}

@MainActor
private func drainSecuritySettingsMainQueue() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async {
            DispatchQueue.main.async { continuation.resume() }
        }
    }
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
    func lock() { state = .locked }
    func listFolders() throws -> [PasswordVaultFolder] { [] }
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

private enum ResetControllerEvent: Equatable {
    case systemAuthorized
    case agentGrantsRevoked
    case syncResetPrepared
    case localVaultReset
    case syncRequested
}

private final class ResetControllerEventRecorder {
    private let lock = NSLock()
    private var storage = [ResetControllerEvent]()

    var values: [ResetControllerEvent] { lock.withLock { storage } }

    func append(_ event: ResetControllerEvent) {
        lock.withLock { storage.append(event) }
    }
}

private final class ResetControllerFixture {
    let defaults: UserDefaults
    let events = ResetControllerEventRecorder()
    let authorizer: ResetAuthorizerSpy
    let store: ResetStoreSpy
    let syncController: ResetSyncControllerSpy
    let agentResetter: ResetAgentAuthorizationSpy
    let controller: PasswordVaultUIController
    private let suiteName: String

    init(
        syncMode: PasswordVaultSyncMode = .localOnly,
        bindAgentResetter: Bool = true
    ) {
        suiteName = "PasswordVaultResetControllerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let queue = DispatchQueue(label: "PasswordVaultResetControllerTests.store")
        let queueKey = DispatchSpecificKey<String>()
        queue.setSpecific(key: queueKey, value: "vault")
        authorizer = ResetAuthorizerSpy(events: events)
        store = ResetStoreSpy(events: events, queueKey: queueKey)
        syncController = ResetSyncControllerSpy(mode: syncMode, events: events, queueKey: queueKey)
        agentResetter = ResetAgentAuthorizationSpy(events: events, queueKey: queueKey)
        controller = PasswordVaultUIController(
            store: store,
            syncController: syncController,
            authorizer: authorizer,
            defaults: defaults,
            storeQueue: queue
        )
        if bindAgentResetter {
            controller.bindAgentAuthorizationResetter(agentResetter)
        }
    }

    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    // swiftlint:disable:next inclusive_language
    func resetMasterPassword() async -> Result<PasswordVaultMasterPasswordResetResult, PasswordVaultError> {
        await result { controller.resetMasterPassword(newPassword: "replacement password", completion: $0) }
    }

    func forceReset() async -> Result<PasswordVaultForcedResetOutcome, PasswordVaultError> {
        await result { controller.forceResetPasswordVault(newPassword: "replacement password", completion: $0) }
    }

    func securitySettings() async -> PasswordVaultSecuritySettingsState {
        await withCheckedContinuation { continuation in
            controller.loadSecuritySettings { continuation.resume(returning: $0) }
        }
    }
}

private final class ResetAuthorizerSpy: PasswordVaultAuthorizing {
    let context = LAContext()
    var result: Result<PasswordVaultAuthorizationContext, PasswordVaultError>?
    private(set) var callCount = 0
    private let events: ResetControllerEventRecorder

    init(events: ResetControllerEventRecorder) {
        self.events = events
    }

    func authorize(
        reason: String,
        completion: @escaping (Result<PasswordVaultAuthorizationContext, PasswordVaultError>) -> Void
    ) {
        callCount += 1
        let result = result ?? .success(.init(localAuthenticationContext: context))
        if case .success = result {
            events.append(.systemAuthorized)
        }
        completion(result)
    }
}

private final class ResetAgentAuthorizationSpy: VaultAgentAuthorizationResetting {
    var error: Error?
    private(set) var callCount = 0
    private(set) var allOperationsUsedBoundExecutor = true
    private let events: ResetControllerEventRecorder
    private let queueKey: DispatchSpecificKey<String>

    init(events: ResetControllerEventRecorder, queueKey: DispatchSpecificKey<String>) {
        self.events = events
        self.queueKey = queueKey
    }

    func revokeAll() throws {
        callCount += 1
        allOperationsUsedBoundExecutor = allOperationsUsedBoundExecutor
            && DispatchQueue.getSpecific(key: queueKey) == "vault"
        if let error { throw error }
        events.append(.agentGrantsRevoked)
    }
}

private final class ResetSyncControllerSpy: PasswordVaultSyncControlling {
    private let lock = NSLock()
    private var currentSnapshot: PasswordVaultSyncSnapshot
    private var observers = [UUID: (PasswordVaultSyncSnapshot) -> Void]()
    private(set) var preparedDigests = [String]()
    private(set) var cancelledDigests = [String]()
    private(set) var reasons = [SyncCoordinator.Reason]()
    private var replacementDigestRecorded = false
    var prepareError: Error?
    var pendingAfterSynchronization = false
    private(set) var retryForcedResetCallCount = 0
    private(set) var allOperationsUsedBoundExecutor = true
    private let events: ResetControllerEventRecorder
    private let queueKey: DispatchSpecificKey<String>

    init(
        mode: PasswordVaultSyncMode,
        events: ResetControllerEventRecorder,
        queueKey: DispatchSpecificKey<String>
    ) {
        currentSnapshot = .init(
            mode: mode,
            phase: mode == .localOnly ? .disabled : .synced,
            localVaultAvailable: true,
            remoteVaultAvailable: mode == .localOnly ? nil : true,
            pendingChangeCount: 0,
            conflictCopyCount: 0,
            lastSyncAt: nil
        )
        self.events = events
        self.queueKey = queueKey
    }

    var snapshot: PasswordVaultSyncSnapshot { lock.withLock { currentSnapshot } }

    func addObserver(_ observer: @escaping (PasswordVaultSyncSnapshot) -> Void) -> UUID {
        let identifier = UUID()
        let initial = lock.withLock {
            observers[identifier] = observer
            return currentSnapshot
        }
        observer(initial)
        return identifier
    }

    func removeObserver(_ identifier: UUID) {
        _ = lock.withLock { observers.removeValue(forKey: identifier) }
    }

    func record(_ commit: PasswordVaultCommit) {
        guard commit.origin == .forcedReset else { return }
        replacementDigestRecorded = true
        publish(phase: .pendingForcedReset(nil))
    }

    func synchronize(reason: SyncCoordinator.Reason) {
        recordQueueUse()
        reasons.append(reason)
        events.append(.syncRequested)
        if currentSnapshot.mode == .oneDrive {
            publish(phase: pendingAfterSynchronization ? .pendingForcedReset(.remoteUnavailable) : .synced)
        }
    }

    func prepareForcedReset(previousLocalDigest: String) throws {
        recordQueueUse()
        preparedDigests.append(previousLocalDigest)
        events.append(.syncResetPrepared)
        if let prepareError { throw prepareError }
        replacementDigestRecorded = false
        if currentSnapshot.mode == .oneDrive {
            publish(phase: .pendingForcedReset(nil))
        }
    }

    func cancelPreparedForcedReset(previousLocalDigest: String) {
        recordQueueUse()
        cancelledDigests.append(previousLocalDigest)
        guard preparedDigests.last == previousLocalDigest, !replacementDigestRecorded else { return }
        publish(phase: currentSnapshot.mode == .localOnly ? .disabled : .synced)
    }

    func retryForcedReset(completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void) {
        retryForcedResetCallCount += 1
        publish(phase: .synced)
        completion(.success(()))
    }

    func enableOneDrive(
        rootURL: URL,
        remoteMasterPassword: String?, // swiftlint:disable:this inclusive_language
        completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) {
        completion(.success(()))
    }

    func publish(phase: PasswordVaultSyncPhase) {
        let callbacks: [(PasswordVaultSyncSnapshot) -> Void] = lock.withLock {
            currentSnapshot = .init(
                mode: currentSnapshot.mode,
                phase: phase,
                localVaultAvailable: currentSnapshot.localVaultAvailable,
                remoteVaultAvailable: currentSnapshot.remoteVaultAvailable,
                pendingChangeCount: currentSnapshot.pendingChangeCount,
                conflictCopyCount: currentSnapshot.conflictCopyCount,
                lastSyncAt: currentSnapshot.lastSyncAt
            )
            return Array(observers.values)
        }
        let snapshot = snapshot
        callbacks.forEach { $0(snapshot) }
    }

    private func recordQueueUse() {
        allOperationsUsedBoundExecutor = allOperationsUsedBoundExecutor
            && DispatchQueue.getSpecific(key: queueKey) == "vault"
    }
}

private final class ResetStoreSpy: PasswordVaultStore, PasswordVaultSyncAccess {
    var state: PasswordVaultState = .unlocked
    var canQuickUnlock = true
    var canAutomationUnlock = true
    var resetCapability: PasswordVaultMasterPasswordResetCapability = .preservesData
    // swiftlint:disable:next inclusive_language
    var masterPasswordResetCapability: PasswordVaultMasterPasswordResetCapability { resetCapability }
    var resetResult = PasswordVaultMasterPasswordResetResult(warnings: [])
    var resetError: PasswordVaultError?
    var forceResetResult = PasswordVaultForcedResetResult(
        encryptedSnapshot: .init(data: Data("new vault".utf8), digest: "new-digest"),
        localArchiveDigest: "archive-digest",
        warnings: []
    )
    var forceResetError: Error?
    var publishForcedResetCommitBeforeError = false
    private var encryptedSnapshotValue = PasswordVaultEncryptedSnapshot(
        data: Data("old vault".utf8),
        digest: "old-digest"
    )
    private(set) var resetCallCount = 0
    private(set) var forceResetCallCount = 0
    private(set) var resetAuthorization: PasswordVaultAuthorizationContext?
    private(set) var resetKeepSystemUnlock: Bool?
    private(set) var allOperationsUsedBoundExecutor = true
    private var commitObserver: ((PasswordVaultCommit) -> Void)?
    private let events: ResetControllerEventRecorder
    private let queueKey: DispatchSpecificKey<String>

    init(events: ResetControllerEventRecorder, queueKey: DispatchSpecificKey<String>) {
        self.events = events
        self.queueKey = queueKey
    }

    // swiftlint:disable:next inclusive_language
    func resetMasterPassword(
        newPassword: String,
        keepSystemUnlockEnabled: Bool,
        authorization: PasswordVaultAuthorizationContext
    ) throws -> PasswordVaultMasterPasswordResetResult {
        recordQueueUse()
        resetCallCount += 1
        resetAuthorization = authorization
        resetKeepSystemUnlock = keepSystemUnlockEnabled
        if let resetError { throw resetError }
        return resetResult
    }

    func forceReset(
        newPassword: String,
        rememberSystemUnlock: Bool
    ) throws -> PasswordVaultForcedResetResult {
        recordQueueUse()
        forceResetCallCount += 1
        events.append(.localVaultReset)
        if publishForcedResetCommitBeforeError {
            encryptedSnapshotValue = forceResetResult.encryptedSnapshot
            commitObserver?(.init(origin: .forcedReset, encryptedDigest: forceResetResult.encryptedSnapshot.digest))
        }
        if let forceResetError { throw forceResetError }
        encryptedSnapshotValue = forceResetResult.encryptedSnapshot
        commitObserver?(.init(origin: .forcedReset, encryptedDigest: forceResetResult.encryptedSnapshot.digest))
        return forceResetResult
    }

    func encryptedSnapshot() throws -> PasswordVaultEncryptedSnapshot {
        recordQueueUse()
        return encryptedSnapshotValue
    }

    func mergeRemoteSnapshot(
        _ remoteData: Data,
        remoteMasterPassword: String? // swiftlint:disable:this inclusive_language
    ) throws -> PasswordVaultMergeApplication {
        throw PasswordVaultError.unsupportedFormat
    }

    func setCommitObserver(_ observer: @escaping (PasswordVaultCommit) -> Void) {
        commitObserver = observer
    }

    func listFolders() throws -> [PasswordVaultFolder] { [] }
    func listEntries() throws -> [PasswordVaultEntry] { [] }
    func createFolder(name: String) throws -> PasswordVaultFolder { throw PasswordVaultError.unsupportedFormat }
    func renameFolder(id: UUID, name: String) throws -> PasswordVaultFolder {
        throw PasswordVaultError.unsupportedFormat
    }
    func deleteFolder(id: UUID) throws { throw PasswordVaultError.unsupportedFormat }
    func reorderFolders(_ folderIDs: [UUID]) throws { throw PasswordVaultError.unsupportedFormat }
    func moveEntry(id: UUID, to folderID: UUID) throws { throw PasswordVaultError.unsupportedFormat }
    func moveEntry(id: UUID, to folderID: UUID, orderedEntryIDsByFolder: [UUID: [UUID]]) throws {
        throw PasswordVaultError.unsupportedFormat
    }
    func create(_ draft: PasswordVaultDraft) throws -> PasswordVaultEntry {
        throw PasswordVaultError.unsupportedFormat
    }
    func update(id: UUID, draft: PasswordVaultDraft) throws -> PasswordVaultEntry {
        throw PasswordVaultError.unsupportedFormat
    }
    func revealPassword(id: UUID, reason: String) throws -> String { throw PasswordVaultError.unsupportedFormat }
    func delete(id: UUID, reason: String) throws { throw PasswordVaultError.unsupportedFormat }

    private func recordQueueUse() {
        allOperationsUsedBoundExecutor = allOperationsUsedBoundExecutor
            && DispatchQueue.getSpecific(key: queueKey) == "vault"
    }
}

private final class InMemoryEnvironmentGrantStore: VaultAgentGrantStoring {
    private var grants = [VaultAgentClientKind: VaultAgentGrant]()

    func load() -> [VaultAgentClientKind: VaultAgentGrant] { grants }
    func save(_ grants: [VaultAgentClientKind: VaultAgentGrant]) { self.grants = grants }
}

private extension Result {
    var success: Success? {
        if case let .success(value) = self { return value }
        return nil
    }
}
// swiftlint:disable:this file_length
