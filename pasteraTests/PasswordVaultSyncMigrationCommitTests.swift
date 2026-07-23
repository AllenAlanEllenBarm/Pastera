import Testing
@testable import Pastera

@Suite("Password vault sync migration commits", .serialized)
struct PasswordVaultSyncMigrationCommitTests {
    @Test("migration commit reloads the metadata written by migration before publishing")
    func migrationCommitReloadsPersistedModeAndBaselines() throws {
        let fixture = try makeSyncServiceFixture()
        var migrated = PasswordVaultSyncMetadata.defaultLocalOnly
        migrated.mode = .oneDrive
        migrated.localRevision = 4
        migrated.lastSyncedLocalRevision = 4
        migrated.lastObservedRemoteDigest = "remote-baseline"
        migrated.migrationVersion = 1
        fixture.metadata.value = migrated

        fixture.service.record(PasswordVaultCommit(origin: .migration, encryptedDigest: "local-baseline"))
        fixture.drain()

        #expect(fixture.metadata.value.mode == .oneDrive)
        #expect(fixture.metadata.value.localRevision == 4)
        #expect(fixture.metadata.value.lastSyncedLocalRevision == 4)
        #expect(fixture.metadata.value.lastSyncedLocalDigest == "local-baseline")
        #expect(fixture.metadata.value.lastObservedRemoteDigest == "remote-baseline")
        #expect(fixture.metadata.value.migrationVersion == 1)
        #expect(fixture.service.snapshot.mode == .oneDrive)
    }
}
