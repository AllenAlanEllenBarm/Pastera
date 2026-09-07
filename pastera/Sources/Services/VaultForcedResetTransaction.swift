import CryptoKit
import Darwin
import Foundation

enum VaultForcedResetCheckpoint: Equatable {
    case archiveStageWrite
    case archiveReadback
    case newVaultStageWrite
    case newVaultReadback
    case revisionCheck
    case archiveReplace
    case activeReplace
}

enum VaultForcedResetCleanupOutcome: Equatable {
    case complete
    case pendingDeletion
    case requiresRecovery

    mutating func combine(with other: Self) {
        if self == .requiresRecovery || other == .requiresRecovery {
            self = .requiresRecovery
        } else if self == .pendingDeletion || other == .pendingDeletion {
            self = .pendingDeletion
        }
    }
}

struct VaultForcedResetTransactionResult {
    let localArchiveDigest: String
    let cleanupOutcome: VaultForcedResetCleanupOutcome

    var hasPendingCleanup: Bool { cleanupOutcome == .pendingDeletion }
    var requiresRecovery: Bool { cleanupOutcome == .requiresRecovery }
}

enum VaultForcedResetRecoveryPhase: String, Codable, Equatable {
    case prepared
    case committed
}

struct VaultForcedResetRecoveryRecord: Codable, Equatable {
    static let currentVersion = 2

    let version: Int
    let transactionID: String
    var phase: VaultForcedResetRecoveryPhase
    let hadPreviousArchive: Bool
    let oldActiveDigest: String
    let newActiveDigest: String
    let priorArchiveDigest: String?
}

private struct VaultForcedResetRecoveryPaths {
    let archiveStageURL: URL
    let activeStageURL: URL
    let archiveRollbackURL: URL
    let activeRollbackURL: URL
}

protocol VaultForcedResetFileOperating {
    func fileExists(at url: URL) -> Bool
    func createDirectory(at url: URL) throws
    func read(from url: URL) throws -> Data
    func write(_ data: Data, to url: URL, options: Data.WritingOptions) throws
    func remove(at url: URL) throws
    func rename(_ sourceURL: URL, to destinationURL: URL) throws
    func contentsOfDirectory(at url: URL) throws -> [URL]
}

final class VaultForcedResetFileOperator: VaultForcedResetFileOperating {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func read(from url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func write(_ data: Data, to url: URL, options: Data.WritingOptions) throws {
        try data.write(to: url, options: options)
    }

    func remove(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    func rename(_ sourceURL: URL, to destinationURL: URL) throws {
        let errorCode: Int32 = sourceURL.withUnsafeFileSystemRepresentation { sourcePath in
            destinationURL.withUnsafeFileSystemRepresentation { destinationPath in
                guard let sourcePath, let destinationPath else { return EINVAL }
                guard Darwin.rename(sourcePath, destinationPath) != 0 else { return 0 }
                return errno
            }
        }
        guard errorCode == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errorCode) ?? .EIO)
        }
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        )
    }
}

// The transaction and recovery state machine share the same exact artifact contract.
// swiftlint:disable:next type_body_length
final class VaultForcedResetTransaction {
    typealias CheckpointAction = (VaultForcedResetCheckpoint) throws -> Void
    typealias Validator = (URL, Data) throws -> Void

    private let fileOperator: VaultForcedResetFileOperating
    private let checkpointAction: CheckpointAction

    init(
        fileOperator: VaultForcedResetFileOperating = VaultForcedResetFileOperator(),
        checkpointAction: @escaping CheckpointAction = { _ in }
    ) {
        self.fileOperator = fileOperator
        self.checkpointAction = checkpointAction
    }

    convenience init(checkpointAction: @escaping CheckpointAction) {
        self.init(fileOperator: VaultForcedResetFileOperator(), checkpointAction: checkpointAction)
    }

