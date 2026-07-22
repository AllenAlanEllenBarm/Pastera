import Foundation

enum PasswordVaultLocalPreparationFailure: Error, Equatable {
    case oneDriveUnavailable
    case remoteCorrupted
    case localWriteFailed
    case localCleanupFailed
}

enum PasswordVaultMigrationOutcome: Equatable {
    case notNeeded
    case migrated
    case waitingForOneDrive
    case failed(PasswordVaultLocalPreparationFailure)
}

protocol PasswordVaultMigrating {
    func migrateLegacyVaultIfNeeded() throws -> PasswordVaultMigrationOutcome
}

protocol PasswordVaultLegacyReading {
    func readCompleteFile(at url: URL) throws -> Data
}

private struct PasswordVaultMigrationJournal: Codable, Equatable {
    static let currentVersion = 1
    static let copyingState = "copyingLegacyCloudVault"

    let version: Int
    let state: String
    let remoteDigest: String

    init(remoteDigest: String) {
        version = Self.currentVersion
        state = Self.copyingState
        self.remoteDigest = remoteDigest
    }

    var isValid: Bool {
        version == Self.currentVersion &&
            state == Self.copyingState &&
            remoteDigest.count == 64 &&
            remoteDigest.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }
}

private enum PasswordVaultMigrationJournalError: Error {
    case invalidJournal
}

private protocol PasswordVaultMigrationJournaling {
    func load() throws -> PasswordVaultMigrationJournal?
    func begin(remoteDigest: String) throws
    func clear() throws
}

private final class FilePasswordVaultMigrationJournal: PasswordVaultMigrationJournaling {
    private let directoryURL: URL
    private let journalURL: URL
    private let fileManager: FileManager

    init(paths: PasswordVaultLocalPaths, fileManager: FileManager) {
        directoryURL = paths.directoryURL
        journalURL = paths.directoryURL.appendingPathComponent("PasswordVaultMigrationJournal.json")
        self.fileManager = fileManager
    }

    func load() throws -> PasswordVaultMigrationJournal? {
        guard fileManager.fileExists(atPath: journalURL.path) else { return nil }
        let journal = try JSONDecoder().decode(
            PasswordVaultMigrationJournal.self,
            from: Data(contentsOf: journalURL)
        )
        guard journal.isValid else { throw PasswordVaultMigrationJournalError.invalidJournal }
        return journal
    }

    func begin(remoteDigest: String) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(PasswordVaultMigrationJournal(remoteDigest: remoteDigest))
        try data.write(to: journalURL, options: .atomic)
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: journalURL.path) else { return }
        try fileManager.removeItem(at: journalURL)
    }
}

final class CoordinatedPasswordVaultLegacyReader: PasswordVaultLegacyReading {
    private let fileCoordinator: NSFileCoordinator

    init(fileCoordinator: NSFileCoordinator = NSFileCoordinator()) {
        self.fileCoordinator = fileCoordinator
    }

    func readCompleteFile(at url: URL) throws -> Data {
        do {
            let values = try url.resourceValues(forKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey
            ])
            guard values.isRegularFile == true else {
                throw PasswordVaultLocalPreparationFailure.oneDriveUnavailable
            }
            if values.isUbiquitousItem == true,
               values.ubiquitousItemDownloadingStatus != .current {
                throw PasswordVaultLocalPreparationFailure.oneDriveUnavailable
            }

            var coordinationError: NSError?
            var result: Result<Data, Error>?
            fileCoordinator.coordinate(
                readingItemAt: url,
                options: .withoutChanges,
                error: &coordinationError
            ) { coordinatedURL in
                result = Result {
                    let coordinatedValues = try coordinatedURL.resourceValues(forKeys: [.fileSizeKey])
                    let data = try Data(contentsOf: coordinatedURL, options: .mappedIfSafe)
                    guard coordinatedValues.fileSize == data.count else {
                        throw PasswordVaultLocalPreparationFailure.oneDriveUnavailable
                    }
                    return data
                }
            }
            if coordinationError != nil {
                throw PasswordVaultLocalPreparationFailure.oneDriveUnavailable
            }
            guard let result else {
                throw PasswordVaultLocalPreparationFailure.oneDriveUnavailable
            }
            return try result.get()
        } catch let failure as PasswordVaultLocalPreparationFailure {
            throw failure
        } catch {
            throw PasswordVaultLocalPreparationFailure.oneDriveUnavailable
        }
    }
}

final class PasswordVaultMigrationService: PasswordVaultMigrating {
    private static let signature = Data([0x03, 0xD9, 0xA2, 0x9A, 0x67, 0xFB, 0x4B, 0xB5])

    private let localStorage: PasswordVaultLocalStoring
    private let metadataStore: PasswordVaultSyncMetadataStoring
    private let legacySyncRootProvider: () -> URL?
    private let legacyReader: PasswordVaultLegacyReading
    private let fileManager: FileManager
    private let now: () -> Date
    private let journal: PasswordVaultMigrationJournaling

