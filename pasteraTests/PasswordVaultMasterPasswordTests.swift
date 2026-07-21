import Foundation
import KDBXKit
import Testing
@testable import Pastera

@Suite("Password vault master password change")
struct PasswordVaultMasterPasswordTests {
    @Test("wrong current password leaves every managed artifact unchanged")
    func wrongCurrentPasswordDoesNotMutateArtifacts() throws {
        let fixture = try RekeyFixture()
        defer { fixture.remove() }
        try fixture.addManagedCopies()
        let original = try fixture.artifactBytes()

        #expect(throws: PasswordVaultError.wrongMasterPassword) {
            try fixture.store.changeMasterPassword(
                currentPassword: "incorrect fixture password",
                newPassword: fixture.newPassword,
                keepQuickUnlockEnabled: true
            )
        }

        #expect(try fixture.artifactBytes() == original)
        #expect(fixture.rekeyTemporaryFiles().isEmpty)
    }

    @Test("empty new password is rejected before staging")
    func emptyNewPasswordDoesNotStageFiles() throws {
        let fixture = try RekeyFixture()
        defer { fixture.remove() }

        #expect(throws: PasswordVaultError.invalidPassword) {
            try fixture.store.changeMasterPassword(
                currentPassword: fixture.oldPassword,
                newPassword: "",
                keepQuickUnlockEnabled: false
            )
        }

        #expect(fixture.rekeyTemporaryFiles().isEmpty)
        #expect(fixture.canOpen(fixture.vaultURL, password: fixture.oldPassword))
    }

    @Test("success rekeys all artifacts and keeps merged vault data")
    func successfulChangeRekeysAllArtifactsAndMergesLatestData() throws {
        let fixture = try RekeyFixture()
        defer { fixture.remove() }
        try fixture.addLocalEntry(title: "Memory Entry")
        try fixture.addExternalEntry(title: "Disk Entry")
        try fixture.addConflictEntry(title: "Conflict Entry")
        try fixture.addResolvedArchive()

        let result = try fixture.store.changeMasterPassword(
            currentPassword: fixture.oldPassword,
            newPassword: fixture.newPassword,
            keepQuickUnlockEnabled: true
        )

        #expect(result.warnings.isEmpty)
        #expect(Set(try fixture.store.listEntries().map(\.title)) == ["Memory Entry", "Disk Entry", "Conflict Entry"])
        let artifacts = try fixture.transaction.managedArtifactURLs(alongside: fixture.vaultURL)
        #expect(artifacts.count >= 3)
        for url in artifacts {
            #expect(fixture.canOpen(url, password: fixture.newPassword))
            #expect(!fixture.canOpen(url, password: fixture.oldPassword))
        }
        #expect(fixture.rekeyTemporaryFiles().isEmpty)
    }

    @Test(
        "staging, readback, revision, and replacement failures roll back every artifact",
        arguments: RekeyFault.allCases
    )
    func transactionFailureRollsBackAllArtifacts(fault: RekeyFault) throws {
        var injected = false
        let transaction = VaultArtifactRekeyTransaction { checkpoint in
            guard !injected, fault.matches(checkpoint) else { return }
            injected = true
            throw PasswordVaultError.saveFailed
        }
        let fixture = try RekeyFixture(transaction: transaction)
        defer { fixture.remove() }
        try fixture.addManagedCopies()
        let original = try fixture.artifactBytes()

        #expect(throws: PasswordVaultError.saveFailed) {
            try fixture.store.changeMasterPassword(
                currentPassword: fixture.oldPassword,
                newPassword: fixture.newPassword,
                keepQuickUnlockEnabled: true
            )
        }

        #expect(injected)
        #expect(try fixture.artifactBytes() == original)
        for url in original.keys {
            #expect(fixture.canOpen(url, password: fixture.oldPassword))
            #expect(!fixture.canOpen(url, password: fixture.newPassword))
        }
        #expect(fixture.rekeyTemporaryFiles().isEmpty)
    }

    @Test("a source revision change after staging is never overwritten")
    func sourceRevisionRaceIsPreserved() throws {
        var replacementData = Data()
        var didMutate = false
        let transaction = VaultArtifactRekeyTransaction { checkpoint in
            guard !didMutate, case let .revisionCheck(url) = checkpoint else { return }
            didMutate = true
            replacementData = Data("external fixture revision".utf8)
            try replacementData.write(to: url, options: .atomic)
        }
        let fixture = try RekeyFixture(transaction: transaction)
        defer { fixture.remove() }
        try fixture.addManagedCopies()

        #expect(throws: PasswordVaultError.externalConflict) {
            try fixture.store.changeMasterPassword(
                currentPassword: fixture.oldPassword,
                newPassword: fixture.newPassword,
                keepQuickUnlockEnabled: false
            )
        }

        #expect(didMutate)
        #expect(try Data(contentsOf: fixture.vaultURL) == replacementData)
        #expect(fixture.rekeyTemporaryFiles().isEmpty)
    }

    @Test("a locked store stays locked after a successful password change")
    func lockedStoreRemainsLocked() throws {
        let fixture = try RekeyFixture()
        defer { fixture.remove() }
        try fixture.addLocalEntry(title: "Preserved Entry")
        fixture.store.lock()

        _ = try fixture.store.changeMasterPassword(
            currentPassword: fixture.oldPassword,
            newPassword: fixture.newPassword,
            keepQuickUnlockEnabled: false
        )

        #expect(fixture.store.state == .locked)
        #expect(throws: PasswordVaultError.vaultLocked) { try fixture.store.listEntries() }
        try fixture.store.unlock(masterPassword: fixture.newPassword, rememberQuickUnlock: false)
        #expect(try fixture.store.listEntries().map(\.title) == ["Preserved Entry"])
    }
}

