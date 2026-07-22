import Foundation
import Testing
@testable import Pastera

// The serialized migration matrix keeps its crash/retry fixtures beside the scenarios they support.
// swiftlint:disable file_length

@Suite("Password vault legacy migration", .serialized)
struct PasswordVaultMigrationTests {
    @Test("an existing local vault always wins without reading or changing legacy cloud data")
    func existingLocalVaultSkipsMigration() throws {
        let fixture = try MigrationFixture(localData: validKDBXData("local"), remoteData: validKDBXData("remote"))
        defer { fixture.remove() }
        fixture.metadataStore.saveError = .saveFailed

        let outcome = try fixture.migrator.migrateLegacyVaultIfNeeded()

        #expect(outcome == .notNeeded)
        #expect(fixture.reader.readCount == 0)
        #expect(fixture.metadataStore.savedValues.isEmpty)
        #expect(try fixture.localStorage.read() == validKDBXData("local"))
        #expect(try Data(contentsOf: fixture.remoteURL) == validKDBXData("remote"))
    }

    @Test("migration copies complete encrypted bytes and marks baselines only after local digest readback")
    func successfulMigrationVerifiesBeforeMarkingComplete() throws {
        let remoteData = validKDBXData("complete-encrypted-legacy-vault")
        let events = MigrationEventRecorder()
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.localRevision = 7
        metadata.lastSyncedLocalRevision = 2
        let fixture = try MigrationFixture(remoteData: remoteData, metadata: metadata, events: events)
        defer { fixture.remove() }

        let outcome = try fixture.migrator.migrateLegacyVaultIfNeeded()

        #expect(outcome == .migrated)
        #expect(events.values == ["read-remote", "write-local", "read-local", "save-metadata"])
        #expect(try fixture.localStorage.read() == remoteData)
        #expect(try Data(contentsOf: fixture.remoteURL) == remoteData)
        let saved = try #require(fixture.metadataStore.savedValues.last)
        let digest = PasswordVaultDigest.hex(remoteData)
        #expect(saved.migrationVersion == 1)
        #expect(saved.mode == .oneDrive)
        #expect(saved.lastSyncedLocalDigest == digest)
        #expect(saved.lastObservedRemoteDigest == digest)
        #expect(saved.localRevision == 7)
        #expect(saved.lastSyncedLocalRevision == saved.localRevision)
        #expect(saved.pendingChangeCount == 0)
        #expect(saved.lastFailure == nil)
    }

    @Test("missing configured OneDrive directory waits without completing or creating a local vault")
    func missingConfiguredDirectoryWaits() throws {
        let fixture = try MigrationFixture(remoteData: nil, createSyncRoot: false)
        defer { fixture.remove() }

        let outcome = try fixture.migrator.migrateLegacyVaultIfNeeded()

        #expect(outcome == .waitingForOneDrive)
        #expect(!fixture.localStorage.containsVault())
        #expect(fixture.metadataStore.savedValues.isEmpty)
    }

    @Test("a short cloud read waits for OneDrive and preserves the remote bytes")
    func shortCloudReadWaits() throws {
        let shortData = Data([0x03, 0xD9, 0xA2])
        let fixture = try MigrationFixture(remoteData: shortData)
        defer { fixture.remove() }

        let outcome = try fixture.migrator.migrateLegacyVaultIfNeeded()

        #expect(outcome == .waitingForOneDrive)
        #expect(try Data(contentsOf: fixture.remoteURL) == shortData)
        #expect(!fixture.localStorage.containsVault())
        #expect(fixture.metadataStore.savedValues.isEmpty)
    }

    @Test("an unavailable placeholder waits without changing cloud or local data")
    func placeholderWaits() throws {
        let remoteData = validKDBXData("placeholder")
        let fixture = try MigrationFixture(remoteData: remoteData)
        defer { fixture.remove() }
        fixture.reader.result = .failure(.oneDriveUnavailable)

        let outcome = try fixture.migrator.migrateLegacyVaultIfNeeded()

        #expect(outcome == .waitingForOneDrive)
        #expect(try Data(contentsOf: fixture.remoteURL) == remoteData)
        #expect(!fixture.localStorage.containsVault())
        #expect(fixture.metadataStore.savedValues.isEmpty)
    }

