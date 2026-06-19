//
//  PasteboardHistoryRepository.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Shunsuke Furubayashi on 2026/05/28.
//
//  Copyright © 2015-2026 Clipy Project.
//

import AppKit
import Combine
import Dependencies
import SQLiteData

enum HistorySearchError: Error, Equatable {
    case invalidRegularExpression(String)
}

struct HistoryRetentionSettings: Equatable {
    static let defaultStoredHistoryLimit = 2000
    static let defaultMaxSyncedHistoryTextBytes = 256 * 1024
    static let defaultMaxHistorySnapshotTextBudgetBytes = 8 * 1024 * 1024

    let menuDisplayLimit: Int
    let storedHistoryLimit: Int
    let maxSyncedHistoryTextBytes: Int
    let maxHistorySnapshotTextBudgetBytes: Int

    static func current(defaults: UserDefaults = AppEnvironment.current.defaults) -> HistoryRetentionSettings {
        let menuDisplayLimit = defaults.integer(forKey: Constants.UserDefaults.maxHistorySize)
        let storedHistoryLimit = defaults.integer(forKey: Constants.UserDefaults.storedHistoryLimit)
        let maxSyncedHistoryTextBytes = defaults.integer(forKey: Constants.UserDefaults.maxSyncedHistoryTextBytes)
        let maxHistorySnapshotTextBudgetBytes = defaults.integer(
            forKey: Constants.UserDefaults.maxHistorySnapshotTextBudgetBytes
        )

        return HistoryRetentionSettings(
            menuDisplayLimit: max(0, menuDisplayLimit),
            storedHistoryLimit: storedHistoryLimit > 0 ? storedHistoryLimit : defaultStoredHistoryLimit,
            maxSyncedHistoryTextBytes: maxSyncedHistoryTextBytes > 0
                ? maxSyncedHistoryTextBytes
                : defaultMaxSyncedHistoryTextBytes,
            maxHistorySnapshotTextBudgetBytes: maxHistorySnapshotTextBudgetBytes > 0
                ? maxHistorySnapshotTextBudgetBytes
                : defaultMaxHistorySnapshotTextBudgetBytes
        )
    }
}

enum HistoryTextSourceKind: String, Codable {
    case plainText
    case url
}

struct PasteboardHistorySyncPayload: Equatable {
    let id: String
    let text: String
    let updateAt: Int
    let deviceID: String?
    let sourceKind: HistoryTextSourceKind

    var textByteCount: Int {
        text.lengthOfBytes(using: .utf8)
    }
}

struct HistorySearchQuery: Equatable {
    enum Mode: Equatable {
        case plain
        case regex
    }

    enum SortOrder: Equatable {
        case newestFirst
        case oldestFirst
    }

    let text: String
    let mode: Mode
    let caseSensitive: Bool
    let types: Set<NSPasteboard.PasteboardType>
    let sortOrder: SortOrder

    init(
        text: String,
        mode: Mode = .plain,
        caseSensitive: Bool = false,
        types: Set<NSPasteboard.PasteboardType> = [],
        sortOrder: SortOrder = .newestFirst
    ) {
        self.text = text
        self.mode = mode
        self.caseSensitive = caseSensitive
        self.types = types
        self.sortOrder = sortOrder
    }
}

struct PasteboardHistorySearchCandidate: Equatable {
    let id: PasteboardHistory.ID
    let title: String
    let pasteboardTypes: [NSPasteboard.PasteboardType]
    let updateAt: Int

    init(history: PasteboardHistory) {
        self.id = history.id
        self.title = history.title
        self.pasteboardTypes = history.pasteboardTypes
        self.updateAt = history.updateAt
    }
}

@Selection
struct PasteboardHistoryChangeToken: Equatable {
    let id: PasteboardHistory.ID
    let updateAt: Int
}

protocol PasteboardHistoryRepositoryProtocol {
    func observeHistoryChanges() -> AnyPublisher<Void, Never>
    func observeHistories() -> AnyPublisher<[PasteboardHistory], Never>
    func hasHistories() -> Bool
    func fetchHistoryDetails(
        ascending: Bool,
        includesThumbnailAsset: Bool,
        limit: Int,
        offset: Int
    ) -> [PasteboardHistoryDetail]
    func searchHistoryDetails(
        query: HistorySearchQuery,
        includesThumbnailAsset: Bool,
        limit: Int,
        offset: Int
    ) throws -> [PasteboardHistoryDetail]
    func fetchHistory(id: PasteboardHistory.ID) -> PasteboardHistory?
    func fetchContent(id: PasteboardHistory.ID) -> PasteboardContent?

