import CryptoKit
import Foundation

enum PasswordVaultCommitOrigin: Equatable {
    case userMutation
    case syncMerge
    case migration
}

struct PasswordVaultCommit: Equatable {
    let origin: PasswordVaultCommitOrigin
    let encryptedDigest: String
}

struct PasswordVaultEncryptedSnapshot: Equatable {
    let data: Data
    let digest: String
}

protocol PasswordVaultSyncAccess: AnyObject {
    var state: PasswordVaultState { get }

    func encryptedSnapshot() throws -> PasswordVaultEncryptedSnapshot
    // swiftlint:disable inclusive_language
    func mergeRemoteSnapshot(
        _ remoteData: Data,
        remoteMasterPassword: String?
    ) throws -> PasswordVaultMergeApplication
    // swiftlint:enable inclusive_language
    func setCommitObserver(_ observer: @escaping (PasswordVaultCommit) -> Void)
}

struct PasswordVaultMergeApplication: Equatable {
    let encryptedSnapshot: PasswordVaultEncryptedSnapshot
    let conflictCopyCount: Int
}

enum PasswordVaultSyncMode: String, Codable, Equatable {
    case localOnly
    case oneDrive
}

enum PasswordVaultSyncFailure: String, Codable, Equatable, Error {
    case oneDriveNotInstalled
    case oneDriveNotRunning
    case folderUnavailable
    case folderNotWritable
    case remoteUnavailable
    case remoteCorrupted
    case remoteCredentialsRequired
    case remoteWriteFailed
    case remoteVerificationFailed
}

enum PasswordVaultSyncPhase: Equatable {
    case disabled
    case synced
    case syncing(PasswordVaultSyncStep)
    case disconnected(PasswordVaultSyncFailure)
    case waitingForUnlock
    case conflicts(Int)
    case failed(PasswordVaultSyncFailure)
}

enum PasswordVaultSyncStep: String, Codable, Equatable {
    case checking
    case downloading
    case merging
    case savingLocal
    case uploading
    case verifying
}

enum PasswordVaultSyncDecision: Equatable {
    case noChange
    case uploadLocal
    case applyRemote
    case mergeBoth
}

func passwordVaultSyncDecision(
    localChanged: Bool,
    remoteChanged: Bool
) -> PasswordVaultSyncDecision {
    switch (localChanged, remoteChanged) {
    case (false, false): .noChange
    case (true, false): .uploadLocal
    case (false, true): .applyRemote
    case (true, true): .mergeBoth
    }
}

struct PasswordVaultSyncSnapshot: Equatable {
    let mode: PasswordVaultSyncMode
    let phase: PasswordVaultSyncPhase
    let localVaultAvailable: Bool
    let remoteVaultAvailable: Bool?
    let pendingChangeCount: Int
    let conflictCopyCount: Int
    let lastSyncAt: Date?
}

struct PasswordVaultSyncMetadata: Codable, Equatable {
    static let currentSchemaVersion = 1
    static let defaultLocalOnly = PasswordVaultSyncMetadata(
        schemaVersion: currentSchemaVersion,
        mode: .localOnly,
        localRevision: 0,
        lastSyncedLocalRevision: 0,
        lastSyncedLocalDigest: nil,
        lastObservedRemoteDigest: nil,
        lastSyncAt: nil,
        pendingChangeCount: 0,
        conflictCopyCount: 0,
        lastFailure: nil,
        migrationVersion: 0
    )

    var schemaVersion: Int
    var mode: PasswordVaultSyncMode
    var localRevision: UInt64
    var lastSyncedLocalRevision: UInt64
    var lastSyncedLocalDigest: String?
    var lastObservedRemoteDigest: String?
    var lastSyncAt: Date?
    var pendingChangeCount: Int
    var conflictCopyCount: Int
    var lastFailure: PasswordVaultSyncFailure?
    var migrationVersion: Int
}

protocol PasswordVaultSyncMetadataStoring {
    func load() throws -> PasswordVaultSyncMetadata
    func save(_ metadata: PasswordVaultSyncMetadata) throws
}

enum PasswordVaultDigest {
    static func hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