    @Test("a corrupt KDBX signature is a remote recovery failure rather than a password failure")
    func corruptSignatureFailsWithoutWriting() throws {
        let corruptData = Data(repeating: 0xFF, count: 32)
        let fixture = try MigrationFixture(remoteData: corruptData)
        defer { fixture.remove() }

        let outcome = try fixture.migrator.migrateLegacyVaultIfNeeded()

        #expect(outcome == .failed(.remoteCorrupted))
        #expect(try Data(contentsOf: fixture.remoteURL) == corruptData)
        #expect(!fixture.localStorage.containsVault())
        #expect(fixture.metadataStore.savedValues.isEmpty)
    }

    @Test("a local atomic write failure leaves no empty vault and no completion marker")
    func localWriteFailureDoesNotComplete() throws {
        let remoteData = validKDBXData("remote-remains-authoritative")
        let fixture = try MigrationFixture(remoteData: remoteData)
        defer { fixture.remove() }
        fixture.localStorage.writeError = .saveFailed

        let outcome = try fixture.migrator.migrateLegacyVaultIfNeeded()

        #expect(outcome == .failed(.localWriteFailed))
        #expect(try Data(contentsOf: fixture.remoteURL) == remoteData)
        #expect(!fixture.localStorage.containsVault())
        #expect(fixture.metadataStore.savedValues.isEmpty)
    }

    @Test("a mismatched local digest after write never marks migration complete")
    func localReadbackMismatchDoesNotComplete() throws {
        let fixture = try MigrationFixture(remoteData: validKDBXData("remote"))
        defer { fixture.remove() }
        fixture.localStorage.readOverride = validKDBXData("different-local-bytes")

        let outcome = try fixture.migrator.migrateLegacyVaultIfNeeded()

        #expect(outcome == .failed(.localWriteFailed))
        #expect(!fixture.localStorage.containsVault())
        #expect(fixture.metadataStore.savedValues.isEmpty)
    }

    @Test("metadata save failure removes only the new local copy so retry can finish")
    func metadataSaveFailureCanRetry() throws {
        let remoteData = validKDBXData("metadata-retry")
        let fixture = try MigrationFixture(remoteData: remoteData)
        defer { fixture.remove() }
        fixture.metadataStore.saveError = .saveFailed

        let firstOutcome = try fixture.migrator.migrateLegacyVaultIfNeeded()

        #expect(firstOutcome == .failed(.localWriteFailed))
        #expect(!fixture.localStorage.containsVault())
        #expect(try Data(contentsOf: fixture.remoteURL) == remoteData)
        fixture.metadataStore.saveError = nil

        let retryOutcome = try fixture.migrator.migrateLegacyVaultIfNeeded()

        #expect(retryOutcome == .migrated)
        #expect(fixture.localStorage.data == remoteData)
        #expect(fixture.metadataStore.savedValues.last?.migrationVersion == 1)
    }

    @Test("failed rollback survives a new migrator and retries cleanup before trusting the local file")
    func failedRollbackDoesNotBecomeReadyAfterRestart() throws {
        let remoteData = validKDBXData("cleanup-retry")
        let fixture = try MigrationFixture(remoteData: remoteData)
        defer { fixture.remove() }
        fixture.metadataStore.saveError = .saveFailed
        fixture.localStorage.removeError = .saveFailed

        let firstOutcome = try fixture.migrator.migrateLegacyVaultIfNeeded()

        #expect(firstOutcome == .failed(.localCleanupFailed))
        #expect(fixture.localStorage.containsVault())
        #expect(fixture.reader.readCount == 1)
        #expect(fixture.metadataStore.savedValues.isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.journalURL.path))

        let restartedMigrator = fixture.makeMigrator()

        let stillBlockedOutcome = try restartedMigrator.migrateLegacyVaultIfNeeded()

        #expect(stillBlockedOutcome == .failed(.localCleanupFailed))
        #expect(fixture.reader.readCount == 1)

        fixture.localStorage.removeError = nil
        fixture.metadataStore.saveError = nil
        let recoveredMigrator = fixture.makeMigrator()
        let recoveredOutcome = try recoveredMigrator.migrateLegacyVaultIfNeeded()

        #expect(recoveredOutcome == .migrated)
        #expect(fixture.reader.readCount == 2)
        #expect(fixture.localStorage.data == remoteData)
        #expect(fixture.metadataStore.savedValues.last?.migrationVersion == 1)
        #expect(!FileManager.default.fileExists(atPath: fixture.journalURL.path))
    }