    init(
        localStorage: PasswordVaultLocalStoring,
        metadataStore: PasswordVaultSyncMetadataStoring,
        legacySyncRootProvider: @escaping () -> URL?,
        legacyReader: PasswordVaultLegacyReading = CoordinatedPasswordVaultLegacyReader(),
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.localStorage = localStorage
        self.metadataStore = metadataStore
        self.legacySyncRootProvider = legacySyncRootProvider
        self.legacyReader = legacyReader
        self.fileManager = fileManager
        self.now = now
        journal = FilePasswordVaultMigrationJournal(paths: localStorage.paths, fileManager: fileManager)
    }

    func migrateLegacyVaultIfNeeded() throws -> PasswordVaultMigrationOutcome {
        if let recoveryOutcome = recoverJournaledMigrationIfNeeded() { return recoveryOutcome }
        guard !localStorage.containsVault() else { return .notNeeded }

        var metadata = try metadataStore.load()
        guard let syncRootURL = legacySyncRootProvider() else {
            return metadata.mode == .oneDrive ? .waitingForOneDrive : .notNeeded
        }
        guard fileManager.fileExists(atPath: syncRootURL.path) else {
            return .waitingForOneDrive
        }

        let remoteURL = VaultFileCoordinator.vaultURL(for: syncRootURL)
        guard fileManager.fileExists(atPath: remoteURL.path) else {
            return metadata.mode == .oneDrive ? .waitingForOneDrive : .notNeeded
        }

        let remoteData: Data
        do {
            remoteData = try legacyReader.readCompleteFile(at: remoteURL)
        } catch let failure as PasswordVaultLocalPreparationFailure {
            return failure == .oneDriveUnavailable ? .waitingForOneDrive : .failed(failure)
        } catch {
            return .waitingForOneDrive
        }
        guard remoteData.count >= Self.signature.count else {
            return .waitingForOneDrive
        }
        guard remoteData.prefix(Self.signature.count) == Self.signature else {
            return .failed(.remoteCorrupted)
        }

        let remoteDigest = PasswordVaultDigest.hex(remoteData)
        do {
            try journal.begin(remoteDigest: remoteDigest)
        } catch {
            return .failed(.localWriteFailed)
        }
        do {
            try localStorage.writeAtomically(remoteData)
            let localData = try localStorage.read()
            guard PasswordVaultDigest.hex(localData) == remoteDigest else {
                return discardNewLocalCopy()
            }
        } catch {
            return discardNewLocalCopy()
        }

        metadata.migrationVersion = 1
        metadata.mode = .oneDrive
        metadata.lastSyncedLocalRevision = metadata.localRevision
        metadata.lastSyncedLocalDigest = remoteDigest
        metadata.lastObservedRemoteDigest = remoteDigest
        metadata.lastSyncAt = now()
        metadata.pendingChangeCount = 0
        metadata.lastFailure = nil
        do {
            try metadataStore.save(metadata)
        } catch {
            return discardNewLocalCopy()
        }
        do {
            try journal.clear()
        } catch {
            return .failed(.localCleanupFailed)
        }
        return .migrated
    }

    private func discardNewLocalCopy() -> PasswordVaultMigrationOutcome {
        do {
            try localStorage.removeVaultCreatedByFailedMigration()
        } catch {
            return .failed(.localCleanupFailed)
        }
        do {
            try journal.clear()
            return .failed(.localWriteFailed)
        } catch {
            return .failed(.localCleanupFailed)
        }
    }

    private func recoverJournaledMigrationIfNeeded() -> PasswordVaultMigrationOutcome? {
        let savedJournal: PasswordVaultMigrationJournal
        do {
            guard let loadedJournal = try journal.load() else { return nil }
            savedJournal = loadedJournal
        } catch {
            return .failed(.localCleanupFailed)
        }

        let metadata: PasswordVaultSyncMetadata
        do {
            metadata = try metadataStore.load()
        } catch {
            return .failed(.localCleanupFailed)
        }

        if metadata.migrationVersion >= 1,
           metadata.lastSyncedLocalDigest == savedJournal.remoteDigest,
           localDigestMatches(savedJournal.remoteDigest) {
            do {
                try journal.clear()
                return .migrated
            } catch {
                return .failed(.localCleanupFailed)
            }
        }

        do {
            if localStorage.containsVault() {
                guard localDigestMatches(savedJournal.remoteDigest) else {
                    return .failed(.localCleanupFailed)
                }
                try localStorage.removeVaultCreatedByFailedMigration()
            }
            try journal.clear()
            return nil
        } catch {
            return .failed(.localCleanupFailed)
        }
    }

    private func localDigestMatches(_ expectedDigest: String) -> Bool {
        guard localStorage.containsVault(),
              let localData = try? localStorage.read() else { return false }
        return PasswordVaultDigest.hex(localData) == expectedDigest
    }
}
