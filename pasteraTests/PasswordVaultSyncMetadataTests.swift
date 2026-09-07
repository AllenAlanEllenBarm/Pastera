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

    @Test(
        "raw Foundation missing metadata errors start in local-only mode",
        arguments: [NSFileReadNoSuchFileError, NSFileNoSuchFileError]
    )
    func rawFoundationMissingErrorsUseDefault(errorCode: Int) throws {
        try withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("PasswordVaultSyncMetadata.json")
            let store = JSONPasswordVaultSyncMetadataStore(
                url: url,
                readData: { _ in
                    throw NSError(domain: NSCocoaErrorDomain, code: errorCode)
                }
            )

            let loaded = try store.load()
            #expect(loaded == .defaultLocalOnly)
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

    @Test("legacy metadata without a pending merge marker remains readable")
    func legacyMetadataWithoutPendingMergeMarkerRemainsReadable() throws {
        let legacyData = try JSONEncoder().encode(PasswordVaultSyncMetadata.defaultLocalOnly)

        let decoded = try JSONDecoder().decode(PasswordVaultSyncMetadata.self, from: legacyData)

        #expect(decoded.pendingMergedRemoteDigest == nil)
        #expect(decoded.pendingForcedReset == nil)
    }

    @Test("pending merge marker round trips as an anonymous digest")
    func pendingMergeMarkerRoundTrips() throws {
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.pendingMergedRemoteDigest = String(repeating: "d", count: 64)

        let encoded = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(PasswordVaultSyncMetadata.self, from: encoded)

        #expect(decoded == metadata)
        #expect(decoded.pendingMergedRemoteDigest == String(repeating: "d", count: 64))
    }

    @Test("pending forced reset round trips with digests and progress only")
    func pendingForcedResetRoundTripsWithoutPlaintext() throws {
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.pendingForcedReset = PasswordVaultPendingForcedReset(
            previousLocalDigest: String(repeating: "a", count: 64),
            replacementLocalDigest: String(repeating: "b", count: 64),
            didInspectRemote: true,
            observedRemoteDigest: String(repeating: "c", count: 64),
            archivedRemoteDigest: String(repeating: "d", count: 64),
            remoteArchiveRequired: true
        )

        let encoded = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(PasswordVaultSyncMetadata.self, from: encoded)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let pending = try #require(object["pendingForcedReset"] as? [String: Any])

        #expect(decoded == metadata)
        #expect(Set(pending.keys) == [
            "previousLocalDigest",
            "replacementLocalDigest",
            "didInspectRemote",
            "observedRemoteDigest",
            "archivedRemoteDigest",
            "remoteArchiveRequired"
        ])
        #expect(pending["remoteArchiveRequired"] as? Bool == true)
        let text = try #require(String(data: encoded, encoding: .utf8))
        #expect(!text.contains("vault-password-DO-NOT-PERSIST"))
        #expect(!text.contains("raw-key-DO-NOT-PERSIST"))
        #expect(!text.contains("KDBX-plaintext-DO-NOT-PERSIST"))
        #expect(!text.contains("authentication-value-DO-NOT-PERSIST"))
    }

    @Test("schema one pending reset without archive requirement decodes as unknown")
    func legacyPendingForcedResetWithoutArchiveRequirementRemainsReadable() throws {
        var metadata = PasswordVaultSyncMetadata.defaultLocalOnly
        metadata.mode = .oneDrive
        metadata.pendingForcedReset = PasswordVaultPendingForcedReset(
            previousLocalDigest: String(repeating: "a", count: 64),
            replacementLocalDigest: String(repeating: "b", count: 64),
            didInspectRemote: true,
            observedRemoteDigest: String(repeating: "c", count: 64),
            archivedRemoteDigest: String(repeating: "c", count: 64),
            remoteArchiveRequired: true
        )
        let encoded = try JSONEncoder().encode(metadata)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var pending = try #require(object["pendingForcedReset"] as? [String: Any])
        pending.removeValue(forKey: "remoteArchiveRequired")
        object["pendingForcedReset"] = pending
        let legacySchemaOneData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(
            PasswordVaultSyncMetadata.self,
            from: legacySchemaOneData
        )

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.pendingForcedReset?.remoteArchiveRequired == nil)
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