    @Test("journal creation failure never writes a local vault")
    func journalCreationFailureDoesNotWriteLocal() throws {
        let fixture = try MigrationFixture(remoteData: validKDBXData("journal-failure"))
        defer { fixture.remove() }
        try Data("not-a-directory".utf8).write(to: fixture.localStorage.paths.directoryURL)

        let outcome = try fixture.migrator.migrateLegacyVaultIfNeeded()

        #expect(outcome == .failed(.localWriteFailed))
        #expect(fixture.localStorage.data == nil)
        #expect(fixture.metadataStore.savedValues.isEmpty)
    }

    @Test("invalid journal never authorizes deletion of an existing local vault")
    func invalidJournalPreservesLocalVault() throws {
        let localData = validKDBXData("local-after-invalid-journal")
        let fixture = try MigrationFixture(localData: localData, remoteData: validKDBXData("remote"))
        defer { fixture.remove() }
        try FileManager.default.createDirectory(
            at: fixture.localStorage.paths.directoryURL,
            withIntermediateDirectories: true
        )
        try Data(#"{"version":2,"state":"unknown","remoteDigest":"not-a-sha256"}"#.utf8)
            .write(to: fixture.journalURL, options: .atomic)

        let outcome = try fixture.makeMigrator().migrateLegacyVaultIfNeeded()

        #expect(outcome == .failed(.localCleanupFailed))
        #expect(fixture.localStorage.data == localData)
        #expect(FileManager.default.fileExists(atPath: fixture.journalURL.path))
        #expect(fixture.reader.readCount == 0)
    }

    @Test("journal digest mismatch preserves a newer local vault for recovery")
    func journalDigestMismatchPreservesLocalVault() throws {
        let journaledData = validKDBXData("journaled")
        let newerLocalData = validKDBXData("newer-local")
        let fixture = try MigrationFixture(localData: newerLocalData, remoteData: journaledData)
        defer { fixture.remove() }
        try writeJournal(digest: PasswordVaultDigest.hex(journaledData), to: fixture.journalURL)

        let outcome = try fixture.makeMigrator().migrateLegacyVaultIfNeeded()

        #expect(outcome == .failed(.localCleanupFailed))
        #expect(fixture.localStorage.data == newerLocalData)
        #expect(FileManager.default.fileExists(atPath: fixture.journalURL.path))
        #expect(fixture.reader.readCount == 0)
    }

    @Test("completed metadata recovers a matching journal without recopying cloud data")
    func completedMetadataRecoversJournalAfterRestart() throws {
        let localData = validKDBXData("completed-before-journal-clear")
        let digest = PasswordVaultDigest.hex(localData)
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.migrationVersion = 1
        metadata.mode = .oneDrive
        metadata.lastSyncedLocalDigest = digest
        metadata.lastObservedRemoteDigest = digest
        let fixture = try MigrationFixture(localData: localData, remoteData: localData, metadata: metadata)
        defer { fixture.remove() }
        try writeJournal(digest: digest, to: fixture.journalURL)

        let outcome = try fixture.makeMigrator().migrateLegacyVaultIfNeeded()

        #expect(outcome == .migrated)
        #expect(fixture.localStorage.data == localData)
        #expect(!FileManager.default.fileExists(atPath: fixture.journalURL.path))
        #expect(fixture.reader.readCount == 0)
    }

    @Test("file storage removes a newly migrated vault when metadata cannot commit")
    func fileStorageRollsBackNewVaultAfterMetadataFailure() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let syncRoot = root.appendingPathComponent("OneDrive", isDirectory: true)
        let remoteURL = VaultFileCoordinator.vaultURL(for: syncRoot)
        let remoteData = validKDBXData("real-file-storage")
        try FileManager.default.createDirectory(at: remoteURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try remoteData.write(to: remoteURL)
        let localPaths = PasswordVaultLocalPaths(
            directoryURL: root.appendingPathComponent("Local", isDirectory: true),
            vaultURL: root.appendingPathComponent("Local/PasteraVault.kdbx"),
            backupURL: root.appendingPathComponent("Local/PasteraVault.kdbx.bak"),
            metadataURL: root.appendingPathComponent("Local/PasswordVaultSyncMetadata.json")
        )
        let localStorage = FilePasswordVaultLocalStorage(paths: localPaths)
        let metadataStore = MigrationMetadataStore(metadata: .defaultLocalOnly)
        metadataStore.saveError = .saveFailed
        let migrator = PasswordVaultMigrationService(
            localStorage: localStorage,
            metadataStore: metadataStore,
            legacySyncRootProvider: { syncRoot }
        )

        let outcome = try migrator.migrateLegacyVaultIfNeeded()

        #expect(outcome == .failed(.localWriteFailed))
        #expect(!localStorage.containsVault())
        #expect(try Data(contentsOf: remoteURL) == remoteData)
        #expect(!FileManager.default.fileExists(atPath: localPaths.backupURL.path))
    }

    @Test("no legacy candidate and local-only metadata stays not configured")
    func noCandidateRemainsNotConfigured() throws {
        let fixture = try MigrationFixture(remoteData: nil, createSyncRoot: true)
        defer { fixture.remove() }

        let outcome = try fixture.migrator.migrateLegacyVaultIfNeeded()

        #expect(outcome == .notNeeded)
        #expect(!fixture.localStorage.containsVault())
        #expect(fixture.metadataStore.savedValues.isEmpty)
    }

    @Test("OneDrive intent without a candidate waits for recovery")
    func enabledOneDriveWithoutCandidateWaits() throws {
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        let fixture = try MigrationFixture(remoteData: nil, metadata: metadata, createSyncRoot: true)
        defer { fixture.remove() }

        let outcome = try fixture.migrator.migrateLegacyVaultIfNeeded()

        #expect(outcome == .waitingForOneDrive)
        #expect(!fixture.localStorage.containsVault())
        #expect(fixture.metadataStore.savedValues.isEmpty)
    }
}

@MainActor
@Suite("Password vault migration environment", .serialized)
struct PasswordVaultMigrationEnvironmentTests {
    @Test("a verified migration publishes one anonymous migration commit")
    func migrationPublishesCommitOriginAndDigest() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = validKDBXData("commit")
        let storage = MigrationLocalStorage(root: root)
        let store = KDBXPasswordVaultStore(localStorage: storage)
        let migrator = BlockingMigrator {
            storage.data = data
            return .migrated
        }
        var commits = [PasswordVaultCommit]()
        store.setCommitObserver { commits.append($0) }

