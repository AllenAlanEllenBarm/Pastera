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
import SQLite3
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

enum SyncEntityKind: String, Codable {
    case history
    case snippet
    case snippetFolder
}

struct HistorySyncSnapshot: Equatable {
    let deviceID: String
    let payloads: [PasteboardHistorySyncPayload]
}

struct SnippetDeviceSyncSnapshot: Equatable {
    let deviceID: String
    let snapshot: SnippetSyncSnapshot
}

enum SyncSQLiteError: LocalizedError {
    case openFailed(String)
    case executeFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case missingMetadata(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            return "无法打开同步数据库：\(message)"
        case .executeFailed(let message):
            return "无法写入同步数据库：\(message)"
        case .prepareFailed(let message):
            return "无法准备同步数据库查询：\(message)"
        case .stepFailed(let message):
            return "无法读取同步数据库：\(message)"
        case .missingMetadata(let key):
            return "同步数据库缺少元数据：\(key)"
        }
    }
}

final class OneDriveFolderSyncProvider {
    private let rootURL: URL
    private let fileManager: FileManager

    init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    func saveHistorySnapshot(
        _ payloads: [PasteboardHistorySyncPayload],
        deviceID: String,
        limit: Int,
        maxTextBytes: Int,
        snapshotTextBudgetBytes: Int
    ) throws {
        try removeLegacyV1Paths()
        let destinationURL = historyDevicesURL.appendingPathComponent(fileName(for: deviceID))
        let sortedPayloads = Array(payloads
            .sorted {
                if $0.updateAt == $1.updateAt {
                    return $0.id < $1.id
                }
                return $0.updateAt > $1.updateAt
            }
            .prefix(max(0, limit)))
        try writeSQLiteSnapshot(to: destinationURL) { database in
            try database.execute("""
                CREATE TABLE metadata (
                  key TEXT PRIMARY KEY NOT NULL,
                  value TEXT NOT NULL
                );
                CREATE TABLE histories (
                  id TEXT PRIMARY KEY NOT NULL,
                  updatedAt INTEGER NOT NULL,
                  sourceKind TEXT NOT NULL,
                  text TEXT NOT NULL
                );
                CREATE INDEX histories_updatedAt_index ON histories(updatedAt DESC);
                """)
            try writeMetadata([
                "schemaVersion": "3",
                "deviceID": deviceID,
                "platform": "macOS",
                "generatedAt": "\(Int(Date().timeIntervalSince1970))",
                "historyLimit": "\(limit)",
                "maxTextBytes": "\(maxTextBytes)",
                "snapshotTextBudgetBytes": "\(snapshotTextBudgetBytes)"
            ], database: database)
            let historyStatement = try database.prepare(
                "INSERT INTO histories(id, updatedAt, sourceKind, text) VALUES (?, ?, ?, ?)"
            )
            for payload in sortedPayloads {
                try historyStatement.reset()
                try historyStatement.bind(payload.id, at: 1)
                try historyStatement.bind(payload.updateAt, at: 2)
                try historyStatement.bind(payload.sourceKind.rawValue, at: 3)
                try historyStatement.bind(payload.text, at: 4)
                try historyStatement.stepToCompletion()
            }
        }
    }

    func loadHistorySnapshots(excludingDeviceID deviceID: String) throws -> [HistorySyncSnapshot] {
        try loadSQLiteFiles(in: historyDevicesURL).compactMap { url in
            guard let snapshot = try? loadHistorySnapshot(at: url), snapshot.deviceID != deviceID else {
                return nil
            }
            return snapshot
        }
    }

