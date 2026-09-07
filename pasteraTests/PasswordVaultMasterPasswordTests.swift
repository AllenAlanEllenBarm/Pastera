import Foundation
import KDBXKit
import LocalAuthentication
import Testing
@testable import Pastera

extension PasswordVaultAuthorizationContext {
    static var testing: Self { .init(localAuthenticationContext: nil) }
}

@Suite("Password vault master password reset")
struct PasswordVaultMasterPasswordTests {
    @Test("no authorized unlock material leaves every managed artifact unchanged")
    func resetWithoutUnlockMaterialDoesNotMutateArtifacts() throws {
        let fixture = try RekeyFixture()
        defer { fixture.remove() }
        try fixture.addManagedCopies()
        let original = try fixture.artifactBytes()
        fixture.store.lock()

        #expect(throws: PasswordVaultError.resetRequiresForcedReset) {
            try fixture.store.resetMasterPassword(
                newPassword: fixture.newPassword,
                keepSystemUnlockEnabled: true,
                authorization: .testing
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
            try fixture.store.resetMasterPassword(
                newPassword: "",
                keepSystemUnlockEnabled: false,
                authorization: .testing
            )
        }

        #expect(fixture.rekeyTemporaryFiles().isEmpty)
        #expect(fixture.canOpen(fixture.vaultURL, password: fixture.oldPassword))
    }

    @Test("readable session resets the master password without the old password")
    func readableSessionResetPreservesData() throws {
        let fixture = try RekeyFixture()
        defer { fixture.remove() }
        try fixture.addLocalEntry(title: "Preserved Entry")

        _ = try fixture.store.resetMasterPassword(
            newPassword: fixture.newPassword,
            keepSystemUnlockEnabled: true,
            authorization: .testing
        )

        #expect(try fixture.store.listEntries().map(\.title) == ["Preserved Entry"])
        #expect(fixture.canOpen(fixture.vaultURL, password: fixture.newPassword))
        #expect(!fixture.canOpen(fixture.vaultURL, password: fixture.oldPassword))
    }

    @Test("locked vault uses the authorized quick-unlock key once")
    func quickKeyResetPreservesData() throws {
        let fixture = try RekeyFixture()
        defer { fixture.remove() }
        try fixture.addLocalEntry(title: "Preserved Entry")
        try fixture.store.enableQuickUnlock()
        fixture.store.lock()
        let authorizationContext = LAContext()

        _ = try fixture.store.resetMasterPassword(
            newPassword: fixture.newPassword,
            keepSystemUnlockEnabled: true,
            authorization: .init(localAuthenticationContext: authorizationContext)
        )

        #expect(fixture.quickKey.authorizationContextLoadCount == 1)
        #expect(try #require(fixture.quickKey.receivedAuthenticationContext) === authorizationContext)
        #expect(fixture.canOpen(fixture.vaultURL, password: fixture.newPassword))
    }

    @Test("quick-unlock cancellation leaves every managed artifact unchanged")
    func quickKeyCancellationDoesNotMutateArtifacts() throws {
        let fixture = try RekeyFixture()
        defer { fixture.remove() }
        try fixture.addManagedCopies()
        try fixture.store.enableQuickUnlock()
        fixture.store.lock()
        let original = try fixture.artifactBytes()
        fixture.quickKey.nextAuthorizationContextLoadError = .userCancelled

        #expect(throws: PasswordVaultError.userCancelled) {
            try fixture.store.resetMasterPassword(
                newPassword: fixture.newPassword,
                keepSystemUnlockEnabled: true,
                authorization: .init(localAuthenticationContext: LAContext())
            )
        }