    func save(id: PasteboardHistory.ID, content: PasteboardContent, updateAt: Int)
    func deleteHistory(id: PasteboardHistory.ID)
    func deleteAll()
    func deleteOverflowingHistories(maxHistorySize: Int)
    func pruneHistories(settings: HistoryRetentionSettings)
    func fetchSyncPayloads(
        currentDeviceID: String?,
        limit: Int,
        maxTextBytes: Int,
        snapshotTextBudgetBytes: Int
    ) -> [PasteboardHistorySyncPayload]
    @discardableResult
    func upsertSyncPayload(_ payload: PasteboardHistorySyncPayload) -> Bool
    func suppressSyncedHistory(id: PasteboardHistory.ID)
}

extension PasteboardHistoryRepositoryProtocol {
    func observeHistoryChanges() -> AnyPublisher<Void, Never> {
        observeHistories()
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func fetchHistoryDetails(
        ascending: Bool,
        includesThumbnailAsset: Bool,
        limit: Int
    ) -> [PasteboardHistoryDetail] {
        fetchHistoryDetails(
            ascending: ascending,
            includesThumbnailAsset: includesThumbnailAsset,
            limit: limit,
            offset: 0
        )
    }

    func fetchSyncPayloads(
        currentDeviceID: String?,
        limit: Int,
        maxTextBytes: Int,
        snapshotTextBudgetBytes: Int
    ) -> [PasteboardHistorySyncPayload] {
        []
    }

    func upsertSyncPayload(_ payload: PasteboardHistorySyncPayload) -> Bool { false }

    func suppressSyncedHistory(id: PasteboardHistory.ID) {}
}

final class PasteboardHistoryRepository: PasteboardHistoryRepositoryProtocol {
    private var database: any DatabaseWriter {
        @Dependency(\.defaultDatabase) var database
        return database
    }

    func observeHistoryChanges() -> AnyPublisher<Void, Never> {
        @FetchAll(
            PasteboardHistory
                .all
                .order { $0.updateAt.desc() }
                .select {
                    PasteboardHistoryChangeToken.Columns(
                        id: $0.id,
                        updateAt: $0.updateAt
                    )
                }
        )
        var historyChangeTokens

        return $historyChangeTokens.publisher
            .map { _ in () }
            .prepend(())
            .eraseToAnyPublisher()
    }

    func observeHistories() -> AnyPublisher<[PasteboardHistory], Never> {
        @FetchAll(PasteboardHistory.all.order { $0.updateAt.desc() })
        var histories

        return $histories.publisher.eraseToAnyPublisher()
    }

    func hasHistories() -> Bool {
        withErrorReporting {
            try database.read { database in
                try PasteboardHistory
                    .select { $0.id }
                    .limit(1)
                    .fetchOne(database) != nil
            }
        } ?? false
    }

    func fetchHistoryDetails(
        ascending: Bool,
        includesThumbnailAsset: Bool,
        limit: Int,
        offset: Int = 0
    ) -> [PasteboardHistoryDetail] {
        guard limit > 0 else { return [] }
        return withErrorReporting {
            try database.read { database in
                let histories = PasteboardHistory
                    .all
                    .order { columns in
                        if ascending {
                            columns.updateAt
                        } else {
                            columns.updateAt.desc()
                        }
                    }
                    .limit(limit, offset: max(0, offset))

                guard includesThumbnailAsset else {
                    return try histories
                        .fetchAll(database)
                        .map { PasteboardHistoryDetail(history: $0, thumbnailAsset: nil) }
                }

                return try histories
                    .leftJoin(PasteboardHistoryThumbnailAsset.all) { $0.id.eq($1.pasteboardHistoryID) }
                    .select { PasteboardHistoryDetail.Columns(history: $0, thumbnailAsset: $1) }
                    .fetchAll(database)
            }
        } ?? []
    }

    func searchHistoryDetails(
        query: HistorySearchQuery,
        includesThumbnailAsset: Bool,
        limit: Int,
        offset: Int
    ) throws -> [PasteboardHistoryDetail] {
        guard limit > 0 else { return [] }
        if query.text.isEmpty && query.types.isEmpty {
            return fetchHistoryDetails(
                ascending: query.sortOrder == .oldestFirst,
                includesThumbnailAsset: includesThumbnailAsset,
                limit: limit,
                offset: offset
            )
        }

        let ids = try matchingHistoryIDs(query: query, limit: limit, offset: offset)
        return fetchHistoryDetails(ids: ids, includesThumbnailAsset: includesThumbnailAsset)
    }

