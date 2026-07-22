import Foundation

struct PasswordVaultCloudSnapshot: Equatable {
    let data: Data
    let digest: String
}

protocol PasswordVaultCloudReplica {
    func read(rootURL: URL) throws -> PasswordVaultCloudSnapshot?
    func writeAtomically(_ data: Data, rootURL: URL) throws -> String
    func delete(rootURL: URL) throws
}

struct PasswordVaultCloudFileOperations {
    var fileExists: (URL) -> Bool
    var isDirectory: (URL) throws -> Bool
    var isWritable: (URL) -> Bool
    var fileSize: (URL) throws -> Int
    var readData: (URL) throws -> Data
    var writeData: (Data, URL) throws -> Void
    var createDirectory: (URL) throws -> Void
    var moveItem: (URL, URL) throws -> Void
    var replaceItem: (URL, URL) throws -> Void
    var removeItem: (URL) throws -> Void

    static let live = PasswordVaultCloudFileOperations(
        fileExists: { FileManager.default.fileExists(atPath: $0.path) },
        isDirectory: { url in
            try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        },
        isWritable: { FileManager.default.isWritableFile(atPath: $0.path) },
        fileSize: { url in
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let size = values.fileSize else {
                throw CocoaError(.fileReadUnknown)
            }
            return size
        },
        readData: { try Data(contentsOf: $0, options: .mappedIfSafe) },
        writeData: { data, url in try data.write(to: url) },
        createDirectory: {
            try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
        },
        moveItem: { try FileManager.default.moveItem(at: $0, to: $1) },
        replaceItem: { destination, replacement in
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: replacement)
        },
        removeItem: { try FileManager.default.removeItem(at: $0) }
    )
}

final class OneDrivePasswordVaultCloudReplica: PasswordVaultCloudReplica {
    private static let kdbxSignature = Data([0x03, 0xD9, 0xA2, 0x9A, 0x67, 0xFB, 0x4B, 0xB5])

    private let fileCoordinator: NSFileCoordinator
    private let operations: PasswordVaultCloudFileOperations

    init(
        fileCoordinator: NSFileCoordinator = NSFileCoordinator(),
        operations: PasswordVaultCloudFileOperations = .live
    ) {
        self.fileCoordinator = fileCoordinator
        self.operations = operations
    }

    func read(rootURL: URL) throws -> PasswordVaultCloudSnapshot? {
        try validateRoot(rootURL, requiresWriteAccess: false)
        let targetURL = VaultFileCoordinator.vaultURL(for: rootURL)
        guard operations.fileExists(targetURL) else { return nil }

        do {
            return try coordinateRead(at: targetURL) { coordinatedURL in
                let expectedSize = try operations.fileSize(coordinatedURL)
                let data = try operations.readData(coordinatedURL)
                guard data.count == expectedSize else {
                    throw PasswordVaultSyncFailure.remoteUnavailable
                }
                guard Self.hasKDBXSignature(data) else {
                    throw PasswordVaultSyncFailure.remoteCorrupted
                }
                return PasswordVaultCloudSnapshot(
                    data: data,
                    digest: PasswordVaultDigest.hex(data)
                )
            }
        } catch let failure as PasswordVaultSyncFailure {
            throw failure
        } catch {
            throw PasswordVaultSyncFailure.remoteUnavailable
        }
    }

