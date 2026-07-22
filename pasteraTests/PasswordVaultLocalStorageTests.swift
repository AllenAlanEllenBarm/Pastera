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

            #expect(storage.containsVault())
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
            #expect(!storage.containsVault())
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
