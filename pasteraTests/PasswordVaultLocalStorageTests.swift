import Foundation
import Testing
@testable import Pastera

@Suite("Password vault local storage")
struct PasswordVaultLocalStorageTests {
    private let signature = Data([0x03, 0xD9, 0xA2, 0x9A, 0x67, 0xFB, 0x4B, 0xB5])

    @Test("live paths isolate vaults by bundle identifier")
    func livePathsAreBundleIdentifierScoped() {
        let first = PasswordVaultLocalPaths.live(bundleIdentifier: "com.example.first")
        let second = PasswordVaultLocalPaths.live(bundleIdentifier: "com.example.second")

        #expect(first.directoryURL != second.directoryURL)
        #expect(first.directoryURL.path.hasSuffix("com.example.first/PasswordVault"))
        #expect(first.vaultURL.lastPathComponent == "PasteraVault.kdbx")
        #expect(first.backupURL.lastPathComponent == "PasteraVault.kdbx.bak")
        #expect(first.metadataURL.lastPathComponent == "PasswordVaultSyncMetadata.json")
    }

    @Test("first atomic write creates a readable KDBX without a backup")
    func firstWriteCreatesVault() throws {
        try withTemporaryStorage { storage in
            let data = kdbxData("first")

            try storage.writeAtomically(data)

            #expect(try storage.containsVault())
            #expect(try storage.read() == data)
            #expect(!FileManager.default.fileExists(atPath: storage.paths.backupURL.path))
        }
    }

    @Test("overwriting a vault preserves the previous KDBX as backup")
    func overwriteCreatesBackup() throws {
        try withTemporaryStorage { storage in
            let original = kdbxData("original")
            let replacement = kdbxData("replacement")
            try storage.writeAtomically(original)

            try storage.writeAtomically(replacement)

            #expect(try storage.read() == replacement)
            #expect(try storage.readBackup() == original)
        }
    }

