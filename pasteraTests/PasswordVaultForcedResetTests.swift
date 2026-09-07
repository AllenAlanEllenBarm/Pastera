import Foundation
import KDBXKit
import LocalAuthentication
import Testing
@testable import Pastera

// swiftlint:disable file_length

@Suite("Password vault forced reset")
// swiftlint:disable:next type_body_length
struct PasswordVaultForcedResetTests {
    @Test("forced reset archives the old encrypted vault and creates an empty new vault")
    func forcedResetArchivesAndCreatesEmptyVault() throws {
        let fixture = try ForcedResetFixture()
        defer { fixture.remove() }
        try fixture.addEntry(title: "Old Entry")
        let oldBytes = try Data(contentsOf: fixture.activeURL)

        let result = try fixture.store.forceReset(
            newPassword: fixture.newPassword,
            rememberSystemUnlock: true
        )
        let newBytes = try Data(contentsOf: fixture.activeURL)

        #expect(try Data(contentsOf: fixture.archiveURL) == oldBytes)
        #expect(result.localArchiveDigest == PasswordVaultDigest.hex(oldBytes))
        #expect(result.encryptedSnapshot.data == newBytes)
        #expect(result.encryptedSnapshot.digest == PasswordVaultDigest.hex(result.encryptedSnapshot.data))
        #expect(try fixture.store.listEntries().isEmpty)
        #expect(fixture.canOpen(fixture.archiveURL, password: fixture.oldPassword))
        #expect(fixture.canOpen(fixture.activeURL, password: fixture.newPassword))
        #expect(fixture.quickKey.data?.count == 32)
        #expect(fixture.commits.map(\.origin) == [.forcedReset])
        #expect(!FileManager.default.fileExists(
            atPath: fixture.localStorage.paths.forcedResetRecoveryMarkerURL.path
        ))
    }

    @Test("a second forced reset replaces the only archive")
    func repeatedForcedResetKeepsOneLatestArchive() throws {
        let fixture = try ForcedResetFixture()
        defer { fixture.remove() }
        _ = try fixture.store.forceReset(newPassword: fixture.newPassword, rememberSystemUnlock: false)
        let secondPreResetBytes = try Data(contentsOf: fixture.activeURL)

        _ = try fixture.store.forceReset(newPassword: fixture.thirdPassword, rememberSystemUnlock: false)

        let archivePaths = try fixture.archiveFiles().map { $0.resolvingSymlinksInPath().path }
        #expect(archivePaths == [fixture.archiveURL.resolvingSymlinksInPath().path])
        #expect(try Data(contentsOf: fixture.archiveURL) == secondPreResetBytes)
        #expect(!fixture.quickKey.containsKey)
    }

    @Test(
        "every pre-commit checkpoint restores the active vault and prior archive",
        arguments: ForcedResetFault.allCases
    )
    fileprivate func checkpointFailureRollsBackActiveAndPriorArchive(fault: ForcedResetFault) throws {
        var injected = false
        let transaction = VaultForcedResetTransaction { checkpoint in
            guard !injected, fault.matches(checkpoint) else { return }
            injected = true
            throw PasswordVaultError.saveFailed
        }
        let fixture = try ForcedResetFixture(transaction: transaction)
        defer { fixture.remove() }
        let priorArchiveBytes = try fixture.installPriorArchive()
        try fixture.addEntry(title: "Current generation")
        let activeBytes = try Data(contentsOf: fixture.activeURL)

        #expect(throws: PasswordVaultError.saveFailed) {
            try fixture.store.forceReset(
                newPassword: fixture.newPassword,
                rememberSystemUnlock: false
            )
        }

        #expect(injected)
        #expect(try Data(contentsOf: fixture.activeURL) == activeBytes)
        #expect(try Data(contentsOf: fixture.archiveURL) == priorArchiveBytes)
        #expect(fixture.forcedResetTemporaryFiles().isEmpty)
        #expect(try fixture.store.listEntries().map(\.title) == ["Current generation"])
        #expect(fixture.canOpen(fixture.activeURL, password: fixture.oldPassword))
        #expect(!FileManager.default.fileExists(
            atPath: fixture.localStorage.paths.forcedResetRecoveryMarkerURL.path
        ))
    }

    @Test("empty new password is rejected before credentials or files change")
    func emptyNewPasswordDoesNotMutateState() throws {
        let fixture = try ForcedResetFixture()
        defer { fixture.remove() }
        try fixture.store.enableAutomationUnlock()
        let activeBytes = try Data(contentsOf: fixture.activeURL)

        #expect(throws: PasswordVaultError.invalidPassword) {
            try fixture.store.forceReset(newPassword: "", rememberSystemUnlock: false)
        }

        #expect(try Data(contentsOf: fixture.activeURL) == activeBytes)
        #expect(fixture.automationKey.containsKey)
        #expect(!FileManager.default.fileExists(atPath: fixture.archiveURL.path))
    }

    @Test("a corrupted active vault is rejected without replacing a prior archive")
    func corruptedActiveVaultDoesNotMutateArchive() throws {
        let fixture = try ForcedResetFixture()
        defer { fixture.remove() }
        let priorArchiveBytes = try fixture.installPriorArchive()
        let corrupted = Data("not a KDBX vault".utf8)
        try corrupted.write(to: fixture.activeURL, options: .atomic)

        #expect(throws: PasswordVaultError.corruptedData) {
            try fixture.store.forceReset(
                newPassword: fixture.newPassword,
                rememberSystemUnlock: false
            )
        }

        #expect(try Data(contentsOf: fixture.activeURL) == corrupted)
        #expect(try Data(contentsOf: fixture.archiveURL) == priorArchiveBytes)
        #expect(fixture.forcedResetTemporaryFiles().isEmpty)
    }

    @Test("automation unlock deletion failure aborts before vault bytes change")
    func automationUnlockDeleteFailureAbortsBeforeMutation() throws {
        let fixture = try ForcedResetFixture()
        defer { fixture.remove() }
        try fixture.store.enableAutomationUnlock()
        fixture.automationKey.deleteError = .keychainUnavailable
        let activeBytes = try Data(contentsOf: fixture.activeURL)

        #expect(throws: PasswordVaultError.keychainUnavailable) {
            try fixture.store.forceReset(
                newPassword: fixture.newPassword,
                rememberSystemUnlock: false
            )
        }

        #expect(try Data(contentsOf: fixture.activeURL) == activeBytes)
        #expect(!FileManager.default.fileExists(atPath: fixture.archiveURL.path))
        #expect(fixture.automationKey.containsKey)
    }

    @Test("committed rollback cleanup failure leaves only new ciphertext outside the latest archive")
    func committedCleanupFailureSanitizesRollback() throws {
        let fileOperator = FaultingForcedResetFileOperator()
        fileOperator.failRollbackRemoval = true
        let transaction = VaultForcedResetTransaction(fileOperator: fileOperator)
        let fixture = try ForcedResetFixture(transaction: transaction)
        defer { fixture.remove() }
        try fixture.addEntry(title: "Old Entry")

        let result = try fixture.store.forceReset(
            newPassword: fixture.newPassword,
            rememberSystemUnlock: false
        )

        #expect(result.warnings == [.resetArtifactCleanupPending])
        let rollbackFiles = fixture.forcedResetTemporaryFiles().filter { $0.pathExtension == "rollback" }
        #expect(!rollbackFiles.isEmpty)
        for rollbackURL in rollbackFiles {
            #expect(try Data(contentsOf: rollbackURL) == result.encryptedSnapshot.data)
            #expect(fixture.canOpen(rollbackURL, password: fixture.newPassword))
            #expect(!fixture.canOpen(rollbackURL, password: fixture.oldPassword))
        }
        #expect(fixture.canOpen(fixture.archiveURL, password: fixture.oldPassword))
    }

    @Test("an active change at the final replacement checkpoint is preserved as an external conflict")
    func finalRevisionCheckProtectsConcurrentActiveChange() throws {
        var activeURL: URL?
        var externalBytes = Data()
        let transaction = VaultForcedResetTransaction { checkpoint in
            guard checkpoint == .activeReplace, let activeURL else { return }
            try externalBytes.write(to: activeURL, options: .atomic)
        }
        let fixture = try ForcedResetFixture(transaction: transaction)
        defer { fixture.remove() }
        externalBytes = try Data(contentsOf: fixture.activeURL)
        let priorArchiveBytes = try fixture.installPriorArchive()
        try fixture.addEntry(title: "Current generation")
        activeURL = fixture.activeURL

        #expect(throws: PasswordVaultError.externalConflict) {
            try fixture.store.forceReset(
                newPassword: fixture.newPassword,
                rememberSystemUnlock: false
            )
        }

        #expect(try Data(contentsOf: fixture.activeURL) == externalBytes)
        #expect(try Data(contentsOf: fixture.archiveURL) == priorArchiveBytes)
        #expect(fixture.forcedResetTemporaryFiles().isEmpty)
        #expect(fixture.commits.isEmpty)
    }

    @Test(
        "a rename failure after moving rollback material restores active and archive",
        arguments: ForcedResetRenameFault.restorableCases
    )
    fileprivate func halfCompletedRenameRollsBack(fault: ForcedResetRenameFault) throws {
        let fileOperator = FaultingForcedResetFileOperator()
        fileOperator.renameFault = fault
        let fixture = try ForcedResetFixture(
            transaction: VaultForcedResetTransaction(fileOperator: fileOperator)
        )
        defer { fixture.remove() }
        let priorArchiveBytes = try fixture.installPriorArchive()
        try fixture.addEntry(title: "Current generation")
        let activeBytes = try Data(contentsOf: fixture.activeURL)

        #expect(throws: PasswordVaultError.saveFailed) {
            try fixture.store.forceReset(
                newPassword: fixture.newPassword,
                rememberSystemUnlock: false
            )
        }

        #expect(try Data(contentsOf: fixture.activeURL) == activeBytes)
        #expect(try Data(contentsOf: fixture.archiveURL) == priorArchiveBytes)
        #expect(fixture.forcedResetTemporaryFiles().isEmpty)
    }

    @Test(
        "real staging write and readback failures leave no partial reset artifacts",
        arguments: ForcedResetPreCommitIOFault.allCases
    )
    fileprivate func stagingIOFailureRollsBack(fault: ForcedResetPreCommitIOFault) throws {
        let fileOperator = FaultingForcedResetFileOperator()
        fileOperator.preCommitIOFault = fault
        let fixture = try ForcedResetFixture(
            transaction: VaultForcedResetTransaction(fileOperator: fileOperator)
        )
        defer { fixture.remove() }
        let priorArchiveBytes = try fixture.installPriorArchive()
        try fixture.addEntry(title: "Current generation")
        let activeBytes = try Data(contentsOf: fixture.activeURL)

        #expect(throws: PasswordVaultError.saveFailed) {
            try fixture.store.forceReset(
                newPassword: fixture.newPassword,
                rememberSystemUnlock: false
            )
        }

        #expect(try Data(contentsOf: fixture.activeURL) == activeBytes)
        #expect(try Data(contentsOf: fixture.archiveURL) == priorArchiveBytes)
        #expect(fixture.forcedResetTemporaryFiles().isEmpty)
        #expect(fixture.commits.isEmpty)
    }

    @Test("rollback restores archive even when active restoration fails")
    func rollbackRestoresBothTargetsBestEffort() throws {
        let fileOperator = FaultingForcedResetFileOperator()
        fileOperator.renameFault = .activeInstallAndRestore
        let fixture = try ForcedResetFixture(
            transaction: VaultForcedResetTransaction(fileOperator: fileOperator)
        )
        defer { fixture.remove() }
        let priorArchiveBytes = try fixture.installPriorArchive()
        try fixture.addEntry(title: "Current generation")
        let activeBytes = try Data(contentsOf: fixture.activeURL)

        #expect(throws: PasswordVaultForcedResetError.recoveryRequired) {
            try fixture.store.forceReset(
                newPassword: fixture.newPassword,
                rememberSystemUnlock: false
            )
        }

        #expect(try Data(contentsOf: fixture.archiveURL) == priorArchiveBytes)
        #expect(fixture.store.state == .recoveryRequired("forced-reset-cleanup"))
        let activeRollback = try #require(
            fixture.forcedResetTemporaryFiles().first { $0.lastPathComponent.contains("active.rollback") }
        )
        #expect(try Data(contentsOf: activeRollback) == activeBytes)
    }

    @Test("an installed new active with failed verification and failed rollback requires recovery")
    func committedActiveVerificationAndRollbackFailureRequiresRecovery() throws {
        let fileOperator = FaultingForcedResetFileOperator()
        fileOperator.failCommittedActiveReadback = true
        fileOperator.failActiveRollbackRestore = true
        let fixture = try ForcedResetFixture(
            transaction: VaultForcedResetTransaction(fileOperator: fileOperator)
        )
        defer { fixture.remove() }
        try fixture.addEntry(title: "Current generation")
        let oldBytes = try Data(contentsOf: fixture.activeURL)

        #expect(throws: PasswordVaultForcedResetError.recoveryRequired) {
            try fixture.store.forceReset(
                newPassword: fixture.newPassword,
                rememberSystemUnlock: false
            )
        }

        let activeRollback = try #require(
            fixture.forcedResetTemporaryFiles().first { $0.lastPathComponent.contains("active.rollback") }
        )
        #expect(try Data(contentsOf: activeRollback) == oldBytes)
        #expect(fixture.canOpen(fixture.activeURL, password: fixture.newPassword))
        #expect(!fixture.canOpen(fixture.activeURL, password: fixture.oldPassword))
        #expect(fixture.store.state == .recoveryRequired("forced-reset-cleanup"))
        #expect(fixture.commits.isEmpty)
        #expect(FileManager.default.fileExists(
            atPath: fixture.localStorage.paths.forcedResetRecoveryMarkerURL.path
        ))
        #expect(throws: PasswordVaultError.vaultLocked) {
            try fixture.store.listEntries()
        }
    }

    @Test("committed marker readback failure keeps verified bytes recoverable")
    func committedMarkerReadbackFailureKeepsVerifiedBytesRecoverable() throws {
        let fileOperator = FaultingForcedResetFileOperator()
        fileOperator.failCommittedRecoveryMarkerReadback = true
        fileOperator.failRecoveryMarkerRemoval = true
        let transaction = VaultForcedResetTransaction(fileOperator: fileOperator)
        let fixture = try ForcedResetFixture(transaction: transaction)
        defer { fixture.remove() }
        _ = try fixture.installPriorArchive()
        try fixture.addEntry(title: "Current generation")
        let oldActive = try Data(contentsOf: fixture.activeURL)

        #expect(throws: PasswordVaultForcedResetError.recoveryRequired) {
            try fixture.store.forceReset(
                newPassword: fixture.newPassword,
                rememberSystemUnlock: false
            )
        }

        #expect(fixture.store.state == .recoveryRequired("forced-reset-cleanup"))
        #expect(fixture.canOpen(fixture.activeURL, password: fixture.newPassword))
        #expect(try Data(contentsOf: fixture.archiveURL) == oldActive)
        let markerURL = fixture.localStorage.paths.forcedResetRecoveryMarkerURL
        let record = try JSONDecoder().decode(
            VaultForcedResetRecoveryRecord.self,
            from: Data(contentsOf: markerURL)
        )
        #expect(record.phase == .committed)

        fileOperator.failCommittedRecoveryMarkerReadback = false
        fileOperator.failRecoveryMarkerRemoval = false
        let rebuiltStore = KDBXPasswordVaultStore(
            localStorage: fixture.localStorage,
            unlockKeyStore: fixture.quickKey,
            automationUnlockKeyStore: fixture.automationKey,
            forcedResetTransaction: transaction
        )

        #expect(rebuiltStore.state == .locked)
        #expect(fixture.canOpen(fixture.activeURL, password: fixture.newPassword))
        #expect(try Data(contentsOf: fixture.archiveURL) == oldActive)
        #expect(!FileManager.default.fileExists(atPath: markerURL.path))
        #expect(fixture.forcedResetTemporaryFiles().isEmpty)
    }

    @Test("startup committed recovery deletes the stale quick-unlock key")
    func committedStartupRecoveryDeletesStaleQuickUnlockKey() throws {
        let fileOperator = FaultingForcedResetFileOperator()
        fileOperator.failCommittedRecoveryMarkerReadback = true
        fileOperator.failRecoveryMarkerRemoval = true
        let transaction = VaultForcedResetTransaction(fileOperator: fileOperator)
        let fixture = try ForcedResetFixture(transaction: transaction)
        defer { fixture.remove() }
        try fixture.store.enableQuickUnlock()
        try fixture.store.enableAutomationUnlock()
        try fixture.addEntry(title: "Current generation")

        #expect(throws: PasswordVaultForcedResetError.recoveryRequired) {
            try fixture.store.forceReset(
                newPassword: fixture.newPassword,
                rememberSystemUnlock: false
            )
        }
        #expect(fixture.quickKey.containsKey)
        #expect(!fixture.automationKey.containsKey)

        fileOperator.failCommittedRecoveryMarkerReadback = false
        fileOperator.failRecoveryMarkerRemoval = false
        let rebuiltStore = KDBXPasswordVaultStore(
            localStorage: fixture.localStorage,
            unlockKeyStore: fixture.quickKey,
            automationUnlockKeyStore: fixture.automationKey,
            forcedResetTransaction: transaction
        )

        #expect(rebuiltStore.state == .locked)
        #expect(!fixture.quickKey.containsKey)
        #expect(!fixture.automationKey.containsKey)
        #expect(!FileManager.default.fileExists(
            atPath: fixture.localStorage.paths.forcedResetRecoveryMarkerURL.path
        ))
    }

    @Test("failed committed quick-key cleanup keeps recovery retryable")
    func committedQuickUnlockCleanupFailureCanRetry() throws {
        let fileOperator = FaultingForcedResetFileOperator()
        fileOperator.failCommittedRecoveryMarkerReadback = true
        fileOperator.failRecoveryMarkerRemoval = true
        let transaction = VaultForcedResetTransaction(fileOperator: fileOperator)
        let fixture = try ForcedResetFixture(transaction: transaction)
        defer { fixture.remove() }
        try fixture.store.enableQuickUnlock()
        try fixture.store.enableAutomationUnlock()
        try fixture.addEntry(title: "Current generation")
        #expect(throws: PasswordVaultForcedResetError.recoveryRequired) {
            try fixture.store.forceReset(
                newPassword: fixture.newPassword,
                rememberSystemUnlock: false
            )
        }
        let installedDigest = PasswordVaultDigest.hex(try Data(contentsOf: fixture.activeURL))

        fileOperator.failCommittedRecoveryMarkerReadback = false
        fileOperator.failRecoveryMarkerRemoval = false
        fixture.quickKey.deleteError = .keychainUnavailable
        let rebuiltStore = KDBXPasswordVaultStore(
            localStorage: fixture.localStorage,
            unlockKeyStore: fixture.quickKey,
            automationUnlockKeyStore: fixture.automationKey,
            forcedResetTransaction: transaction
        )

        #expect(rebuiltStore.state == .recoveryRequired("forced-reset-cleanup"))
        #expect(fixture.quickKey.containsKey)
        #expect(FileManager.default.fileExists(
            atPath: fixture.localStorage.paths.forcedResetRecoveryMarkerURL.path
        ))
        fixture.quickKey.deleteError = nil
        #expect(try rebuiltStore.retryForcedResetRecovery() == .committed(newDigest: installedDigest))
        #expect(rebuiltStore.state == .locked)
        #expect(!fixture.quickKey.containsKey)
        #expect(!fixture.automationKey.containsKey)
        #expect(!FileManager.default.fileExists(
            atPath: fixture.localStorage.paths.forcedResetRecoveryMarkerURL.path
        ))
    }

    @Test("prepared recovery rebuild rolls back locally and cancels matching OneDrive preparation")
    func controllerRecoveryPreservesPreparedResetAcrossRestart() async throws {
        let fileOperator = FaultingForcedResetFileOperator()
        fileOperator.failCommittedActiveReadback = true
        fileOperator.failActiveRollbackRestore = true
        let fixture = try ForcedResetFixture(
            transaction: VaultForcedResetTransaction(fileOperator: fileOperator)
        )
        defer { fixture.remove() }
        try fixture.store.enableQuickUnlock()
        try fixture.store.enableAutomationUnlock()
        let priorArchiveData = try fixture.installPriorArchive()
        try fixture.addEntry(title: "Current generation")
        let previousData = try Data(contentsOf: fixture.activeURL)
        let previousDigest = PasswordVaultDigest.hex(previousData)
        var initialMetadata = PasswordVaultSyncMetadata.defaultLocalOnly
        initialMetadata.mode = .oneDrive
        let metadata = FakePasswordVaultSyncMetadataStore(value: initialMetadata)
        let cloud = FakePasswordVaultCloudReplica()
        cloud.snapshot = PasswordVaultCloudSnapshot(data: previousData, digest: previousDigest)
        let processStatus = FakeOneDriveProcessStatusService()
        let oneDriveRoot = fixture.root.appendingPathComponent("OneDrive", isDirectory: true)
        let queue = DispatchQueue(label: "PasswordVaultForcedResetTests.controller-recovery")
        let syncService = try PasswordVaultSyncService(
            access: fixture.store,
            metadataStore: metadata,
            cloudReplica: cloud,
            processStatus: processStatus,
            rootURLProvider: { oneDriveRoot },
            rootURLSetter: { _ in },
            rootValidator: { _ in nil },
            queue: queue,
            callbackDispatcher: { $0() }
        )
        let controller = PasswordVaultUIController(
            store: fixture.store,
            syncController: syncService,
            authorizer: ForcedResetAllowAuthorizer(),
            agentAuthorizationResetter: ForcedResetNoopAgentAuthorizationResetter(),
            storeQueue: queue
        )

        let outcome = await withCheckedContinuation { continuation in
            controller.forceResetPasswordVault(newPassword: fixture.newPassword) {
                continuation.resume(returning: $0)
            }
        }

        #expect(outcome == .failure(.recoveryRequired))
        let prepared = try #require(metadata.value.pendingForcedReset)
        #expect(prepared.previousLocalDigest == previousDigest)
        #expect(prepared.replacementLocalDigest == nil)
        #expect(fixture.canOpen(fixture.activeURL, password: fixture.newPassword))
        #expect(fixture.store.state == .recoveryRequired("forced-reset-cleanup"))
        #expect(cloud.operations.isEmpty)
        let preparedRecordData = try Data(
            contentsOf: fixture.localStorage.paths.forcedResetRecoveryMarkerURL
        )
        let preparedRecord = try JSONDecoder().decode(
            VaultForcedResetRecoveryRecord.self,
            from: preparedRecordData
        )
        #expect(preparedRecord.version == VaultForcedResetRecoveryRecord.currentVersion)
        #expect(preparedRecord.phase == .prepared)
        #expect(preparedRecord.hadPreviousArchive)
        #expect(preparedRecord.oldActiveDigest == previousDigest)
        #expect(preparedRecord.priorArchiveDigest == PasswordVaultDigest.hex(priorArchiveData))
        #expect(!String(decoding: preparedRecordData, as: UTF8.self).contains(fixture.oldPassword))
        #expect(!String(decoding: preparedRecordData, as: UTF8.self).contains(fixture.newPassword))

        let rebuiltStore = KDBXPasswordVaultStore(
            localStorage: fixture.localStorage,
            unlockKeyStore: fixture.quickKey,
            automationUnlockKeyStore: fixture.automationKey
        )
        let restartQueue = DispatchQueue(label: "PasswordVaultForcedResetTests.restart-sync")
        let restartedSyncService = try PasswordVaultSyncService(
            access: rebuiltStore,
            metadataStore: metadata,
            cloudReplica: cloud,
            processStatus: processStatus,
            rootURLProvider: { oneDriveRoot },
            rootURLSetter: { _ in },
            rootValidator: { _ in nil },
            queue: restartQueue,
            callbackDispatcher: { $0() }
        )

        #expect(rebuiltStore.state == .locked)
        #expect(fixture.quickKey.containsKey)
        #expect(!fixture.automationKey.containsKey)
        #expect(try Data(contentsOf: fixture.activeURL) == previousData)
        #expect(try Data(contentsOf: fixture.archiveURL) == priorArchiveData)
        #expect(metadata.value.pendingForcedReset == nil)
        #expect(restartedSyncService.snapshot.phase == .syncing(.checking))
        #expect(cloud.operations.isEmpty)
        #expect(!FileManager.default.fileExists(
            atPath: fixture.localStorage.paths.forcedResetRecoveryMarkerURL.path
        ))
    }

    @Test("marker deletion failure after committed cleanup enters recovery and preserves OneDrive reset")
    func recoveryMarkerRemovalFailurePreservesCommittedResetAndPendingMetadata() async throws {
        let fileOperator = FaultingForcedResetFileOperator()
        fileOperator.failRecoveryMarkerRemoval = true
        let fixture = try ForcedResetFixture(
            transaction: VaultForcedResetTransaction(fileOperator: fileOperator)
        )
        defer { fixture.remove() }
        try fixture.addEntry(title: "Current generation")
        let previousData = try Data(contentsOf: fixture.activeURL)
        let previousDigest = PasswordVaultDigest.hex(previousData)
        var initialMetadata = PasswordVaultSyncMetadata.defaultLocalOnly
        initialMetadata.mode = .oneDrive
        let metadata = FakePasswordVaultSyncMetadataStore(value: initialMetadata)
        let cloud = FakePasswordVaultCloudReplica()
        cloud.snapshot = PasswordVaultCloudSnapshot(data: previousData, digest: previousDigest)
        let queue = DispatchQueue(label: "PasswordVaultForcedResetTests.marker-removal-recovery")
        let syncService = try PasswordVaultSyncService(
            access: fixture.store,
            metadataStore: metadata,
            cloudReplica: cloud,
            processStatus: FakeOneDriveProcessStatusService(),
            rootURLProvider: {
                fixture.root.appendingPathComponent("OneDrive", isDirectory: true)
            },
            rootURLSetter: { _ in },
            rootValidator: { _ in nil },
            queue: queue,
            callbackDispatcher: { $0() }
        )
        let controller = PasswordVaultUIController(
            store: fixture.store,
            syncController: syncService,
            authorizer: ForcedResetAllowAuthorizer(),
            agentAuthorizationResetter: ForcedResetNoopAgentAuthorizationResetter(),
            storeQueue: queue
        )

        let outcome = await withCheckedContinuation { continuation in
            controller.forceResetPasswordVault(newPassword: fixture.newPassword) {
                continuation.resume(returning: $0)
            }
        }
        queue.sync {}

        #expect(outcome == .failure(.recoveryRequired))
        #expect(fixture.store.state == .recoveryRequired("forced-reset-cleanup"))
        let installedData = try Data(contentsOf: fixture.activeURL)
        let installedDigest = PasswordVaultDigest.hex(installedData)
        #expect(fixture.canOpen(fixture.activeURL, password: fixture.newPassword))
        #expect(!fixture.canOpen(fixture.activeURL, password: fixture.oldPassword))
        #expect(try Data(contentsOf: fixture.archiveURL) == previousData)
        #expect(FileManager.default.fileExists(
            atPath: fixture.localStorage.paths.forcedResetRecoveryMarkerURL.path
        ))
        #expect(fixture.forcedResetTemporaryFiles().allSatisfy { $0.pathExtension == "marker" })
        let prepared = try #require(metadata.value.pendingForcedReset)
        #expect(prepared.previousLocalDigest == previousDigest)
        #expect(prepared.replacementLocalDigest == installedDigest)
        #expect(metadata.value.localRevision == 1)
        let committedRecord = try JSONDecoder().decode(
            VaultForcedResetRecoveryRecord.self,
            from: Data(contentsOf: fixture.localStorage.paths.forcedResetRecoveryMarkerURL)
        )
        #expect(committedRecord.phase == .committed)
        #expect(committedRecord.oldActiveDigest == previousDigest)
        #expect(committedRecord.newActiveDigest == installedDigest)

        let rebuiltStore = KDBXPasswordVaultStore(
            localStorage: fixture.localStorage,
            unlockKeyStore: fixture.quickKey,
            automationUnlockKeyStore: fixture.automationKey
        )
        let restartQueue = DispatchQueue(label: "PasswordVaultForcedResetTests.marker-removal-restart")
        let restartedSyncService = try PasswordVaultSyncService(
            access: rebuiltStore,
            metadataStore: metadata,
            cloudReplica: cloud,
            processStatus: FakeOneDriveProcessStatusService(),
            rootURLProvider: {
                fixture.root.appendingPathComponent("OneDrive", isDirectory: true)
            },
            rootURLSetter: { _ in },
            rootValidator: { _ in nil },
            queue: restartQueue,
            callbackDispatcher: { $0() }
        )

        #expect(rebuiltStore.state == .locked)
        #expect(try Data(contentsOf: fixture.activeURL) == installedData)
        #expect(try Data(contentsOf: fixture.archiveURL) == previousData)
        #expect(!FileManager.default.fileExists(
            atPath: fixture.localStorage.paths.forcedResetRecoveryMarkerURL.path
        ))
        #expect(metadata.value.pendingForcedReset?.replacementLocalDigest == installedDigest)
        #expect(cloud.operations.isEmpty)

        restartedSyncService.synchronize(reason: .manual)
        restartQueue.sync {}

        #expect(cloud.operations.map(\.kind) == [.archiveWrite, .activeWrite])
        #expect(metadata.value.pendingForcedReset == nil)
    }

    @Test("durable recovery gate survives every unlock path and blocks all remote work")
    func durableRecoveryGateCannotBeDisguisedByStateTransitions() async throws {
        let fileOperator = FaultingForcedResetFileOperator()
        fileOperator.failRecoveryMarkerRemoval = true
        let fixture = try ForcedResetFixture(
            transaction: VaultForcedResetTransaction(fileOperator: fileOperator)
        )
        defer { fixture.remove() }
        try fixture.addEntry(title: "Current generation")
        let previousData = try Data(contentsOf: fixture.activeURL)
        let previousDigest = PasswordVaultDigest.hex(previousData)
        var initialMetadata = PasswordVaultSyncMetadata.defaultLocalOnly
        initialMetadata.mode = .oneDrive
        let metadata = FakePasswordVaultSyncMetadataStore(value: initialMetadata)
        let cloud = FakePasswordVaultCloudReplica()
        cloud.snapshot = .init(data: previousData, digest: previousDigest)
        let processStatus = FakeOneDriveProcessStatusService()
        var rootReadCount = 0
        let queue = DispatchQueue(label: "PasswordVaultForcedResetTests.durable-recovery-gate")
        let syncService = try PasswordVaultSyncService(
            access: fixture.store,
            metadataStore: metadata,
            cloudReplica: cloud,
            processStatus: processStatus,
            rootURLProvider: {
                rootReadCount += 1
                return fixture.root
            },
            rootURLSetter: { _ in },
            rootValidator: { _ in nil },
            queue: queue,
            callbackDispatcher: { $0() }
        )
        fixture.store.setCommitObserver { syncService.record($0) }
        try syncService.prepareForcedReset(previousLocalDigest: previousDigest)
        #expect(throws: PasswordVaultForcedResetError.recoveryRequired) {
            try fixture.store.forceReset(
                newPassword: fixture.newPassword,
                rememberSystemUnlock: false
            )
        }

        fixture.quickKey.data = Data(repeating: 0x11, count: 32)
        fixture.automationKey.data = Data(repeating: 0x22, count: 32)
        fixture.store.lock()
        #expect(fixture.store.state == .recoveryRequired("forced-reset-cleanup"))
        #expect(throws: PasswordVaultForcedResetError.recoveryRequired) {
            try fixture.store.unlock(
                masterPassword: fixture.newPassword,
                rememberQuickUnlock: false
            )
        }
        #expect(fixture.store.state == .recoveryRequired("forced-reset-cleanup"))
        #expect(throws: PasswordVaultForcedResetError.recoveryRequired) {
            try fixture.store.unlockWithQuickKey(reason: "test")
        }
        #expect(fixture.store.state == .recoveryRequired("forced-reset-cleanup"))
        #expect(throws: PasswordVaultForcedResetError.recoveryRequired) {
            try fixture.store.unlockForAutomation()
        }
        #expect(fixture.store.state == .recoveryRequired("forced-reset-cleanup"))

        let controller = PasswordVaultUIController(
            store: fixture.store,
            syncController: syncService,
            authorizer: ForcedResetAllowAuthorizer(),
            agentAuthorizationResetter: ForcedResetNoopAgentAuthorizationResetter(),
            storeQueue: queue
        )
        let pendingBeforeLifecycleAttempts = metadata.value.pendingForcedReset
        let masterOutcome = await withCheckedContinuation { continuation in
            controller.unlock(masterPassword: fixture.newPassword) {
                continuation.resume(returning: $0)
            }
        }
        guard case .failure(.recoveryRequired) = masterOutcome else {
            Issue.record("Master unlock must surface forced-reset recovery")
            return
        }
        let quickOutcome = await withCheckedContinuation { continuation in
            controller.unlockWithQuickKey { continuation.resume(returning: $0) }
        }
        guard case .failure(.recoveryRequired) = quickOutcome else {
            Issue.record("Quick unlock must surface forced-reset recovery")
            return
        }
        let agentOutcome = await withCheckedContinuation { continuation in
            controller.ensureReadyForAgent { continuation.resume(returning: $0) }
        }
        guard case .failure(.recoveryRequired) = agentOutcome else {
            Issue.record("Agent readiness must surface forced-reset recovery")
            return
        }
        #expect(fixture.store.state == .recoveryRequired("forced-reset-cleanup"))
        #expect(metadata.value.pendingForcedReset == pendingBeforeLifecycleAttempts)

        syncService.synchronize(reason: .manual)
        queue.sync {}
        #expect(metadata.value.pendingForcedReset != nil)
        #expect(processStatus.readCount == 0)
        #expect(rootReadCount == 0)
        #expect(cloud.readCount == 0)
        #expect(cloud.operations.isEmpty)
    }

    @Test("queued master-password and force resets cannot overwrite committed recovery")
    func queuedForceResetCannotOverwriteCommittedPendingReset() async throws {
        let fileOperator = FaultingForcedResetFileOperator()
        fileOperator.failRecoveryMarkerRemoval = true
        let fixture = try ForcedResetFixture(
            transaction: VaultForcedResetTransaction(fileOperator: fileOperator)
        )
        defer { fixture.remove() }
        try fixture.addEntry(title: "Current generation")
        let previousData = try Data(contentsOf: fixture.activeURL)
        let previousDigest = PasswordVaultDigest.hex(previousData)
        var initialMetadata = PasswordVaultSyncMetadata.defaultLocalOnly
        initialMetadata.mode = .oneDrive
        let metadata = FakePasswordVaultSyncMetadataStore(value: initialMetadata)
        let cloud = FakePasswordVaultCloudReplica()
        cloud.snapshot = .init(data: previousData, digest: previousDigest)
        let processStatus = FakeOneDriveProcessStatusService()
        var rootReadCount = 0
        let queue = DispatchQueue(label: "PasswordVaultForcedResetTests.queued-force-reset")
        let syncService = try PasswordVaultSyncService(
            access: fixture.store,
            metadataStore: metadata,
            cloudReplica: cloud,
            processStatus: processStatus,
            rootURLProvider: {
                rootReadCount += 1
                return fixture.root
            },
            rootURLSetter: { _ in },
            rootValidator: { _ in nil },
            queue: queue,
            callbackDispatcher: { $0() }
        )
        let agentResetter = ForcedResetNoopAgentAuthorizationResetter()
        let controller = PasswordVaultUIController(
            store: fixture.store,
            syncController: syncService,
            authorizer: ForcedResetAllowAuthorizer(),
            agentAuthorizationResetter: agentResetter,
            storeQueue: queue
        )

        let firstOutcome = await withCheckedContinuation { continuation in
            controller.forceResetPasswordVault(newPassword: fixture.newPassword) {
                continuation.resume(returning: $0)
            }
        }
        guard case .failure(.recoveryRequired) = firstOutcome else {
            Issue.record("Initial marker-retained reset must require recovery")
            return
        }
        queue.sync {}
        let pendingBeforeQueuedSubmit = try #require(metadata.value.pendingForcedReset)
        let activeBeforeQueuedSubmit = try Data(contentsOf: fixture.activeURL)
        let archiveBeforeQueuedSubmit = try Data(contentsOf: fixture.archiveURL)
        let markerURL = fixture.localStorage.paths.forcedResetRecoveryMarkerURL
        let markerBeforeQueuedSubmit = try Data(contentsOf: markerURL)

        let staleMasterPasswordOutcome = await withCheckedContinuation { continuation in
            controller.resetMasterPassword(newPassword: fixture.thirdPassword) {
                continuation.resume(returning: $0)
            }
        }
        queue.sync {}

        guard case .failure(.recoveryRequired) = staleMasterPasswordOutcome else {
            Issue.record("Stale master-password reset must surface forced-reset recovery")
            return
        }
        #expect(metadata.value.pendingForcedReset == pendingBeforeQueuedSubmit)
        #expect(try Data(contentsOf: fixture.activeURL) == activeBeforeQueuedSubmit)
        #expect(try Data(contentsOf: fixture.archiveURL) == archiveBeforeQueuedSubmit)
        #expect(try Data(contentsOf: markerURL) == markerBeforeQueuedSubmit)

        #expect(throws: PasswordVaultForcedResetError.recoveryRequired) {
            try syncService.prepareForcedReset(previousLocalDigest: "unrelated-digest")
        }
        #expect(metadata.value.pendingForcedReset == pendingBeforeQueuedSubmit)

        let queuedOutcome = await withCheckedContinuation { continuation in
            controller.forceResetPasswordVault(newPassword: fixture.thirdPassword) {
                continuation.resume(returning: $0)
            }
        }
        queue.sync {}

        guard case .failure(.recoveryRequired) = queuedOutcome else {
            Issue.record("Queued reset must be rejected by the durable recovery gate")
            return
        }
        #expect(agentResetter.callCount == 1)
        #expect(metadata.value.pendingForcedReset == pendingBeforeQueuedSubmit)
        #expect(try Data(contentsOf: fixture.activeURL) == activeBeforeQueuedSubmit)
        #expect(try Data(contentsOf: fixture.archiveURL) == archiveBeforeQueuedSubmit)
        #expect(try Data(contentsOf: markerURL) == markerBeforeQueuedSubmit)
        #expect(processStatus.readCount == 0)
        #expect(rootReadCount == 0)
        #expect(cloud.readCount == 0)
        #expect(cloud.operations.isEmpty)

        fileOperator.failRecoveryMarkerRemoval = false
        let recoveryOutcome = await withCheckedContinuation { continuation in
            controller.retryForcedResetRecovery { continuation.resume(returning: $0) }
        }
        queue.sync {}

        #expect(recoveryOutcome == .success(.committed(
            newDigest: PasswordVaultDigest.hex(activeBeforeQueuedSubmit)
        )))
        #expect(cloud.operations.map(\.kind) == [.archiveWrite, .activeWrite])
        #expect(cloud.archiveSnapshot?.data == previousData)
        #expect(cloud.snapshot?.data == activeBeforeQueuedSubmit)
        #expect(metadata.value.pendingForcedReset == nil)
    }

    @Test(
        "unknown or corrupted recovery records fail closed without changing any bytes",
        arguments: [
            Data("pastera-forced-reset-recovery-v1\n".utf8),
            Data("{not-json".utf8)
        ]
    )
    func invalidRecoveryRecordRemainsUntouched(markerData: Data) throws {
        let fixture = try ForcedResetFixture()
        defer { fixture.remove() }
        let archiveData = try fixture.installPriorArchive()
        try fixture.addEntry(title: "Current generation")
        let activeData = try Data(contentsOf: fixture.activeURL)
        try markerData.write(
            to: fixture.localStorage.paths.forcedResetRecoveryMarkerURL,
            options: .atomic
        )

        let rebuiltStore = KDBXPasswordVaultStore(
            localStorage: fixture.localStorage,
            unlockKeyStore: fixture.quickKey,
            automationUnlockKeyStore: fixture.automationKey
        )

        #expect(rebuiltStore.state == .recoveryRequired("forced-reset-cleanup"))
        #expect(try Data(contentsOf: fixture.activeURL) == activeData)
        #expect(try Data(contentsOf: fixture.archiveURL) == archiveData)
        #expect(try Data(contentsOf: fixture.localStorage.paths.forcedResetRecoveryMarkerURL) == markerData)
    }

    @Test("failed automatic prepared recovery blocks cloud and controller retry rolls back")
    func failedAutomaticRecoveryBlocksCloudUntilControllerRetry() async throws {
        let transactionOperator = FaultingForcedResetFileOperator()
        transactionOperator.failCommittedActiveReadback = true
        transactionOperator.failActiveRollbackRestore = true
        let fixture = try ForcedResetFixture(
            transaction: VaultForcedResetTransaction(fileOperator: transactionOperator)
        )
        defer { fixture.remove() }
        let priorArchiveData = try fixture.installPriorArchive()
        try fixture.addEntry(title: "Current generation")
        let previousData = try Data(contentsOf: fixture.activeURL)
        let previousDigest = PasswordVaultDigest.hex(previousData)
        var initialMetadata = PasswordVaultSyncMetadata.defaultLocalOnly
        initialMetadata.mode = .oneDrive
        let metadata = FakePasswordVaultSyncMetadataStore(value: initialMetadata)
        let originalQueue = DispatchQueue(label: "PasswordVaultForcedResetTests.retry-original")
        let originalSync = try PasswordVaultSyncService(
            access: fixture.store,
            metadataStore: metadata,
            cloudReplica: FakePasswordVaultCloudReplica(),
            processStatus: FakeOneDriveProcessStatusService(),
            rootURLProvider: { fixture.root },
            rootURLSetter: { _ in },
            rootValidator: { _ in nil },
            queue: originalQueue,
            callbackDispatcher: { $0() }
        )
        fixture.store.setCommitObserver { originalSync.record($0) }
        try originalSync.prepareForcedReset(previousLocalDigest: previousDigest)
        #expect(throws: PasswordVaultForcedResetError.recoveryRequired) {
            try fixture.store.forceReset(
                newPassword: fixture.newPassword,
                rememberSystemUnlock: false
            )
        }
        let activeBeforePreparedRecovery = try Data(contentsOf: fixture.activeURL)
        let archiveBeforePreparedRecovery = try Data(contentsOf: fixture.archiveURL)
        let markerURL = fixture.localStorage.paths.forcedResetRecoveryMarkerURL
        let markerBeforePreparedRecovery = try Data(contentsOf: markerURL)

        let recoveryOperator = FaultingForcedResetFileOperator()
        recoveryOperator.failRecoveryMarkerRemoval = true
        let rebuiltStore = KDBXPasswordVaultStore(
            localStorage: fixture.localStorage,
            unlockKeyStore: fixture.quickKey,
            automationUnlockKeyStore: fixture.automationKey,
            forcedResetTransaction: VaultForcedResetTransaction(fileOperator: recoveryOperator)
        )
        #expect(rebuiltStore.requiresForcedResetRecovery)
        #expect(rebuiltStore.state == .recoveryRequired("forced-reset-cleanup"))
        #expect(try Data(contentsOf: fixture.activeURL) == previousData)
        #expect(try Data(contentsOf: fixture.archiveURL) == priorArchiveData)
        #expect(
            activeBeforePreparedRecovery != previousData
                || archiveBeforePreparedRecovery != priorArchiveData
        )
        #expect(try Data(contentsOf: markerURL) == markerBeforePreparedRecovery)
        let cloud = FakePasswordVaultCloudReplica()
        cloud.snapshot = .init(data: previousData, digest: previousDigest)
        let processStatus = FakeOneDriveProcessStatusService()
        let queue = DispatchQueue(label: "PasswordVaultForcedResetTests.retry-recovery")
        let syncService = try PasswordVaultSyncService(
            access: rebuiltStore,
            metadataStore: metadata,
            cloudReplica: cloud,
            processStatus: processStatus,
            rootURLProvider: { fixture.root },
            rootURLSetter: { _ in },
            rootValidator: { _ in nil },
            queue: queue,
            callbackDispatcher: { $0() }
        )

        syncService.synchronize(reason: .manual)
        queue.sync {}
        #expect(rebuiltStore.state == .recoveryRequired("forced-reset-cleanup"))
        #expect(metadata.value.pendingForcedReset != nil)
        #expect(cloud.operations.isEmpty)
        #expect(processStatus.readCount == 0)

        recoveryOperator.failRecoveryMarkerRemoval = false
        let countedSync = CountingForcedResetSyncController(base: syncService)
        let controller = PasswordVaultUIController(
            store: rebuiltStore,
            syncController: countedSync,
            authorizer: ForcedResetAllowAuthorizer(),
            agentAuthorizationResetter: ForcedResetNoopAgentAuthorizationResetter(),
            storeQueue: queue
        )
        let outcomes = await withCheckedContinuation { continuation in
            var captured = [Result<PasswordVaultForcedResetRecoveryResult, PasswordVaultError>]()
            let capture: (Result<PasswordVaultForcedResetRecoveryResult, PasswordVaultError>) -> Void = {
                captured.append($0)
                if captured.count == 2 { continuation.resume(returning: captured) }
            }
            controller.retryForcedResetRecovery(completion: capture)
            controller.retryForcedResetRecovery(completion: capture)
        }

        #expect(outcomes == [
            .success(.rolledBack(oldDigest: previousDigest)),
            .success(.rolledBack(oldDigest: previousDigest))
        ])
        #expect(rebuiltStore.state == .locked)
        #expect(!rebuiltStore.requiresForcedResetRecovery)
        #expect(try Data(contentsOf: fixture.activeURL) == previousData)
        #expect(try Data(contentsOf: fixture.archiveURL) == priorArchiveData)
        #expect(!FileManager.default.fileExists(atPath: markerURL.path))
        #expect(metadata.value.pendingForcedReset == nil)
        #expect(cloud.operations.isEmpty)
        #expect(countedSync.cancelPreparedCallCount == 1)
        #expect(countedSync.synchronizeCallCount == 0)
    }

    @Test("controller retry commits recovery once and resumes the protected forced sync")
    func committedControllerRecoveryRetryIsIdempotentAndResumesSync() async throws {
        let transactionOperator = FaultingForcedResetFileOperator()
        transactionOperator.failRecoveryMarkerRemoval = true
        let fixture = try ForcedResetFixture(
            transaction: VaultForcedResetTransaction(fileOperator: transactionOperator)
        )
        defer { fixture.remove() }
        try fixture.addEntry(title: "Current generation")
        let previousData = try Data(contentsOf: fixture.activeURL)
        let previousDigest = PasswordVaultDigest.hex(previousData)
        var initialMetadata = PasswordVaultSyncMetadata.defaultLocalOnly
        initialMetadata.mode = .oneDrive
        let metadata = FakePasswordVaultSyncMetadataStore(value: initialMetadata)
        let cloud = FakePasswordVaultCloudReplica()
        cloud.snapshot = .init(data: previousData, digest: previousDigest)
        let originalQueue = DispatchQueue(label: "PasswordVaultForcedResetTests.committed-retry-original")
        let originalSync = try PasswordVaultSyncService(
            access: fixture.store,
            metadataStore: metadata,
            cloudReplica: cloud,
            processStatus: FakeOneDriveProcessStatusService(),
            rootURLProvider: { fixture.root },
            rootURLSetter: { _ in },
            rootValidator: { _ in nil },
            queue: originalQueue,
            callbackDispatcher: { $0() }
        )
        fixture.store.setCommitObserver { originalSync.record($0) }
        try originalSync.prepareForcedReset(previousLocalDigest: previousDigest)
        #expect(throws: PasswordVaultForcedResetError.recoveryRequired) {
            try fixture.store.forceReset(
                newPassword: fixture.newPassword,
                rememberSystemUnlock: false
            )
        }
        let installedData = try Data(contentsOf: fixture.activeURL)
        let installedDigest = PasswordVaultDigest.hex(installedData)
        #expect(metadata.value.localRevision == 1)
        #expect(metadata.value.pendingForcedReset?.replacementLocalDigest == installedDigest)

        let recoveryOperator = FaultingForcedResetFileOperator()
        recoveryOperator.failRecoveryMarkerRemoval = true
        let rebuiltStore = KDBXPasswordVaultStore(
            localStorage: fixture.localStorage,
            unlockKeyStore: fixture.quickKey,
            automationUnlockKeyStore: fixture.automationKey,
            forcedResetTransaction: VaultForcedResetTransaction(fileOperator: recoveryOperator)
        )
        let queue = DispatchQueue(label: "PasswordVaultForcedResetTests.committed-retry")
        let syncService = try PasswordVaultSyncService(
            access: rebuiltStore,
            metadataStore: metadata,
            cloudReplica: cloud,
            processStatus: FakeOneDriveProcessStatusService(),
            rootURLProvider: { fixture.root },
            rootURLSetter: { _ in },
            rootValidator: { _ in nil },
            queue: queue,
            callbackDispatcher: { $0() }
        )
        syncService.synchronize(reason: .manual)
        queue.sync {}
        #expect(rebuiltStore.state == .recoveryRequired("forced-reset-cleanup"))
        #expect(cloud.operations.isEmpty)

        recoveryOperator.failRecoveryMarkerRemoval = false
        let countedSync = CountingForcedResetSyncController(base: syncService)
        let controller = PasswordVaultUIController(
            store: rebuiltStore,
            syncController: countedSync,
            authorizer: ForcedResetAllowAuthorizer(),
            agentAuthorizationResetter: ForcedResetNoopAgentAuthorizationResetter(),
            storeQueue: queue
        )
        let outcomes = await withCheckedContinuation { continuation in
            var captured = [Result<PasswordVaultForcedResetRecoveryResult, PasswordVaultError>]()
            let capture: (Result<PasswordVaultForcedResetRecoveryResult, PasswordVaultError>) -> Void = {
                captured.append($0)
                if captured.count == 2 { continuation.resume(returning: captured) }
            }
            controller.retryForcedResetRecovery(completion: capture)
            controller.retryForcedResetRecovery(completion: capture)
        }
        queue.sync {}

        #expect(outcomes == [
            .success(.committed(newDigest: installedDigest)),
            .success(.committed(newDigest: installedDigest))
        ])
        #expect(rebuiltStore.state == .locked)
        #expect(metadata.value.localRevision == 1)
        #expect(countedSync.synchronizeCallCount == 1)
        #expect(countedSync.cancelPreparedCallCount == 0)
        #expect(cloud.operations.map(\.kind) == [.archiveWrite, .activeWrite])
        #expect(cloud.archiveSnapshot?.digest == previousDigest)
        #expect(cloud.snapshot?.digest == installedDigest)
        #expect(metadata.value.pendingForcedReset == nil)
    }

    @Test(
        "startup resumes committed cleanup after an unverifiable post-commit rollback",
        arguments: ForcedResetSanitizeFault.allCases
    )
    fileprivate func unsafeRollbackSanitizeEntersRecovery(fault: ForcedResetSanitizeFault) throws {
        let fileOperator = FaultingForcedResetFileOperator()
        fileOperator.failRollbackRemoval = true
        fileOperator.sanitizeFault = fault
        let fixture = try ForcedResetFixture(
            transaction: VaultForcedResetTransaction(fileOperator: fileOperator)
        )
        defer { fixture.remove() }
        try fixture.addEntry(title: "Old Entry")

        #expect(throws: PasswordVaultForcedResetError.recoveryRequired) {
            try fixture.store.forceReset(
                newPassword: fixture.newPassword,
                rememberSystemUnlock: false
            )
        }

        let committedActive = try Data(contentsOf: fixture.activeURL)
        let committedArchive = try Data(contentsOf: fixture.archiveURL)
        #expect(fixture.canOpen(fixture.activeURL, password: fixture.newPassword))
        #expect(fixture.canOpen(fixture.archiveURL, password: fixture.oldPassword))
        #expect(fixture.store.state == .recoveryRequired("forced-reset-cleanup"))
        #expect(fixture.commits.map(\.origin) == [.forcedReset])
        #expect(FileManager.default.fileExists(
            atPath: fixture.localStorage.paths.forcedResetRecoveryMarkerURL.path
        ))

        #expect(throws: PasswordVaultForcedResetError.recoveryRequired) {
            try fixture.store.forceReset(
                newPassword: fixture.thirdPassword,
                rememberSystemUnlock: false
            )
        }
        #expect(try Data(contentsOf: fixture.activeURL) == committedActive)
        #expect(try Data(contentsOf: fixture.archiveURL) == committedArchive)

        fixture.automationKey.data = Data(repeating: 0xA5, count: 32)
        let rebuiltStore = KDBXPasswordVaultStore(
            localStorage: fixture.localStorage,
            unlockKeyStore: fixture.quickKey,
            automationUnlockKeyStore: fixture.automationKey
        )

        #expect(rebuiltStore.state == .locked)
        #expect(fixture.automationKey.containsKey)
        #expect(try Data(contentsOf: fixture.activeURL) == committedActive)
        #expect(try Data(contentsOf: fixture.archiveURL) == committedArchive)
        #expect(fixture.forcedResetTemporaryFiles().isEmpty)
        #expect(!FileManager.default.fileExists(
            atPath: fixture.localStorage.paths.forcedResetRecoveryMarkerURL.path
        ))
    }

    @Test("a post-commit validation failure is an explicit unsafe transaction outcome")
    func sanitizeValidationFailureIsExplicitlyCommittedButUnsafe() throws {
        let fileOperator = FaultingForcedResetFileOperator()
        fileOperator.failRollbackRemoval = true
        let transaction = VaultForcedResetTransaction(fileOperator: fileOperator)
        let fixture = try ForcedResetFixture()
        defer { fixture.remove() }
        let oldBytes = try Data(contentsOf: fixture.activeURL)
        let newBytes = try fixture.emptyVaultData(password: fixture.newPassword)

        let result = try transaction.replace(
            activeURL: fixture.activeURL,
            archiveURL: fixture.archiveURL,
            recoveryMarkerURL: fixture.localStorage.paths.forcedResetRecoveryMarkerURL,
            newVaultData: newBytes
        ) { url, data in
            if url.pathExtension == "rollback" { throw PasswordVaultError.corruptedData }
            _ = try KDBXReader.parse(data, unlockData: UnlockData(masterPassword: fixture.newPassword))
        }

        #expect(result.requiresRecovery)
        #expect(try Data(contentsOf: fixture.archiveURL) == oldBytes)
        #expect(try Data(contentsOf: fixture.activeURL) == newBytes)
    }

    @Test("a lock release failure returns a committed reset when cleanup is complete")
    func lockReleaseFailureUsesCompleteCommittedOutcome() throws {
        var releaseFailingStorage: ForcedResetReleaseFailingLocalStorage?
        let fixture = try ForcedResetFixture { backing in
            let storage = ForcedResetReleaseFailingLocalStorage(backing: backing)
            releaseFailingStorage = storage
            return storage
        }
        defer { fixture.remove() }
        try fixture.addEntry(title: "Old Entry")
        let oldBytes = try Data(contentsOf: fixture.activeURL)
        releaseFailingStorage?.failAfterNextTransaction = true

        let result = try fixture.store.forceReset(
            newPassword: fixture.newPassword,
            rememberSystemUnlock: false
        )

        #expect(try Data(contentsOf: fixture.archiveURL) == oldBytes)
        #expect(result.warnings.isEmpty)
        #expect(fixture.canOpen(fixture.activeURL, password: fixture.newPassword))
        #expect(fixture.store.state == .unlocked)
        #expect(fixture.commits.map(\.origin) == [.forcedReset])
        #expect(!FileManager.default.fileExists(
            atPath: fixture.localStorage.paths.forcedResetRecoveryMarkerURL.path
        ))

        _ = try fixture.store.forceReset(
            newPassword: fixture.thirdPassword,
            rememberSystemUnlock: false
        )
        #expect(fixture.commits.map(\.origin) == [.forcedReset, .forcedReset])
    }

    @Test("a lock release failure returns cleanup warning when old artifacts were safely sanitized")
    func lockReleaseFailureUsesPendingDeletionCommittedOutcome() throws {
        let fileOperator = FaultingForcedResetFileOperator()
        fileOperator.failRollbackRemoval = true
        var releaseFailingStorage: ForcedResetReleaseFailingLocalStorage?
        let fixture = try ForcedResetFixture(
            transaction: VaultForcedResetTransaction(fileOperator: fileOperator)
        ) { backing in
            let storage = ForcedResetReleaseFailingLocalStorage(backing: backing)
            releaseFailingStorage = storage
            return storage
        }
        defer { fixture.remove() }
        try fixture.addEntry(title: "Old Entry")
        releaseFailingStorage?.failAfterNextTransaction = true

        let result = try fixture.store.forceReset(
            newPassword: fixture.newPassword,
            rememberSystemUnlock: false
        )

        #expect(result.warnings == [.resetArtifactCleanupPending])
        #expect(fixture.store.state == .unlocked)
        #expect(fixture.commits.map(\.origin) == [.forcedReset])
        #expect(!FileManager.default.fileExists(
            atPath: fixture.localStorage.paths.forcedResetRecoveryMarkerURL.path
        ))
    }

    @Test("recovery marker write failure aborts before the destructive commit")
    func recoveryMarkerWriteFailureDoesNotReplaceVaultOrArchive() throws {
        let fileOperator = FaultingForcedResetFileOperator()
        fileOperator.failRecoveryMarkerWrite = true
        let fixture = try ForcedResetFixture(
            transaction: VaultForcedResetTransaction(fileOperator: fileOperator)
        )
        defer { fixture.remove() }
        let priorArchiveBytes = try fixture.installPriorArchive()
        try fixture.addEntry(title: "Current generation")
        let activeBytes = try Data(contentsOf: fixture.activeURL)

        #expect(throws: PasswordVaultError.saveFailed) {
            try fixture.store.forceReset(
                newPassword: fixture.newPassword,
                rememberSystemUnlock: false
            )
        }

        #expect(try Data(contentsOf: fixture.activeURL) == activeBytes)
        #expect(try Data(contentsOf: fixture.archiveURL) == priorArchiveBytes)
        #expect(fixture.commits.isEmpty)
    }

    @Test("startup resumes prepared rollback after pre-commit cleanup failure")
    func preCommitStageCleanupFailureKeepsDurableRecoveryMarker() throws {
        let fileOperator = FaultingForcedResetFileOperator()
        fileOperator.failArchiveStageRemoval = true
        var injected = false
        let transaction = VaultForcedResetTransaction(fileOperator: fileOperator) { checkpoint in
            guard checkpoint == .archiveReadback else { return }
            injected = true
            throw PasswordVaultError.saveFailed
        }
        let fixture = try ForcedResetFixture(transaction: transaction)
        defer { fixture.remove() }
        let priorArchiveBytes = try fixture.installPriorArchive()
        try fixture.addEntry(title: "Current generation")
        let activeBytes = try Data(contentsOf: fixture.activeURL)

        #expect(throws: PasswordVaultForcedResetError.recoveryRequired) {
            try fixture.store.forceReset(
                newPassword: fixture.newPassword,
                rememberSystemUnlock: false
            )
        }

        #expect(injected)
        #expect(fixture.store.state == .recoveryRequired("forced-reset-cleanup"))
        #expect(try Data(contentsOf: fixture.activeURL) == activeBytes)
        #expect(try Data(contentsOf: fixture.archiveURL) == priorArchiveBytes)
        let archiveStage = try #require(fixture.forcedResetTemporaryFiles().first {
            $0.lastPathComponent.contains("archive.staged")
        })
        #expect(try Data(contentsOf: archiveStage) == activeBytes)
        #expect(FileManager.default.fileExists(
            atPath: fixture.localStorage.paths.forcedResetRecoveryMarkerURL.path
        ))

        fixture.automationKey.data = Data(repeating: 0x5A, count: 32)
        let rebuiltStore = KDBXPasswordVaultStore(
            localStorage: fixture.localStorage,
            unlockKeyStore: fixture.quickKey,
            automationUnlockKeyStore: fixture.automationKey
        )

        #expect(rebuiltStore.state == .locked)
        #expect(fixture.automationKey.containsKey)
        #expect(try Data(contentsOf: fixture.activeURL) == activeBytes)
        #expect(try Data(contentsOf: fixture.archiveURL) == priorArchiveBytes)
        #expect(!FileManager.default.fileExists(atPath: archiveStage.path))
        #expect(fixture.forcedResetTemporaryFiles().isEmpty)
        #expect(!FileManager.default.fileExists(
            atPath: fixture.localStorage.paths.forcedResetRecoveryMarkerURL.path
        ))
    }

    @Test("forced reset deletes stale backup and immediate and resolved conflict artifacts")
    func forcedResetDeletesEveryStaleManagedArtifact() throws {
        let fixture = try ForcedResetFixture()
        defer { fixture.remove() }
        try fixture.addEntry(title: "Old Entry")
        let staleURLs = try fixture.installStaleManagedArtifacts()

        _ = try fixture.store.forceReset(
            newPassword: fixture.newPassword,
            rememberSystemUnlock: false
        )

        for url in staleURLs {
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
        let archivePaths = try fixture.archiveFiles().map { $0.resolvingSymlinksInPath().path }
        #expect(archivePaths == [fixture.archiveURL.resolvingSymlinksInPath().path])
    }

    @Test("undeletable stale artifacts are verified new ciphertext before cleanup warning")
    func forcedResetSanitizesEveryUndeletableStaleArtifact() throws {
        let fileOperator = FaultingForcedResetFileOperator()
        fileOperator.failStaleArtifactRemoval = true
        let fixture = try ForcedResetFixture(
            transaction: VaultForcedResetTransaction(fileOperator: fileOperator)
        )
        defer { fixture.remove() }
        try fixture.addEntry(title: "Old Entry")
        let staleURLs = try fixture.installStaleManagedArtifacts()

        let result = try fixture.store.forceReset(
            newPassword: fixture.newPassword,
            rememberSystemUnlock: false
        )

        #expect(result.warnings == [.resetArtifactCleanupPending])
        for url in staleURLs {
            #expect(try Data(contentsOf: url) == result.encryptedSnapshot.data)
            #expect(fixture.canOpen(url, password: fixture.newPassword))
            #expect(!fixture.canOpen(url, password: fixture.oldPassword))
        }
    }

    @Test("forced reset removes an existing quick key when System Unlock is disabled")
    func forcedResetDeletesExistingQuickKey() throws {
        let fixture = try ForcedResetFixture()
        defer { fixture.remove() }
        try fixture.store.enableQuickUnlock()
        #expect(fixture.quickKey.containsKey)

        let result = try fixture.store.forceReset(
            newPassword: fixture.newPassword,
            rememberSystemUnlock: false
        )

        #expect(!fixture.quickKey.containsKey)
        #expect(result.warnings.isEmpty)
    }

    @Test("stale quick key is gone when the committed marker clears")
    func forcedResetDeletesStaleQuickKeyBeforeMarkerClear() throws {
        let fileOperator = FaultingForcedResetFileOperator()
        let fixture = try ForcedResetFixture(
            transaction: VaultForcedResetTransaction(fileOperator: fileOperator)
        )
        defer { fixture.remove() }
        try fixture.store.enableQuickUnlock()
        let staleQuickKey = try #require(fixture.quickKey.data)
        fixture.quickKey.saveError = .keychainUnavailable
        var quickKeyAbsentAtMarkerClear = false
        var restartAtMarkerClearHadNoQuickKey = false
        var staleKeyOpenedNewActiveAtMarkerClear = true
        fileOperator.afterRecoveryMarkerRemoval = {
            quickKeyAbsentAtMarkerClear = !fixture.quickKey.containsKey
            let interruptedStore = KDBXPasswordVaultStore(
                localStorage: fixture.localStorage,
                unlockKeyStore: fixture.quickKey,
                automationUnlockKeyStore: fixture.automationKey
            )
            restartAtMarkerClearHadNoQuickKey = !interruptedStore.canQuickUnlock
            staleKeyOpenedNewActiveAtMarkerClear = ((try? KDBXReader.parse(
                Data(contentsOf: fixture.activeURL),
                unlockData: UnlockData(rawKeyData: staleQuickKey)
            )) != nil)
        }

        let result = try fixture.store.forceReset(
            newPassword: fixture.newPassword,
            rememberSystemUnlock: true
        )

        #expect(quickKeyAbsentAtMarkerClear)
        #expect(restartAtMarkerClearHadNoQuickKey)
        #expect(!staleKeyOpenedNewActiveAtMarkerClear)
        #expect(result.warnings == [.systemUnlockDisabled])
        #expect(!fixture.quickKey.containsKey)
        #expect(!FileManager.default.fileExists(
            atPath: fixture.localStorage.paths.forcedResetRecoveryMarkerURL.path
        ))
        #expect(fixture.canOpen(fixture.activeURL, password: fixture.newPassword))
    }

    @Test("quick-key deletion failure retains committed recovery until retry")
    func forcedResetQuickKeyDeleteFailureRetainsRecovery() throws {
        let fixture = try ForcedResetFixture()
        defer { fixture.remove() }
        try fixture.store.enableQuickUnlock()
        try fixture.addEntry(title: "Old Entry")
        let oldActive = try Data(contentsOf: fixture.activeURL)
        fixture.quickKey.deleteError = .keychainUnavailable

        #expect(throws: PasswordVaultForcedResetError.recoveryRequired) {
            try fixture.store.forceReset(
                newPassword: fixture.newPassword,
                rememberSystemUnlock: false
            )
        }

        let markerURL = fixture.localStorage.paths.forcedResetRecoveryMarkerURL
        let newDigest = PasswordVaultDigest.hex(try Data(contentsOf: fixture.activeURL))
        #expect(fixture.store.requiresForcedResetRecovery)
        #expect(fixture.store.state == .recoveryRequired("forced-reset-cleanup"))
        #expect(FileManager.default.fileExists(atPath: markerURL.path))
        #expect(fixture.quickKey.containsKey)
        #expect(try Data(contentsOf: fixture.archiveURL) == oldActive)
        #expect(fixture.canOpen(fixture.activeURL, password: fixture.newPassword))
        #expect(fixture.canOpen(fixture.archiveURL, password: fixture.oldPassword))

        fixture.quickKey.deleteError = nil
        let recovered = try fixture.store.retryForcedResetRecovery()
        #expect(recovered == .committed(newDigest: newDigest))
        #expect(try fixture.store.retryForcedResetRecovery() == recovered)
        #expect(!fixture.store.requiresForcedResetRecovery)
        #expect(fixture.store.state == .locked)
        #expect(!fixture.quickKey.containsKey)
        #expect(!FileManager.default.fileExists(atPath: markerURL.path))
    }
}