    func matchingHistoryIDs(
        query: HistorySearchQuery,
        limit: Int,
        offset: Int
    ) throws -> [PasteboardHistory.ID] {
        guard limit > 0 else { return [] }

        let matcher = try makeMatcher(for: query)
        let candidates = fetchSearchCandidates(ascending: query.sortOrder == .oldestFirst)
        let filteredIDs = candidates.lazy
            .filter { candidate in
                if !query.types.isEmpty && Set(candidate.pasteboardTypes).isDisjoint(with: query.types) {
                    return false
                }
                return matcher(candidate.title)
            }
            .map(\.id)

        return Array(filteredIDs.dropFirst(max(0, offset)).prefix(limit))
    }

    func fetchHistoryDetails(
        ids: [PasteboardHistory.ID],
        includesThumbnailAsset: Bool
    ) -> [PasteboardHistoryDetail] {
        guard !ids.isEmpty else { return [] }
        var indexByID = [PasteboardHistory.ID: Int]()
        ids.enumerated().forEach { offset, id in
            if indexByID[id] == nil {
                indexByID[id] = offset
            }
        }
        return (withErrorReporting {
            try database.read { database in
                let histories = PasteboardHistory
                    .where { $0.id.in(ids) }

                let details: [PasteboardHistoryDetail]
                if includesThumbnailAsset {
                    details = try histories
                        .leftJoin(PasteboardHistoryThumbnailAsset.all) { $0.id.eq($1.pasteboardHistoryID) }
                        .select { PasteboardHistoryDetail.Columns(history: $0, thumbnailAsset: $1) }
                        .fetchAll(database)
                } else {
                    details = try histories
                        .fetchAll(database)
                        .map { PasteboardHistoryDetail(history: $0, thumbnailAsset: nil) }
                }

                return details.sorted {
                    indexByID[$0.history.id, default: Int.max] < indexByID[$1.history.id, default: Int.max]
                }
            }
        } ?? [])
    }

    func fetchHistory(id: PasteboardHistory.ID) -> PasteboardHistory? {
        withErrorReporting {
            try database.read { database in
                try PasteboardHistory.find(id).fetchOne(database)
            }
        }
    }

    func fetchContent(id: PasteboardHistory.ID) -> PasteboardContent? {
        withErrorReporting {
            try database.read { database in
                let assets = try PasteboardHistoryAsset
                    .where { $0.pasteboardHistoryID.eq(id) }
                    .fetchAll(database)
                return PasteboardContent(
                    assets: assets.map {
                        PasteboardContent.Asset(type: $0.pasteboardType, data: $0.data)
                    }
                )
            }
        }
    }

    func save(id: PasteboardHistory.ID, content: PasteboardContent, updateAt: Int) {
        let history = PasteboardHistory(
            id: id,
            title: content.stringValue[0...10000],
            pasteboardTypes: content.types,
            updateAt: updateAt,
            deviceID: CPYUtilities.deviceID
        )
        withErrorReporting {
            try database.write { database in
                let exists = try PasteboardHistory
                    .find(id)
                    .fetchOne(database) != nil
                try PasteboardHistory
                    .upsert { history }
                    .execute(database)
                // When a history already exists, its ID is derived from the content hash,
                // so the assets are guaranteed to be identical and do not need to be inserted again.
                if !exists {
                    let assets = content.assets.map {
                        PasteboardHistoryAsset.Draft(pasteboardHistoryID: id, pasteboardType: $0.type, data: $0.data)
                    }
                    try PasteboardHistoryAsset.insert { assets }.execute(database)
                    if let thumbnailAsset = thumbnailAsset(from: content, id: id) {
                        try PasteboardHistoryThumbnailAsset.insert { thumbnailAsset }.execute(database)
                    }
                }
            }
        }
    }

    func deleteHistory(id: PasteboardHistory.ID) {
        suppressSyncedHistory(id: id)
        withErrorReporting {
            try database.write { database in
                try PasteboardHistory
                    .delete()
                    .where { $0.id.eq(id) }
                    .execute(database)
            }
        }
    }

