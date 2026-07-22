import Darwin
import Foundation

struct PasswordVaultLocalPaths: Equatable {
    let directoryURL: URL
    let vaultURL: URL
    let backupURL: URL
    let metadataURL: URL

    static func live(
        fileManager: FileManager = .default,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.pastera-app.Pastera"
    ) -> PasswordVaultLocalPaths {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        let directory = applicationSupport
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("PasswordVault", isDirectory: true)
        return PasswordVaultLocalPaths(
            directoryURL: directory,
            vaultURL: directory.appendingPathComponent("PasteraVault.kdbx"),
            backupURL: directory.appendingPathComponent("PasteraVault.kdbx.bak"),
            metadataURL: directory.appendingPathComponent("PasswordVaultSyncMetadata.json")
        )
    }
}

protocol PasswordVaultLocalStoring {
    var paths: PasswordVaultLocalPaths { get }

    func containsVault() -> Bool
    func read() throws -> Data
    func writeAtomically(_ data: Data) throws
    func removeVaultCreatedByFailedMigration() throws
    func readBackup() throws -> Data
}

final class FilePasswordVaultLocalStorage: PasswordVaultLocalStoring {
    let paths: PasswordVaultLocalPaths
    private let fileManager: FileManager

    init(paths: PasswordVaultLocalPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    static func live(fileManager: FileManager = .default) -> FilePasswordVaultLocalStorage {
        FilePasswordVaultLocalStorage(
            paths: .live(fileManager: fileManager),
            fileManager: fileManager
        )
    }

    func containsVault() -> Bool {
        fileManager.fileExists(atPath: paths.vaultURL.path)
    }

    func read() throws -> Data {
        let data = try Data(contentsOf: paths.vaultURL)
        try validate(data)
        return data
    }

    func readBackup() throws -> Data {
        let data = try Data(contentsOf: paths.backupURL)
        try validate(data)
        return data
    }

    func writeAtomically(_ data: Data) throws {
        try validate(data)
        try fileManager.createDirectory(
            at: paths.directoryURL,
            withIntermediateDirectories: true
        )
        let temporaryURL = paths.directoryURL
            .appendingPathComponent("PasteraVault-\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporaryURL) }

        try data.write(to: temporaryURL, options: .withoutOverwriting)
        try validate(Data(contentsOf: temporaryURL))

        guard containsVault() else {
            try fileManager.moveItem(at: temporaryURL, to: paths.vaultURL)
            return
        }

        let current = try Data(contentsOf: paths.vaultURL)
        try validate(current)
        try current.write(to: paths.backupURL, options: .atomic)
        try replaceVault(with: temporaryURL)
    }

    func removeVaultCreatedByFailedMigration() throws {
        // Migration calls this only after its entry guard established that no local vault existed.
        guard containsVault() else { return }
        try fileManager.removeItem(at: paths.vaultURL)
    }

    private func replaceVault(with temporaryURL: URL) throws {
        let errorCode: Int32 = temporaryURL.withUnsafeFileSystemRepresentation { temporaryPath in
            paths.vaultURL.withUnsafeFileSystemRepresentation { vaultPath in
                guard let temporaryPath, let vaultPath else { return EINVAL }
                guard Darwin.rename(temporaryPath, vaultPath) != 0 else { return 0 }
                return errno
            }
        }
        guard errorCode == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errorCode) ?? .EIO)
        }
    }

    private func validate(_ data: Data) throws {
        let signature = Data([0x03, 0xD9, 0xA2, 0x9A, 0x67, 0xFB, 0x4B, 0xB5])
        guard data.count >= signature.count, data.prefix(signature.count) == signature else {
            throw PasswordVaultError.corruptedData
        }
    }
}