private enum ForcedResetFault: CaseIterable {
    case archiveStageWrite
    case archiveReadback
    case newVaultStageWrite
    case newVaultReadback
    case revisionCheck
    case archiveReplace
    case activeReplace

    fileprivate func matches(_ checkpoint: VaultForcedResetCheckpoint) -> Bool {
        switch (self, checkpoint) {
        case (.archiveStageWrite, .archiveStageWrite),
             (.archiveReadback, .archiveReadback),
             (.newVaultStageWrite, .newVaultStageWrite),
             (.newVaultReadback, .newVaultReadback),
             (.revisionCheck, .revisionCheck),
             (.archiveReplace, .archiveReplace),
             (.activeReplace, .activeReplace):
            true
        default:
            false
        }
    }
}

private enum ForcedResetRenameFault {
    case archiveInstall
    case activeInstall
    case activeInstallAndRestore

    static let restorableCases: [ForcedResetRenameFault] = [.archiveInstall, .activeInstall]
}

private enum ForcedResetSanitizeFault: CaseIterable {
    case write
    case readback
}

private enum ForcedResetPreCommitIOFault: CaseIterable {
    case archiveWrite
    case archiveReadback
    case activeWrite
    case activeReadback
}

private final class ForcedResetFixture {
    let oldPassword = "forced reset old password"
    let newPassword = "forced reset new password"
    let thirdPassword = "forced reset third password"
    let root: URL
    let localStorage: PasswordVaultLocalStoring
    let activeURL: URL
    let archiveURL: URL
    let quickKey = ForcedResetUnlockKeyStore()
    let automationKey = ForcedResetAutomationKeyStore()
    let store: KDBXPasswordVaultStore
    private(set) var commits = [PasswordVaultCommit]()