    func deleteAll() {
        withErrorReporting {
            try database.write { database in
                let ids = try PasteboardHistory
                    .select { $0.id }
                    .fetchAll(database)
                try ids.forEach { id in
                    try SyncSuppression.upsert {
                        SyncSuppression(
                            syncIdentity: syncIdentity(kind: .history, id: id.rawValue),
                            kind: .history,
                            recordID: id.rawValue,
                            suppressedAt: Int(Date().timeIntervalSince1970)
                        )
                    }
                    .execute(database)
                }
                try PasteboardHistory.delete().execute(database)
            }
        }
    }

    func deleteOverflowingHistories(maxHistorySize: Int) {
        guard maxHistorySize > 0 else {
            deleteAll()
            return
        }
        withErrorReporting {
            try database.write { database in
                let deletingIDs = try PasteboardHistory
                    .order { $0.updateAt.desc() }
                    .limit(-1, offset: maxHistorySize)
                    .select { $0.id }
                    .fetchAll(database)
                guard !deletingIDs.isEmpty else { return }
                try PasteboardHistory
                    .delete()
                    .where { $0.id.in(deletingIDs) }
                    .execute(database)
            }
        }
    }

    func pruneHistories(settings: HistoryRetentionSettings) {
        deleteOverflowingHistories(maxHistorySize: settings.storedHistoryLimit)
    }

    func fetchSyncPayloads(
        currentDeviceID: String?,
        limit: Int,
        maxTextBytes: Int,
        snapshotTextBudgetBytes: Int
    ) -> [PasteboardHistorySyncPayload] {
        guard let currentDeviceID else { return [] }
        return withErrorReporting {
            try database.read { database in
                let histories = try PasteboardHistory
                    .all
                    .order { $0.updateAt.desc() }
                    .fetchAll(database)
                    .filter {
                        $0.deviceID == currentDeviceID
                    }
                var remainingTextBudget = max(0, snapshotTextBudgetBytes)
                var payloads = [PasteboardHistorySyncPayload]()
                for history in histories {
                    let assets = try PasteboardHistoryAsset
                        .where { $0.pasteboardHistoryID.eq(history.id) }
                        .fetchAll(database)
                    guard let textPayload = Self.textSyncPayload(from: assets) else { continue }
                    let textByteCount = textPayload.text.lengthOfBytes(using: .utf8)
                    guard textByteCount <= maxTextBytes else { continue }
                    guard textByteCount <= remainingTextBudget else { break }
                    remainingTextBudget -= textByteCount
                    payloads.append(PasteboardHistorySyncPayload(
                        id: history.id.rawValue,
                        text: textPayload.text,
                        updateAt: history.updateAt,
                        deviceID: history.deviceID,
                        sourceKind: textPayload.sourceKind
                    ))
                    if payloads.count >= max(0, limit) {
                        break
                    }
                }
                return payloads
            }
        } ?? []
    }

    @discardableResult
    func upsertSyncPayload(_ payload: PasteboardHistorySyncPayload) -> Bool {
        withErrorReporting {
            try database.write { database in
                guard try SyncSuppression
                    .find(syncIdentity(kind: .history, id: payload.id))
                    .fetchOne(database) == nil else {
                    return false
                }
                let historyID = PasteboardHistory.ID(rawValue: payload.id)
                if let existingHistory = try PasteboardHistory.find(historyID).fetchOne(database),
                   payload.updateAt <= existingHistory.updateAt {
                    return false
                }
                try PasteboardHistory
                    .upsert {
                            PasteboardHistory(
                                id: historyID,
                                title: payload.text[0...10000],
                                pasteboardTypes: [.string],
                                updateAt: payload.updateAt,
                                deviceID: payload.deviceID
                            )
                    }
                    .execute(database)
                try PasteboardHistoryAsset
                    .delete()
                    .where { $0.pasteboardHistoryID.eq(historyID) }
                    .execute(database)
                try PasteboardHistoryThumbnailAsset
                    .delete()
                    .where { $0.pasteboardHistoryID.eq(historyID) }
                    .execute(database)
                let assets = [
                    PasteboardHistoryAsset.Draft(
                        pasteboardHistoryID: historyID,
                        pasteboardType: .string,
                        data: Data(payload.text.utf8)
                    )
                ]
                try PasteboardHistoryAsset.insert { assets }.execute(database)
                return true
            }
        } ?? false
    }