    func replace(
        activeURL: URL,
        archiveURL: URL,
        recoveryMarkerURL: URL,
        newVaultData: Data,
        validate: Validator
    ) throws -> VaultForcedResetTransactionResult {
        guard !hasRecoveryMarker(at: recoveryMarkerURL) else {
            throw PasswordVaultForcedResetError.recoveryRequired
        }
        let activeData: Data
        do {
            activeData = try fileOperator.read(from: activeURL)
        } catch {
            throw PasswordVaultError.databaseNotConfigured
        }
        try validateKDBXSignature(activeData)
        try validateKDBXSignature(newVaultData)

        let transactionID = UUID().uuidString
        let paths = try recoveryPaths(
            transactionID: transactionID,
            activeURL: activeURL,
            archiveURL: archiveURL
        )
        let hadPreviousArchive = fileOperator.fileExists(at: archiveURL)
        let priorArchiveData = hadPreviousArchive ? try fileOperator.read(from: archiveURL) : nil
        if let priorArchiveData { try validateKDBXSignature(priorArchiveData) }
        let activeRevision = revision(of: activeData)
        var recoveryRecord = VaultForcedResetRecoveryRecord(
            version: VaultForcedResetRecoveryRecord.currentVersion,
            transactionID: transactionID,
            phase: .prepared,
            hadPreviousArchive: hadPreviousArchive,
            oldActiveDigest: PasswordVaultDigest.hex(activeData),
            newActiveDigest: PasswordVaultDigest.hex(newVaultData),
            priorArchiveDigest: priorArchiveData.map(PasswordVaultDigest.hex)
        )

        try fileOperator.createDirectory(at: archiveURL.deletingLastPathComponent())
        var archiveInstalled = false
        var verifiedBytesCommitted = false
        do {
            try writeRecoveryRecord(recoveryRecord, to: recoveryMarkerURL)

            try checkpointAction(.archiveStageWrite)
            try fileOperator.write(activeData, to: paths.archiveStageURL, options: .withoutOverwriting)
            try checkpointAction(.archiveReadback)
            let archiveStageData = try fileOperator.read(from: paths.archiveStageURL)
            guard archiveStageData == activeData else { throw PasswordVaultError.saveFailed }
            try validateKDBXSignature(archiveStageData)

            try checkpointAction(.newVaultStageWrite)
            try fileOperator.write(newVaultData, to: paths.activeStageURL, options: .withoutOverwriting)
            try checkpointAction(.newVaultReadback)
            let activeStageData = try fileOperator.read(from: paths.activeStageURL)
            guard activeStageData == newVaultData else { throw PasswordVaultError.saveFailed }
            try validate(activeURL, activeStageData)

            try checkpointAction(.archiveReplace)
            if hadPreviousArchive {
                try fileOperator.rename(archiveURL, to: paths.archiveRollbackURL)
            }
            try fileOperator.rename(paths.archiveStageURL, to: archiveURL)
            archiveInstalled = true

            try checkpointAction(.activeReplace)
            try checkpointAction(.revisionCheck)
            let currentActiveData = try fileOperator.read(from: activeURL)
            guard revision(of: currentActiveData) == activeRevision else {
                throw PasswordVaultError.externalConflict
            }
            try fileOperator.rename(activeURL, to: paths.activeRollbackURL)
            try fileOperator.rename(paths.activeStageURL, to: activeURL)

            let committedArchive = try fileOperator.read(from: archiveURL)
            guard committedArchive == activeData else { throw PasswordVaultError.saveFailed }
            try validateKDBXSignature(committedArchive)
            let committedActive = try fileOperator.read(from: activeURL)
            guard committedActive == newVaultData else { throw PasswordVaultError.saveFailed }
            try validate(activeURL, committedActive)
            verifiedBytesCommitted = true
            recoveryRecord.phase = .committed
            try writeRecoveryRecord(recoveryRecord, to: recoveryMarkerURL)
        } catch {
            // Once both target files have been installed and validated, the atomic
            // record write decides whether recovery resumes committed cleanup or
            // the prepared rollback. Do not create a mismatched record/files pair.
            if verifiedBytesCommitted {
                throw PasswordVaultForcedResetError.recoveryRequired
            }
            let rollbackSucceeded = rollback(
                activeURL: activeURL,
                activeRollbackURL: paths.activeRollbackURL,
                archiveURL: archiveURL,
                archiveRollbackURL: paths.archiveRollbackURL,
                archiveInstalled: archiveInstalled,
                hadPreviousArchive: hadPreviousArchive
            )
            let stagingCleanupSucceeded = cleanup([paths.archiveStageURL, paths.activeStageURL])
            let rollbackCleanupSucceeded = rollbackSucceeded
                ? cleanup([paths.archiveRollbackURL, paths.activeRollbackURL])
                : false
            if rollbackSucceeded, stagingCleanupSucceeded, rollbackCleanupSucceeded {
                try? fileOperator.remove(at: recoveryMarkerURL)
            }
            guard rollbackSucceeded else {
                throw PasswordVaultForcedResetError.recoveryRequired
            }
            if let vaultError = error as? PasswordVaultError { throw vaultError }
            throw PasswordVaultError.saveFailed
        }

        let cleanupOutcome = sanitizeAfterCommit(
            [
                paths.archiveStageURL,
                paths.activeStageURL,
                paths.archiveRollbackURL,
                paths.activeRollbackURL
            ],
            replacementData: newVaultData,
            validate: validate
        )
        return VaultForcedResetTransactionResult(
            localArchiveDigest: PasswordVaultDigest.hex(activeData),
            cleanupOutcome: cleanupOutcome
        )
    }

