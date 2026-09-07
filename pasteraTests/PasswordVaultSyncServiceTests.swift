import Foundation
import Testing
@testable import Pastera

// Integration coverage mirrors the full sync state machine in one suite.
// swiftlint:disable file_length

@Suite("Password vault sync service", .serialized)
struct PasswordVaultSyncServiceTests { // swiftlint:disable:this type_body_length
    @Test("sync decision covers all local and remote change combinations")
    func syncDecisionMatrix() {
        #expect(passwordVaultSyncDecision(localChanged: false, remoteChanged: false) == .noChange)
        #expect(passwordVaultSyncDecision(localChanged: true, remoteChanged: false) == .uploadLocal)
        #expect(passwordVaultSyncDecision(localChanged: false, remoteChanged: true) == .applyRemote)
        #expect(passwordVaultSyncDecision(localChanged: true, remoteChanged: true) == .mergeBoth)
    }

    @Test("local-only mode is disabled and never inspects OneDrive")
    func localOnlyNeverTouchesCloud() throws {
        let fixture = try makeSyncServiceFixture()

        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.service.snapshot.mode == .localOnly)
        #expect(fixture.service.snapshot.phase == .disabled)
        #expect(fixture.processStatus.readCount == 0)
        #expect(fixture.root.urlReadCount == 0)
        #expect(fixture.cloud.readCount == 0)
    }

    @Test("local-only forced reset preparation is a no-op")
    func localOnlyForcedResetPreparationIsNoOp() throws {
        let fixture = try makeSyncServiceFixture()

        try fixture.service.prepareForcedReset(previousLocalDigest: "local-only")

        #expect(fixture.metadata.value.pendingForcedReset == nil)
        #expect(fixture.metadata.savedValues.isEmpty)
        #expect(fixture.service.snapshot.phase == .disabled)
    }

    @Test("forced reset preparation persists synchronously and reenters the shared queue")
    func forcedResetPreparationPersistsReentrantlyBeforeLocalMutation() throws {
        let oldLocalData = Data("old-local".utf8)
        let newLocalData = Data("new-local".utf8)
        let previousDigest = PasswordVaultDigest.hex(oldLocalData)
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        let fixture = try makeSyncServiceFixture(metadata: metadata, localData: oldLocalData)

        try fixture.queue.sync {
            try fixture.service.prepareForcedReset(previousLocalDigest: previousDigest)
            #expect(fixture.metadata.value.pendingForcedReset?.previousLocalDigest == previousDigest)
            #expect(fixture.metadata.value.pendingForcedReset?.replacementLocalDigest == nil)
            fixture.access.data = newLocalData
        }

        #expect(fixture.metadata.savedValues.count == 1)
        #expect(fixture.metadata.savedValues[0].pendingForcedReset?.previousLocalDigest == previousDigest)
        #expect(fixture.service.snapshot.phase == .pendingForcedReset(nil))
    }

    @Test("cancellation only clears the matching uncommitted preparation")
    func cancellationRequiresMatchingUncommittedPreparation() throws {
        let oldLocalData = Data("old-local".utf8)
        let previousDigest = PasswordVaultDigest.hex(oldLocalData)
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        let fixture = try makeSyncServiceFixture(metadata: metadata, localData: oldLocalData)

        try fixture.service.prepareForcedReset(previousLocalDigest: previousDigest)
        fixture.service.cancelPreparedForcedReset(previousLocalDigest: "different")
        #expect(fixture.metadata.value.pendingForcedReset != nil)

        fixture.service.cancelPreparedForcedReset(previousLocalDigest: previousDigest)
        #expect(fixture.metadata.value.pendingForcedReset == nil)
        #expect(fixture.service.snapshot.phase == .syncing(.checking))

        try fixture.service.prepareForcedReset(previousLocalDigest: previousDigest)
        fixture.service.record(PasswordVaultCommit(origin: .forcedReset, encryptedDigest: "replacement"))
        fixture.drain()
        fixture.service.cancelPreparedForcedReset(previousLocalDigest: previousDigest)
        #expect(fixture.metadata.value.pendingForcedReset?.replacementLocalDigest == "replacement")
    }

    @Test("startup cancels a prepared reset when the local digest never changed")
    func unchangedPreparedResetIsCancelled() throws {
        let oldLocalData = Data("old-local".utf8)
        let fixture = try makePreparedResetFixture(
            previousLocalData: oldLocalData,
            localData: oldLocalData
        )

        fixture.service.reconcilePendingForcedResetForTesting()

        #expect(fixture.metadata.value.pendingForcedReset == nil)
        #expect(fixture.access.snapshotReadCount == 1)
        #expect(fixture.service.snapshot.phase == .syncing(.checking))
    }

    @Test("startup adopts the changed local digest after a crash")
    func committedLocalResetIsRecoveredAfterRestart() throws {
        let oldLocalData = Data("old-local".utf8)
        let newLocalData = Data("new-local".utf8)
        let fixture = try makePreparedResetFixture(
            previousLocalData: oldLocalData,
            localData: newLocalData
        )

        fixture.service.reconcilePendingForcedResetForTesting()

        #expect(fixture.metadata.value.pendingForcedReset?.replacementLocalDigest
            == PasswordVaultDigest.hex(newLocalData))
        #expect(fixture.service.snapshot.phase == .pendingForcedReset(nil))
    }

    @Test("startup retains a committed forced reset regardless of the current digest")
    func committedPreparedResetRemainsPending() throws {
        let oldLocalData = Data("old-local".utf8)
        let replacementDigest = PasswordVaultDigest.hex(Data("replacement".utf8))
        let fixture = try makePreparedResetFixture(
            previousLocalData: oldLocalData,
            localData: oldLocalData,
            replacementLocalDigest: replacementDigest
        )

        fixture.service.reconcilePendingForcedResetForTesting()

        #expect(fixture.metadata.value.pendingForcedReset?.replacementLocalDigest == replacementDigest)
        #expect(fixture.access.snapshotReadCount == 2)
        #expect(fixture.service.snapshot.phase == .pendingForcedReset(nil))
    }

    @Test("startup retains forced reset state when the local snapshot is unavailable")
    func unavailableLocalSnapshotKeepsPreparedResetPending() throws {
        let oldLocalData = Data("old-local".utf8)
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.pendingForcedReset = PasswordVaultPendingForcedReset(
            previousLocalDigest: PasswordVaultDigest.hex(oldLocalData),
            replacementLocalDigest: nil,
            didInspectRemote: false,
            observedRemoteDigest: nil,
            archivedRemoteDigest: nil,
            remoteArchiveRequired: nil
        )
        let access = FakePasswordVaultSyncAccess(data: oldLocalData)
        access.snapshotError = PasswordVaultSyncFailure.remoteUnavailable
        let fixture = try makeSyncServiceFixture(metadata: metadata, access: access)

        #expect(fixture.metadata.value.pendingForcedReset == metadata.pendingForcedReset)
        #expect(fixture.service.snapshot.phase == .pendingForcedReset(.remoteUnavailable))
        #expect(fixture.cloud.readCount == 0)
    }

    @Test("forced reset commits advance revision without entering ordinary merge pending")
    func forcedResetCommitUsesDedicatedPendingRecord() throws {
        let oldLocalData = Data("old-local".utf8)
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.localRevision = 4
        metadata.pendingChangeCount = 2
        metadata.pendingForcedReset = PasswordVaultPendingForcedReset(
            previousLocalDigest: PasswordVaultDigest.hex(oldLocalData),
            replacementLocalDigest: "prepared-replacement",
            didInspectRemote: false,
            observedRemoteDigest: nil,
            archivedRemoteDigest: nil,
            remoteArchiveRequired: nil
        )
        let fixture = try makeSyncServiceFixture(metadata: metadata, localData: oldLocalData)

        fixture.service.record(PasswordVaultCommit(origin: .forcedReset, encryptedDigest: "committed-replacement"))
        fixture.drain()

        #expect(fixture.metadata.value.localRevision == 5)
        #expect(fixture.metadata.value.pendingChangeCount == 2)
        #expect(fixture.metadata.value.pendingForcedReset?.replacementLocalDigest == "committed-replacement")
        #expect(fixture.service.snapshot.phase == .pendingForcedReset(nil))
    }

    @Test("forced reset commit persists before a reentrant cancellation can run")
    func forcedResetCommitPrecedesReentrantCancellation() throws {
        let oldLocalData = Data("old-local".utf8)
        let previousDigest = PasswordVaultDigest.hex(oldLocalData)
        let replacementDigest = "committed-replacement"
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        let fixture = try makeSyncServiceFixture(metadata: metadata, localData: oldLocalData)
        try fixture.service.prepareForcedReset(previousLocalDigest: previousDigest)

        fixture.queue.sync {
            fixture.service.record(
                PasswordVaultCommit(origin: .forcedReset, encryptedDigest: replacementDigest)
            )
            fixture.service.cancelPreparedForcedReset(previousLocalDigest: previousDigest)

            #expect(fixture.metadata.value.pendingForcedReset?.replacementLocalDigest == replacementDigest)
            #expect(fixture.metadata.savedValues.map(\.pendingForcedReset?.replacementLocalDigest) == [nil, replacementDigest])
        }
        fixture.drain()

        #expect(fixture.metadata.savedValues.count == 2)
        #expect(fixture.metadata.value.pendingForcedReset?.replacementLocalDigest == replacementDigest)
        #expect(fixture.service.snapshot.phase == .pendingForcedReset(nil))
    }

    @Test("ordinary mutations keep their pending count while forced reset stays pending")
    func ordinaryMutationKeepsPendingCountAndForcedResetPhase() throws {
        let localData = Data("replacement".utf8)
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.localRevision = 4
        metadata.pendingChangeCount = 2
        metadata.pendingForcedReset = PasswordVaultPendingForcedReset(
            previousLocalDigest: "previous",
            replacementLocalDigest: PasswordVaultDigest.hex(localData),
            didInspectRemote: false,
            observedRemoteDigest: nil,
            archivedRemoteDigest: nil,
            remoteArchiveRequired: nil
        )
        let fixture = try makeSyncServiceFixture(metadata: metadata, localData: localData)

        fixture.service.record(PasswordVaultCommit(origin: .userMutation, encryptedDigest: "newer-local"))
        fixture.drain()

        #expect(fixture.metadata.value.localRevision == 5)
        #expect(fixture.metadata.value.pendingChangeCount == 3)
        #expect(fixture.metadata.value.pendingForcedReset == metadata.pendingForcedReset)
        #expect(fixture.service.snapshot.phase == .pendingForcedReset(nil))
    }

    @Test("offline OneDrive disconnects before resolving or reading its folder")
    func offlineOneDriveNeverTouchesCloud() throws {
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        let fixture = try makeSyncServiceFixture(metadata: metadata)
        fixture.processStatus.status = .notRunning(appURL: fixture.oneDriveAppURL)

        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.service.snapshot.phase == .disconnected(.oneDriveNotRunning))
        #expect(fixture.processStatus.readCount == 1)
        #expect(fixture.root.urlReadCount == 0)
        #expect(fixture.cloud.readCount == 0)
    }

    @Test("missing OneDrive reports installation failure without cloud access")
    func missingOneDriveNeverTouchesCloud() throws {
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        let fixture = try makeSyncServiceFixture(metadata: metadata)
        fixture.processStatus.status = .notInstalled

        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.service.snapshot.phase == .disconnected(.oneDriveNotInstalled))
        #expect(fixture.root.urlReadCount == 0)
        #expect(fixture.cloud.readCount == 0)
    }

    @Test("unavailable root fails before invoking the cloud replica")
    func unavailableRootNeverTouchesCloud() throws {
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        let fixture = try makeSyncServiceFixture(metadata: metadata)
        fixture.root.validationFailure = .folderUnavailable

        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.service.snapshot.phase == .disconnected(.folderUnavailable))
        #expect(fixture.root.validationCount == 1)
        #expect(fixture.cloud.readCount == 0)
    }

    @Test("user mutations accumulate revisions and only enabled sync accumulates pending changes")
    func userMutationsAccumulatePendingOnlyForOneDrive() throws {
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        let enabled = try makeSyncServiceFixture(metadata: metadata)

        enabled.service.record(PasswordVaultCommit(origin: .userMutation, encryptedDigest: "one"))
        enabled.service.record(PasswordVaultCommit(origin: .userMutation, encryptedDigest: "two"))
        enabled.drain()

        #expect(enabled.metadata.value.localRevision == 2)
        #expect(enabled.metadata.value.pendingChangeCount == 2)
        #expect(enabled.service.snapshot.pendingChangeCount == 2)

        let localOnly = try makeSyncServiceFixture()
        localOnly.service.record(PasswordVaultCommit(origin: .userMutation, encryptedDigest: "local"))
        localOnly.drain()
        #expect(localOnly.metadata.value.localRevision == 1)
        #expect(localOnly.metadata.value.pendingChangeCount == 0)
        #expect(localOnly.service.snapshot.pendingChangeCount == 0)
    }

    @Test("sync-merge and migration commits refresh the digest without adding pending work")
    func nonUserCommitsDoNotAddPendingChanges() throws {
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.pendingChangeCount = 2
        let fixture = try makeSyncServiceFixture(metadata: metadata)

        fixture.service.record(PasswordVaultCommit(origin: .syncMerge, encryptedDigest: "merged"))
        fixture.service.record(PasswordVaultCommit(origin: .migration, encryptedDigest: "migrated"))
        fixture.drain()

        #expect(fixture.metadata.value.localRevision == 0)
        #expect(fixture.metadata.value.pendingChangeCount == 2)
        #expect(fixture.metadata.value.lastSyncedLocalDigest == "migrated")
    }

    @Test("metadata save failure never publishes a revision that was not persisted")
    func recordSaveFailureIsNotPublished() throws {
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        let fixture = try makeSyncServiceFixture(metadata: metadata)
        fixture.metadata.saveError = SyncServiceFixtureError.metadataWrite

        fixture.service.record(PasswordVaultCommit(origin: .userMutation, encryptedDigest: "lost"))
        fixture.drain()

        #expect(fixture.metadata.value.localRevision == 0)
        #expect(fixture.service.snapshot.pendingChangeCount == 0)
    }

    @Test("local upload uses absent CAS and publishes the required phase order")
    func localUploadCreatesRemoteWithCAS() throws {
        let localData = Data("local-encrypted".utf8)
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.localRevision = 1
        metadata.pendingChangeCount = 1
        let fixture = try makeSyncServiceFixture(metadata: metadata, localData: localData)
        var phases = [PasswordVaultSyncPhase]()
        let observer = fixture.service.addObserver { phases.append($0.phase) }
        phases.removeAll()

        fixture.service.synchronize(reason: .manual)
        fixture.drain()
        fixture.service.removeObserver(observer)

        #expect(fixture.cloud.writes.count == 1)
        #expect(fixture.cloud.writes.first?.expectation == .absent)
        #expect(fixture.cloud.writes.first?.data == localData)
        #expect(fixture.metadata.value.pendingChangeCount == 0)
        #expect(fixture.metadata.value.lastSyncedLocalRevision == 1)
        #expect(fixture.metadata.value.lastSyncedLocalDigest == PasswordVaultDigest.hex(localData))
        #expect(fixture.metadata.value.lastObservedRemoteDigest == PasswordVaultDigest.hex(localData))
        #expect(phases == [.syncing(.checking), .syncing(.uploading), .syncing(.verifying), .synced])
    }

    @Test("an unchanged revision with a changed encrypted digest still uploads")
    func digestChangeCannotBeMissedByRevision() throws {
        let previous = Data("previous-encrypted".utf8)
        let current = Data("current-encrypted".utf8)
        let remote = Data("remote-encrypted".utf8)
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.lastSyncedLocalDigest = PasswordVaultDigest.hex(previous)
        metadata.lastObservedRemoteDigest = PasswordVaultDigest.hex(remote)
        let fixture = try makeSyncServiceFixture(metadata: metadata, localData: current)
        fixture.cloud.snapshot = PasswordVaultCloudSnapshot(
            data: remote,
            digest: PasswordVaultDigest.hex(remote)
        )

        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.cloud.writes.count == 1)
        #expect(fixture.cloud.writes.first?.expectation == .digest(PasswordVaultDigest.hex(remote)))
    }

    @Test("a missing remote is rebuilt even when the local digest already has a baseline")
    func missingRemoteCannotBeReportedAsSynced() throws {
        let local = Data("local-with-baseline".utf8)
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.lastSyncedLocalDigest = PasswordVaultDigest.hex(local)
        let fixture = try makeSyncServiceFixture(metadata: metadata, localData: local)

        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.cloud.writes.count == 1)
        #expect(fixture.cloud.writes.first?.expectation == .absent)
        #expect(fixture.metadata.value.lastObservedRemoteDigest == PasswordVaultDigest.hex(local))
        #expect(fixture.service.snapshot.phase == .synced)
    }

    @Test("no changes do not write either side")
    func noChangesAreNoOp() throws {
        let local = Data("local".utf8)
        let remote = Data("remote".utf8)
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.lastSyncedLocalDigest = PasswordVaultDigest.hex(local)
        metadata.lastObservedRemoteDigest = PasswordVaultDigest.hex(remote)
        let fixture = try makeSyncServiceFixture(metadata: metadata, localData: local)
        fixture.cloud.snapshot = PasswordVaultCloudSnapshot(
            data: remote,
            digest: PasswordVaultDigest.hex(remote)
        )

        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.cloud.writes.isEmpty)
        #expect(fixture.access.mergeCount == 0)
        #expect(fixture.service.snapshot.phase == .synced)
    }

    @Test("remote-only change waits for unlock without modifying either replica")
    func remoteChangeWaitsForUnlock() throws {
        let local = Data("local".utf8)
        let remote = Data("remote-new".utf8)
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.lastSyncedLocalDigest = PasswordVaultDigest.hex(local)
        metadata.lastObservedRemoteDigest = "remote-old"
        let fixture = try makeSyncServiceFixture(metadata: metadata, localData: local)
        fixture.access.state = .locked
        fixture.cloud.snapshot = PasswordVaultCloudSnapshot(
            data: remote,
            digest: PasswordVaultDigest.hex(remote)
        )

        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.service.snapshot.phase == .waitingForUnlock)
        #expect(fixture.access.mergeCount == 0)
        #expect(fixture.cloud.writes.isEmpty)
        #expect(fixture.metadata.value.lastObservedRemoteDigest == "remote-old")
    }

    @Test("remote-only change merges locally when unlocked")
    func remoteChangeMergesWhenUnlocked() throws {
        let local = Data("local".utf8)
        let remote = Data("remote-new".utf8)
        let merged = Data("merged-local".utf8)
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.lastSyncedLocalDigest = PasswordVaultDigest.hex(local)
        metadata.lastObservedRemoteDigest = "remote-old"
        metadata.conflictCopyCount = 2
        let fixture = try makeSyncServiceFixture(metadata: metadata, localData: local)
        fixture.access.state = .unlocked
        fixture.access.mergeApplication = PasswordVaultMergeApplication(
            encryptedSnapshot: PasswordVaultEncryptedSnapshot(
                data: merged,
                digest: PasswordVaultDigest.hex(merged)
            ),
            conflictCopyCount: 1
        )
        fixture.cloud.snapshot = PasswordVaultCloudSnapshot(
            data: remote,
            digest: PasswordVaultDigest.hex(remote)
        )

        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.access.mergeCount == 1)
        #expect(fixture.cloud.writes.isEmpty)
        #expect(fixture.metadata.value.lastSyncedLocalDigest == PasswordVaultDigest.hex(merged))
        #expect(fixture.metadata.value.lastObservedRemoteDigest == PasswordVaultDigest.hex(remote))
        #expect(fixture.metadata.value.conflictCopyCount == 3)
        #expect(fixture.service.snapshot.phase == .conflicts(3))
    }
}

