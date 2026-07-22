import CryptoKit
import Foundation

enum VaultArtifactRekeyCheckpoint: Equatable {
    case stageWrite(URL)
    case stageReadback(URL)
    case revisionCheck(URL)
    case replace(URL, index: Int)
}

struct VaultArtifactRekeyReplacement {
    let url: URL
    let data: Data
}

struct VaultArtifactRekeyResult {
    let hasPendingCleanup: Bool
}

final class VaultArtifactRekeyTransaction {
    typealias CheckpointAction = (VaultArtifactRekeyCheckpoint) throws -> Void
    typealias Validator = (URL, Data) throws -> Void

    private struct StagedArtifact {
        let replacement: VaultArtifactRekeyReplacement
        let sourceRevision: Data
        let stagedURL: URL
        let rollbackURL: URL
    }

    private let fileManager: FileManager
    private let checkpointAction: CheckpointAction

    init(
        fileManager: FileManager = .default,
        checkpointAction: @escaping CheckpointAction = { _ in }
    ) {
        self.fileManager = fileManager
        self.checkpointAction = checkpointAction
    }

    convenience init(checkpointAction: @escaping CheckpointAction) {
        self.init(fileManager: .default, checkpointAction: checkpointAction)
    }

    func managedArtifactURLs(in paths: PasswordVaultLocalPaths) throws -> [URL] {
        let mainURL = paths.vaultURL
        guard fileManager.fileExists(atPath: mainURL.path) else {
            throw PasswordVaultError.databaseNotConfigured
        }
        var artifacts = [mainURL]
        let backupURL = paths.backupURL
        if fileManager.fileExists(atPath: backupURL.path) {
            artifacts.append(backupURL)
        }

        let directory = paths.directoryURL
        let mainPath = mainURL.standardizedFileURL.path
        let immediateConflicts = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            guard url.standardizedFileURL.path != mainPath,
                  url.pathExtension.lowercased() == "kdbx" else { return false }
            return (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.sorted { $0.path < $1.path }
        artifacts.append(contentsOf: immediateConflicts)

        let resolvedDirectory = directory
            .appendingPathComponent("conflicts", isDirectory: true)
            .appendingPathComponent("resolved", isDirectory: true)
        if let enumerator = fileManager.enumerator(
            at: resolvedDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        ) {
            let archived = (enumerator.allObjects as? [URL] ?? []).filter { url in
                guard url.pathExtension.lowercased() == "kdbx" else { return false }
                return (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }.sorted { $0.path < $1.path }
            artifacts.append(contentsOf: archived)
        }
        var seenPaths = Set<String>()
        return artifacts.filter { seenPaths.insert($0.standardizedFileURL.path).inserted }
    }

    func replace(
        _ replacements: [VaultArtifactRekeyReplacement],
        validate: Validator
    ) throws -> VaultArtifactRekeyResult {
        guard !replacements.isEmpty else { throw PasswordVaultError.databaseNotConfigured }
        let transactionID = UUID().uuidString
        var staged = [StagedArtifact]()
        var mainArtifactsCommitted = false
        defer { cleanup(staged, recoverRollbacks: !mainArtifactsCommitted) }

        do {
            for replacement in replacements {
                let sourceData = try Data(contentsOf: replacement.url)
                let directory = replacement.url.deletingLastPathComponent()
                let stem = ".pastera-rekey-\(transactionID)-\(replacement.url.lastPathComponent)"
                let stagedURL = directory.appendingPathComponent("\(stem).staged")
                let rollbackURL = directory.appendingPathComponent("\(stem).rollback")
                let artifact = StagedArtifact(
                    replacement: replacement,
                    sourceRevision: revision(of: sourceData),
                    stagedURL: stagedURL,
                    rollbackURL: rollbackURL
                )
                staged.append(artifact)

                try checkpointAction(.stageWrite(replacement.url))
                try replacement.data.write(to: stagedURL, options: .atomic)
                try checkpointAction(.stageReadback(replacement.url))
                let stagedData = try Data(contentsOf: stagedURL)
                guard stagedData == replacement.data else { throw PasswordVaultError.saveFailed }
                try validate(replacement.url, stagedData)
            }

            for artifact in staged {
                try checkpointAction(.revisionCheck(artifact.replacement.url))
                let currentData = try Data(contentsOf: artifact.replacement.url)
                guard revision(of: currentData) == artifact.sourceRevision else {
                    throw PasswordVaultError.externalConflict
                }
            }

            try commit(staged)
            // Past this point, every managed artifact uses the new key. Cleanup faults must not roll them back.
            mainArtifactsCommitted = true
            return finalizeCommittedArtifacts(staged)
        } catch let error as PasswordVaultError {
            throw error
        } catch {
            throw PasswordVaultError.saveFailed
        }
    }

    private func commit(_ staged: [StagedArtifact]) throws {
        var committed = [StagedArtifact]()
        do {
            for (index, artifact) in staged.enumerated() {
                try checkpointAction(.replace(artifact.replacement.url, index: index))
                try fileManager.moveItem(at: artifact.replacement.url, to: artifact.rollbackURL)
                do {
                    try fileManager.moveItem(at: artifact.stagedURL, to: artifact.replacement.url)
                } catch {
                    try? fileManager.moveItem(at: artifact.rollbackURL, to: artifact.replacement.url)
                    throw error
                }
                committed.append(artifact)
            }
        } catch {
            for artifact in committed.reversed() {
                try? fileManager.removeItem(at: artifact.replacement.url)
                try? fileManager.moveItem(at: artifact.rollbackURL, to: artifact.replacement.url)
            }
            throw error
        }
    }

    private func finalizeCommittedArtifacts(_ committed: [StagedArtifact]) -> VaultArtifactRekeyResult {
        var hasPendingCleanup = false
        for artifact in committed {
            guard sanitizeRollback(artifact) else {
                hasPendingCleanup = true
                continue
            }
            do {
                try fileManager.removeItem(at: artifact.rollbackURL)
            } catch {
                hasPendingCleanup = true
            }
        }
        return VaultArtifactRekeyResult(hasPendingCleanup: hasPendingCleanup)
    }

    private func sanitizeRollback(_ artifact: StagedArtifact) -> Bool {
        do {
            let handle = try FileHandle(forWritingTo: artifact.rollbackURL)
            do {
                try handle.truncate(atOffset: 0)
                try handle.synchronize()
                try handle.close()
            } catch {
                try? handle.close()
                return false
            }
        } catch {
            return false
        }

        do {
            try artifact.replacement.data.write(to: artifact.rollbackURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private func cleanup(_ staged: [StagedArtifact], recoverRollbacks: Bool) {
        for artifact in staged {
            if fileManager.fileExists(atPath: artifact.stagedURL.path) {
                try? fileManager.removeItem(at: artifact.stagedURL)
            }
            guard recoverRollbacks,
                  fileManager.fileExists(atPath: artifact.rollbackURL.path) else { continue }
            if !fileManager.fileExists(atPath: artifact.replacement.url.path) {
                try? fileManager.moveItem(at: artifact.rollbackURL, to: artifact.replacement.url)
            }
            if fileManager.fileExists(atPath: artifact.replacement.url.path) {
                try? fileManager.removeItem(at: artifact.rollbackURL)
            }
        }
    }

    private func revision(of data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }
}