    func saveSnippetSnapshot(_ snapshot: SnippetSyncSnapshot, deviceID: String) throws {
        try removeLegacyV1Paths()
        let destinationURL = snippetDevicesURL.appendingPathComponent(fileName(for: deviceID))
        try writeSQLiteSnapshot(to: destinationURL) { database in
            try database.execute("""
                CREATE TABLE metadata (
                  key TEXT PRIMARY KEY NOT NULL,
                  value TEXT NOT NULL
                );
                CREATE TABLE folders (
                  id TEXT PRIMARY KEY NOT NULL,
                  title TEXT NOT NULL,
                  displayIndex INTEGER NOT NULL,
                  isEnabled INTEGER NOT NULL,
                  updatedAt INTEGER NOT NULL,
                  lastModifiedDeviceID TEXT
                );
                CREATE TABLE snippets (
                  id TEXT PRIMARY KEY NOT NULL,
                  folderID TEXT NOT NULL,
                  title TEXT NOT NULL,
                  content TEXT NOT NULL,
                  displayIndex INTEGER NOT NULL,
                  isEnabled INTEGER NOT NULL,
                  updatedAt INTEGER NOT NULL,
                  lastModifiedDeviceID TEXT
                );
                """)
            try writeMetadata([
                "schemaVersion": "2",
                "deviceID": deviceID,
                "generatedAt": "\(Int(Date().timeIntervalSince1970))"
            ], database: database)
            let folderStatement = try database.prepare("""
                INSERT INTO folders(id, title, displayIndex, isEnabled, updatedAt, lastModifiedDeviceID)
                VALUES (?, ?, ?, ?, ?, ?)
                """)
            let snippetStatement = try database.prepare("""
                INSERT INTO snippets(id, folderID, title, content, displayIndex, isEnabled, updatedAt, lastModifiedDeviceID)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """)
            for folder in snapshot.folders {
                try folderStatement.reset()
                try folderStatement.bind(folder.id, at: 1)
                try folderStatement.bind(folder.title, at: 2)
                try folderStatement.bind(folder.index, at: 3)
                try folderStatement.bind(folder.isEnabled, at: 4)
                try folderStatement.bind(folder.updatedAt, at: 5)
                try folderStatement.bind(folder.deviceID, at: 6)
                try folderStatement.stepToCompletion()
            }
            for snippet in snapshot.snippets {
                try snippetStatement.reset()
                try snippetStatement.bind(snippet.id, at: 1)
                try snippetStatement.bind(snippet.folderID, at: 2)
                try snippetStatement.bind(snippet.title, at: 3)
                try snippetStatement.bind(snippet.content, at: 4)
                try snippetStatement.bind(snippet.index, at: 5)
                try snippetStatement.bind(snippet.isEnabled, at: 6)
                try snippetStatement.bind(snippet.updatedAt, at: 7)
                try snippetStatement.bind(snippet.deviceID, at: 8)
                try snippetStatement.stepToCompletion()
            }
        }
    }

    func loadSnippetSnapshots(excludingDeviceID deviceID: String) throws -> [SnippetDeviceSyncSnapshot] {
        try loadSQLiteFiles(in: snippetDevicesURL).compactMap { url in
            guard let snapshot = try? loadSnippetSnapshot(at: url), snapshot.deviceID != deviceID else {
                return nil
            }
            return snapshot
        }
    }

    private func loadHistorySnapshot(at url: URL) throws -> HistorySyncSnapshot {
        let database = try SyncSQLiteDatabase(url: url)
        let metadata = try readMetadata(database: database)
        guard metadata["schemaVersion"] == "3" else { throw SyncSQLiteError.missingMetadata("schemaVersion") }
        guard let deviceID = metadata["deviceID"] else { throw SyncSQLiteError.missingMetadata("deviceID") }
        let statement = try database.prepare(
            "SELECT id, updatedAt, sourceKind, text FROM histories ORDER BY updatedAt DESC, id ASC"
        )
        var payloads = [PasteboardHistorySyncPayload]()
        while try statement.step() {
            guard let sourceKind = HistoryTextSourceKind(rawValue: statement.columnString(at: 2)) else {
                continue
            }
            let payload = PasteboardHistorySyncPayload(
                id: statement.columnString(at: 0),
                text: statement.columnString(at: 3),
                updateAt: statement.columnInt(at: 1),
                deviceID: deviceID,
                sourceKind: sourceKind
            )
            payloads.append(payload)
        }
        return HistorySyncSnapshot(deviceID: deviceID, payloads: payloads)
    }