enum RekeyFault: CaseIterable {
    case stageWrite
    case stageReadback
    case revisionCheck
    case secondReplace

    func matches(_ checkpoint: VaultArtifactRekeyCheckpoint) -> Bool {
        switch (self, checkpoint) {
        case (.stageWrite, .stageWrite):
            true
        case (.stageReadback, .stageReadback):
            true
        case (.revisionCheck, .revisionCheck):
            true
        case let (.secondReplace, .replace(_, index)):
            index == 1
        default:
            false
        }
    }
}

private final class RekeyFixture {
    let oldPassword = "old fixture password"
    let newPassword = "new fixture password"
    let root: URL
    let vaultURL: URL
    let transaction: VaultArtifactRekeyTransaction
    let store: KDBXPasswordVaultStore

    init(transaction: VaultArtifactRekeyTransaction = VaultArtifactRekeyTransaction()) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        vaultURL = VaultFileCoordinator.vaultURL(for: root)
        self.transaction = transaction
        store = KDBXPasswordVaultStore(
            syncRootProvider: { [root] in root },
            unlockKeyStore: RekeyUnlockKeyStore(),
            automationUnlockKeyStore: RekeyAutomationKeyStore(),
            rekeyTransaction: transaction
        )
        try store.createDatabase(masterPassword: oldPassword, rememberQuickUnlock: false)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func addLocalEntry(title: String) throws {
        let folder = try store.listFolders().first ?? store.createFolder(name: "Fixture")
        _ = try store.create(.init(
            folderID: folder.id,
            title: title,
            website: "",
            username: "fixture",
            note: "",
            password: "entry fixture value"
        ))
    }

    func addExternalEntry(title: String) throws {
        let external = KDBXPasswordVaultStore(syncRootProvider: { [root] in root })
        try external.unlock(masterPassword: oldPassword, rememberQuickUnlock: false)
        let folder = try external.listFolders().first ?? external.createFolder(name: "External")
        _ = try external.create(.init(
            folderID: folder.id,
            title: title,
            website: "",
            username: "external",
            note: "",
            password: "external fixture value"
        ))
    }

    func addConflictEntry(title: String) throws {
        let conflictRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: conflictRoot) }
        try FileManager.default.createDirectory(at: conflictRoot, withIntermediateDirectories: true)
        let conflictStore = KDBXPasswordVaultStore(syncRootProvider: { [conflictRoot] in conflictRoot })
        try conflictStore.createDatabase(masterPassword: oldPassword, rememberQuickUnlock: false)
        let folder = try conflictStore.createFolder(name: "Conflict")
        _ = try conflictStore.create(.init(
            folderID: folder.id,
            title: title,
            website: "",
            username: "conflict",
            note: "",
            password: "conflict fixture value"
        ))
        let conflictURL = vaultURL.deletingLastPathComponent().appendingPathComponent("PasteraVault-conflict.kdbx")
        try Data(contentsOf: VaultFileCoordinator.vaultURL(for: conflictRoot)).write(to: conflictURL, options: .atomic)
    }

    func addResolvedArchive() throws {
        let resolved = vaultURL.deletingLastPathComponent()
            .appendingPathComponent("conflicts/resolved", isDirectory: true)
        try FileManager.default.createDirectory(at: resolved, withIntermediateDirectories: true)
        try Data(contentsOf: vaultURL).write(
            to: resolved.appendingPathComponent("previous-conflict.kdbx"),
            options: .atomic
        )
    }

    func addManagedCopies() throws {
        try Data(contentsOf: vaultURL).write(to: vaultURL.appendingPathExtension("bak"), options: .atomic)
        try Data(contentsOf: vaultURL).write(
            to: vaultURL.deletingLastPathComponent().appendingPathComponent("PasteraVault-conflict.kdbx"),
            options: .atomic
        )
        try addResolvedArchive()
    }

    func artifactBytes() throws -> [URL: Data] {
        try Dictionary(uniqueKeysWithValues: transaction.managedArtifactURLs(alongside: vaultURL).map {
            ($0, try Data(contentsOf: $0))
        })
    }

    func rekeyTemporaryFiles() -> [URL] {
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        return (enumerator?.allObjects as? [URL] ?? []).filter { $0.lastPathComponent.hasPrefix(".pastera-rekey-") }
    }

    func canOpen(_ url: URL, password: String) -> Bool {
        do {
            _ = try KDBXReader.parse(Data(contentsOf: url), unlockData: UnlockData(masterPassword: password))
            return true
        } catch {
            return false
        }
    }
}

private final class RekeyUnlockKeyStore: VaultUnlockKeyStoring {
    var data: Data?
    var containsKey: Bool { data != nil }
    func save(_ data: Data) throws { self.data = data }
    func load(reason: String) throws -> Data { try #require(data) }
    func delete() throws { data = nil }
}

private final class RekeyAutomationKeyStore: VaultAutomationUnlockKeyStoring {
    var data: Data?
    var containsKey: Bool { data != nil }
    func save(_ data: Data) throws { self.data = data }
    func load() throws -> Data { try #require(data) }
    func delete() throws { data = nil }
}