extension PasswordVaultSyncServiceTests {
    @Test("remote credential retry passes the password to one merge only")
    func remoteCredentialRetryIsOneShot() throws {
        let local = Data("local-new".utf8)
        let remote = Data("remote-new".utf8)
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.lastSyncedLocalDigest = "local-old"
        metadata.lastObservedRemoteDigest = "remote-old"
        let fixture = try makeSyncServiceFixture(metadata: metadata, localData: local)
        fixture.access.state = .unlocked
        fixture.cloud.snapshot = PasswordVaultCloudSnapshot(
            data: remote,
            digest: PasswordVaultDigest.hex(remote)
        )
        var result: Result<Void, PasswordVaultSyncFailure>?

        fixture.service.retry(remoteMasterPassword: "remote-only-secret") { result = $0 }
        fixture.drain()

        #expect(try result?.get() != nil)
        #expect(fixture.access.receivedRemotePasswords == ["remote-only-secret"])

        fixture.service.synchronize(reason: .manual)
        fixture.drain()
        #expect(fixture.access.receivedRemotePasswords == ["remote-only-secret"])
    }

    @Test("concurrent changes stay untouched while the local vault is locked")
    func concurrentChangesWaitForUnlock() throws {
        let local = Data("local-new".utf8)
        let remote = Data("remote-new".utf8)
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.localRevision = 2
        metadata.lastSyncedLocalRevision = 1
        metadata.lastSyncedLocalDigest = "local-old"
        metadata.lastObservedRemoteDigest = "remote-old"
        metadata.pendingChangeCount = 1
        let fixture = try makeSyncServiceFixture(metadata: metadata, localData: local)
        fixture.access.state = .locked
        fixture.cloud.snapshot = PasswordVaultCloudSnapshot(
            data: remote,
            digest: PasswordVaultDigest.hex(remote)
        )

        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.service.snapshot.phase == .waitingForUnlock)
        #expect(fixture.access.mergeCount == 0)
        #expect(fixture.cloud.writes.isEmpty)
        #expect(fixture.metadata.value.pendingChangeCount == 1)
        #expect(fixture.metadata.value.lastSyncedLocalDigest == "local-old")
        #expect(fixture.metadata.value.lastObservedRemoteDigest == "remote-old")
    }

    @Test("remote credentials failure preserves the unlocked local replica and pending work")
    func remoteCredentialsFailurePreservesLocalState() throws {
        let local = Data("local-new".utf8)
        let remote = Data("remote-new".utf8)
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.localRevision = 2
        metadata.lastSyncedLocalRevision = 1
        metadata.lastSyncedLocalDigest = "local-old"
        metadata.lastObservedRemoteDigest = "remote-old"
        metadata.pendingChangeCount = 1
        let fixture = try makeSyncServiceFixture(metadata: metadata, localData: local)
        fixture.access.state = .unlocked
        fixture.access.mergeError = PasswordVaultSyncFailure.remoteCredentialsRequired
        fixture.cloud.snapshot = PasswordVaultCloudSnapshot(
            data: remote,
            digest: PasswordVaultDigest.hex(remote)
        )

        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.service.snapshot.phase == .failed(.remoteCredentialsRequired))
        #expect(fixture.access.state == .unlocked)
        #expect(fixture.cloud.writes.isEmpty)
        #expect(fixture.metadata.value.pendingChangeCount == 1)
        #expect(fixture.metadata.value.lastSyncedLocalDigest == "local-old")
        #expect(fixture.metadata.value.lastObservedRemoteDigest == "remote-old")
    }

    @Test("enabling sync passes remote credentials only to the current merge")
    func enablingSyncPassesTransientRemoteCredentials() throws {
        let local = Data("local-new".utf8)
        let remote = Data("remote-new".utf8)
        let merged = Data("merged".utf8)
        let fixture = try makeSyncServiceFixture(localData: local)
        fixture.access.state = .unlocked
        fixture.access.mergeApplication = PasswordVaultMergeApplication(
            encryptedSnapshot: PasswordVaultEncryptedSnapshot(
                data: merged,
                digest: PasswordVaultDigest.hex(merged)
            ),
            conflictCopyCount: 0
        )
        fixture.cloud.snapshot = PasswordVaultCloudSnapshot(
            data: remote,
            digest: PasswordVaultDigest.hex(remote)
        )
        var completed = false

        fixture.service.enableOneDrive(
            rootURL: try #require(fixture.root.url),
            remoteMasterPassword: "ephemeral-remote-secret"
        ) { result in
            if case .success = result { completed = true }
        }
        fixture.drain()

        #expect(completed)
        #expect(fixture.access.receivedRemotePasswords.count == 1)
        #expect(fixture.access.receivedRemotePasswords[0] == "ephemeral-remote-secret")
        #expect(fixture.metadata.value.mode == .oneDrive)
        #expect(fixture.metadata.value.pendingChangeCount == 0)
    }

    @Test("cloud failure persists the merge marker and retries without merging twice")
    func mergeUploadFailureRetriesIdempotently() throws {
        let local = Data("local-new".utf8)
        let remote = Data("remote-new".utf8)
        let merged = Data("merged".utf8)
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.localRevision = 2
        metadata.lastSyncedLocalRevision = 1
        metadata.lastSyncedLocalDigest = "local-old"
        metadata.lastObservedRemoteDigest = "remote-old"
        metadata.pendingChangeCount = 1
        let fixture = try makeSyncServiceFixture(metadata: metadata, localData: local)
        fixture.access.state = .unlocked
        fixture.access.mergeApplication = PasswordVaultMergeApplication(
            encryptedSnapshot: PasswordVaultEncryptedSnapshot(
                data: merged,
                digest: PasswordVaultDigest.hex(merged)
            ),
            conflictCopyCount: 1
        )
        fixture.cloud.snapshot = PasswordVaultCloudSnapshot(
            data: remote,
            digest: PasswordVaultDigest.hex(remote)
        )
        fixture.cloud.writeError = .remoteVerificationFailed

        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.access.mergeCount == 1)
        #expect(fixture.cloud.writes.first?.expectation == .digest(PasswordVaultDigest.hex(remote)))
        #expect(fixture.metadata.value.pendingChangeCount >= 1)
        #expect(fixture.metadata.value.pendingMergedRemoteDigest == PasswordVaultDigest.hex(remote))
        #expect(fixture.metadata.value.conflictCopyCount == 1)
        #expect(fixture.metadata.value.lastSyncedLocalDigest == "local-old")
        #expect(fixture.metadata.value.lastObservedRemoteDigest == "remote-old")
        #expect(fixture.service.snapshot.phase == .failed(.remoteVerificationFailed))

        fixture.service.record(PasswordVaultCommit(
            origin: .syncMerge,
            encryptedDigest: PasswordVaultDigest.hex(merged)
        ))
        fixture.drain()
        #expect(fixture.metadata.value.lastSyncedLocalDigest == "local-old")

        fixture.cloud.writeError = nil
        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.access.mergeCount == 1)
        #expect(fixture.cloud.writes.count == 2)
        #expect(fixture.metadata.value.pendingMergedRemoteDigest == nil)
        #expect(fixture.metadata.value.pendingChangeCount == 0)
        #expect(fixture.metadata.value.lastSyncedLocalDigest == PasswordVaultDigest.hex(merged))
        #expect(fixture.metadata.value.lastObservedRemoteDigest == PasswordVaultDigest.hex(merged))
        #expect(fixture.metadata.value.conflictCopyCount == 1)
        #expect(fixture.service.snapshot.phase == .conflicts(1))
    }

    @Test("a newer remote digest after upload failure is merged before retrying")
    func changedRemoteAfterFailureIsMergedAgain() throws {
        let local = Data("local-new".utf8)
        let firstRemote = Data("remote-one".utf8)
        let secondRemote = Data("remote-two".utf8)
        let firstMerge = Data("merged-one".utf8)
        let secondMerge = Data("merged-two".utf8)
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.localRevision = 2
        metadata.lastSyncedLocalRevision = 1
        metadata.lastSyncedLocalDigest = "local-old"
        metadata.lastObservedRemoteDigest = "remote-old"
        metadata.pendingChangeCount = 1
        let fixture = try makeSyncServiceFixture(metadata: metadata, localData: local)
        fixture.access.state = .unlocked
        fixture.access.mergeApplication = PasswordVaultMergeApplication(
            encryptedSnapshot: PasswordVaultEncryptedSnapshot(
                data: firstMerge,
                digest: PasswordVaultDigest.hex(firstMerge)
            ),
            conflictCopyCount: 0
        )
        fixture.cloud.snapshot = PasswordVaultCloudSnapshot(
            data: firstRemote,
            digest: PasswordVaultDigest.hex(firstRemote)
        )
        fixture.cloud.writeError = .remoteVerificationFailed

        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        fixture.cloud.snapshot = PasswordVaultCloudSnapshot(
            data: secondRemote,
            digest: PasswordVaultDigest.hex(secondRemote)
        )
        fixture.cloud.writeError = nil
        fixture.access.mergeApplication = PasswordVaultMergeApplication(
            encryptedSnapshot: PasswordVaultEncryptedSnapshot(
                data: secondMerge,
                digest: PasswordVaultDigest.hex(secondMerge)
            ),
            conflictCopyCount: 0
        )
        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.access.mergeCount == 2)
        #expect(fixture.cloud.writes.count == 2)
        #expect(fixture.cloud.writes.last?.expectation == .digest(PasswordVaultDigest.hex(secondRemote)))
        #expect(fixture.metadata.value.pendingMergedRemoteDigest == nil)
        #expect(fixture.metadata.value.lastSyncedLocalDigest == PasswordVaultDigest.hex(secondMerge))
    }

    @Test("observer delivery uses the main thread by default")
    func observersUseMainThread() async throws {
        let fixture = try makeSyncServiceFixture(callbackDispatcher: nil)
        let deliveredOnMain = await withCheckedContinuation { continuation in
            _ = fixture.service.addObserver { _ in
                continuation.resume(returning: Thread.isMainThread)
            }
        }
        #expect(deliveredOnMain)
    }
}

