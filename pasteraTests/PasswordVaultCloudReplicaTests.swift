import Foundation
import Testing
@testable import Pastera
@Suite("Password vault OneDrive cloud replica", .serialized)
struct PasswordVaultCloudReplicaTests {
    private let signature = Data([0x03, 0xD9, 0xA2, 0x9A, 0x67, 0xFB, 0x4B, 0xB5])

    @Test("missing compatible vault returns no cloud snapshot")
    func missingVaultReturnsNil() throws {
        try withCloudRoot { rootURL in
            let replica = OneDrivePasswordVaultCloudReplica()
            let snapshot = try replica.read(rootURL: rootURL)
            #expect(snapshot == nil)
            #expect(VaultFileCoordinator.vaultURL(for: rootURL).lastPathComponent == "PasteraVault.kdbx")
        }
    }
    @Test("coordinated read returns the complete encrypted KDBX and digest")
    func completeReadReturnsSnapshot() throws {
        try withCloudRoot { rootURL in
            let data = kdbxData("complete-encrypted-cloud-copy")
            let targetURL = VaultFileCoordinator.vaultURL(for: rootURL)
            try FileManager.default.createDirectory(
                at: targetURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: targetURL)
            let loadedSnapshot = try OneDrivePasswordVaultCloudReplica().read(rootURL: rootURL)
            let snapshot = try #require(loadedSnapshot)
            #expect(snapshot.data == data)
            #expect(snapshot.digest == PasswordVaultDigest.hex(data))
        }
    }
    @Test("first write creates the compatible cloud vault and verifies its digest")
    func firstWriteCreatesVerifiedReplica() throws {
        try withCloudRoot { rootURL in
            let data = kdbxData("first-encrypted-cloud-copy")
            let targetURL = VaultFileCoordinator.vaultURL(for: rootURL)
            #expect(!FileManager.default.fileExists(atPath: targetURL.deletingLastPathComponent().path))
            let digest = try OneDrivePasswordVaultCloudReplica().writeAtomically(
                data,
                rootURL: rootURL,
                expecting: .absent
            )
            let loadedSnapshot = try OneDrivePasswordVaultCloudReplica().read(rootURL: rootURL)
            let snapshot = try #require(loadedSnapshot)
            let remainingTemporaryFiles = try temporaryFiles(alongside: targetURL)
            #expect(digest == PasswordVaultDigest.hex(data))
            #expect(snapshot.data == data)
            #expect(snapshot.digest == digest)
            #expect(remainingTemporaryFiles.isEmpty)
        }
    }
    @Test("existing cloud vault is atomically replaced and returns the new digest")
    func existingVaultIsReplaced() throws {
        try withCloudRoot { rootURL in
            let original = kdbxData("old-encrypted-cloud-copy")
            let replacement = kdbxData("new-encrypted-cloud-copy")
            let targetURL = try writeCloudVault(original, rootURL: rootURL)
            let digest = try OneDrivePasswordVaultCloudReplica().writeAtomically(
                replacement,
                rootURL: rootURL,
                expecting: .digest(PasswordVaultDigest.hex(original))
            )
            let storedData = try Data(contentsOf: targetURL)
            let remainingTemporaryFiles = try temporaryFiles(alongside: targetURL)
            #expect(digest == PasswordVaultDigest.hex(replacement))
            #expect(storedData == replacement)
            #expect(remainingTemporaryFiles.isEmpty)
        }
    }
    @Test("absent expectation preserves a cloud vault that appeared before the write")
    func absentExpectationRejectsAppearedTarget() throws {
        try withCloudRoot { rootURL in
            let appeared = kdbxData("appeared-cloud-copy")
            let targetURL = try writeCloudVault(appeared, rootURL: rootURL)

            #expect(throws: PasswordVaultSyncFailure.remoteVerificationFailed) {
                try OneDrivePasswordVaultCloudReplica().writeAtomically(
                    self.kdbxData("stale-local-copy"),
                    rootURL: rootURL,
                    expecting: .absent
                )
            }
            let storedData = try Data(contentsOf: targetURL)
            let remainingTemporaryFiles = try temporaryFiles(alongside: targetURL)
            #expect(storedData == appeared)
            #expect(remainingTemporaryFiles.isEmpty)
        }
    }
    @Test("digest expectation preserves a cloud vault changed after observation")
    func digestExpectationRejectsChangedTarget() throws {
        try withCloudRoot { rootURL in
            let observed = kdbxData("cloud-version-a")
            let changed = kdbxData("cloud-version-b")
            let targetURL = try writeCloudVault(changed, rootURL: rootURL)
            #expect(throws: PasswordVaultSyncFailure.remoteVerificationFailed) {
                try OneDrivePasswordVaultCloudReplica().writeAtomically(
                    self.kdbxData("local-replacement"),
                    rootURL: rootURL,
                    expecting: .digest(PasswordVaultDigest.hex(observed))
                )
            }
            let storedData = try Data(contentsOf: targetURL)
            let remainingTemporaryFiles = try temporaryFiles(alongside: targetURL)
            #expect(storedData == changed)
            #expect(remainingTemporaryFiles.isEmpty)
        }
    }
    @Test("invalid write input is rejected before any cloud directory is created")
    func invalidWriteInputHasNoSideEffects() throws {
        try withCloudRoot { rootURL in
            let targetURL = VaultFileCoordinator.vaultURL(for: rootURL)
            #expect(throws: PasswordVaultSyncFailure.remoteCorrupted) {
                try OneDrivePasswordVaultCloudReplica().writeAtomically(
                    Data("plaintext-not-kdbx".utf8),
                    rootURL: rootURL,
                    expecting: .absent
                )
            }
            let rootContents = try FileManager.default.contentsOfDirectory(atPath: rootURL.path)
            #expect(!FileManager.default.fileExists(atPath: targetURL.deletingLastPathComponent().path))
            #expect(rootContents.isEmpty)
        }
    }
    @Test("non-writable OneDrive root fails before creating the compatible directory")
    func nonWritableRootFailsWithoutSideEffects() throws {
        try withCloudRoot { rootURL in
            let targetURL = VaultFileCoordinator.vaultURL(for: rootURL)
            var operations = PasswordVaultCloudFileOperations.live
            operations.isWritable = { _ in false }
            let replica = OneDrivePasswordVaultCloudReplica(operations: operations)
            #expect(throws: PasswordVaultSyncFailure.folderNotWritable) {
                try replica.writeAtomically(
                    self.kdbxData("do-not-write"),
                    rootURL: rootURL,
                    expecting: .absent
                )
            }
            #expect(!FileManager.default.fileExists(atPath: targetURL.deletingLastPathComponent().path))
            let rootContents = try FileManager.default.contentsOfDirectory(atPath: rootURL.path)
            #expect(rootContents.isEmpty)
        }
    }
}