    func writeAtomically(_ data: Data, rootURL: URL) throws -> String {
        guard Self.hasKDBXSignature(data) else {
            throw PasswordVaultSyncFailure.remoteCorrupted
        }
        try validateRoot(rootURL, requiresWriteAccess: true)

        let targetURL = VaultFileCoordinator.vaultURL(for: rootURL)
        let directoryURL = targetURL.deletingLastPathComponent()
        let temporaryURL = directoryURL.appendingPathComponent(
            ".PasteraVault-\(UUID().uuidString).tmp",
            isDirectory: false
        )
        let expectedDigest = PasswordVaultDigest.hex(data)

        defer {
            if operations.fileExists(temporaryURL) {
                try? operations.removeItem(temporaryURL)
            }
        }

        do {
            try operations.createDirectory(directoryURL)
            try operations.writeData(data, temporaryURL)
            try validateTemporaryFile(
                at: temporaryURL,
                expectedSize: data.count,
                expectedDigest: expectedDigest
            )
            try coordinateWrite(at: targetURL, options: .forReplacing) { coordinatedURL in
                if operations.fileExists(coordinatedURL) {
                    try operations.replaceItem(coordinatedURL, temporaryURL)
                } else {
                    try operations.moveItem(temporaryURL, coordinatedURL)
                }
            }
        } catch let failure as PasswordVaultSyncFailure {
            throw failure
        } catch {
            throw PasswordVaultSyncFailure.remoteWriteFailed
        }

        do {
            guard let snapshot = try read(rootURL: rootURL), snapshot.digest == expectedDigest else {
                throw PasswordVaultSyncFailure.remoteVerificationFailed
            }
        } catch {
            throw PasswordVaultSyncFailure.remoteVerificationFailed
        }
        return expectedDigest
    }

    func delete(rootURL: URL) throws {
        try validateRoot(rootURL, requiresWriteAccess: true)
        let targetURL = VaultFileCoordinator.vaultURL(for: rootURL)
        guard operations.fileExists(targetURL) else { return }

        do {
            try coordinateWrite(at: targetURL, options: .forDeleting) { coordinatedURL in
                try operations.removeItem(coordinatedURL)
            }
        } catch {
            throw PasswordVaultSyncFailure.remoteWriteFailed
        }
    }

    private func validateRoot(_ rootURL: URL, requiresWriteAccess: Bool) throws {
        guard operations.fileExists(rootURL) else {
            throw PasswordVaultSyncFailure.folderUnavailable
        }
        do {
            guard try operations.isDirectory(rootURL) else {
                throw PasswordVaultSyncFailure.folderUnavailable
            }
        } catch let failure as PasswordVaultSyncFailure {
            throw failure
        } catch {
            throw PasswordVaultSyncFailure.folderUnavailable
        }
        if requiresWriteAccess, !operations.isWritable(rootURL) {
            throw PasswordVaultSyncFailure.folderNotWritable
        }
    }

    private func validateTemporaryFile(
        at url: URL,
        expectedSize: Int,
        expectedDigest: String
    ) throws {
        let storedSize = try operations.fileSize(url)
        let storedData = try operations.readData(url)
        guard storedSize == expectedSize,
              storedData.count == storedSize,
              Self.hasKDBXSignature(storedData),
              PasswordVaultDigest.hex(storedData) == expectedDigest else {
            throw PasswordVaultSyncFailure.remoteWriteFailed
        }
    }

    private func coordinateRead<Result>(
        at url: URL,
        operation: (URL) throws -> Result
    ) throws -> Result {
        var coordinationError: NSError?
        var result: Swift.Result<Result, Error>?
        fileCoordinator.coordinate(
            readingItemAt: url,
            options: .withoutChanges,
            error: &coordinationError
        ) { coordinatedURL in
            result = Swift.Result { try operation(coordinatedURL) }
        }
        if let coordinationError {
            throw coordinationError
        }
        guard let result else {
            throw PasswordVaultSyncFailure.remoteUnavailable
        }
        return try result.get()
    }

    private func coordinateWrite(
        at url: URL,
        options: NSFileCoordinator.WritingOptions,
        operation: (URL) throws -> Void
    ) throws {
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        fileCoordinator.coordinate(
            writingItemAt: url,
            options: options,
            error: &coordinationError
        ) { coordinatedURL in
            result = Result { try operation(coordinatedURL) }
        }
        if let coordinationError {
            throw coordinationError
        }
        guard let result else {
            throw PasswordVaultSyncFailure.remoteWriteFailed
        }
        try result.get()
    }

    private static func hasKDBXSignature(_ data: Data) -> Bool {
        data.starts(with: kdbxSignature)
    }
}