extension PasswordVaultSyncServiceTests {
    @Test("pending forced reset archives remote before replacing active")
    func forcedResetArchivesBeforeActiveReplacement() throws {
        let oldRemoteData = Data("old-remote".utf8)
        let newLocalData = Data("new-local".utf8)
        let fixture = try makePendingForcedResetFixture(
            localData: newLocalData,
            remoteData: oldRemoteData
        )

        fixture.service.synchronize(reason: .localChange)
        fixture.drain()

        #expect(fixture.cloud.operations.map(\.kind) == [.archiveWrite, .activeWrite])
        #expect(fixture.cloud.archiveSnapshot?.data == oldRemoteData)
        #expect(fixture.cloud.snapshot?.data == newLocalData)
        #expect(fixture.metadata.value.pendingForcedReset == nil)
        #expect(fixture.metadata.value.lastSyncedLocalDigest == PasswordVaultDigest.hex(newLocalData))
        #expect(fixture.metadata.value.lastObservedRemoteDigest == PasswordVaultDigest.hex(newLocalData))
        #expect(fixture.access.mergeCount == 0)
    }

    @Test("offline forced reset stays pending and never merges")
    func offlineForcedResetPausesSync() throws {
        let fixture = try makePendingForcedResetFixture()
        fixture.processStatus.status = .notRunning(appURL: fixture.oneDriveAppURL)

        fixture.service.synchronize(reason: .localChange)
        fixture.drain()

        #expect(fixture.metadata.value.pendingForcedReset != nil)
        #expect(fixture.service.snapshot.phase == .pendingForcedReset(.oneDriveNotRunning))
        #expect(fixture.cloud.operations.isEmpty)
        #expect(fixture.access.mergeCount == 0)
    }