    private func loadSnippetSnapshot(at url: URL) throws -> SnippetDeviceSyncSnapshot {
        let database = try SyncSQLiteDatabase(url: url)
        let metadata = try readMetadata(database: database)
        guard metadata["schemaVersion"] == "2" else { throw SyncSQLiteError.missingMetadata("schemaVersion") }
        guard let deviceID = metadata["deviceID"] else { throw SyncSQLiteError.missingMetadata("deviceID") }
        let foldersStatement = try database.prepare("""
            SELECT id, title, displayIndex, isEnabled, updatedAt, lastModifiedDeviceID
            FROM folders
            ORDER BY displayIndex ASC, id ASC
            """)
        var folders = [SnippetFolderSyncPayload]()
        while try foldersStatement.step() {
            folders.append(SnippetFolderSyncPayload(
                id: foldersStatement.columnString(at: 0),
                title: foldersStatement.columnString(at: 1),
                index: foldersStatement.columnInt(at: 2),
                isEnabled: foldersStatement.columnBool(at: 3),
                updatedAt: foldersStatement.columnInt(at: 4),
                deviceID: foldersStatement.columnOptionalString(at: 5)
            ))
        }
        let snippetsStatement = try database.prepare("""
            SELECT id, folderID, title, content, displayIndex, isEnabled, updatedAt, lastModifiedDeviceID
            FROM snippets
            ORDER BY displayIndex ASC, id ASC
            """)
        var snippets = [SnippetSyncPayload]()
        while try snippetsStatement.step() {
            snippets.append(SnippetSyncPayload(
                id: snippetsStatement.columnString(at: 0),
                folderID: snippetsStatement.columnString(at: 1),
                title: snippetsStatement.columnString(at: 2),
                content: snippetsStatement.columnString(at: 3),
                index: snippetsStatement.columnInt(at: 4),
                isEnabled: snippetsStatement.columnBool(at: 5),
                updatedAt: snippetsStatement.columnInt(at: 6),
                deviceID: snippetsStatement.columnOptionalString(at: 7)
            ))
        }
        return SnippetDeviceSyncSnapshot(
            deviceID: deviceID,
            snapshot: SnippetSyncSnapshot(folders: folders, snippets: snippets)
        )
    }

    private func writeMetadata(_ metadata: [String: String], database: SyncSQLiteDatabase) throws {
        let statement = try database.prepare("INSERT INTO metadata(key, value) VALUES (?, ?)")
        for (key, value) in metadata {
            try statement.reset()
            try statement.bind(key, at: 1)
            try statement.bind(value, at: 2)
            try statement.stepToCompletion()
        }
    }

    private func readMetadata(database: SyncSQLiteDatabase) throws -> [String: String] {
        let statement = try database.prepare("SELECT key, value FROM metadata")
        var metadata = [String: String]()
        while try statement.step() {
            metadata[statement.columnString(at: 0)] = statement.columnString(at: 1)
        }
        return metadata
    }

