//
//  PasteboardContent.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Shunsuke Furubayashi on 2026/05/28.
//
//  Copyright © 2015-2026 Clipy Project.
//

import Cocoa
import CryptoKit
import SwiftHEXColors

struct PasteboardContent: Equatable {
    struct Asset: Equatable {
        let type: NSPasteboard.PasteboardType
        let data: Data
    }

    // MARK: - Properties
    let types: [NSPasteboard.PasteboardType]
    let assets: [Asset]
    let hash: String

    var isOnlyStringType: Bool {
        types == [.string] || types == [.deprecatedString]
    }
    var stringValue: String {
        guard let data = data(for: .string) ?? data(for: .deprecatedString) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    var colorCodeImage: NSImage? {
        guard let color = NSColor(hexString: stringValue) else { return nil }
        return NSImage.create(with: color, size: NSSize(width: 20, height: 20))
    }
    var thumbnailImage: NSImage? {
        let defaults = UserDefaults.standard
        let width = defaults.integer(forKey: Constants.UserDefaults.thumbnailWidth)
        let height = defaults.integer(forKey: Constants.UserDefaults.thumbnailHeight)

        let imageURL = assets.filter { $0.type == .fileURL }
            .compactMap { URL(dataRepresentation: $0.data, relativeTo: nil) }
            .first(where: { ["jpg", "jpeg", "png", "bmp", "tiff", "tif", "heic", "webp"].contains($0.pathExtension.lowercased()) })
        if let imageURL {
            return NSImage(contentsOf: imageURL)?.resizeImage(CGFloat(width), CGFloat(height))
        } else if let data = assets.first(where: { $0.type.isClipyImageType })?.data {
            return NSImage(data: data)?.resizeImage(CGFloat(width), CGFloat(height))
        }
        return nil
    }

    // MARK: - Initialize
    init(assets: [Asset]) {
        self.types = assets.map(\.type)
        self.assets = assets
        var data = Data()
        assets.forEach { asset in
            data.append(value: Data(asset.type.rawValue.utf8))
            data.append(value: asset.data)
        }
        self.hash = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    init?(pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) {
        let assets = pasteboard.pasteboardItems?.compactMap { item -> [Asset]? in
            item.types.filter { types.contains($0) }
                .compactMap { type -> Asset? in
                    guard let data = item.data(forType: type) else { return nil }
                    return Asset(type: type, data: data)
                }
        }
        .flatMap { $0 }
        guard let assets, !assets.isEmpty else { return nil }
        self.init(assets: assets)
    }

    init?(image: NSImage) {
        guard let data = image.tiffRepresentation else { return nil }
        self.init(assets: [Asset(type: .tiff, data: data)])
    }
}

private extension PasteboardContent {
    func data(for type: NSPasteboard.PasteboardType) -> Data? {
        assets.first(where: { $0.type == type })?.data
    }
}

private extension Data {
    mutating func append(value: Data) {
        var length = UInt64(value.count).bigEndian
        Swift.withUnsafeBytes(of: &length) {
            append(contentsOf: $0)
        }
        append(value)
    }
}

struct EncryptedSyncPayload: Codable, Equatable {
    let nonce: Data
    let ciphertext: Data
    let tag: Data
}

enum SyncPayloadCipher {
    static func seal(_ payload: Data, passphrase: String, salt: Data) throws -> EncryptedSyncPayload {
        let sealedBox = try AES.GCM.seal(payload, using: key(passphrase: passphrase, salt: salt))
        return EncryptedSyncPayload(
            nonce: sealedBox.nonce.data,
            ciphertext: sealedBox.ciphertext,
            tag: sealedBox.tag
        )
    }

    static func open(_ payload: EncryptedSyncPayload, passphrase: String, salt: Data) throws -> Data {
        let nonce = try AES.GCM.Nonce(data: payload.nonce)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: payload.ciphertext, tag: payload.tag)
        return try AES.GCM.open(sealedBox, using: key(passphrase: passphrase, salt: salt))
    }

    private static func key(passphrase: String, salt: Data) -> SymmetricKey {
        var keyMaterial = Data()
        keyMaterial.append(salt)
        keyMaterial.append(Data(passphrase.utf8))
        let digest = SHA256.hash(data: keyMaterial)
        return SymmetricKey(data: digest)
    }
}

struct SyncRecord: Codable, Equatable {
    enum Kind: String, Codable {
        case history
        case snippet
        case snippetFolder
    }