    private static func textSyncPayload(
        from assets: [PasteboardHistoryAsset]
    ) -> (text: String, sourceKind: HistoryTextSourceKind)? {
        let types = Set(assets.map(\.pasteboardType))
        let plainTextTypes: Set<NSPasteboard.PasteboardType> = [.string, .deprecatedString]
        if types.isSubset(of: plainTextTypes),
           let text = assets.compactMap({ plainText(from: $0) }).first {
            return (text, .plainText)
        }

        let urlTypes: Set<NSPasteboard.PasteboardType> = [.URL, .deprecatedURL]
        if types.isSubset(of: urlTypes),
           let urlText = assets.compactMap({ nonFileURLText(from: $0) }).first {
            return (urlText, .url)
        }
        return nil
    }

    private static func plainText(from asset: PasteboardHistoryAsset) -> String? {
        guard asset.pasteboardType == .string || asset.pasteboardType == .deprecatedString else {
            return nil
        }
        return String(data: asset.data, encoding: .utf8)
    }

    private static func nonFileURLText(from asset: PasteboardHistoryAsset) -> String? {
        guard asset.pasteboardType == .URL || asset.pasteboardType == .deprecatedURL else {
            return nil
        }
        if let url = URL(dataRepresentation: asset.data, relativeTo: nil), !url.isFileURL {
            return url.absoluteString
        }
        guard let text = String(data: asset.data, encoding: .utf8),
              let url = URL(string: text),
              !url.isFileURL else {
            return nil
        }
        return url.absoluteString
    }

    func suppressSyncedHistory(id: PasteboardHistory.ID) {
        withErrorReporting {
            try database.write { database in
                try SyncSuppression.upsert {
                    SyncSuppression(
                        syncIdentity: syncIdentity(kind: .history, id: id.rawValue),
                        kind: .history,
                        recordID: id.rawValue,
                        suppressedAt: Int(Date().timeIntervalSince1970)
                    )
                }
                .execute(database)
            }
        }
    }
}

private extension PasteboardHistoryRepository {
    func fetchSearchCandidates(ascending: Bool) -> [PasteboardHistorySearchCandidate] {
        withErrorReporting {
            try database.read { database in
                try PasteboardHistory
                    .all
                    .order { columns in
                        if ascending {
                            columns.updateAt
                        } else {
                            columns.updateAt.desc()
                        }
                    }
                    .fetchAll(database)
                    .map(PasteboardHistorySearchCandidate.init(history:))
            }
        } ?? []
    }

    func makeMatcher(for query: HistorySearchQuery) throws -> (String) -> Bool {
        guard !query.text.isEmpty else { return { _ in true } }

        switch query.mode {
        case .plain:
            return { value in
                if query.caseSensitive {
                    return value.contains(query.text)
                }
                return value.range(of: query.text, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        case .regex:
            let options: NSRegularExpression.Options = query.caseSensitive ? [] : [.caseInsensitive]
            let regularExpression: NSRegularExpression
            do {
                regularExpression = try NSRegularExpression(pattern: query.text, options: options)
            } catch {
                throw HistorySearchError.invalidRegularExpression(query.text)
            }
            return { value in
                let range = NSRange(value.startIndex..., in: value)
                return regularExpression.firstMatch(in: value, options: [], range: range) != nil
            }
        }
    }

    func thumbnailAsset(from content: PasteboardContent, id: PasteboardHistory.ID) -> PasteboardHistoryThumbnailAsset? {
        var asset: PasteboardHistoryThumbnailAsset?
        if let thumbnailImage = content.thumbnailImage,
           let thumbnailData = PasteraImageEncoding.pngData(from: thumbnailImage) ?? thumbnailImage.tiffRepresentation {
            asset = PasteboardHistoryThumbnailAsset(
                pasteboardHistoryID: id,
                kind: .image,
                data: thumbnailData
            )
        }
        if let colorCodeImage = content.colorCodeImage,
           let colorCodeData = PasteraImageEncoding.pngData(from: colorCodeImage) ?? colorCodeImage.tiffRepresentation {
            asset = PasteboardHistoryThumbnailAsset(
                pasteboardHistoryID: id,
                kind: .colorCode,
                data: colorCodeData
            )
        }
        return asset
    }

    func syncIdentity(kind: SyncEntityKind, id: String) -> String {
        "\(kind.rawValue):\(id)"
    }
}

private enum PasteboardHistoryRepositoryKey: DependencyKey {
    static var liveValue: any PasteboardHistoryRepositoryProtocol { PasteboardHistoryRepository() }
}

extension DependencyValues {
    var pasteboardHistoryRepository: PasteboardHistoryRepositoryProtocol {
        get { self[PasteboardHistoryRepositoryKey.self] }
        set { self[PasteboardHistoryRepositoryKey.self] = newValue }
    }
}
