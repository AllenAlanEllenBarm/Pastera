import Foundation
import Testing
@testable import Pastera

@Suite("Password vault sync metadata")
struct PasswordVaultSyncMetadataTests {
    @Test("missing metadata starts in local-only mode")
    func missingMetadataUsesDefault() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("nested/PasswordVaultSyncMetadata.json")
            let store = JSONPasswordVaultSyncMetadataStore(url: url)

            let loaded = try store.load()
            #expect(loaded == .defaultLocalOnly)
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test("metadata read failure never silently downgrades to local-only mode")
    func readFailureIsPropagated() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("PasswordVaultSyncMetadata.json")
            let store = JSONPasswordVaultSyncMetadataStore(
                url: url,
                readData: { _ in throw CocoaError(.fileReadNoPermission) }
            )

            #expect(throws: CocoaError.self) {
                try store.load()
            }
        }
    }

    @Test("saving metadata atomically replaces the previous complete value")
    func atomicSaveReplacesPreviousValue() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("nested/PasswordVaultSyncMetadata.json")
            let store = JSONPasswordVaultSyncMetadataStore(url: url)
            var first = PasswordVaultSyncMetadata.defaultLocalOnly
            first.localRevision = 2
            var replacement = first
            replacement.mode = .oneDrive
            replacement.localRevision = 7
            replacement.pendingChangeCount = 3

            try store.save(first)
            try store.save(replacement)

            #expect(try store.load() == replacement)
            let siblings = try FileManager.default.contentsOfDirectory(
                at: url.deletingLastPathComponent(),
                includingPropertiesForKeys: nil
            )
            #expect(siblings.count == 1)
            #expect(siblings.first?.lastPathComponent == url.lastPathComponent)
        }
    }

    @Test("failed atomic save preserves the previous sync baseline")
    func failedSavePreservesPreviousValue() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("PasswordVaultSyncMetadata.json")
            let workingStore = JSONPasswordVaultSyncMetadataStore(url: url)
            var baseline = PasswordVaultSyncMetadata.defaultLocalOnly
            baseline.mode = .oneDrive
            baseline.localRevision = 9
            baseline.lastSyncedLocalRevision = 8
            baseline.lastObservedRemoteDigest = String(repeating: "a", count: 64)
            try workingStore.save(baseline)

            let failingStore = JSONPasswordVaultSyncMetadataStore(
                url: url,
                atomicWrite: { _, _ in throw MetadataFixtureError.writeFailed }
            )
            var changed = baseline
            changed.localRevision = 10

            #expect(throws: MetadataFixtureError.writeFailed) {
                try failingStore.save(changed)
            }
            #expect(try workingStore.load() == baseline)
        }
    }

    @Test("corrupted metadata is rejected without erasing enabled sync state")
    func corruptedMetadataIsRejectedAndPreserved() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("PasswordVaultSyncMetadata.json")
            let corrupted = Data("{\"mode\":\"oneDrive\",\"localRevision\":".utf8)
            try corrupted.write(to: url)
            let store = JSONPasswordVaultSyncMetadataStore(url: url)

            #expect(throws: PasswordVaultSyncMetadataStoreError.corrupted) {
                try store.load()
            }
            #expect(try Data(contentsOf: url) == corrupted)
        }
    }

    @Test("unknown metadata schema is rejected without rewriting future data")
    func unknownSchemaIsRejectedAndPreserved() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("PasswordVaultSyncMetadata.json")
            var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
            metadata.schemaVersion = PasswordVaultSyncMetadata.currentSchemaVersion + 1
            metadata.mode = .oneDrive
            let futureData = try JSONEncoder().encode(metadata)
            try futureData.write(to: url)
            let store = JSONPasswordVaultSyncMetadataStore(url: url)

            #expect(throws: PasswordVaultSyncMetadataStoreError.unsupportedSchemaVersion(
                metadata.schemaVersion
            )) {
                try store.load()
            }
            #expect(try Data(contentsOf: url) == futureData)
        }
    }

    @Test("encoded metadata never persists decrypted vault fields")
    func encodedMetadataExcludesSensitiveFixtures() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("PasswordVaultSyncMetadata.json")
            let store = JSONPasswordVaultSyncMetadataStore(url: url)
            var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
            metadata.mode = .oneDrive
            metadata.lastSyncedLocalDigest = String(repeating: "b", count: 64)
            metadata.lastObservedRemoteDigest = String(repeating: "c", count: 64)
            try store.save(metadata)

            let encoded = try Data(contentsOf: url)
            let text = try #require(String(data: encoded, encoding: .utf8))
            let sensitiveFixtures = [
                "Quarterly Payroll",
                "finance-admin@example.com",
                "vault-password-DO-NOT-PERSIST",
                "private recovery note"
            ]
            for fixture in sensitiveFixtures {
                #expect(!text.contains(fixture))
            }
            let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            let forbiddenKeys = ["title", "username", "account", "password", "website", "url", "note", "content"]
            for key in forbiddenKeys {
                #expect(object[key] == nil)
            }
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

private enum MetadataFixtureError: Error {
    case writeFailed
}