        store.prepareLocalCopy(using: migrator)

        #expect(commits == [PasswordVaultCommit(
            origin: .migration,
            encryptedDigest: PasswordVaultDigest.hex(data)
        )])
    }

    @Test("environment starts migration off the main thread on the vault serial executor")
    func environmentStartsMigrationWithoutBlockingMainThread() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = MigrationLocalStorage(root: root)
        let store = KDBXPasswordVaultStore(localStorage: storage)
        let queue = DispatchQueue(label: "PasswordVaultMigrationEnvironmentTests.store")
        let queueKey = DispatchSpecificKey<Int>()
        queue.setSpecific(key: queueKey, value: 1)
        let controller = PasswordVaultUIController(store: store, storeQueue: queue)
        let gate = DispatchSemaphore(value: 0)
        let migrator = BlockingMigrator {
            #expect(!Thread.isMainThread)
            #expect(DispatchQueue.getSpecific(key: queueKey) == 1)
            gate.wait()
            storage.data = validKDBXData("migrated")
            return .migrated
        }

        let startedAt = ContinuousClock.now
        let environment = Environment(
            passwordVaultStore: store,
            passwordVaultMigrator: migrator,
            passwordVaultUIController: controller
        )
        let elapsed = startedAt.duration(to: .now)

        #expect(elapsed < .milliseconds(100))
        await waitForMigrationCall(migrator)
        #expect(environment.passwordVaultStore.state == .preparingLocalCopy)
        gate.signal()
        await waitForMigrationState(store, .locked)
        #expect(migrator.callCount == 1)
    }

    @Test("an unavailable legacy copy can retry successfully and only then become locked")
    func retrySuccessTransitionsToLocked() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = MigrationLocalStorage(root: root)
        let store = KDBXPasswordVaultStore(localStorage: storage)
        let controller = PasswordVaultUIController(
            store: store,
            storeQueue: DispatchQueue(label: "PasswordVaultMigrationEnvironmentTests.retry")
        )
        let migrator = SequencedMigrator(
            outcomes: [.waitingForOneDrive, .migrated],
            beforeOutcome: { index in
                if index == 1 { storage.data = validKDBXData("retried") }
            }
        )

        store.prepareLocalCopy(using: migrator)
        await waitForMigrationState(store, .localCopyUnavailable(.oneDriveUnavailable))
        store.prepareLocalCopy(using: migrator)
        await waitForMigrationState(store, .locked)

        #expect(controller.state == .locked)
        #expect(migrator.callCount == 2)
    }
}