    @Test("forced reset with an absent remote uploads active without creating an archive")
    func forcedResetWithAbsentRemoteSkipsArchive() throws {
        let newLocalData = Data("new-local".utf8)
        let fixture = try makePendingForcedResetFixture(
            localData: newLocalData,
            remoteData: nil
        )

        fixture.service.synchronize(reason: .localChange)
        fixture.drain()

        #expect(fixture.cloud.operations.map(\.kind) == [.activeWrite])
        #expect(fixture.cloud.writes.first?.expectation == .absent)
        #expect(fixture.cloud.archiveSnapshot == nil)
        #expect(fixture.cloud.snapshot?.data == newLocalData)
        #expect(fixture.metadata.value.pendingForcedReset == nil)
        #expect(fixture.access.mergeCount == 0)
    }

    @Test("retry after verified archive replaces only active")
    func verifiedArchiveIsNotRepeatedAfterActiveFailure() throws {
        let oldRemoteData = Data("old-remote".utf8)
        let newLocalData = Data("new-local".utf8)
        let fixture = try makePendingForcedResetFixture(
            localData: newLocalData,
            remoteData: oldRemoteData
        )
        fixture.cloud.writeError = .remoteWriteFailed

        fixture.service.synchronize(reason: .localChange)
        fixture.drain()

        #expect(fixture.metadata.value.pendingForcedReset?.archivedRemoteDigest
            == PasswordVaultDigest.hex(oldRemoteData))
        #expect(fixture.metadata.value.pendingForcedReset?.remoteArchiveRequired == true)
        #expect(fixture.service.snapshot.phase == .pendingForcedReset(.remoteWriteFailed))
        #expect(fixture.access.mergeCount == 0)

