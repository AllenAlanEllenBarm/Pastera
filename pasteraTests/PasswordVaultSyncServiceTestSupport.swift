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
    callbackDispatcher: ((@escaping () -> Void) -> Void)? = { $0() }
) throws -> SyncServiceFixture {
    let access = FakePasswordVaultSyncAccess(data: localData)
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

final class FakePasswordVaultSyncAccess: PasswordVaultSyncAccess {
    var state: PasswordVaultState = .locked
    var data: Data
    var mergeApplication: PasswordVaultMergeApplication?
    var mergeError: Error?
    var mergeCount = 0
    var receivedRemotePasswords = [String?]()
    private var observer: (PasswordVaultCommit) -> Void = { _ in }

    init(data: Data) {
        self.data = data
    }

    func encryptedSnapshot() throws -> PasswordVaultEncryptedSnapshot {
        PasswordVaultEncryptedSnapshot(data: data, digest: PasswordVaultDigest.hex(data))
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
    var savedValues = [PasswordVaultSyncMetadata]()

    init(value: PasswordVaultSyncMetadata) {
        self.value = value
    }

    func load() throws -> PasswordVaultSyncMetadata { value }

    func save(_ metadata: PasswordVaultSyncMetadata) throws {
        if let saveError { throw saveError }
        value = metadata
        savedValues.append(metadata)
    }
}

final class FakePasswordVaultCloudReplica: PasswordVaultCloudReplica {
    struct Write: Equatable {
        let data: Data
        let rootURL: URL
        let expectation: PasswordVaultRemoteExpectation
    }

    var snapshot: PasswordVaultCloudSnapshot?
    var readError: PasswordVaultSyncFailure?
    var writeError: PasswordVaultSyncFailure?
    var readCount = 0
    var writes = [Write]()

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
        writes.append(Write(data: data, rootURL: rootURL, expectation: expectation))
        if let writeError { throw writeError }
        let digest = PasswordVaultDigest.hex(data)
        snapshot = PasswordVaultCloudSnapshot(data: data, digest: digest)
        return digest
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