private final class MigrationFixture {
    let root: URL
    let syncRoot: URL
    let remoteURL: URL
    let localStorage: MigrationLocalStorage
    let metadataStore: MigrationMetadataStore
    let reader: MigrationReader
    let migrator: PasswordVaultMigrationService
    var journalURL: URL {
        localStorage.paths.directoryURL.appendingPathComponent("PasswordVaultMigrationJournal.json")
    }

    init(
        localData: Data? = nil,
        remoteData: Data?,
        metadata: PasswordVaultSyncMetadata = .defaultLocalOnly,
        createSyncRoot: Bool = true,
        events: MigrationEventRecorder? = nil
    ) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        syncRoot = root.appendingPathComponent("OneDrive", isDirectory: true)
        remoteURL = VaultFileCoordinator.vaultURL(for: syncRoot)
        localStorage = MigrationLocalStorage(root: root.appendingPathComponent("Local", isDirectory: true), events: events)
        localStorage.data = localData
        metadataStore = MigrationMetadataStore(metadata: metadata, events: events)
        reader = MigrationReader(events: events)
        if createSyncRoot {
            try FileManager.default.createDirectory(at: remoteURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        if let remoteData {
            try FileManager.default.createDirectory(at: remoteURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try remoteData.write(to: remoteURL)
        }
        migrator = PasswordVaultMigrationService(
            localStorage: localStorage,
            metadataStore: metadataStore,
            legacySyncRootProvider: { [syncRoot] in syncRoot },
            legacyReader: reader
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func makeMigrator() -> PasswordVaultMigrationService {
        PasswordVaultMigrationService(
            localStorage: localStorage,
            metadataStore: metadataStore,
            legacySyncRootProvider: { [syncRoot] in syncRoot },
            legacyReader: reader
        )
    }
}

private final class MigrationLocalStorage: PasswordVaultLocalStoring {
    let paths: PasswordVaultLocalPaths
    var data: Data?
    var readOverride: Data?
    var writeError: PasswordVaultError?
    var removeError: PasswordVaultError?
    private let events: MigrationEventRecorder?

    init(root: URL, events: MigrationEventRecorder? = nil) {
        paths = PasswordVaultLocalPaths(
            directoryURL: root,
            vaultURL: root.appendingPathComponent("PasteraVault.kdbx"),
            backupURL: root.appendingPathComponent("PasteraVault.kdbx.bak"),
            metadataURL: root.appendingPathComponent("PasswordVaultSyncMetadata.json")
        )
        self.events = events
    }

    func containsVault() -> Bool { data != nil }

    func read() throws -> Data {
        events?.append("read-local")
        if let readOverride { return readOverride }
        guard let data else { throw PasswordVaultError.databaseNotConfigured }
        return data
    }

    func writeAtomically(_ data: Data) throws {
        events?.append("write-local")
        if let writeError { throw writeError }
        self.data = data
    }

    func removeVaultCreatedByFailedMigration() throws {
        if let removeError { throw removeError }
        data = nil
        readOverride = nil
    }

    func readBackup() throws -> Data { throw PasswordVaultError.databaseNotConfigured }
}

private final class MigrationMetadataStore: PasswordVaultSyncMetadataStoring {
    private var metadata: PasswordVaultSyncMetadata
    private let events: MigrationEventRecorder?
    private(set) var savedValues = [PasswordVaultSyncMetadata]()
    var saveError: PasswordVaultError?

    init(metadata: PasswordVaultSyncMetadata, events: MigrationEventRecorder? = nil) {
        self.metadata = metadata
        self.events = events
    }

    func load() throws -> PasswordVaultSyncMetadata { metadata }

    func save(_ metadata: PasswordVaultSyncMetadata) throws {
        events?.append("save-metadata")
        if let saveError { throw saveError }
        self.metadata = metadata
        savedValues.append(metadata)
    }
}

private final class MigrationReader: PasswordVaultLegacyReading {
    var result: Result<Data, PasswordVaultLocalPreparationFailure>?
    private let events: MigrationEventRecorder?
    private(set) var readCount = 0

    init(events: MigrationEventRecorder? = nil) {
        self.events = events
    }

    func readCompleteFile(at url: URL) throws -> Data {
        readCount += 1
        events?.append("read-remote")
        if let result { return try result.get() }
        return try Data(contentsOf: url)
    }
}

private final class MigrationEventRecorder {
    private(set) var values = [String]()

    func append(_ value: String) { values.append(value) }
}

private final class BlockingMigrator: PasswordVaultMigrating {
    private let work: () throws -> PasswordVaultMigrationOutcome
    private let lock = NSLock()
    private var storedCallCount = 0

    var callCount: Int {
        lock.withLock { storedCallCount }
    }

    init(work: @escaping () throws -> PasswordVaultMigrationOutcome) {
        self.work = work
    }

    func migrateLegacyVaultIfNeeded() throws -> PasswordVaultMigrationOutcome {
        lock.withLock { storedCallCount += 1 }
        return try work()
    }
}

private final class SequencedMigrator: PasswordVaultMigrating {
    private let outcomes: [PasswordVaultMigrationOutcome]
    private let beforeOutcome: (Int) -> Void
    private(set) var callCount = 0

    init(outcomes: [PasswordVaultMigrationOutcome], beforeOutcome: @escaping (Int) -> Void) {
        self.outcomes = outcomes
        self.beforeOutcome = beforeOutcome
    }

    func migrateLegacyVaultIfNeeded() throws -> PasswordVaultMigrationOutcome {
        let index = callCount
        beforeOutcome(index)
        callCount += 1
        return outcomes[index]
    }
}

private func validKDBXData(_ suffix: String) -> Data {
    Data([0x03, 0xD9, 0xA2, 0x9A, 0x67, 0xFB, 0x4B, 0xB5]) + Data(suffix.utf8)
}

private func writeJournal(digest: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = Data(
        #"{"version":1,"state":"copyingLegacyCloudVault","remoteDigest":"\#(digest)"}"#
            .utf8
    )
    try data.write(to: url, options: .atomic)
}

@MainActor
private func waitForMigrationState(
    _ store: PasswordVaultStore,
    _ expected: PasswordVaultState,
    timeout: TimeInterval = 5
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while store.state != expected, Date() < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
    #expect(store.state == expected)
}

private func waitForMigrationCall(
    _ migrator: BlockingMigrator,
    timeout: TimeInterval = 5
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while migrator.callCount == 0, Date() < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
    #expect(migrator.callCount == 1)
}