        #expect(try fixture.artifactBytes() == original)
    }

    @Test("quick-unlock authentication failure leaves every managed artifact unchanged")
    func quickKeyAuthenticationFailureDoesNotMutateArtifacts() throws {
        let fixture = try RekeyFixture()
        defer { fixture.remove() }
        try fixture.addManagedCopies()
        try fixture.store.enableQuickUnlock()
        fixture.store.lock()
        let original = try fixture.artifactBytes()
        fixture.quickKey.nextAuthorizationContextLoadError = .authenticationFailed

        #expect(throws: PasswordVaultError.authenticationFailed) {
            try fixture.store.resetMasterPassword(
                newPassword: fixture.newPassword,
                keepSystemUnlockEnabled: true,
                authorization: .init(localAuthenticationContext: LAContext())
            )
        }

        #expect(try fixture.artifactBytes() == original)
    }

    @Test("locked vault uses the automation-unlock key after quick unlock is unavailable")
    func automationKeyResetPreservesData() throws {
        let fixture = try RekeyFixture()
        defer { fixture.remove() }
        try fixture.addLocalEntry(title: "Preserved Entry")
        try fixture.store.enableAutomationUnlock()
        fixture.store.lock()

        _ = try fixture.store.resetMasterPassword(
            newPassword: fixture.newPassword,
            keepSystemUnlockEnabled: true,
            authorization: .testing
        )

        #expect(fixture.automationKey.loadCallCount == 1)
        #expect(fixture.canOpen(fixture.vaultURL, password: fixture.newPassword))
    }

    @Test("success rekeys all artifacts and keeps merged vault data")
    func successfulResetRekeysAllArtifactsAndMergesLatestData() throws {
        let fixture = try RekeyFixture()
        defer { fixture.remove() }
        try fixture.addLocalEntry(title: "Memory Entry")
        try fixture.addExternalEntry(title: "Disk Entry")
        try fixture.addConflictEntry(title: "Conflict Entry")
        try fixture.addResolvedArchive()

        let result = try fixture.store.resetMasterPassword(
            newPassword: fixture.newPassword,
            keepSystemUnlockEnabled: true,
            authorization: .testing
        )

        #expect(result.warnings.isEmpty)
        #expect(Set(try fixture.store.listEntries().map(\.title)) == ["Memory Entry", "Disk Entry", "Conflict Entry"])
        let artifacts = try fixture.transaction.managedArtifactURLs(in: fixture.localStorage.paths)
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
            try fixture.store.resetMasterPassword(
                newPassword: fixture.newPassword,
                keepSystemUnlockEnabled: true,
                authorization: .testing
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
            try fixture.store.resetMasterPassword(
                newPassword: fixture.newPassword,
                keepSystemUnlockEnabled: false,
                authorization: .testing
            )
        }

        #expect(didMutate)
        #expect(try Data(contentsOf: fixture.vaultURL) == replacementData)
        #expect(fixture.rekeyTemporaryFiles().isEmpty)
    }

    @Test("rollback cleanup failure leaves only new-password data and reports pending cleanup")
    func committedRekeySanitizesRollbackBeforeCleanupFailure() throws {
        let fileManager = RekeyRollbackCleanupFailingFileManager()
        let fixture = try RekeyFixture(transaction: VaultArtifactRekeyTransaction(fileManager: fileManager))
        defer { fixture.remove() }
        try fixture.addLocalEntry(title: "Preserved Entry")
        try fixture.store.enableQuickUnlock()
        try fixture.store.enableAutomationUnlock()

        let outcome = Result {
            try fixture.store.resetMasterPassword(
                newPassword: fixture.newPassword,
                keepSystemUnlockEnabled: true,
                authorization: .testing
            )
        }

        let result = try outcome.get()
        #expect(result.warnings.map(\.rawValue) == ["rekeyArtifactCleanupPending"])
        #expect(fixture.canOpen(fixture.vaultURL, password: fixture.newPassword))
        #expect(!fixture.canOpen(fixture.vaultURL, password: fixture.oldPassword))
        #expect(fixture.store.state == .unlocked)
        #expect(try fixture.store.listEntries().map(\.title) == ["Preserved Entry"])
        let rollbackFiles = fixture.rekeyTemporaryFiles().filter { $0.pathExtension == "rollback" }
        #expect(!rollbackFiles.isEmpty)
        for rollbackURL in rollbackFiles {
            #expect(fixture.canOpen(rollbackURL, password: fixture.newPassword))
            #expect(!fixture.canOpen(rollbackURL, password: fixture.oldPassword))
        }

        fixture.store.lock()
        try fixture.store.unlockWithQuickKey(reason: "rekey cleanup test")
        #expect(try fixture.store.listEntries().map(\.title) == ["Preserved Entry"])
        fixture.store.lock()
        try fixture.store.unlockForAutomation()
        #expect(try fixture.store.listEntries().map(\.title) == ["Preserved Entry"])
    }

    @Test(
        "post-commit sanitize faults keep the new key active and report pending cleanup",
        arguments: RekeyPostCommitWriteRestriction.allCases
    )
    func committedRekeyDoesNotRollBackAfterSanitizeFault(
        restriction: RekeyPostCommitWriteRestriction
    ) throws {
        let fileManager = RekeyPostCommitWriteFailingFileManager(restriction: restriction)
        let fixture = try RekeyFixture(transaction: VaultArtifactRekeyTransaction(fileManager: fileManager))
        defer {
            fileManager.restoreWriteAccess()
            fixture.remove()
        }
        try fixture.addLocalEntry(title: "Preserved Entry")
        try FileManager.default.removeItem(at: fixture.localStorage.paths.backupURL)
        try fixture.store.enableQuickUnlock()
        try fixture.store.enableAutomationUnlock()

        let outcome = Result {
            try fixture.store.resetMasterPassword(
                newPassword: fixture.newPassword,
                keepSystemUnlockEnabled: true,
                authorization: .testing
            )
        }
        fileManager.restoreWriteAccess()

        let result = try outcome.get()
        #expect(result.warnings.map(\.rawValue) == ["rekeyArtifactCleanupPending"])
        #expect(fixture.canOpen(fixture.vaultURL, password: fixture.newPassword))
        #expect(!fixture.canOpen(fixture.vaultURL, password: fixture.oldPassword))
        #expect(fixture.store.state == .unlocked)
        #expect(try fixture.store.listEntries().map(\.title) == ["Preserved Entry"])
        let rollbackURL = try #require(
            fixture.rekeyTemporaryFiles().first { $0.pathExtension == "rollback" }
        )
        #expect(FileManager.default.fileExists(atPath: rollbackURL.path))
        #expect(fixture.canOpen(rollbackURL, password: fixture.oldPassword) == restriction.preservesOldRollback)

        fixture.store.lock()
        try fixture.store.unlockWithQuickKey(reason: "rekey sanitize fault test")
        #expect(try fixture.store.listEntries().map(\.title) == ["Preserved Entry"])
        fixture.store.lock()
        try fixture.store.unlockForAutomation()
        #expect(try fixture.store.listEntries().map(\.title) == ["Preserved Entry"])
    }

    @Test("a locked store stays locked after a successful password reset")
    func lockedStoreRemainsLocked() throws {
        let fixture = try RekeyFixture()
        defer { fixture.remove() }
        try fixture.addLocalEntry(title: "Preserved Entry")
        try fixture.store.enableQuickUnlock()
        fixture.store.lock()

        _ = try fixture.store.resetMasterPassword(
            newPassword: fixture.newPassword,
            keepSystemUnlockEnabled: false,
            authorization: .testing
        )

        #expect(fixture.store.state == .locked)
        #expect(throws: PasswordVaultError.vaultLocked) { try fixture.store.listEntries() }
        try fixture.store.unlock(masterPassword: fixture.newPassword, rememberQuickUnlock: false)
        #expect(try fixture.store.listEntries().map(\.title) == ["Preserved Entry"])
    }

    @Test("password change never enumerates a KDBX outside local storage")
    func passwordChangeIgnoresExternalCloudCopy() throws {
        let fixture = try RekeyFixture()
        defer { fixture.remove() }
        let cloudRoot = fixture.root.appendingPathComponent("OneDrive", isDirectory: true)
        let cloudStorage = makeRekeyLocalStorage(at: cloudRoot)
        let cloudStore = KDBXPasswordVaultStore(localStorage: cloudStorage)
        try cloudStore.createDatabase(masterPassword: fixture.oldPassword, rememberQuickUnlock: false)
        let cloudBefore = try Data(contentsOf: cloudStorage.paths.vaultURL)

        _ = try fixture.store.resetMasterPassword(
            newPassword: fixture.newPassword,
            keepSystemUnlockEnabled: false,
            authorization: .testing
        )

        #expect(try Data(contentsOf: cloudStorage.paths.vaultURL) == cloudBefore)
        #expect(fixture.canOpen(cloudStorage.paths.vaultURL, password: fixture.oldPassword))
        #expect(!fixture.canOpen(cloudStorage.paths.vaultURL, password: fixture.newPassword))
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
    let localStorage: FilePasswordVaultLocalStorage
    let vaultURL: URL
    let transaction: VaultArtifactRekeyTransaction
    let quickKey: RekeyUnlockKeyStore
    let automationKey: RekeyAutomationKeyStore
    let store: KDBXPasswordVaultStore

    init(transaction: VaultArtifactRekeyTransaction = VaultArtifactRekeyTransaction()) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        localStorage = makeRekeyLocalStorage(at: root)
        vaultURL = localStorage.paths.vaultURL
        self.transaction = transaction
        quickKey = RekeyUnlockKeyStore()
        automationKey = RekeyAutomationKeyStore()
        store = KDBXPasswordVaultStore(
            localStorage: localStorage,
            unlockKeyStore: quickKey,
            automationUnlockKeyStore: automationKey,
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
        let external = KDBXPasswordVaultStore(localStorage: localStorage)
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
        let conflictStorage = makeRekeyLocalStorage(at: conflictRoot)
        let conflictStore = KDBXPasswordVaultStore(localStorage: conflictStorage)
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
        try Data(contentsOf: conflictStorage.paths.vaultURL).write(to: conflictURL, options: .atomic)
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
        try Data(contentsOf: vaultURL).write(to: localStorage.paths.backupURL, options: .atomic)
        try Data(contentsOf: vaultURL).write(
            to: vaultURL.deletingLastPathComponent().appendingPathComponent("PasteraVault-conflict.kdbx"),
            options: .atomic
        )
        try addResolvedArchive()
    }

    func artifactBytes() throws -> [URL: Data] {
        try Dictionary(uniqueKeysWithValues: transaction.managedArtifactURLs(in: localStorage.paths).map {
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

private func makeRekeyLocalStorage(at root: URL) -> FilePasswordVaultLocalStorage {
    let directory = root.appendingPathComponent("PasswordVault", isDirectory: true)
    return FilePasswordVaultLocalStorage(paths: PasswordVaultLocalPaths(
        directoryURL: directory,
        vaultURL: directory.appendingPathComponent("PasteraVault.kdbx"),
        backupURL: directory.appendingPathComponent("PasteraVault.kdbx.bak"),
        metadataURL: directory.appendingPathComponent("PasswordVaultSyncMetadata.json")
    ))
}

private final class RekeyUnlockKeyStore: VaultUnlockKeyStoring {
    var data: Data?
    var nextAuthorizationContextLoadError: PasswordVaultError?
    private(set) var authorizationContextLoadCount = 0
    private(set) var receivedAuthenticationContext: LAContext?
    var containsKey: Bool { data != nil }
    func save(_ data: Data) throws { self.data = data }
    func load(reason: String) throws -> Data { try #require(data) }
    func load(reason: String, authenticationContext: LAContext?) throws -> Data {
        authorizationContextLoadCount += 1
        receivedAuthenticationContext = authenticationContext
        if let error = nextAuthorizationContextLoadError {
            nextAuthorizationContextLoadError = nil
            throw error
        }
        return try #require(data)
    }
    func delete() throws { data = nil }
}

private final class RekeyAutomationKeyStore: VaultAutomationUnlockKeyStoring {
    var data: Data?
    private(set) var loadCallCount = 0
    var containsKey: Bool { data != nil }
    func save(_ data: Data) throws { self.data = data }
    func load() throws -> Data {
        loadCallCount += 1
        return try #require(data)
    }
    func delete() throws { data = nil }
}

private final class RekeyRollbackCleanupFailingFileManager: FileManager {
    override func removeItem(at URL: URL) throws {
        if URL.pathExtension == "rollback" {
            throw CocoaError(.fileWriteUnknown)
        }
        try super.removeItem(at: URL)
    }
}

enum RekeyPostCommitWriteRestriction: CaseIterable {
    case atomicWriteFailsAfterTruncate
    case rollbackCannotBeInvalidated

    var preservesOldRollback: Bool {
        self == .rollbackCannotBeInvalidated
    }
}

private final class RekeyPostCommitWriteFailingFileManager: FileManager {
    private let restriction: RekeyPostCommitWriteRestriction
    private var restrictedDirectory: URL?

    init(restriction: RekeyPostCommitWriteRestriction) {
        self.restriction = restriction
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try super.moveItem(at: sourceURL, to: destinationURL)
        guard restrictedDirectory == nil,
              sourceURL.pathExtension == "staged",
              destinationURL.pathExtension == "kdbx" else { return }
        let directory = destinationURL.deletingLastPathComponent()
        if restriction == .rollbackCannotBeInvalidated,
           let rollbackURL = try contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "rollback" }) {
            try setAttributes([.posixPermissions: 0o400], ofItemAtPath: rollbackURL.path)
        }
        try setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        restrictedDirectory = directory
    }

    func restoreWriteAccess() {
        guard let restrictedDirectory else { return }
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: restrictedDirectory.path
        )
        self.restrictedDirectory = nil
    }
}