    func recover(
        activeURL: URL,
        archiveURL: URL,
        recoveryMarkerURL: URL,
        managedArtifactURLs: () throws -> [URL],
        beforeCommittedCompletion: () throws -> Void = {}
    ) throws -> PasswordVaultForcedResetRecoveryResult {
        do {
            let record = try readRecoveryRecord(from: recoveryMarkerURL)
            let paths = try recoveryPaths(
                transactionID: record.transactionID,
                activeURL: activeURL,
                archiveURL: archiveURL
            )
            switch record.phase {
            case .prepared:
                return try recoverPrepared(
                    record,
                    paths: paths,
                    activeURL: activeURL,
                    archiveURL: archiveURL,
                    recoveryMarkerURL: recoveryMarkerURL
                )
            case .committed:
                return try recoverCommitted(
                    record,
                    paths: paths,
                    activeURL: activeURL,
                    archiveURL: archiveURL,
                    recoveryMarkerURL: recoveryMarkerURL,
                    managedArtifactURLs: managedArtifactURLs,
                    beforeCompletion: beforeCommittedCompletion
                )
            }
        } catch {
            throw PasswordVaultForcedResetError.recoveryRequired
        }
    }

    func removeOrSanitize(
        _ urls: [URL],
        replacementData: Data,
        validate: Validator
    ) -> VaultForcedResetCleanupOutcome {
        sanitizeAfterCommit(urls, replacementData: replacementData, validate: validate)
    }

    func hasRecoveryMarker(at url: URL) -> Bool {
        fileOperator.fileExists(at: url)
    }

    func clearRecoveryMarkerIfSafe(
        at url: URL,
        cleanupOutcome: VaultForcedResetCleanupOutcome
    ) {
        guard cleanupOutcome != .requiresRecovery else { return }
        try? fileOperator.remove(at: url)
    }

