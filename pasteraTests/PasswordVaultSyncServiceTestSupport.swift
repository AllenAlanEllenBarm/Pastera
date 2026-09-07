import Foundation
@testable import Pastera

enum SyncServiceFixtureError: Error {
    case metadataWrite
}

final class SyncServiceFixture {
    let service: PasswordVaultSyncService
    let access: FakePasswordVaultSyncAccess
    let metadata: FakePasswordVaultSyncMetadataStore
    let cloud: FakePasswordVaultCloudReplica
    let processStatus: FakeOneDriveProcessStatusService
    let root: FakePasswordVaultSyncRoot
    let queue: DispatchQueue
    let oneDriveAppURL = URL(fileURLWithPath: "/Applications/OneDrive.app")

    init(
        service: PasswordVaultSyncService,
        access: FakePasswordVaultSyncAccess,
        metadata: FakePasswordVaultSyncMetadataStore,
        cloud: FakePasswordVaultCloudReplica,
        processStatus: FakeOneDriveProcessStatusService,
        root: FakePasswordVaultSyncRoot,
        queue: DispatchQueue
    ) {
        self.service = service
        self.access = access
        self.metadata = metadata
        self.cloud = cloud
        self.processStatus = processStatus
        self.root = root
        self.queue = queue
    }

    func drain() {
        queue.sync {}
    }
}

func makeSyncServiceFixture(
    metadata initialMetadata: PasswordVaultSyncMetadata = .defaultLocalOnly,
    localData: Data = Data("local".utf8),
    access providedAccess: FakePasswordVaultSyncAccess? = nil,
    callbackDispatcher: ((@escaping () -> Void) -> Void)? = { $0() }
) throws -> SyncServiceFixture {
    let access = providedAccess ?? FakePasswordVaultSyncAccess(data: localData)
    let metadata = FakePasswordVaultSyncMetadataStore(value: initialMetadata)
    let cloud = FakePasswordVaultCloudReplica()
    let process = FakeOneDriveProcessStatusService()
    let root = FakePasswordVaultSyncRoot()
    let queue = DispatchQueue(label: "PasswordVaultSyncServiceTests.\(UUID().uuidString)")
    let service = try PasswordVaultSyncService(
        access: access,
        metadataStore: metadata,
        cloudReplica: cloud,
        processStatus: process,
        rootURLProvider: { root.urlReadCount += 1; return root.url },
        rootURLSetter: { root.url = $0 },
        rootValidator: { url in root.validate(url) },
        queue: queue,
        callbackDispatcher: callbackDispatcher,
        now: { Date(timeIntervalSince1970: 1_725_000_000) }
    )
    return SyncServiceFixture(
        service: service,
        access: access,
        metadata: metadata,
        cloud: cloud,
        processStatus: process,
        root: root,
        queue: queue
    )
}

func makePreparedResetFixture(
    previousLocalData: Data,
    localData: Data,
    replacementLocalDigest: String? = nil
) throws -> SyncServiceFixture {
    var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
    metadata.mode = .oneDrive
    metadata.pendingForcedReset = PasswordVaultPendingForcedReset(
        previousLocalDigest: PasswordVaultDigest.hex(previousLocalData),
        replacementLocalDigest: replacementLocalDigest,
        didInspectRemote: false,
        observedRemoteDigest: nil,
        archivedRemoteDigest: nil,
        remoteArchiveRequired: nil
    )
    return try makeSyncServiceFixture(metadata: metadata, localData: localData)
}

func makePendingForcedResetFixture(
    previousLocalData: Data = Data("previous-local".utf8),
    localData: Data = Data("replacement-local".utf8),
    remoteData: Data? = Data("previous-remote".utf8)
) throws -> SyncServiceFixture {
    let fixture = try makePreparedResetFixture(
        previousLocalData: previousLocalData,
        localData: localData,
        replacementLocalDigest: PasswordVaultDigest.hex(localData)
    )
    fixture.cloud.snapshot = remoteData.map {
        PasswordVaultCloudSnapshot(data: $0, digest: PasswordVaultDigest.hex($0))
    }
    return fixture
}

final class FakePasswordVaultSyncAccess: PasswordVaultSyncAccess {
    var state: PasswordVaultState = .locked
    var data: Data
    var snapshotError: Error?
    var snapshotReadCount = 0
    var mergeApplication: PasswordVaultMergeApplication?
    var mergeError: Error?
    var mergeCount = 0
    var receivedRemotePasswords = [String?]()
    private var observer: (PasswordVaultCommit) -> Void = { _ in }

    init(data: Data) {
        self.data = data
    }

    func encryptedSnapshot() throws -> PasswordVaultEncryptedSnapshot {
        snapshotReadCount += 1
        if let snapshotError { throw snapshotError }
        return PasswordVaultEncryptedSnapshot(data: data, digest: PasswordVaultDigest.hex(data))
    }

    // swiftlint:disable inclusive_language
    func mergeRemoteSnapshot(
        _ remoteData: Data,
        remoteMasterPassword: String?
    ) throws -> PasswordVaultMergeApplication {
        mergeCount += 1
        receivedRemotePasswords.append(remoteMasterPassword)
        if let mergeError { throw mergeError }
        let result = mergeApplication ?? PasswordVaultMergeApplication(
            encryptedSnapshot: PasswordVaultEncryptedSnapshot(
                data: remoteData,
                digest: PasswordVaultDigest.hex(remoteData)
            ),
            conflictCopyCount: 0
        )
        data = result.encryptedSnapshot.data
        observer(PasswordVaultCommit(origin: .syncMerge, encryptedDigest: result.encryptedSnapshot.digest))
        return result
    }
    // swiftlint:enable inclusive_language

