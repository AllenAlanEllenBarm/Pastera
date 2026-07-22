import Darwin
import Foundation

@_silgen_name("flock")
private func passwordVaultFlock(_ descriptor: Int32, _ operation: Int32) -> Int32

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

    func withExclusiveTransaction<Value>(_ operation: () throws -> Value) throws -> Value
    func containsVault() -> Bool
    func read() throws -> Data
    func writeAtomically(_ data: Data) throws
    @discardableResult
    func removeVaultCreatedByFailedMigration(expectedDigest: String) throws -> Bool
    func readBackup() throws -> Data
}

extension PasswordVaultLocalStoring {
    func withExclusiveTransaction<Value>(_ operation: () throws -> Value) throws -> Value {
        try operation()
    }
}

private final class PasswordVaultLocalFileLockRegistry: @unchecked Sendable {
    static let shared = PasswordVaultLocalFileLockRegistry()

    private let registryLock = NSLock()
    private var locks = [String: PasswordVaultLocalFileLock]()

    func lock(for paths: PasswordVaultLocalPaths, fileManager: FileManager) -> PasswordVaultLocalFileLock {
        let path = paths.vaultURL.standardizedFileURL.path
        return registryLock.withLock {
            if let existing = locks[path] { return existing }
            let lock = PasswordVaultLocalFileLock(paths: paths, fileManager: fileManager)
            locks[path] = lock
            return lock
        }
    }
}

private final class PasswordVaultLocalFileLock: @unchecked Sendable {
    private let paths: PasswordVaultLocalPaths
    private let fileManager: FileManager
    private let recursiveLock = NSRecursiveLock()
    private var descriptor: Int32 = -1
    private var depth = 0

    init(paths: PasswordVaultLocalPaths, fileManager: FileManager) {
        self.paths = paths
        self.fileManager = fileManager
    }

    deinit {
        if descriptor >= 0 { Darwin.close(descriptor) }
    }

    func withExclusiveLock<Value>(_ operation: () throws -> Value) throws -> Value {
        recursiveLock.lock()
        defer { recursiveLock.unlock() }

        let isOutermost = depth == 0
        if isOutermost { try acquireFileLock() }
        depth += 1
        let value: Value
        do {
            value = try operation()
        } catch {
            depth -= 1
            if isOutermost { try? releaseFileLock() }
            throw error
        }
        depth -= 1
        if isOutermost { try releaseFileLock() }
        return value
    }

    private func acquireFileLock() throws {
        try fileManager.createDirectory(at: paths.directoryURL, withIntermediateDirectories: true)
        if descriptor < 0 {
            let lockURL = paths.directoryURL.appendingPathComponent(".PasteraVault.lock")
            descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
            guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        }
        while passwordVaultFlock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        }
    }

    private func releaseFileLock() throws {
        while passwordVaultFlock(descriptor, LOCK_UN) != 0 {
            guard errno == EINTR else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        }
    }
}

final class FilePasswordVaultLocalStorage: PasswordVaultLocalStoring {
    let paths: PasswordVaultLocalPaths
    private let fileManager: FileManager
    private let transactionLock: PasswordVaultLocalFileLock

    init(paths: PasswordVaultLocalPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
        transactionLock = PasswordVaultLocalFileLockRegistry.shared.lock(for: paths, fileManager: fileManager)
    }

    static func live(fileManager: FileManager = .default) -> FilePasswordVaultLocalStorage {
        FilePasswordVaultLocalStorage(
            paths: .live(fileManager: fileManager),
            fileManager: fileManager
        )
    }

    func containsVault() -> Bool {
        (try? withExclusiveTransaction {
            fileManager.fileExists(atPath: paths.vaultURL.path)
        }) ?? false
    }

    func withExclusiveTransaction<Value>(_ operation: () throws -> Value) throws -> Value {
        try transactionLock.withExclusiveLock(operation)
    }

    func read() throws -> Data {
        try withExclusiveTransaction {
            let data = try Data(contentsOf: paths.vaultURL)
            try validate(data)
            return data
        }
    }

    func readBackup() throws -> Data {
        try withExclusiveTransaction {
            let data = try Data(contentsOf: paths.backupURL)
            try validate(data)
            return data
        }
    }

    func writeAtomically(_ data: Data) throws {
        try withExclusiveTransaction {
            try validate(data)
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
    }

    @discardableResult
    func removeVaultCreatedByFailedMigration(expectedDigest: String) throws -> Bool {
        try withExclusiveTransaction {
            guard containsVault() else { return true }
            let current = try Data(contentsOf: paths.vaultURL)
            guard PasswordVaultDigest.hex(current) == expectedDigest else { return false }
            try fileManager.removeItem(at: paths.vaultURL)
            return true
        }
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