    private func writeSQLiteSnapshot(to destinationURL: URL, write: (SyncSQLiteDatabase) throws -> Void) throws {
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporaryURL = destinationURL.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).sqlite")
        try? fileManager.removeItem(at: temporaryURL)
        do {
            let database = try SyncSQLiteDatabase(url: temporaryURL)
            try database.execute("PRAGMA journal_mode=DELETE; PRAGMA synchronous=NORMAL; PRAGMA temp_store=MEMORY;")
            try database.execute("BEGIN IMMEDIATE")
            try write(database)
            try database.execute("COMMIT")
            database.close()
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func loadSQLiteFiles(in directoryURL: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return [] }
        return try fileManager
            .contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "sqlite" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func removeLegacyV1Paths() throws {
        for url in [
            syncRootURL.appendingPathComponent("manifest.json"),
            syncRootURL.appendingPathComponent("histories", isDirectory: true),
            syncRootURL.appendingPathComponent("snippets/items", isDirectory: true),
            syncRootURL.appendingPathComponent("snippets/folders", isDirectory: true)
        ] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private var syncRootURL: URL {
        rootURL
    }

    private var historyDevicesURL: URL {
        syncRootURL
            .appendingPathComponent("history", isDirectory: true)
            .appendingPathComponent("devices", isDirectory: true)
    }

    private var snippetDevicesURL: URL {
        syncRootURL
            .appendingPathComponent("snippets", isDirectory: true)
            .appendingPathComponent("devices", isDirectory: true)
    }

    private func fileName(for id: String) -> String {
        let allowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.")
        let sanitized = String(id.unicodeScalars.map {
            allowedCharacters.contains($0) ? Character($0) : "-"
        })
        let trimmed = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        return "\((trimmed.isEmpty ? UUID().uuidString : trimmed)).sqlite"
    }
}

private final class SyncSQLiteDatabase {
    private var handle: OpaquePointer?

    init(url: URL) throws {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard result == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let database {
                sqlite3_close(database)
            }
            throw SyncSQLiteError.openFailed(message)
        }
        handle = database
    }

    deinit {
        close()
    }

    func close() {
        if let handle {
            sqlite3_close(handle)
            self.handle = nil
        }
    }

    func execute(_ sql: String) throws {
        guard let handle else { throw SyncSQLiteError.executeFailed("database is closed") }
        let result = sqlite3_exec(handle, sql, nil, nil, nil)
        guard result == SQLITE_OK else {
            throw SyncSQLiteError.executeFailed(String(cString: sqlite3_errmsg(handle)))
        }
    }

    func prepare(_ sql: String) throws -> SyncSQLiteStatement {
        guard let handle else { throw SyncSQLiteError.prepareFailed("database is closed") }
        return try SyncSQLiteStatement(database: handle, sql: sql)
    }
}

private final class SyncSQLiteStatement {
    private let database: OpaquePointer
    private var statement: OpaquePointer?

    init(database: OpaquePointer, sql: String) throws {
        self.database = database
        var preparedStatement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &preparedStatement, nil)
        guard result == SQLITE_OK, let preparedStatement else {
            throw SyncSQLiteError.prepareFailed(String(cString: sqlite3_errmsg(database)))
        }
        statement = preparedStatement
    }

    deinit {
        sqlite3_finalize(statement)
    }

    func reset() throws {
        guard let statement else { return }
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
    }

    func bind(_ value: String?, at index: Int32) throws {
        guard let statement else { return }
        let result: Int32
        if let value {
            result = sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        try checkBind(result)
    }

    func bind(_ value: Int, at index: Int32) throws {
        guard let statement else { return }
        try checkBind(sqlite3_bind_int64(statement, index, sqlite3_int64(value)))
    }

    func bind(_ value: Bool, at index: Int32) throws {
        try bind(value ? 1 : 0, at: index)
    }

    func bind(_ value: Data, at index: Int32) throws {
        guard let statement else { return }
        let result = value.withUnsafeBytes {
            sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(value.count), sqliteTransient)
        }
        try checkBind(result)
    }

    func step() throws -> Bool {
        guard let statement else { return false }
        let result = sqlite3_step(statement)
        switch result {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            throw SyncSQLiteError.stepFailed(String(cString: sqlite3_errmsg(database)))
        }
    }

    func stepToCompletion() throws {
        guard try !step() else {
            throw SyncSQLiteError.stepFailed("statement unexpectedly returned a row")
        }
    }

    func columnString(at index: Int32) -> String {
        guard let statement, let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    func columnOptionalString(at index: Int32) -> String? {
        guard let statement, sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    func columnInt(at index: Int32) -> Int {
        guard let statement else { return 0 }
        return Int(sqlite3_column_int64(statement, index))
    }

    func columnBool(at index: Int32) -> Bool {
        columnInt(at: index) != 0
    }

    func columnData(at index: Int32) -> Data {
        guard let statement else { return Data() }
        let count = Int(sqlite3_column_bytes(statement, index))
        guard let bytes = sqlite3_column_blob(statement, index), count > 0 else {
            return Data()
        }
        return Data(bytes: bytes, count: count)
    }

    private func checkBind(_ result: Int32) throws {
        guard result == SQLITE_OK else {
            throw SyncSQLiteError.executeFailed(String(cString: sqlite3_errmsg(database)))
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
