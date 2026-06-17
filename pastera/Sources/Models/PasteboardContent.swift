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
        var hasher = SHA256()
        assets.forEach { asset in
            hasher.update(lengthPrefixed: Data(asset.type.rawValue.utf8))
            hasher.update(lengthPrefixed: asset.data)
        }
        self.hash = hasher.finalize()
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

    init?(imageFileURL url: URL) {
        guard let sourceData = try? Data(contentsOf: url),
              let image = NSImage(data: sourceData)
        else { return nil }

        if url.pathExtension.lowercased() == "png" {
            self.init(assets: [Asset(type: .png, data: sourceData)])
        } else if let pngData = PasteraImageEncoding.pngData(from: image) {
            self.init(assets: [Asset(type: .png, data: pngData)])
        } else if let tiffData = image.tiffRepresentation {
            self.init(assets: [Asset(type: .tiff, data: tiffData)])
        } else {
            return nil
        }
    }
}

private extension PasteboardContent {
    func data(for type: NSPasteboard.PasteboardType) -> Data? {
        assets.first(where: { $0.type == type })?.data
    }
}

private extension SHA256 {
    mutating func update(lengthPrefixed data: Data) {
        var length = UInt64(data.count).bigEndian
        let lengthData = Swift.withUnsafeBytes(of: &length) { Data($0) }
        update(data: lengthData)
        update(data: data)
    }
}

enum PasteraImageEncoding {
    static func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

enum SyncJSONValue: Codable, Equatable {
    case object([String: SyncJSONValue])
    case array([SyncJSONValue])
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    init<T: Encodable>(_ value: T) throws {
        let data = try JSONEncoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        self = try SyncJSONValue(jsonObject: object)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: SyncJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([SyncJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: jsonObject, options: [.fragmentsAllowed])
        return try JSONDecoder().decode(type, from: data)
    }

    private init(jsonObject: Any) throws {
        switch jsonObject {
        case let value as [String: Any]:
            self = .object(try value.mapValues { try SyncJSONValue(jsonObject: $0) })
        case let value as [Any]:
            self = .array(try value.map { try SyncJSONValue(jsonObject: $0) })
        case let value as String:
            self = .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else if value.doubleValue.rounded() == value.doubleValue {
                self = .int(value.intValue)
            } else {
                self = .double(value.doubleValue)
            }
        case _ as NSNull:
            self = .null
        default:
            throw EncodingError.invalidValue(jsonObject, EncodingError.Context(
                codingPath: [],
                debugDescription: "Unsupported JSON value"
            ))
        }
    }

    private var jsonObject: Any {
        switch self {
        case .object(let value):
            return value.mapValues(\.jsonObject)
        case .array(let value):
            return value.map(\.jsonObject)
        case .string(let value):
            return value
        case .int(let value):
            return value
        case .double(let value):
            return value
        case .bool(let value):
            return value
        case .null:
            return NSNull()
        }
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
    let payload: SyncJSONValue
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

    init(
        schemaVersion: Int,
        deviceID: String,
        updatedAt: Int,
        records: [SyncManifestRecord]
    ) {
        self.schemaVersion = schemaVersion
        self.deviceID = deviceID
        self.updatedAt = updatedAt
        self.records = records
    }
}

enum SyncConflictPolicy {
    case lastWriteWins

    func resolve(local: SyncRecord, remote: SyncRecord) -> SyncRecord {
        switch self {
        case .lastWriteWins:
            if remote.deletedAt != nil {
                return local
            }
            if local.deletedAt != nil {
                return remote
            }
            if remote.updatedAt > local.updatedAt {
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

    func loadOrCreateManifest(deviceID: String) throws -> SyncManifest {
        let manifestURL = manifestURL
        if fileManager.fileExists(atPath: manifestURL.path) {
            return try JSONDecoder().decode(SyncManifest.self, from: Data(contentsOf: manifestURL))
        }

        let manifest = SyncManifest(
            schemaVersion: 1,
            deviceID: deviceID,
            updatedAt: Int(Date().timeIntervalSince1970),
            records: []
        )
        try saveManifest(manifest)
        return manifest
    }

    func saveManifest(_ manifest: SyncManifest) throws {
        let directoryURL = syncRootURL
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try writeAtomically(JSONEncoder().encode(manifest), to: manifestURL)
    }

    func save(_ record: SyncRecord) throws {
        let directoryURL = directory(for: record.kind)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let destinationURL = directoryURL.appendingPathComponent(fileName(for: record.id))

        try writeAtomically(JSONEncoder().encode(record), to: destinationURL)
    }

    func loadRecords(kind: SyncRecord.Kind) throws -> [SyncRecord] {
        let directoryURL = directory(for: kind)
        guard fileManager.fileExists(atPath: directoryURL.path) else { return [] }

        return try fileManager
            .contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                try? JSONDecoder().decode(SyncRecord.self, from: Data(contentsOf: url))
            }
    }

    private func directory(for kind: SyncRecord.Kind) -> URL {
        switch kind {
        case .history:
            return syncRootURL.appendingPathComponent("histories", isDirectory: true)
        case .snippet:
            return syncRootURL.appendingPathComponent("snippets/items", isDirectory: true)
        case .snippetFolder:
            return syncRootURL.appendingPathComponent("snippets/folders", isDirectory: true)
        }
    }

    private var syncRootURL: URL {
        rootURL
    }

    private var manifestURL: URL {
        syncRootURL.appendingPathComponent("manifest.json")
    }

    private func fileName(for id: String) -> String {
        var allowedCharacters = CharacterSet.alphanumerics
        allowedCharacters.insert(charactersIn: "-_.")
        let encodedID = id.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? UUID().uuidString
        return "\(encodedID).json"
    }

    private func writeAtomically(_ data: Data, to destinationURL: URL) throws {
        let temporaryURL = destinationURL.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        try data.write(to: temporaryURL, options: .atomic)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
    }
}

private extension SyncRecord {
    var syncIdentity: String {
        "\(kind.rawValue):\(id)"
    }
}