    let id: String
    let kind: Kind
    let deviceID: String
    let updatedAt: Int
    let deletedAt: Int?
    let payload: EncryptedSyncPayload
    let schemaVersion: Int
}

struct SyncManifestRecord: Codable, Equatable {
    let id: String
    let kind: SyncRecord.Kind
    let updatedAt: Int
    let deletedAt: Int?
}

struct SyncManifest: Codable, Equatable {
    let schemaVersion: Int
    let deviceID: String
    let updatedAt: Int
    let records: [SyncManifestRecord]
}

enum SyncConflictPolicy {
    case lastWriteWins

    func resolve(local: SyncRecord, remote: SyncRecord) -> SyncRecord {
        switch self {
        case .lastWriteWins:
            if remote.updatedAt > local.updatedAt {
                return remote
            }
            if remote.updatedAt == local.updatedAt, remote.deletedAt != nil, local.deletedAt == nil {
                return remote
            }
            return local
        }
    }
}

protocol SyncProvider {
    func save(_ record: SyncRecord) throws
    func loadRecords(kind: SyncRecord.Kind) throws -> [SyncRecord]
}

final class SyncService {
    private let provider: SyncProvider
    private let conflictPolicy: SyncConflictPolicy

    init(provider: SyncProvider, conflictPolicy: SyncConflictPolicy = .lastWriteWins) {
        self.provider = provider
        self.conflictPolicy = conflictPolicy
    }

    func push(_ records: [SyncRecord]) throws {
        try records.forEach(provider.save)
    }

    func pull(kind: SyncRecord.Kind) throws -> [SyncRecord] {
        try provider.loadRecords(kind: kind)
    }

    func merge(local: [SyncRecord], remote: [SyncRecord]) -> [SyncRecord] {
        var merged = [String: SyncRecord]()
        local.forEach { record in
            merged[record.syncIdentity] = record
        }
        remote.forEach { record in
            if let existingRecord = merged[record.syncIdentity] {
                merged[record.syncIdentity] = conflictPolicy.resolve(local: existingRecord, remote: record)
            } else {
                merged[record.syncIdentity] = record
            }
        }
        return merged.values.sorted { lhs, rhs in
            if lhs.kind.rawValue == rhs.kind.rawValue {
                return lhs.id < rhs.id
            }
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
    }
}

final class OneDriveFolderSyncProvider: SyncProvider {
    private let rootURL: URL
    private let fileManager: FileManager

    init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    func save(_ record: SyncRecord) throws {
        let directoryURL = directory(for: record.kind)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let destinationURL = directoryURL.appendingPathComponent(fileName(for: record.id))
        let temporaryURL = directoryURL.appendingPathComponent(".\(UUID().uuidString).tmp")
        let data = try JSONEncoder().encode(record)

        try data.write(to: temporaryURL, options: .atomic)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
    }

    func loadRecords(kind: SyncRecord.Kind) throws -> [SyncRecord] {
        let directoryURL = directory(for: kind)
        guard fileManager.fileExists(atPath: directoryURL.path) else { return [] }

        return try fileManager
            .contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { try JSONDecoder().decode(SyncRecord.self, from: Data(contentsOf: $0)) }
    }

    private func directory(for kind: SyncRecord.Kind) -> URL {
        switch kind {
        case .history:
            return rootURL.appendingPathComponent("PasteraSync/histories", isDirectory: true)
        case .snippet:
            return rootURL.appendingPathComponent("PasteraSync/snippets/items", isDirectory: true)
        case .snippetFolder:
            return rootURL.appendingPathComponent("PasteraSync/snippets/folders", isDirectory: true)
        }
    }

    private func fileName(for id: String) -> String {
        var allowedCharacters = CharacterSet.alphanumerics
        allowedCharacters.insert(charactersIn: "-_.")
        let encodedID = id.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? UUID().uuidString
        return "\(encodedID).json"
    }
}

private extension SyncRecord {
    var syncIdentity: String {
        "\(kind.rawValue):\(id)"
    }
}

private extension AES.GCM.Nonce {
    var data: Data {
        Data(self)
    }
}