    init(
        transaction: VaultForcedResetTransaction = VaultForcedResetTransaction(),
        storageTransform: (FilePasswordVaultLocalStorage) -> PasswordVaultLocalStoring = { $0 }
    ) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let directory = root.appendingPathComponent("PasswordVault", isDirectory: true)
        let backingStorage = FilePasswordVaultLocalStorage(paths: PasswordVaultLocalPaths(
            directoryURL: directory,
            vaultURL: directory.appendingPathComponent("PasteraVault.kdbx"),
            backupURL: directory.appendingPathComponent("PasteraVault.kdbx.bak"),
            metadataURL: directory.appendingPathComponent("PasswordVaultSyncMetadata.json")
        ))
        localStorage = storageTransform(backingStorage)
        activeURL = localStorage.paths.vaultURL
        archiveURL = localStorage.paths.latestForcedResetArchiveURL
        store = KDBXPasswordVaultStore(
            localStorage: localStorage,
            unlockKeyStore: quickKey,
            automationUnlockKeyStore: automationKey,
            forcedResetTransaction: transaction
        )
        store.setCommitObserver { [weak self] commit in self?.commits.append(commit) }
        try store.createDatabase(masterPassword: oldPassword, rememberQuickUnlock: false)
        commits.removeAll()
    }

    func addEntry(title: String) throws {
        let folderID = try store.createFolder(name: "Accounts").id
        _ = try store.create(PasswordVaultDraft(
            folderID: folderID,
            title: title,
            website: "https://example.com",
            username: "fixture",
            note: "",
            password: "fixture secret"
        ))
        commits.removeAll()
    }

    func installPriorArchive() throws -> Data {
        let data = try Data(contentsOf: activeURL)
        try FileManager.default.createDirectory(
            at: localStorage.paths.forcedResetRecoveryDirectoryURL,
            withIntermediateDirectories: true
        )
        try data.write(to: archiveURL, options: .atomic)
        return data
    }

    func installStaleManagedArtifacts() throws -> [URL] {
        let activeData = try Data(contentsOf: activeURL)
        let immediate = localStorage.paths.directoryURL
            .appendingPathComponent("PasteraVault-conflict.kdbx")
        let resolved = localStorage.paths.directoryURL
            .appendingPathComponent("conflicts", isDirectory: true)
            .appendingPathComponent("resolved", isDirectory: true)
            .appendingPathComponent("PasteraVault-resolved.kdbx")
        try FileManager.default.createDirectory(
            at: resolved.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        for url in [localStorage.paths.backupURL, immediate, resolved] {
            try? FileManager.default.removeItem(at: url)
            try activeData.write(to: url, options: .withoutOverwriting)
        }
        return [localStorage.paths.backupURL, immediate, resolved]
    }

    func emptyVaultData(password: String) throws -> Data {
        var content = KDBXContent.makeEmpty(databaseName: "Pastera", generator: "Pastera")
        content.database.meta.historyMaxItems = .value(10)
        let stream = OutputStream(toMemory: ())
        stream.open()
        defer { stream.close() }
        try KDBXWriter(to: stream).write(content, unlockData: UnlockData(masterPassword: password))
        return try #require(stream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data)
    }

    func archiveFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: localStorage.paths.forcedResetRecoveryDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey]
        ).filter { $0.pathExtension.lowercased() == "kdbx" }
            .sorted { $0.path < $1.path }
    }

    func forcedResetTemporaryFiles() -> [URL] {
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        return (enumerator?.allObjects as? [URL] ?? []).filter {
            $0.lastPathComponent.hasPrefix(".pastera-forced-reset-")
        }
    }

    func canOpen(_ url: URL, password: String) -> Bool {
        do {
            _ = try KDBXReader.parse(
                Data(contentsOf: url),
                unlockData: UnlockData(masterPassword: password)
            )
            return true
        } catch {
            return false
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class ForcedResetUnlockKeyStore: VaultUnlockKeyStoring {
    var data: Data?
    var saveError: PasswordVaultError?
    var deleteError: PasswordVaultError?
    var containsKey: Bool { data != nil }
    func save(_ data: Data) throws {
        if let saveError { throw saveError }
        self.data = data
    }
    func load(reason: String) throws -> Data { try #require(data) }
    func delete() throws {
        if let deleteError { throw deleteError }
        data = nil
    }
}

private final class ForcedResetAutomationKeyStore: VaultAutomationUnlockKeyStoring {
    var data: Data?
    var deleteError: PasswordVaultError?
    var containsKey: Bool { data != nil }
    func save(_ data: Data) throws { self.data = data }
    func load() throws -> Data { try #require(data) }
    func delete() throws {
        if let deleteError { throw deleteError }
        data = nil
    }
}

private final class ForcedResetAllowAuthorizer: PasswordVaultAuthorizing {
    func authorize(
        reason: String,
        completion: @escaping (Result<PasswordVaultAuthorizationContext, PasswordVaultError>) -> Void
    ) {
        completion(.success(.init(localAuthenticationContext: LAContext())))
    }
}

private final class ForcedResetNoopAgentAuthorizationResetter: VaultAgentAuthorizationResetting {
    private(set) var callCount = 0
    func revokeAll() throws { callCount += 1 }
}

private final class CountingForcedResetSyncController: PasswordVaultSyncControlling {
    private let base: PasswordVaultSyncControlling
    private let lock = NSLock()
    private var synchronizeCalls = 0
    private var cancelPreparedCalls = 0

    init(base: PasswordVaultSyncControlling) {
        self.base = base
    }

    var snapshot: PasswordVaultSyncSnapshot { base.snapshot }
    var synchronizeCallCount: Int { lock.withLock { synchronizeCalls } }
    var cancelPreparedCallCount: Int { lock.withLock { cancelPreparedCalls } }

    func addObserver(_ observer: @escaping (PasswordVaultSyncSnapshot) -> Void) -> UUID {
        base.addObserver(observer)
    }

    func removeObserver(_ identifier: UUID) {
        base.removeObserver(identifier)
    }

    func record(_ commit: PasswordVaultCommit) {
        base.record(commit)
    }

    func synchronize(reason: SyncCoordinator.Reason) {
        lock.withLock { synchronizeCalls += 1 }
        base.synchronize(reason: reason)
    }

    func prepareForcedReset(previousLocalDigest: String) throws {
        try base.prepareForcedReset(previousLocalDigest: previousLocalDigest)
    }

    func cancelPreparedForcedReset(previousLocalDigest: String) {
        lock.withLock { cancelPreparedCalls += 1 }
        base.cancelPreparedForcedReset(previousLocalDigest: previousLocalDigest)
    }

    func retryForcedReset(
        completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) {
        base.retryForcedReset(completion: completion)
    }

    func enableOneDrive(
        rootURL: URL,
        remoteMasterPassword: String?,
        completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) {
        base.enableOneDrive(
            rootURL: rootURL,
            remoteMasterPassword: remoteMasterPassword,
            completion: completion
        )
    }

    func retry(
        remoteMasterPassword: String,
        completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) {
        base.retry(remoteMasterPassword: remoteMasterPassword, completion: completion)
    }
}

private final class FaultingForcedResetFileOperator: VaultForcedResetFileOperating {
    private let backing = VaultForcedResetFileOperator()
    var renameFault: ForcedResetRenameFault?
    var preCommitIOFault: ForcedResetPreCommitIOFault?
    var failRollbackRemoval = false
    var failStaleArtifactRemoval = false
    var failRecoveryMarkerWrite = false
    var failRecoveryMarkerRemoval = false
    var failCommittedRecoveryMarkerReadback = false
    var failArchiveStageRemoval = false
    var failCommittedActiveReadback = false
    var failActiveRollbackRestore = false
    var afterRecoveryMarkerRemoval: (() -> Void)?
    var sanitizeFault: ForcedResetSanitizeFault?
    private var sanitizedPaths = Set<String>()
    private var didInstallNewActive = false
    private var didWriteCommittedRecoveryMarker = false

    func fileExists(at url: URL) -> Bool {
        backing.fileExists(at: url)
    }

    func createDirectory(at url: URL) throws {
        try backing.createDirectory(at: url)
    }

    func read(from url: URL) throws -> Data {
        if failCommittedRecoveryMarkerReadback,
           didWriteCommittedRecoveryMarker,
           url.pathExtension == "marker" {
            throw CocoaError(.fileReadUnknown)
        }
        if failCommittedActiveReadback,
           didInstallNewActive,
           url.lastPathComponent == "PasteraVault.kdbx" {
            throw CocoaError(.fileReadUnknown)
        }
        if preCommitIOFault == .archiveReadback,
           url.lastPathComponent.contains("archive.staged") {
            throw CocoaError(.fileReadUnknown)
        }
        if preCommitIOFault == .activeReadback,
           url.lastPathComponent.contains("active.staged") {
            throw CocoaError(.fileReadUnknown)
        }
        if sanitizeFault == .readback, sanitizedPaths.contains(url.path) {
            return Data("forced reset readback fault".utf8)
        }
        return try backing.read(from: url)
    }

    func write(_ data: Data, to url: URL, options: Data.WritingOptions) throws {
        if failRecoveryMarkerWrite, url.pathExtension == "marker" {
            throw CocoaError(.fileWriteUnknown)
        }
        if url.pathExtension == "rollback", sanitizeFault == .write {
            throw CocoaError(.fileWriteUnknown)
        }
        try backing.write(data, to: url, options: options)
        if url.pathExtension == "marker",
           let record = try? JSONDecoder().decode(VaultForcedResetRecoveryRecord.self, from: data),
           record.phase == .committed {
            didWriteCommittedRecoveryMarker = true
        }
        if preCommitIOFault == .archiveWrite,
           url.lastPathComponent.contains("archive.staged") {
            throw CocoaError(.fileWriteUnknown)
        }
        if preCommitIOFault == .activeWrite,
           url.lastPathComponent.contains("active.staged") {
            throw CocoaError(.fileWriteUnknown)
        }
        if url.pathExtension == "rollback" { sanitizedPaths.insert(url.path) }
    }

    func remove(at url: URL) throws {
        if failRecoveryMarkerRemoval, url.pathExtension == "marker" {
            throw CocoaError(.fileWriteUnknown)
        }
        if failArchiveStageRemoval, url.lastPathComponent.contains("archive.staged") {
            throw CocoaError(.fileWriteUnknown)
        }
        if failRollbackRemoval, url.pathExtension == "rollback" {
            throw CocoaError(.fileWriteUnknown)
        }
        if failStaleArtifactRemoval, isStaleManagedArtifact(url) {
            throw CocoaError(.fileWriteUnknown)
        }
        try backing.remove(at: url)
        if url.pathExtension == "marker" {
            afterRecoveryMarkerRemoval?()
        }
    }

    func rename(_ sourceURL: URL, to destinationURL: URL) throws {
        if failActiveRollbackRestore,
           sourceURL.lastPathComponent.contains("active.rollback") {
            throw CocoaError(.fileWriteUnknown)
        }
        if renameFault == .archiveInstall,
           sourceURL.lastPathComponent.contains("archive.staged") {
            throw CocoaError(.fileWriteUnknown)
        }
        if renameFault == .activeInstall,
           sourceURL.lastPathComponent.contains("active.staged") {
            throw CocoaError(.fileWriteUnknown)
        }
        if renameFault == .activeInstallAndRestore {
            if sourceURL.lastPathComponent.contains("active.staged")
                || sourceURL.lastPathComponent.contains("active.rollback") {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        try backing.rename(sourceURL, to: destinationURL)
        if sourceURL.lastPathComponent.contains("active.staged"),
           destinationURL.lastPathComponent == "PasteraVault.kdbx" {
            didInstallNewActive = true
        }
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try backing.contentsOfDirectory(at: url)
    }

    private func isStaleManagedArtifact(_ url: URL) -> Bool {
        url.pathExtension == "bak"
            || url.lastPathComponent.contains("conflict")
            || url.path.contains("/conflicts/resolved/")
    }
}

private final class ForcedResetReleaseFailingLocalStorage: PasswordVaultLocalStoring {
    let paths: PasswordVaultLocalPaths
    var failAfterNextTransaction = false
    private let backing: FilePasswordVaultLocalStorage

    init(backing: FilePasswordVaultLocalStorage) {
        self.backing = backing
        paths = backing.paths
    }

    func withExclusiveTransaction<Value>(_ operation: () throws -> Value) throws -> Value {
        let value = try backing.withExclusiveTransaction(operation)
        if failAfterNextTransaction {
            failAfterNextTransaction = false
            throw CocoaError(.fileWriteUnknown)
        }
        return value
    }

    func containsVault() throws -> Bool { try backing.containsVault() }
    func read() throws -> Data { try backing.read() }
    func writeAtomically(_ data: Data) throws { try backing.writeAtomically(data) }
    func removeVaultCreatedByFailedMigration(expectedDigest: String) throws -> Bool {
        try backing.removeVaultCreatedByFailedMigration(expectedDigest: expectedDigest)
    }
    func readBackup() throws -> Data { try backing.readBackup() }
}

// swiftlint:enable file_length