    private func recoverPrepared(
        _ record: VaultForcedResetRecoveryRecord,
        paths: VaultForcedResetRecoveryPaths,
        activeURL: URL,
        archiveURL: URL,
        recoveryMarkerURL: URL
    ) throws -> PasswordVaultForcedResetRecoveryResult {
        let activeData = try existingData(
            at: activeURL,
            allowedDigests: [record.oldActiveDigest, record.newActiveDigest]
        )
        let archiveAllowed = record.hadPreviousArchive
            ? [record.oldActiveDigest, try requiredPriorArchiveDigest(record)]
            : [record.oldActiveDigest]
        let archiveData = try existingData(at: archiveURL, allowedDigests: archiveAllowed)
        let archiveStageData = try existingData(
            at: paths.archiveStageURL,
            allowedDigests: [record.oldActiveDigest]
        )
        let activeStageData = try existingData(
            at: paths.activeStageURL,
            allowedDigests: [record.newActiveDigest]
        )
        let activeRollbackData = try existingData(
            at: paths.activeRollbackURL,
            allowedDigests: [record.oldActiveDigest]
        )
        let archiveRollbackData: Data?
        if record.hadPreviousArchive {
            archiveRollbackData = try existingData(
                at: paths.archiveRollbackURL,
                allowedDigests: [try requiredPriorArchiveDigest(record)]
            )
        } else {
            guard !fileOperator.fileExists(at: paths.archiveRollbackURL) else {
                throw PasswordVaultError.corruptedData
            }
            archiveRollbackData = nil
        }

        let oldActiveData = try requiredData(
            matching: record.oldActiveDigest,
            candidates: [activeData, activeRollbackData, archiveStageData, archiveData]
        )
        _ = activeStageData
        let priorArchiveData: Data?
        if record.hadPreviousArchive {
            priorArchiveData = try requiredData(
                matching: try requiredPriorArchiveDigest(record),
                candidates: [archiveData, archiveRollbackData]
            )
        } else {
            priorArchiveData = nil
        }

        try writeAndVerify(oldActiveData, digest: record.oldActiveDigest, to: activeURL)
        if let priorArchiveData {
            try writeAndVerify(
                priorArchiveData,
                digest: try requiredPriorArchiveDigest(record),
                to: archiveURL
            )
        } else if fileOperator.fileExists(at: archiveURL) {
            try fileOperator.remove(at: archiveURL)
            guard !fileOperator.fileExists(at: archiveURL) else {
                throw PasswordVaultError.saveFailed
            }
        }

        guard cleanup([
            paths.archiveStageURL,
            paths.activeStageURL,
            paths.archiveRollbackURL,
            paths.activeRollbackURL
        ]) else {
            throw PasswordVaultError.saveFailed
        }
        _ = try requiredExistingData(at: activeURL, digest: record.oldActiveDigest)
        if record.hadPreviousArchive {
            _ = try requiredExistingData(
                at: archiveURL,
                digest: try requiredPriorArchiveDigest(record)
            )
        } else if fileOperator.fileExists(at: archiveURL) {
            throw PasswordVaultError.saveFailed
        }
        try removeRecoveryMarker(at: recoveryMarkerURL)
        return .rolledBack(oldDigest: record.oldActiveDigest)
    }