        fixture.cloud.writeError = nil
        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.cloud.operations.map(\.kind) == [.archiveWrite, .activeWrite, .activeWrite])
        #expect(fixture.cloud.archiveWrites.count == 1)
        #expect(fixture.cloud.archiveSnapshot?.data == oldRemoteData)
        #expect(fixture.cloud.snapshot?.data == newLocalData)
        #expect(fixture.metadata.value.pendingForcedReset == nil)
        #expect(fixture.access.mergeCount == 0)
    }

    @Test("restart after active replacement finalizes only with recorded archive progress")
    func replacedActiveFinalizesAfterCrash() throws {
        let oldRemoteData = Data("old-remote".utf8)
        let newLocalData = Data("new-local".utf8)
        let fixture = try makePendingForcedResetFixture(
            localData: newLocalData,
            remoteData: oldRemoteData
        )
        fixture.cloud.postActiveWriteError = .remoteUnavailable

        fixture.service.synchronize(reason: .localChange)
        fixture.drain()

        #expect(fixture.cloud.snapshot?.data == newLocalData)
        #expect(fixture.metadata.value.pendingForcedReset?.archivedRemoteDigest
            == PasswordVaultDigest.hex(oldRemoteData))
        #expect(fixture.service.snapshot.phase == .pendingForcedReset(.remoteUnavailable))

        fixture.cloud.postActiveWriteError = nil
        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.cloud.operations.map(\.kind) == [.archiveWrite, .activeWrite])
        #expect(fixture.metadata.value.pendingForcedReset == nil)
        #expect(fixture.service.snapshot.phase == .synced)
        #expect(fixture.access.mergeCount == 0)
    }

    @Test("explicit retry after finalize save failure preserves the original archive")
    func explicitRetryAfterFinalizeSaveFailureOnlyFinalizes() throws {
        let oldRemoteData = Data("old-remote".utf8)
        let replacementData = Data("replacement".utf8)
        let fixture = try makePendingForcedResetFixture(
            localData: replacementData,
            remoteData: oldRemoteData
        )
        fixture.metadata.saveFailurePredicate = { $0.pendingForcedReset == nil }

        fixture.service.synchronize(reason: .localChange)
        fixture.drain()

        #expect(fixture.cloud.snapshot?.data == replacementData)
        #expect(fixture.cloud.archiveSnapshot?.data == oldRemoteData)
        #expect(fixture.metadata.value.pendingForcedReset != nil)
        #expect(fixture.service.snapshot.phase == .pendingForcedReset(.remoteWriteFailed))

        fixture.metadata.saveFailurePredicate = nil
        var retryResult: Result<Void, PasswordVaultSyncFailure>?
        fixture.service.retryForcedReset { retryResult = $0 }
        fixture.drain()

        #expect(try retryResult?.get() != nil)
        #expect(fixture.cloud.operations.map(\.kind) == [.archiveWrite, .activeWrite])
        #expect(fixture.cloud.archiveWrites.count == 1)
        #expect(fixture.cloud.archiveSnapshot?.data == oldRemoteData)
        #expect(fixture.cloud.snapshot?.data == replacementData)
        #expect(fixture.metadata.value.pendingForcedReset == nil)
        #expect(fixture.service.snapshot.phase == .synced)
        #expect(fixture.access.mergeCount == 0)
    }

    @Test("first observation equal to replacement cannot manufacture archive proof")
    func firstObservationEqualToReplacementFailsClosedWithoutOverwritingArchive() throws {
        let archivedOldRemoteData = Data("archived-old-remote".utf8)
        let replacementData = Data("replacement".utf8)
        let fixture = try makePendingForcedResetFixture(
            localData: replacementData,
            remoteData: replacementData
        )
        fixture.cloud.archiveSnapshot = PasswordVaultCloudSnapshot(
            data: archivedOldRemoteData,
            digest: PasswordVaultDigest.hex(archivedOldRemoteData)
        )

        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.metadata.value.pendingForcedReset != nil)
        #expect(fixture.metadata.value.pendingForcedReset?.remoteArchiveRequired == true)
        #expect(fixture.service.snapshot.phase == .pendingForcedReset(.remoteVerificationFailed))

        var retryResult: Result<Void, PasswordVaultSyncFailure>?
        fixture.service.retryForcedReset { retryResult = $0 }
        fixture.drain()

        #expect(throws: PasswordVaultSyncFailure.remoteVerificationFailed) {
            try retryResult?.get()
        }
        #expect(fixture.cloud.operations.isEmpty)
        #expect(fixture.cloud.archiveWrites.isEmpty)
        #expect(fixture.cloud.archiveSnapshot?.data == archivedOldRemoteData)
        #expect(fixture.cloud.snapshot?.data == replacementData)
        #expect(fixture.access.mergeCount == 0)
    }

    @Test("local edit after active replacement advances CAS without replacing the original archive")
    func localEditAfterFinalizeSaveFailureAdvancesActiveExpectation() throws {
        let oldRemoteData = Data("old-remote".utf8)
        let firstReplacement = Data("replacement-r1".utf8)
        let latestLocalData = Data("replacement-r2".utf8)
        let fixture = try makePendingForcedResetFixture(
            localData: firstReplacement,
            remoteData: oldRemoteData
        )
        fixture.metadata.saveFailurePredicate = { $0.pendingForcedReset == nil }

        fixture.service.synchronize(reason: .localChange)
        fixture.drain()

        #expect(fixture.cloud.snapshot?.data == firstReplacement)
        #expect(fixture.cloud.archiveSnapshot?.data == oldRemoteData)
        #expect(fixture.metadata.value.pendingForcedReset?.replacementLocalDigest
            == PasswordVaultDigest.hex(firstReplacement))

        fixture.metadata.saveFailurePredicate = nil
        fixture.access.data = latestLocalData
        fixture.service.record(
            PasswordVaultCommit(
                origin: .userMutation,
                encryptedDigest: PasswordVaultDigest.hex(latestLocalData)
            )
        )
        fixture.drain()
        fixture.cloud.postActiveWriteError = .remoteUnavailable
        fixture.service.synchronize(reason: .localChange)
        fixture.drain()

        #expect(fixture.cloud.snapshot?.data == latestLocalData)
        #expect(fixture.metadata.value.pendingForcedReset?.observedRemoteDigest
            == PasswordVaultDigest.hex(firstReplacement))
        #expect(fixture.metadata.value.pendingForcedReset?.replacementLocalDigest
            == PasswordVaultDigest.hex(latestLocalData))
        #expect(fixture.metadata.value.pendingForcedReset?.archivedRemoteDigest
            == PasswordVaultDigest.hex(oldRemoteData))

        fixture.cloud.postActiveWriteError = nil
        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.cloud.operations.map(\.kind) == [.archiveWrite, .activeWrite, .activeWrite])
        #expect(fixture.cloud.writes.last?.expectation
            == .digest(PasswordVaultDigest.hex(firstReplacement)))
        #expect(fixture.cloud.archiveWrites.count == 1)
        #expect(fixture.cloud.archiveSnapshot?.data == oldRemoteData)
        #expect(fixture.cloud.snapshot?.data == latestLocalData)
        #expect(fixture.metadata.value.lastSyncedLocalDigest == PasswordVaultDigest.hex(latestLocalData))
        #expect(fixture.metadata.value.pendingForcedReset == nil)
        #expect(fixture.access.mergeCount == 0)
    }

    @Test("absent remote proof survives R1 to R2 progress without touching an existing archive")
    func absentRemoteProofSurvivesReplacementAdvanceAndReadbackFailure() throws {
        let existingArchiveData = Data("precious-existing-archive".utf8)
        let firstReplacement = Data("replacement-r1".utf8)
        let latestLocalData = Data("replacement-r2".utf8)
        let fixture = try makePendingForcedResetFixture(
            localData: firstReplacement,
            remoteData: nil
        )
        fixture.cloud.archiveSnapshot = PasswordVaultCloudSnapshot(
            data: existingArchiveData,
            digest: PasswordVaultDigest.hex(existingArchiveData)
        )
        fixture.metadata.saveFailurePredicate = { $0.pendingForcedReset == nil }

        fixture.service.synchronize(reason: .localChange)
        fixture.drain()

        #expect(fixture.cloud.snapshot?.data == firstReplacement)
        #expect(fixture.cloud.archiveSnapshot?.data == existingArchiveData)
        #expect(fixture.cloud.archiveWrites.isEmpty)
        #expect(fixture.metadata.value.pendingForcedReset?.remoteArchiveRequired == false)

        fixture.metadata.saveFailurePredicate = nil
        fixture.access.data = latestLocalData
        fixture.service.record(
            PasswordVaultCommit(
                origin: .userMutation,
                encryptedDigest: PasswordVaultDigest.hex(latestLocalData)
            )
        )
        fixture.drain()
        fixture.cloud.postActiveWriteError = .remoteUnavailable
        fixture.service.synchronize(reason: .localChange)
        fixture.drain()

        #expect(fixture.cloud.snapshot?.data == latestLocalData)
        #expect(fixture.cloud.archiveSnapshot?.data == existingArchiveData)
        #expect(fixture.cloud.archiveWrites.isEmpty)
        #expect(fixture.metadata.value.pendingForcedReset?.remoteArchiveRequired == false)
        #expect(fixture.access.mergeCount == 0)

        fixture.cloud.postActiveWriteError = nil
        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.cloud.operations.map(\.kind) == [.activeWrite, .activeWrite])
        #expect(fixture.cloud.archiveSnapshot?.data == existingArchiveData)
        #expect(fixture.cloud.archiveWrites.isEmpty)
        #expect(fixture.cloud.snapshot?.data == latestLocalData)
        #expect(fixture.metadata.value.pendingForcedReset == nil)
        #expect(fixture.metadata.value.lastSyncedLocalDigest == PasswordVaultDigest.hex(latestLocalData))
        #expect(fixture.access.mergeCount == 0)
    }

    @Test("legacy inspected reset without archive requirement fails closed")
    func unknownLegacyArchiveRequirementCannotWriteRemote() throws {
        let oldRemoteData = Data("old-remote".utf8)
        let replacementData = Data("replacement".utf8)
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.pendingForcedReset = PasswordVaultPendingForcedReset(
            previousLocalDigest: "previous-local",
            replacementLocalDigest: PasswordVaultDigest.hex(replacementData),
            didInspectRemote: true,
            observedRemoteDigest: PasswordVaultDigest.hex(oldRemoteData),
            archivedRemoteDigest: PasswordVaultDigest.hex(oldRemoteData),
            remoteArchiveRequired: nil
        )
        let fixture = try makeSyncServiceFixture(metadata: metadata, localData: replacementData)
        fixture.cloud.snapshot = PasswordVaultCloudSnapshot(
            data: oldRemoteData,
            digest: PasswordVaultDigest.hex(oldRemoteData)
        )

        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.metadata.value.pendingForcedReset?.remoteArchiveRequired == nil)
        #expect(fixture.service.snapshot.phase == .pendingForcedReset(.remoteVerificationFailed))

        var retryResult: Result<Void, PasswordVaultSyncFailure>?
        fixture.service.retryForcedReset { retryResult = $0 }
        fixture.drain()

        #expect(throws: PasswordVaultSyncFailure.remoteVerificationFailed) {
            try retryResult?.get()
        }
        #expect(fixture.cloud.operations.isEmpty)
        #expect(fixture.access.mergeCount == 0)
    }

    @Test("an unrecorded archive never authorizes finalizing an already replaced active")
    func missingArchiveProgressKeepsReplacementPending() throws {
        let oldRemoteData = Data("old-remote".utf8)
        let newLocalData = Data("new-local".utf8)
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.pendingForcedReset = PasswordVaultPendingForcedReset(
            previousLocalDigest: "previous-local",
            replacementLocalDigest: PasswordVaultDigest.hex(newLocalData),
            didInspectRemote: true,
            observedRemoteDigest: PasswordVaultDigest.hex(oldRemoteData),
            archivedRemoteDigest: nil,
            remoteArchiveRequired: true
        )
        let fixture = try makeSyncServiceFixture(metadata: metadata, localData: newLocalData)
        fixture.cloud.snapshot = PasswordVaultCloudSnapshot(
            data: newLocalData,
            digest: PasswordVaultDigest.hex(newLocalData)
        )

        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.metadata.value.pendingForcedReset != nil)
        #expect(fixture.service.snapshot.phase == .pendingForcedReset(.remoteVerificationFailed))
        #expect(fixture.cloud.operations.isEmpty)
        #expect(fixture.access.mergeCount == 0)
    }

    @Test("remote CAS race preserves the changed active and requires explicit retry")
    func remoteCASRacePreservesChangedActiveUntilExplicitRetry() throws {
        let oldRemoteData = Data("old-remote".utf8)
        let racedRemoteData = Data("raced-remote".utf8)
        let newLocalData = Data("new-local".utf8)
        let fixture = try makePendingForcedResetFixture(
            localData: newLocalData,
            remoteData: oldRemoteData
        )
        fixture.cloud.activeSnapshotBeforeNextWrite = PasswordVaultCloudSnapshot(
            data: racedRemoteData,
            digest: PasswordVaultDigest.hex(racedRemoteData)
        )

        fixture.service.synchronize(reason: .localChange)
        fixture.drain()

        #expect(fixture.cloud.snapshot?.data == racedRemoteData)
        #expect(fixture.metadata.value.pendingForcedReset != nil)
        #expect(fixture.service.snapshot.phase == .pendingForcedReset(.remoteVerificationFailed))
        #expect(fixture.access.mergeCount == 0)

        fixture.service.synchronize(reason: .manual)
        fixture.drain()
        #expect(fixture.cloud.archiveWrites.count == 1)
        #expect(fixture.cloud.snapshot?.data == racedRemoteData)

        var retryResult: Result<Void, PasswordVaultSyncFailure>?
        fixture.service.retryForcedReset { retryResult = $0 }
        fixture.drain()

        #expect(try retryResult?.get() != nil)
        #expect(fixture.metadata.savedValues.contains {
            $0.pendingForcedReset?.observedRemoteDigest == PasswordVaultDigest.hex(racedRemoteData)
                && $0.pendingForcedReset?.remoteArchiveRequired == true
        })
        #expect(fixture.cloud.archiveWrites.count == 2)
        #expect(fixture.cloud.archiveSnapshot?.data == racedRemoteData)
        #expect(fixture.cloud.snapshot?.data == newLocalData)
        #expect(fixture.metadata.value.pendingForcedReset == nil)
        #expect(fixture.access.mergeCount == 0)
    }

    @Test("local edits while forced reset is pending upload the latest local snapshot")
    func pendingForcedResetUploadsLatestLocalSnapshot() throws {
        let oldRemoteData = Data("old-remote".utf8)
        let initialReplacement = Data("initial-replacement".utf8)
        let latestLocalData = Data("latest-local-edit".utf8)
        let fixture = try makePendingForcedResetFixture(
            localData: initialReplacement,
            remoteData: oldRemoteData
        )
        fixture.cloud.writeError = .remoteWriteFailed
        fixture.service.synchronize(reason: .localChange)
        fixture.drain()

        fixture.access.data = latestLocalData
        fixture.service.record(
            PasswordVaultCommit(
                origin: .userMutation,
                encryptedDigest: PasswordVaultDigest.hex(latestLocalData)
            )
        )
        fixture.cloud.writeError = nil
        fixture.service.synchronize(reason: .localChange)
        fixture.drain()

        #expect(fixture.cloud.archiveWrites.count == 1)
        #expect(fixture.cloud.snapshot?.data == latestLocalData)
        #expect(fixture.metadata.value.lastSyncedLocalDigest == PasswordVaultDigest.hex(latestLocalData))
        #expect(fixture.metadata.value.pendingChangeCount == 0)
        #expect(fixture.metadata.value.pendingForcedReset == nil)
        #expect(fixture.access.mergeCount == 0)
    }

    @Test("repeated forced reset keeps one latest remote archive")
    func repeatedForcedResetKeepsSingleRemoteArchive() throws {
        let firstRemoteData = Data("first-remote".utf8)
        let firstReplacement = Data("first-replacement".utf8)
        let secondReplacement = Data("second-replacement".utf8)
        let fixture = try makePendingForcedResetFixture(
            localData: firstReplacement,
            remoteData: firstRemoteData
        )

        fixture.service.synchronize(reason: .localChange)
        fixture.drain()
        try fixture.service.prepareForcedReset(
            previousLocalDigest: PasswordVaultDigest.hex(firstReplacement)
        )
        fixture.access.data = secondReplacement
        fixture.service.record(
            PasswordVaultCommit(
                origin: .forcedReset,
                encryptedDigest: PasswordVaultDigest.hex(secondReplacement)
            )
        )
        fixture.service.synchronize(reason: .localChange)
        fixture.drain()

        #expect(fixture.cloud.archiveWrites.count == 2)
        #expect(fixture.cloud.archiveSnapshot?.data == firstReplacement)
        #expect(fixture.cloud.snapshot?.data == secondReplacement)
        #expect(fixture.metadata.value.pendingForcedReset == nil)
        #expect(fixture.access.mergeCount == 0)
    }
}

// swiftlint:enable file_length
