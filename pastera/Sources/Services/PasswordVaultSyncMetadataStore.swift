import Foundation

enum PasswordVaultSyncMetadataStoreError: Error, Equatable {
    case corrupted
    case unsupportedSchemaVersion(Int)
}

final class JSONPasswordVaultSyncMetadataStore: PasswordVaultSyncMetadataStoring {
    typealias ReadData = (URL) throws -> Data
    typealias AtomicWrite = (Data, URL) throws -> Void

    private let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let readData: ReadData
    private let atomicWrite: AtomicWrite

    init(
        url: URL,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        readData: @escaping ReadData = { try Data(contentsOf: $0) },
        atomicWrite: @escaping AtomicWrite = { data, url in
            try data.write(to: url, options: .atomic)
        }
    ) {
        self.url = url
        self.encoder = encoder
        self.decoder = decoder
        self.readData = readData
        self.atomicWrite = atomicWrite
    }

    func load() throws -> PasswordVaultSyncMetadata {
        let data: Data
        do {
            data = try readData(url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return PasswordVaultSyncMetadata.defaultLocalOnly
        }
        let metadata: PasswordVaultSyncMetadata
        do {
            metadata = try decoder.decode(PasswordVaultSyncMetadata.self, from: data)
        } catch is DecodingError {
            throw PasswordVaultSyncMetadataStoreError.corrupted
        }
        guard metadata.schemaVersion == PasswordVaultSyncMetadata.currentSchemaVersion else {
            throw PasswordVaultSyncMetadataStoreError.unsupportedSchemaVersion(metadata.schemaVersion)
        }
        return metadata
    }

    func save(_ metadata: PasswordVaultSyncMetadata) throws {
        guard metadata.schemaVersion == PasswordVaultSyncMetadata.currentSchemaVersion else {
            throw PasswordVaultSyncMetadataStoreError.unsupportedSchemaVersion(metadata.schemaVersion)
        }
        let data = try encoder.encode(metadata)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try atomicWrite(data, url)
    }
}
