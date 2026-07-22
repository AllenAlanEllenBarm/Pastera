import CryptoKit
import Foundation
import KDBXKit

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
        let initialOutcome: PasswordVaultMigrationOutcome?
        do {
            initialOutcome = try localStorage.withExclusiveTransaction {
                if let recoveryOutcome = recoverJournaledMigrationIfNeeded() { return recoveryOutcome }
                return try localStorage.containsVault() ? .notNeeded : nil
            }
        } catch {
            return .failed(.localCleanupFailed)
        }
        if let initialOutcome { return initialOutcome }

        let metadata = try metadataStore.load()
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
        guard remoteData.prefix(Self.signature.count) == Self.signature,
              PasswordVaultKDBXEnvelopeValidator.isValid(remoteData) else {
            return .failed(.remoteCorrupted)
        }

        let remoteDigest = PasswordVaultDigest.hex(remoteData)
        do {
            return try localStorage.withExclusiveTransaction {
                if let recoveryOutcome = recoverJournaledMigrationIfNeeded() { return recoveryOutcome }
                guard try !localStorage.containsVault() else { return .notNeeded }
                var migratedMetadata = try metadataStore.load()

                do {
                    try journal.begin(remoteDigest: remoteDigest)
                } catch {
                    return .failed(.localWriteFailed)
                }
                do {
                    try localStorage.writeAtomically(remoteData)
                    let localData = try localStorage.read()
                    guard PasswordVaultDigest.hex(localData) == remoteDigest else {
                        return discardNewLocalCopy(expectedDigest: remoteDigest)
                    }
                } catch {
                    return discardNewLocalCopy(expectedDigest: remoteDigest)
                }

                migratedMetadata.migrationVersion = 1
                migratedMetadata.mode = .oneDrive
                migratedMetadata.lastSyncedLocalRevision = migratedMetadata.localRevision
                migratedMetadata.lastSyncedLocalDigest = remoteDigest
                migratedMetadata.lastObservedRemoteDigest = remoteDigest
                migratedMetadata.lastSyncAt = now()
                migratedMetadata.pendingChangeCount = 0
                migratedMetadata.lastFailure = nil
                do {
                    try metadataStore.save(migratedMetadata)
                } catch {
                    return discardNewLocalCopy(expectedDigest: remoteDigest)
                }
                do {
                    try journal.clear()
                } catch {
                    return .failed(.localCleanupFailed)
                }
                return .migrated
            }
        } catch {
            return .failed(.localWriteFailed)
        }
    }

    private func discardNewLocalCopy(expectedDigest: String) -> PasswordVaultMigrationOutcome {
        do {
            guard try localStorage.removeVaultCreatedByFailedMigration(expectedDigest: expectedDigest) else {
                return .failed(.localCleanupFailed)
            }
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
            if try localStorage.containsVault() {
                guard localDigestMatches(savedJournal.remoteDigest) else {
                    return .failed(.localCleanupFailed)
                }
                guard try localStorage.removeVaultCreatedByFailedMigration(
                    expectedDigest: savedJournal.remoteDigest
                ) else {
                    return .failed(.localCleanupFailed)
                }
            }
            try journal.clear()
            return nil
        } catch {
            return .failed(.localCleanupFailed)
        }
    }

    private func localDigestMatches(_ expectedDigest: String) -> Bool {
        // Inspection failure must preserve both the journal and local file; false never authorizes cleanup.
        guard (try? localStorage.containsVault()) == true,
              let localData = try? localStorage.read() else { return false }
        return PasswordVaultDigest.hex(localData) == expectedDigest
    }
}

private enum PasswordVaultKDBXEnvelopeValidator {
    private static let fixedHeaderLength = 12
    private static let digestLength = 32
    private static let blockFrameLength = 36

    static func isValid(_ data: Data) -> Bool {
        do {
            let header = try KDBXReader.parseHeader(data)
            guard let headerEnd = headerEnd(in: data, isLegacy3x: header.formatVersion.isLegacy3x) else {
                return false
            }
            if header.formatVersion.isLegacy3x {
                return validateLegacyPayload(data, headerEnd: headerEnd)
            }
            return validate4xPayload(data, headerEnd: headerEnd, cipher: header.encryptionAlgorithm)
        } catch {
            return false
        }
    }

    private static func headerEnd(in data: Data, isLegacy3x: Bool) -> Int? {
        var cursor = fixedHeaderLength
        while cursor < data.count {
            guard let type = byte(in: data, at: cursor) else { return nil }
            cursor += 1
            let length: Int
            if isLegacy3x {
                guard let value = uint16(in: data, at: cursor) else { return nil }
                cursor += MemoryLayout<UInt16>.size
                length = Int(value)
            } else {
                guard let value = uint32(in: data, at: cursor) else { return nil }
                cursor += MemoryLayout<UInt32>.size
                length = Int(value)
            }
            guard length <= data.count - cursor else { return nil }
            cursor += length
            if type == 0 { return cursor }
        }
        return nil
    }

    private static func validateLegacyPayload(_ data: Data, headerEnd: Int) -> Bool {
        let payloadLength = data.count - headerEnd
        return payloadLength >= 80 && payloadLength.isMultiple(of: 16)
    }

    private static func validate4xPayload(
        _ data: Data,
        headerEnd: Int,
        cipher: Header.EncryptionAlgorithm
    ) -> Bool {
        guard headerEnd <= data.count - (digestLength * 2) else { return false }
        let expectedHeaderDigest = Data(SHA256.hash(data: data.prefix(headerEnd)))
        let storedHeaderDigest = data.subdata(in: headerEnd..<(headerEnd + digestLength))
        guard expectedHeaderDigest == storedHeaderDigest else { return false }

        var cursor = headerEnd + (digestLength * 2)
        var encryptedPayloadLength = 0
        var foundPayload = false
        while cursor <= data.count - blockFrameLength {
            cursor += digestLength
            guard let rawSize = uint32(in: data, at: cursor) else { return false }
            let size = Int32(bitPattern: rawSize)
            cursor += MemoryLayout<Int32>.size
            guard size >= 0 else { return false }
            let blockLength = Int(size)
            guard blockLength <= data.count - cursor else { return false }
            if blockLength == 0 {
                guard cursor == data.count, foundPayload else { return false }
                switch cipher {
                case .AES256CBC:
                    return encryptedPayloadLength.isMultiple(of: 16)
                case .ChaCha20:
                    return true
                }
            }
            foundPayload = true
            encryptedPayloadLength += blockLength
            cursor += blockLength
        }
        return false
    }

    private static func byte(in data: Data, at offset: Int) -> UInt8? {
        guard offset >= 0, offset < data.count else { return nil }
        return data[data.startIndex + offset]
    }

    private static func uint16(in data: Data, at offset: Int) -> UInt16? {
        guard offset >= 0, offset <= data.count - MemoryLayout<UInt16>.size else { return nil }
        return data.withUnsafeBytes {
            UInt16(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
        }
    }

    private static func uint32(in data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset <= data.count - MemoryLayout<UInt32>.size else { return nil }
        return data.withUnsafeBytes {
            UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
        }
    }
}
