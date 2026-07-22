import Foundation
import Testing
@testable import Pastera

extension PasswordVaultCloudReplicaTests {
    @Test("raw Foundation missing error after target status returns no cloud snapshot")
    func foundationMissingDuringReadReturnsNil() throws {
        try withFoundationMissingCloudRoot { rootURL in
            let data = foundationMissingKDBXData("disappeared-before-read")
            let targetURL = try writeFoundationMissingCloudVault(data, rootURL: rootURL)
            var operations = PasswordVaultCloudFileOperations.live
            let liveRead = operations.readData
            operations.readData = { url in
                if url.standardizedFileURL == targetURL.standardizedFileURL {
                    throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
                }
                return try liveRead(url)
            }

            let snapshot = try OneDrivePasswordVaultCloudReplica(operations: operations)
                .read(rootURL: rootURL)
            #expect(snapshot == nil)
            #expect(try Data(contentsOf: targetURL) == data)
        }
    }

    @Test("wrapped POSIX missing error after target status returns no cloud snapshot")
    func wrappedPOSIXMissingDuringReadReturnsNil() throws {
        try withFoundationMissingCloudRoot { rootURL in
            let data = foundationMissingKDBXData("wrapped-disappearance")
            let targetURL = try writeFoundationMissingCloudVault(data, rootURL: rootURL)
            var operations = PasswordVaultCloudFileOperations.live
            operations.readData = { _ in
                throw NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileReadUnknownError,
                    userInfo: [NSUnderlyingErrorKey: POSIXError(.ENOENT)]
                )
            }

            let snapshot = try OneDrivePasswordVaultCloudReplica(operations: operations)
                .read(rootURL: rootURL)
            #expect(snapshot == nil)
            #expect(try Data(contentsOf: targetURL) == data)
        }
    }

    @Test("raw Foundation missing error after removal keeps delete idempotent")
    func foundationMissingAfterRemovalSucceeds() throws {
        try withFoundationMissingCloudRoot { rootURL in
            let data = foundationMissingKDBXData("delete-before-error")
            let targetURL = try writeFoundationMissingCloudVault(data, rootURL: rootURL)
            var operations = PasswordVaultCloudFileOperations.live
            let liveRemove = operations.removeItem
            operations.removeItem = { url in
                try liveRemove(url)
                if url.standardizedFileURL == targetURL.standardizedFileURL {
                    throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
                }
            }

            try OneDrivePasswordVaultCloudReplica(operations: operations).delete(rootURL: rootURL)
            #expect(!FileManager.default.fileExists(atPath: targetURL.path))
            #expect(FileManager.default.fileExists(atPath: rootURL.path))
        }
    }
}

private let foundationMissingKDBXSignature = Data([
    0x03, 0xD9, 0xA2, 0x9A, 0x67, 0xFB, 0x4B, 0xB5
])

private func foundationMissingKDBXData(_ payload: String) -> Data {
    foundationMissingKDBXSignature + Data(payload.utf8)
}

private func writeFoundationMissingCloudVault(_ data: Data, rootURL: URL) throws -> URL {
    let targetURL = VaultFileCoordinator.vaultURL(for: rootURL)
    try FileManager.default.createDirectory(
        at: targetURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: targetURL)
    return targetURL
}

private func withFoundationMissingCloudRoot(_ operation: (URL) throws -> Void) throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }
    try operation(rootURL)
}