extension PasswordVaultCloudReplicaTests {
    @Test("short coordinated read is a remote availability failure")
    func shortReadFailsWithoutChangingCloudData() throws {
        try withCloudRoot { rootURL in
            let data = kdbxData("complete-before-short-read")
            let targetURL = try writeCloudVault(data, rootURL: rootURL)
            var operations = PasswordVaultCloudFileOperations.live
            let liveRead = operations.readData
            operations.readData = { url in
                let complete = try liveRead(url)
                return url.standardizedFileURL == targetURL.standardizedFileURL
                    ? Data(complete.dropLast())
                    : complete
            }
            let replica = OneDrivePasswordVaultCloudReplica(operations: operations)
            #expect(throws: PasswordVaultSyncFailure.remoteUnavailable) {
                try replica.read(rootURL: rootURL)
            }
            let storedData = try Data(contentsOf: targetURL)
            #expect(storedData == data)
        }
    }
    @Test("target query permission failure is not treated as a missing cloud vault")
    func readTargetQueryFailureFailsClosed() throws {
        try withCloudRoot { rootURL in
            let data = kdbxData("unreadable-target-status")
            let targetURL = try writeCloudVault(data, rootURL: rootURL)
            var operations = PasswordVaultCloudFileOperations.live
            let liveItemStatus = operations.itemStatus
            operations.itemStatus = { url in
                if url.standardizedFileURL == targetURL.standardizedFileURL {
                    throw CocoaError(.fileReadNoPermission)
                }
                return try liveItemStatus(url)
            }
            let replica = OneDrivePasswordVaultCloudReplica(operations: operations)
            #expect(throws: PasswordVaultSyncFailure.remoteUnavailable) {
                try replica.read(rootURL: rootURL)
            }
            let storedData = try Data(contentsOf: targetURL)
            #expect(storedData == data)
        }
    }

    @Test("POSIX no-such-file target query is treated as explicitly missing")
    func posixMissingTargetReturnsNil() throws {
        try withCloudRoot { rootURL in
            let targetURL = VaultFileCoordinator.vaultURL(for: rootURL)
            var operations = PasswordVaultCloudFileOperations.live
            let liveItemStatus = operations.itemStatus
            operations.itemStatus = { url in
                if url.standardizedFileURL == targetURL.standardizedFileURL {
                    throw POSIXError(.ENOENT)
                }
                return try liveItemStatus(url)
            }

            let snapshot = try OneDrivePasswordVaultCloudReplica(operations: operations)
                .read(rootURL: rootURL)
            #expect(snapshot == nil)
        }
    }
    @Test("invalid KDBX signature is a remote corruption failure")
    func invalidSignatureIsRejected() throws {
        try withCloudRoot { rootURL in
            let targetURL = try writeCloudVault(Data("plaintext-not-kdbx".utf8), rootURL: rootURL)

            #expect(throws: PasswordVaultSyncFailure.remoteCorrupted) {
                try OneDrivePasswordVaultCloudReplica().read(rootURL: rootURL)
            }
            let storedData = try Data(contentsOf: targetURL)
            #expect(storedData == Data("plaintext-not-kdbx".utf8))
        }
    }

    @Test("read rejects a directory at the cloud vault path without touching its contents")
    func readRejectsNonRegularTarget() throws {
        try withCloudRoot { rootURL in
            let fixture = try writeDirectoryTarget(rootURL: rootURL)

            #expect(throws: PasswordVaultSyncFailure.remoteCorrupted) {
                try OneDrivePasswordVaultCloudReplica().read(rootURL: rootURL)
            }
            #expect(FileManager.default.fileExists(atPath: fixture.targetURL.path))
            let sentinelData = try Data(contentsOf: fixture.sentinelURL)
            #expect(sentinelData == Data("sentinel".utf8))
        }
    }

    @Test("write rejects a directory at the cloud vault path without replacing it")
    func writeRejectsNonRegularTarget() throws {
        try withCloudRoot { rootURL in
            let fixture = try writeDirectoryTarget(rootURL: rootURL)

            #expect(throws: PasswordVaultSyncFailure.remoteCorrupted) {
                try OneDrivePasswordVaultCloudReplica().writeAtomically(
                    self.kdbxData("must-not-replace-directory"),
                    rootURL: rootURL,
                    expecting: .absent
                )
            }
            #expect(FileManager.default.fileExists(atPath: fixture.targetURL.path))
            let sentinelData = try Data(contentsOf: fixture.sentinelURL)
            let remainingTemporaryFiles = try temporaryFiles(alongside: fixture.targetURL)
            #expect(sentinelData == Data("sentinel".utf8))
            #expect(remainingTemporaryFiles.isEmpty)
        }
    }

    @Test("temporary write failure preserves the cloud vault and removes only its temporary file")
    func temporaryWriteFailurePreservesTarget() throws {
        try withCloudRoot { rootURL in
            let original = kdbxData("existing-cloud")
            let targetURL = try writeCloudVault(original, rootURL: rootURL)
            let conflictURL = targetURL.deletingLastPathComponent()
                .appendingPathComponent("PasteraVault-conflicted-copy.kdbx")
            try kdbxData("conflict").write(to: conflictURL)
            var operations = PasswordVaultCloudFileOperations.live
            operations.writeData = { _, _ in throw CloudReplicaFixtureError.writeFailed }
            let replica = OneDrivePasswordVaultCloudReplica(operations: operations)

            #expect(throws: PasswordVaultSyncFailure.remoteWriteFailed) {
                try replica.writeAtomically(
                    self.kdbxData("replacement"),
                    rootURL: rootURL,
                    expecting: .digest(PasswordVaultDigest.hex(original))
                )
            }
            let storedData = try Data(contentsOf: targetURL)
            let remainingTemporaryFiles = try temporaryFiles(alongside: targetURL)
            #expect(storedData == original)
            #expect(FileManager.default.fileExists(atPath: conflictURL.path))
            #expect(remainingTemporaryFiles.isEmpty)
        }
    }

    @Test("atomic replacement failure preserves the previous vault and unrelated conflicts")
    func replacementFailurePreservesTarget() throws {
        try withCloudRoot { rootURL in
            let original = kdbxData("before-replace")
            let targetURL = try writeCloudVault(original, rootURL: rootURL)
            let conflictURL = targetURL.deletingLastPathComponent()
                .appendingPathComponent("PasteraVault-PC-conflict.kdbx")
            try kdbxData("conflict").write(to: conflictURL)
            var operations = PasswordVaultCloudFileOperations.live
            operations.replaceItem = { _, _ in throw CloudReplicaFixtureError.replaceFailed }
            let replica = OneDrivePasswordVaultCloudReplica(operations: operations)

            #expect(throws: PasswordVaultSyncFailure.remoteWriteFailed) {
                try replica.writeAtomically(
                    self.kdbxData("after-replace"),
                    rootURL: rootURL,
                    expecting: .digest(PasswordVaultDigest.hex(original))
                )
            }
            let storedData = try Data(contentsOf: targetURL)
            let conflictData = try Data(contentsOf: conflictURL)
            let remainingTemporaryFiles = try temporaryFiles(alongside: targetURL)
            #expect(storedData == original)
            #expect(conflictData == kdbxData("conflict"))
            #expect(remainingTemporaryFiles.isEmpty)
        }
    }

    @Test("mismatched cloud readback digest fails verification and cleans the owned temporary file")
    func readbackDigestMismatchFailsVerification() throws {
        try withCloudRoot { rootURL in
            let targetURL = VaultFileCoordinator.vaultURL(for: rootURL)
            let expected = kdbxData("expected")
            var mismatched = expected
            mismatched[mismatched.index(before: mismatched.endIndex)] ^= 0x01
            #expect(mismatched.count == expected.count)
            var operations = PasswordVaultCloudFileOperations.live
            let liveRead = operations.readData
            operations.readData = { url in
                if url.standardizedFileURL == targetURL.standardizedFileURL {
                    return mismatched
                }
                return try liveRead(url)
            }
            let replica = OneDrivePasswordVaultCloudReplica(operations: operations)

            #expect(throws: PasswordVaultSyncFailure.remoteVerificationFailed) {
                try replica.writeAtomically(expected, rootURL: rootURL, expecting: .absent)
            }
            let remainingTemporaryFiles = try temporaryFiles(alongside: targetURL)
            #expect(remainingTemporaryFiles.isEmpty)
        }
    }
}