    private func recoverCommitted(
        _ record: VaultForcedResetRecoveryRecord,
        paths: VaultForcedResetRecoveryPaths,
        activeURL: URL,
        archiveURL: URL,
        recoveryMarkerURL: URL,
        managedArtifactURLs: () throws -> [URL],
        beforeCompletion: () throws -> Void
    ) throws -> PasswordVaultForcedResetRecoveryResult {
        let activeData = try requiredExistingData(at: activeURL, digest: record.newActiveDigest)
        _ = try requiredExistingData(at: archiveURL, digest: record.oldActiveDigest)
        let priorDigest = record.priorArchiveDigest
        _ = try existingData(
            at: paths.archiveStageURL,
            allowedDigests: [record.oldActiveDigest, record.newActiveDigest]
        )
        _ = try existingData(
            at: paths.activeStageURL,
            allowedDigests: [record.newActiveDigest]
        )
        _ = try existingData(
            at: paths.activeRollbackURL,
            allowedDigests: [record.oldActiveDigest, record.newActiveDigest]
        )
        let archiveRollbackAllowed = [record.newActiveDigest] + (priorDigest.map { [$0] } ?? [])
        _ = try existingData(
            at: paths.archiveRollbackURL,
            allowedDigests: archiveRollbackAllowed
        )
        try validateSingleArchive(at: archiveURL)

        let exactTransactionArtifacts = [
            paths.archiveStageURL,
            paths.activeStageURL,
            paths.archiveRollbackURL,
            paths.activeRollbackURL
        ]
        let excluded = Set([
            activeURL.standardizedFileURL.path,
            archiveURL.standardizedFileURL.path,
            recoveryMarkerURL.standardizedFileURL.path
        ])
        var seen = Set<String>()
        let managedArtifacts = try managedArtifactURLs().filter { url in
            let path = url.standardizedFileURL.path
            return !excluded.contains(path) && seen.insert(path).inserted
        }
        let cleanupOutcome = sanitizeAfterCommit(
            exactTransactionArtifacts + managedArtifacts,
            replacementData: activeData
        ) { [newActiveDigest = record.newActiveDigest] _, data in
            try self.validateKDBXSignature(data)
            guard PasswordVaultDigest.hex(data) == newActiveDigest else {
                throw PasswordVaultError.corruptedData
            }
        }
        guard cleanupOutcome != .requiresRecovery else {
            throw PasswordVaultError.saveFailed
        }

        _ = try requiredExistingData(at: activeURL, digest: record.newActiveDigest)
        _ = try requiredExistingData(at: archiveURL, digest: record.oldActiveDigest)
        try validateSingleArchive(at: archiveURL)
        try beforeCompletion()
        try removeRecoveryMarker(at: recoveryMarkerURL)
        return .committed(newDigest: record.newActiveDigest)
    }

    private func rollback(
        activeURL: URL,
        activeRollbackURL: URL,
        archiveURL: URL,
        archiveRollbackURL: URL,
        archiveInstalled: Bool,
        hadPreviousArchive: Bool
    ) -> Bool {
        var succeeded = true
        if fileOperator.fileExists(at: activeRollbackURL) {
            do {
                try fileOperator.rename(activeRollbackURL, to: activeURL)
            } catch {
                succeeded = false
            }
        }

        if fileOperator.fileExists(at: archiveRollbackURL) {
            do {
                try fileOperator.rename(archiveRollbackURL, to: archiveURL)
            } catch {
                succeeded = false
            }
        } else if !hadPreviousArchive, archiveInstalled,
                  fileOperator.fileExists(at: archiveURL) {
            do {
                try fileOperator.remove(at: archiveURL)
            } catch {
                succeeded = false
            }
        }
        return succeeded
    }

    private func sanitizeAfterCommit(
        _ urls: [URL],
        replacementData: Data,
        validate: Validator
    ) -> VaultForcedResetCleanupOutcome {
        var outcome = VaultForcedResetCleanupOutcome.complete
        for url in urls where fileOperator.fileExists(at: url) {
            do {
                try fileOperator.remove(at: url)
            } catch {
                do {
                    try fileOperator.write(replacementData, to: url, options: .atomic)
                    let sanitized = try fileOperator.read(from: url)
                    guard sanitized == replacementData else { throw PasswordVaultError.saveFailed }
                    try validate(url, sanitized)
                    outcome.combine(with: .pendingDeletion)
                } catch {
                    outcome.combine(with: .requiresRecovery)
                }
            }
        }
        return outcome
    }

    private func cleanup(_ urls: [URL]) -> Bool {
        var succeeded = true
        for url in urls where fileOperator.fileExists(at: url) {
            do {
                try fileOperator.remove(at: url)
                if fileOperator.fileExists(at: url) { succeeded = false }
            } catch {
                succeeded = false
            }
        }
        return succeeded
    }

    private func writeRecoveryRecord(
        _ record: VaultForcedResetRecoveryRecord,
        to url: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        try fileOperator.write(data, to: url, options: .atomic)
        guard try fileOperator.read(from: url) == data else {
            throw PasswordVaultError.saveFailed
        }
    }

