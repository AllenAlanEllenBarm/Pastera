import Darwin
import Foundation

struct PasswordVaultCloudSnapshot: Equatable {
    let data: Data
    let digest: String
}

enum PasswordVaultRemoteExpectation: Equatable {
    case absent
    case digest(String)
}

protocol PasswordVaultCloudReplica {
    func read(rootURL: URL) throws -> PasswordVaultCloudSnapshot?
    func writeAtomically(
        _ data: Data,
        rootURL: URL,
        expecting expectation: PasswordVaultRemoteExpectation
    ) throws -> String
}

enum PasswordVaultCloudItemStatus: Equatable {
    case missing
    case regular(size: Int)
    case other
}

struct PasswordVaultCloudFileOperations {
    var fileExists: (URL) -> Bool
    var isDirectory: (URL) throws -> Bool
    var isWritable: (URL) -> Bool
    var itemStatus: (URL) throws -> PasswordVaultCloudItemStatus
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
        itemStatus: { url in
            var fileInformation = stat()
            guard lstat(url.path, &fileInformation) == 0 else {
                let errorCode = errno
                if errorCode == ENOENT {
                    return .missing
                }
                throw POSIXError(POSIXErrorCode(rawValue: errorCode) ?? .EIO)
            }
            guard fileInformation.st_mode & S_IFMT == S_IFREG else { return .other }
            return .regular(size: Int(fileInformation.st_size))
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
    private static let cocoaNoSuchFileErrorCodes: Set<Int> = [
        NSFileReadNoSuchFileError,
        NSFileNoSuchFileError
    ]

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
        do {
            return try coordinateRead(at: targetURL) { coordinatedURL in
                switch try itemStatus(at: coordinatedURL) {
                case .missing:
                    return nil
                case let .regular(size):
                    return try readSnapshot(
                        at: coordinatedURL,
                        expectedSize: size,
                        shortReadFailure: .remoteUnavailable
                    )
                case .other:
                    throw PasswordVaultSyncFailure.remoteCorrupted
                }
            }
        } catch let error where Self.isNoSuchFile(error) {
            return nil
        } catch let failure as PasswordVaultSyncFailure {
            throw failure
        } catch {
            throw PasswordVaultSyncFailure.remoteUnavailable
        }
    }

    func writeAtomically(
        _ data: Data,
        rootURL: URL,
        expecting expectation: PasswordVaultRemoteExpectation
    ) throws -> String {
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

        defer { try? operations.removeItem(temporaryURL) }

        do {
            try operations.createDirectory(directoryURL)
            try operations.writeData(data, temporaryURL)
            try validateTemporaryFile(
                at: temporaryURL,
                expectedSize: data.count,
                expectedDigest: expectedDigest
            )
            try coordinateWrite(at: targetURL, options: .forReplacing) { coordinatedURL in
                try replaceTarget(
                    at: coordinatedURL,
                    with: temporaryURL,
                    expecting: expectation
                )
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
        guard case let .regular(storedSize) = try itemStatus(at: url),
              storedSize == expectedSize else {
            throw PasswordVaultSyncFailure.remoteWriteFailed
        }
        let snapshot = try readSnapshot(
            at: url,
            expectedSize: storedSize,
            shortReadFailure: .remoteWriteFailed
        )
        guard snapshot.digest == expectedDigest else {
            throw PasswordVaultSyncFailure.remoteWriteFailed
        }
    }

    private func replaceTarget(
        at targetURL: URL,
        with temporaryURL: URL,
        expecting expectation: PasswordVaultRemoteExpectation
    ) throws {
        let status = try itemStatus(at: targetURL)
        switch (expectation, status) {
        case (.absent, .missing):
            try moveWithoutOverwriting(temporaryURL, to: targetURL)
        case (.absent, .regular):
            throw PasswordVaultSyncFailure.remoteVerificationFailed
        case (.absent, .other), (.digest, .other):
            throw PasswordVaultSyncFailure.remoteCorrupted
        case (.digest, .missing):
            throw PasswordVaultSyncFailure.remoteVerificationFailed
        case let (.digest(expectedDigest), .regular(size)):
            let current = try readSnapshot(
                at: targetURL,
                expectedSize: size,
                shortReadFailure: .remoteWriteFailed
            )
            guard current.digest == expectedDigest else {
                throw PasswordVaultSyncFailure.remoteVerificationFailed
            }
            try operations.replaceItem(targetURL, temporaryURL)
        }
    }

    private func moveWithoutOverwriting(_ sourceURL: URL, to targetURL: URL) throws {
        do {
            try operations.moveItem(sourceURL, targetURL)
        } catch {
            switch try itemStatus(at: targetURL) {
            case .missing:
                throw error
            case .regular:
                throw PasswordVaultSyncFailure.remoteVerificationFailed
            case .other:
                throw PasswordVaultSyncFailure.remoteCorrupted
            }
        }
    }

    private func itemStatus(at url: URL) throws -> PasswordVaultCloudItemStatus {
        do {
            return try operations.itemStatus(url)
        } catch let error where Self.isNoSuchFile(error) {
            return .missing
        }
    }

    private static func isNoSuchFile(_ error: Error) -> Bool {
        var currentError: NSError? = error as NSError
        var inspectedErrors = Set<ObjectIdentifier>()
        while let error = currentError {
            guard inspectedErrors.insert(ObjectIdentifier(error)).inserted else { return false }
            if error.domain == NSCocoaErrorDomain,
               cocoaNoSuchFileErrorCodes.contains(error.code) {
                return true
            }
            if error.domain == NSPOSIXErrorDomain, error.code == Int(ENOENT) {
                return true
            }
            if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? Error {
                currentError = underlyingError as NSError
            } else {
                currentError = nil
            }
        }
        return false
    }

    private func readSnapshot(
        at url: URL,
        expectedSize: Int,
        shortReadFailure: PasswordVaultSyncFailure
    ) throws -> PasswordVaultCloudSnapshot {
        let data = try operations.readData(url)
        guard data.count == expectedSize else { throw shortReadFailure }
        guard Self.hasKDBXSignature(data) else {
            throw PasswordVaultSyncFailure.remoteCorrupted
        }
        return PasswordVaultCloudSnapshot(data: data, digest: PasswordVaultDigest.hex(data))
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