extension PasswordVaultCloudReplicaTests {

    @Test("delete failure preserves the cloud vault and all neighboring data")
    func deleteFailurePreservesEverything() throws {
        try withCloudRoot { rootURL in
            let targetURL = try writeCloudVault(kdbxData("keep-on-failure"), rootURL: rootURL)
            let siblingURL = rootURL.appendingPathComponent("history/device.sqlite")
            try FileManager.default.createDirectory(
                at: siblingURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("history".utf8).write(to: siblingURL)
            var operations = PasswordVaultCloudFileOperations.live
            let liveRemove = operations.removeItem
            operations.removeItem = { url in
                if url.standardizedFileURL == targetURL.standardizedFileURL {
                    throw CloudReplicaFixtureError.deleteFailed
                }
                try liveRemove(url)
            }
            let replica = OneDrivePasswordVaultCloudReplica(operations: operations)

            #expect(throws: PasswordVaultSyncFailure.remoteWriteFailed) {
                try replica.delete(rootURL: rootURL)
            }
            #expect(FileManager.default.fileExists(atPath: targetURL.path))
            #expect(FileManager.default.fileExists(atPath: siblingURL.path))
            #expect(FileManager.default.fileExists(atPath: rootURL.path))
        }
    }

    @Test("target query permission failure does not make delete idempotently succeed")
    func deleteTargetQueryFailureFailsClosed() throws {
        try withCloudRoot { rootURL in
            let data = kdbxData("preserve-on-query-failure")
            let targetURL = try writeCloudVault(data, rootURL: rootURL)
            var operations = PasswordVaultCloudFileOperations.live
            let liveItemStatus = operations.itemStatus
            operations.itemStatus = { url in
                if url.standardizedFileURL == targetURL.standardizedFileURL {
                    throw CocoaError(.fileReadNoPermission)
                }
                return try liveItemStatus(url)
            }
            let replica = OneDrivePasswordVaultCloudReplica(operations: operations)

            #expect(throws: PasswordVaultSyncFailure.remoteWriteFailed) {
                try replica.delete(rootURL: rootURL)
            }
            let storedData = try Data(contentsOf: targetURL)
            #expect(storedData == data)
        }
    }

    @Test("delete rejects a directory at the cloud vault path without removing it")
    func deleteRejectsNonRegularTarget() throws {
        try withCloudRoot { rootURL in
            let fixture = try writeDirectoryTarget(rootURL: rootURL)

            #expect(throws: PasswordVaultSyncFailure.remoteCorrupted) {
                try OneDrivePasswordVaultCloudReplica().delete(rootURL: rootURL)
            }
            #expect(FileManager.default.fileExists(atPath: fixture.targetURL.path))
            let sentinelData = try Data(contentsOf: fixture.sentinelURL)
            #expect(sentinelData == Data("sentinel".utf8))
        }
    }

    @Test("delete removes only the compatible cloud KDBX")
    func deleteRemovesOnlyMainCloudVault() throws {
        try withCloudRoot { rootURL in
            let targetURL = try writeCloudVault(kdbxData("delete-me"), rootURL: rootURL)
            let conflictURL = targetURL.deletingLastPathComponent()
                .appendingPathComponent("PasteraVault-Mac-conflict.kdbx")
            try kdbxData("preserve-conflict").write(to: conflictURL)
            let siblingURL = rootURL.appendingPathComponent("snippets/device.sqlite")
            try FileManager.default.createDirectory(
                at: siblingURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("snippets".utf8).write(to: siblingURL)

            try OneDrivePasswordVaultCloudReplica().delete(rootURL: rootURL)

            #expect(!FileManager.default.fileExists(atPath: targetURL.path))
            #expect(FileManager.default.fileExists(atPath: conflictURL.path))
            #expect(FileManager.default.fileExists(atPath: siblingURL.path))
            #expect(FileManager.default.fileExists(atPath: rootURL.path))
        }
    }

    @Test("deleting a missing cloud vault is idempotent")
    func deletingMissingVaultSucceeds() throws {
        try withCloudRoot { rootURL in
            try OneDrivePasswordVaultCloudReplica().delete(rootURL: rootURL)

            let rootContents = try FileManager.default.contentsOfDirectory(atPath: rootURL.path)
            #expect(rootContents.isEmpty)
        }
    }

    @Test("unavailable OneDrive root fails without creating replacement directories")
    func unavailableRootFailsClosed() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let missingRoot = parent.appendingPathComponent("missing-OneDrive", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        #expect(throws: PasswordVaultSyncFailure.folderUnavailable) {
            try OneDrivePasswordVaultCloudReplica().writeAtomically(
                self.kdbxData("do-not-write"),
                rootURL: missingRoot,
                expecting: .absent
            )
        }
        #expect(!FileManager.default.fileExists(atPath: parent.path))
    }
}

private extension PasswordVaultCloudReplicaTests {

    func kdbxData(_ payload: String) -> Data {
        signature + Data(payload.utf8)
    }

    func writeCloudVault(_ data: Data, rootURL: URL) throws -> URL {
        let targetURL = VaultFileCoordinator.vaultURL(for: rootURL)
        try FileManager.default.createDirectory(
            at: targetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: targetURL)
        return targetURL
    }

    func writeDirectoryTarget(rootURL: URL) throws -> (targetURL: URL, sentinelURL: URL) {
        let targetURL = VaultFileCoordinator.vaultURL(for: rootURL)
        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
        let sentinelURL = targetURL.appendingPathComponent("sentinel.txt")
        try Data("sentinel".utf8).write(to: sentinelURL)
        return (targetURL, sentinelURL)
    }

    func temporaryFiles(alongside targetURL: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: targetURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".PasteraVault-") && $0.pathExtension == "tmp" }
    }

    func withCloudRoot(_ operation: (URL) throws -> Void) throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try operation(rootURL)
    }
}

private enum CloudReplicaFixtureError: Error {
    case writeFailed
    case replaceFailed
    case deleteFailed
}