    private func readRecoveryRecord(from url: URL) throws -> VaultForcedResetRecoveryRecord {
        let data = try fileOperator.read(from: url)
        let record = try JSONDecoder().decode(VaultForcedResetRecoveryRecord.self, from: data)
        guard record.version == VaultForcedResetRecoveryRecord.currentVersion,
              let identifier = UUID(uuidString: record.transactionID),
              identifier.uuidString == record.transactionID,
              isDigest(record.oldActiveDigest),
              isDigest(record.newActiveDigest),
              record.hadPreviousArchive == (record.priorArchiveDigest != nil),
              record.priorArchiveDigest.map(isDigest) ?? true else {
            throw PasswordVaultError.corruptedData
        }
        return record
    }

    private func recoveryPaths(
        transactionID: String,
        activeURL: URL,
        archiveURL: URL
    ) throws -> VaultForcedResetRecoveryPaths {
        guard let identifier = UUID(uuidString: transactionID),
              identifier.uuidString == transactionID else {
            throw PasswordVaultError.corruptedData
        }
        let stem = ".pastera-forced-reset-\(transactionID)"
        return VaultForcedResetRecoveryPaths(
            archiveStageURL: archiveURL.deletingLastPathComponent()
                .appendingPathComponent("\(stem)-archive.staged"),
            activeStageURL: activeURL.deletingLastPathComponent()
                .appendingPathComponent("\(stem)-active.staged"),
            archiveRollbackURL: archiveURL.deletingLastPathComponent()
                .appendingPathComponent("\(stem)-archive.rollback"),
            activeRollbackURL: activeURL.deletingLastPathComponent()
                .appendingPathComponent("\(stem)-active.rollback")
        )
    }

    private func existingData(at url: URL, allowedDigests: [String]) throws -> Data? {
        guard fileOperator.fileExists(at: url) else { return nil }
        let data = try fileOperator.read(from: url)
        try validateKDBXSignature(data)
        guard allowedDigests.contains(PasswordVaultDigest.hex(data)) else {
            throw PasswordVaultError.corruptedData
        }
        return data
    }

    private func requiredExistingData(at url: URL, digest: String) throws -> Data {
        guard let data = try existingData(at: url, allowedDigests: [digest]) else {
            throw PasswordVaultError.corruptedData
        }
        return data
    }

    private func requiredData(matching digest: String, candidates: [Data?]) throws -> Data {
        guard let data = candidates.compactMap({ $0 }).first(where: {
            PasswordVaultDigest.hex($0) == digest
        }) else {
            throw PasswordVaultError.corruptedData
        }
        return data
    }

    private func requiredPriorArchiveDigest(_ record: VaultForcedResetRecoveryRecord) throws -> String {
        guard record.hadPreviousArchive, let digest = record.priorArchiveDigest else {
            throw PasswordVaultError.corruptedData
        }
        return digest
    }

    private func writeAndVerify(_ data: Data, digest: String, to url: URL) throws {
        try fileOperator.write(data, to: url, options: .atomic)
        _ = try requiredExistingData(at: url, digest: digest)
    }

    private func removeRecoveryMarker(at url: URL) throws {
        try fileOperator.remove(at: url)
        guard !fileOperator.fileExists(at: url) else {
            throw PasswordVaultError.saveFailed
        }
    }

    private func validateSingleArchive(at archiveURL: URL) throws {
        let archiveDirectory = archiveURL.deletingLastPathComponent()
        let archives = try fileOperator.contentsOfDirectory(at: archiveDirectory).filter {
            $0.pathExtension.lowercased() == "kdbx"
        }
        guard archives.map(\.standardizedFileURL.path) == [archiveURL.standardizedFileURL.path] else {
            throw PasswordVaultError.corruptedData
        }
    }

    private func isDigest(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    private func validateKDBXSignature(_ data: Data) throws {
        let signature = Data([0x03, 0xD9, 0xA2, 0x9A, 0x67, 0xFB, 0x4B, 0xB5])
        guard data.count >= signature.count, data.prefix(signature.count) == signature else {
            throw PasswordVaultError.corruptedData
        }
    }

    private func revision(of data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }
}