    @Test("failed backup write leaves the current vault unchanged")
    func failedWritePreservesCurrentVault() throws {
        try withTemporaryDirectory { directory in
            let paths = PasswordVaultLocalPaths(
                directoryURL: directory,
                vaultURL: directory.appendingPathComponent("PasteraVault.kdbx"),
                backupURL: directory
                    .appendingPathComponent("missing", isDirectory: true)
                    .appendingPathComponent("PasteraVault.kdbx.bak"),
                metadataURL: directory.appendingPathComponent("PasswordVaultSyncMetadata.json")
            )
            let storage = FilePasswordVaultLocalStorage(paths: paths)
            let original = kdbxData("original")
            try storage.writeAtomically(original)

            #expect(throws: (any Error).self) {
                try storage.writeAtomically(kdbxData("replacement"))
            }
            #expect(try Data(contentsOf: paths.vaultURL) == original)
            #expect(try storage.read() == original)
            #expect(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "tmp" }
                .isEmpty)
        }
    }

    @Test("empty and invalid signatures are rejected before persistence")
    func invalidKDBXDataIsRejected() throws {
        try withTemporaryStorage { storage in
            #expect(throws: PasswordVaultError.corruptedData) {
                try storage.writeAtomically(Data())
            }
            #expect(throws: PasswordVaultError.corruptedData) {
                try storage.writeAtomically(Data("not-a-kdbx".utf8))
            }
            let containsVault = try storage.containsVault()
            #expect(!containsVault)
        }
    }

    @Test("two file storage instances serialize the same local vault transaction")
    func samePathTransactionsAreSharedAcrossInstances() throws {
        try withTemporaryDirectory { directory in
            let paths = PasswordVaultLocalPaths(
                directoryURL: directory,
                vaultURL: directory.appendingPathComponent("PasteraVault.kdbx"),
                backupURL: directory.appendingPathComponent("PasteraVault.kdbx.bak"),
                metadataURL: directory.appendingPathComponent("PasswordVaultSyncMetadata.json")
            )
            let first = FilePasswordVaultLocalStorage(paths: paths)
            let second = FilePasswordVaultLocalStorage(paths: paths)
            let transactionEntered = DispatchSemaphore(value: 0)
            let releaseTransaction = DispatchSemaphore(value: 0)
            let writerStarted = DispatchSemaphore(value: 0)
            let writerFinished = DispatchSemaphore(value: 0)
            let transactionFinished = DispatchSemaphore(value: 0)
            let secondData = kdbxData("second")

            Thread.detachNewThread {
                _ = try? first.withExclusiveTransaction {
                    transactionEntered.signal()
                    releaseTransaction.wait()
                }
                transactionFinished.signal()
            }
            #expect(transactionEntered.wait(timeout: .now() + 30) == .success)
            Thread.detachNewThread {
                writerStarted.signal()
                try? second.writeAtomically(secondData)
                writerFinished.signal()
            }
            #expect(writerStarted.wait(timeout: .now() + 30) == .success)
            let writerBeforeRelease = writerFinished.wait(timeout: .now() + 1)
            releaseTransaction.signal()

            #expect(transactionFinished.wait(timeout: .now() + 30) == .success)
            if writerBeforeRelease == .timedOut {
                #expect(writerFinished.wait(timeout: .now() + 30) == .success)
            }
            #expect(writerBeforeRelease == .timedOut)
            let readback = try second.read()
            #expect(readback == secondData)
        }
    }

    @Test("the local vault transaction blocks a separate process flock")
    func separateProcessFlockBlocksTransaction() throws {
        try withTemporaryDirectory { directory in
            let lockURL = directory.appendingPathComponent(".PasteraVault.lock")
            let paths = PasswordVaultLocalPaths(
                directoryURL: directory,
                vaultURL: directory.appendingPathComponent("PasteraVault.kdbx"),
                backupURL: directory.appendingPathComponent("PasteraVault.kdbx.bak"),
                metadataURL: directory.appendingPathComponent("PasswordVaultSyncMetadata.json")
            )
            let storage = FilePasswordVaultLocalStorage(paths: paths)
            let transactionEntered = DispatchSemaphore(value: 0)
            let releaseTransaction = DispatchSemaphore(value: 0)
            let transactionFinished = DispatchSemaphore(value: 0)
            Thread.detachNewThread {
                _ = try? storage.withExclusiveTransaction {
                    transactionEntered.signal()
                    releaseTransaction.wait()
                }
                transactionFinished.signal()
            }
            #expect(transactionEntered.wait(timeout: .now() + 30) == .success)

            let child = Process()
            let childOutput = Pipe()
            child.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            child.arguments = [
                "-c",
                """
                import fcntl, os, sys
                fd = os.open(sys.argv[1], os.O_CREAT | os.O_RDWR, 0o600)
                print("attempting", flush=True)
                fcntl.flock(fd, fcntl.LOCK_EX)
                print("locked", flush=True)
                fcntl.flock(fd, fcntl.LOCK_UN)
                os.close(fd)
                """,
                lockURL.path
            ]
            child.standardOutput = childOutput
            try child.run()
            defer {
                releaseTransaction.signal()
                if child.isRunning { child.terminate() }
            }

            let attempting = childOutput.fileHandleForReading.availableData
            let attemptingText = try #require(String(data: attempting, encoding: .utf8))
            #expect(attemptingText.contains("attempting"))
            #expect(!attemptingText.contains("locked"))
            let lockedReadStarted = DispatchSemaphore(value: 0)
            let lockedReadFinished = DispatchSemaphore(value: 0)
            let lockedOutput = PasswordVaultProcessOutputBox()
            Thread.detachNewThread {
                lockedReadStarted.signal()
                lockedOutput.set(childOutput.fileHandleForReading.availableData)
                lockedReadFinished.signal()
            }
            #expect(lockedReadStarted.wait(timeout: .now() + 30) == .success)
            let lockedBeforeRelease = lockedReadFinished.wait(timeout: .now() + 1)
            releaseTransaction.signal()

            #expect(lockedBeforeRelease == .timedOut)
            #expect(transactionFinished.wait(timeout: .now() + 30) == .success)
            if lockedBeforeRelease == .timedOut {
                #expect(lockedReadFinished.wait(timeout: .now() + 30) == .success)
            }
            let lockedText = try #require(String(data: lockedOutput.data, encoding: .utf8))
            #expect(lockedText.contains("locked"))
            child.waitUntilExit()
            #expect(child.terminationStatus == 0)
        }
    }

    @Test("migration cleanup preserves a local vault whose digest no longer matches")
    func migrationCleanupRequiresDigestOwnership() throws {
        try withTemporaryStorage { storage in
            let current = kdbxData("newer-local")
            try storage.writeAtomically(current)

            let removed = try storage.removeVaultCreatedByFailedMigration(
                expectedDigest: PasswordVaultDigest.hex(kdbxData("older-migration"))
            )

            #expect(!removed)
            let readback = try storage.read()
            #expect(readback == current)
        }
    }

    @Test("sync metadata JSON contains no decrypted vault fields")
    func syncMetadataJSONExcludesSensitiveFields() throws {
        let metadata = PasswordVaultSyncMetadata(
            schemaVersion: PasswordVaultSyncMetadata.currentSchemaVersion,
            mode: .oneDrive,
            localRevision: 4,
            lastSyncedLocalRevision: 3,
            lastSyncedLocalDigest: "local-digest",
            lastObservedRemoteDigest: "remote-digest",
            pendingMergedRemoteDigest: nil,
            lastSyncAt: Date(timeIntervalSince1970: 100),
            pendingChangeCount: 1,
            conflictCopyCount: 0,
            lastFailure: .remoteUnavailable,
            migrationVersion: 1
        )

        let encoded = try JSONEncoder().encode(metadata)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let forbiddenKeys = ["title", "username", "account", "password", "website", "url", "note", "content"]

        for key in forbiddenKeys {
            #expect(object[key] == nil)
        }
    }

    @Test("password vault sync settings use dedicated defaults keys")
    func syncSettingsUseDedicatedKeys() {
        #expect(Constants.UserDefaults.passwordVaultSyncMode == "kPasteraPasswordVaultSyncMode")
        #expect(Constants.UserDefaults.passwordVaultLocalFirstMigrationVersion == "kPasteraPasswordVaultLocalFirstMigrationVersion")
    }

    private func kdbxData(_ payload: String) -> Data {
        signature + Data(payload.utf8)
    }

    private func withTemporaryStorage(
        _ operation: (FilePasswordVaultLocalStorage) throws -> Void
    ) throws {
        try withTemporaryDirectory { directory in
            let paths = PasswordVaultLocalPaths(
                directoryURL: directory,
                vaultURL: directory.appendingPathComponent("PasteraVault.kdbx"),
                backupURL: directory.appendingPathComponent("PasteraVault.kdbx.bak"),
                metadataURL: directory.appendingPathComponent("PasswordVaultSyncMetadata.json")
            )
            try operation(FilePasswordVaultLocalStorage(paths: paths))
        }
    }

    private func withTemporaryDirectory(_ operation: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try operation(directory)
    }
}

private final class PasswordVaultProcessOutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var data: Data { lock.withLock { storage } }

    func set(_ data: Data) {
        lock.withLock { storage = data }
    }
}