    func setCommitObserver(_ observer: @escaping (PasswordVaultCommit) -> Void) {
        self.observer = observer
    }
}

final class FakePasswordVaultSyncMetadataStore: PasswordVaultSyncMetadataStoring {
    var value: PasswordVaultSyncMetadata
    var saveError: Error?
    var saveFailurePredicate: ((PasswordVaultSyncMetadata) -> Bool)?
    var savedValues = [PasswordVaultSyncMetadata]()

    init(value: PasswordVaultSyncMetadata) {
        self.value = value
    }

    func load() throws -> PasswordVaultSyncMetadata { value }

    func save(_ metadata: PasswordVaultSyncMetadata) throws {
        if let saveError { throw saveError }
        if saveFailurePredicate?(metadata) == true {
            throw SyncServiceFixtureError.metadataWrite
        }
        value = metadata
        savedValues.append(metadata)
    }
}

final class FakePasswordVaultCloudReplica: PasswordVaultCloudReplica {
    enum OperationKind: Equatable {
        case archiveWrite
        case activeWrite
    }

    struct Operation: Equatable {
        let kind: OperationKind
    }

    struct Write: Equatable {
        let data: Data
        let rootURL: URL
        let expectation: PasswordVaultRemoteExpectation
    }

    var snapshot: PasswordVaultCloudSnapshot?
    var archiveSnapshot: PasswordVaultCloudSnapshot?
    var readError: PasswordVaultSyncFailure?
    var archiveReadError: PasswordVaultSyncFailure?
    var writeError: PasswordVaultSyncFailure?
    var archiveWriteError: PasswordVaultSyncFailure?
    var postActiveWriteError: PasswordVaultSyncFailure?
    var activeSnapshotBeforeNextWrite: PasswordVaultCloudSnapshot?
    var archiveReadSnapshotOverride: PasswordVaultCloudSnapshot?
    var readCount = 0
    var archiveReadCount = 0
    var writes = [Write]()
    var archiveWrites = [Write]()
    var operations = [Operation]()

    func read(rootURL: URL) throws -> PasswordVaultCloudSnapshot? {
        readCount += 1
        if let readError { throw readError }
        return snapshot
    }

    func writeAtomically(
        _ data: Data,
        rootURL: URL,
        expecting expectation: PasswordVaultRemoteExpectation
    ) throws -> String {
        operations.append(Operation(kind: .activeWrite))
        writes.append(Write(data: data, rootURL: rootURL, expectation: expectation))
        if let writeError { throw writeError }
        if let activeSnapshotBeforeNextWrite {
            snapshot = activeSnapshotBeforeNextWrite
            self.activeSnapshotBeforeNextWrite = nil
        }
        try verify(expectation, against: snapshot)
        let digest = PasswordVaultDigest.hex(data)
        snapshot = PasswordVaultCloudSnapshot(data: data, digest: digest)
        if let postActiveWriteError { throw postActiveWriteError }
        return digest
    }

    func readLatestForcedResetArchive(rootURL: URL) throws -> PasswordVaultCloudSnapshot? {
        archiveReadCount += 1
        if let archiveReadError { throw archiveReadError }
        return archiveReadSnapshotOverride ?? archiveSnapshot
    }

    func writeLatestForcedResetArchiveAtomically(
        _ data: Data,
        rootURL: URL,
        expecting expectation: PasswordVaultRemoteExpectation
    ) throws -> String {
        operations.append(Operation(kind: .archiveWrite))
        archiveWrites.append(Write(data: data, rootURL: rootURL, expectation: expectation))
        if let archiveWriteError { throw archiveWriteError }
        try verify(expectation, against: archiveSnapshot)
        let digest = PasswordVaultDigest.hex(data)
        archiveSnapshot = PasswordVaultCloudSnapshot(data: data, digest: digest)
        return digest
    }

    private func verify(
        _ expectation: PasswordVaultRemoteExpectation,
        against current: PasswordVaultCloudSnapshot?
    ) throws {
        switch (expectation, current) {
        case (.absent, nil):
            return
        case let (.digest(expected), current?) where current.digest == expected:
            return
        default:
            throw PasswordVaultSyncFailure.remoteVerificationFailed
        }
    }

}

final class FakeOneDriveProcessStatusService: OneDriveProcessStatusServicing {
    var status: OneDriveProcessStatus = .running(
        appURL: URL(fileURLWithPath: "/Applications/OneDrive.app")
    )
    var readCount = 0

    func currentStatus() -> OneDriveProcessStatus {
        readCount += 1
        return status
    }

    func isMainApplicationRunning() -> Bool { status.isRunning }

    func openOneDrive() -> Bool { true }

    func startMonitoring(_ onChange: @escaping () -> Void) -> OneDriveProcessStatusObservation {
        OneDriveProcessStatusObservation {}
    }
}

final class FakePasswordVaultSyncRoot {
    var url: URL? = FileManager.default.temporaryDirectory
        .appendingPathComponent("OneDrive-Test", isDirectory: true)
    var validationFailure: PasswordVaultSyncFailure?
    var urlReadCount = 0
    var validationCount = 0

    func validate(_ url: URL) -> PasswordVaultSyncFailure? {
        validationCount += 1
        return validationFailure
    }
}
