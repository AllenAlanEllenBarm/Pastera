import Foundation
import Testing
@testable import Pastera

@Suite("Password vault sync service", .serialized)
struct PasswordVaultSyncServiceTests {
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
        let fixture = try makeSyncServiceFixture(metadata: metadata, localData: local)
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

        fixture.service.synchronize(reason: .manual)
        fixture.drain()

        #expect(fixture.access.mergeCount == 1)
        #expect(fixture.cloud.writes.isEmpty)
        #expect(fixture.metadata.value.lastSyncedLocalDigest == PasswordVaultDigest.hex(merged))
        #expect(fixture.metadata.value.lastObservedRemoteDigest == PasswordVaultDigest.hex(remote))
        #expect(fixture.service.snapshot.phase == .synced)
    }

    @Test("cloud verification failure preserves pending work and both old baselines")
    func mergeUploadFailureKeepsPendingWork() throws {
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
        #expect(fixture.metadata.value.lastSyncedLocalDigest == "local-old")
        #expect(fixture.metadata.value.lastObservedRemoteDigest == "remote-old")
        #expect(fixture.service.snapshot.phase == .failed(.remoteVerificationFailed))
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
