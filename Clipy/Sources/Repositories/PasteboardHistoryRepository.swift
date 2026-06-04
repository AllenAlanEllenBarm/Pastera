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
    static let defaultStoredHistoryLimit = 1000
    static let defaultMaxSyncedAssetBytes = 10 * 1024 * 1024

    let menuDisplayLimit: Int
    let storedHistoryLimit: Int
    let maxSyncedAssetBytes: Int

    static func current(defaults: UserDefaults = AppEnvironment.current.defaults) -> HistoryRetentionSettings {
        let menuDisplayLimit = defaults.integer(forKey: Constants.UserDefaults.maxHistorySize)
        let storedHistoryLimit = defaults.integer(forKey: Constants.UserDefaults.storedHistoryLimit)
        let maxSyncedAssetBytes = defaults.integer(forKey: Constants.UserDefaults.maxSyncedAssetBytes)

        return HistoryRetentionSettings(
            menuDisplayLimit: max(0, menuDisplayLimit),
            storedHistoryLimit: storedHistoryLimit > 0 ? storedHistoryLimit : defaultStoredHistoryLimit,
            maxSyncedAssetBytes: maxSyncedAssetBytes > 0 ? maxSyncedAssetBytes : defaultMaxSyncedAssetBytes
        )
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

protocol PasteboardHistoryRepositoryProtocol {
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
}

extension PasteboardHistoryRepositoryProtocol {
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
}

final class PasteboardHistoryRepository: PasteboardHistoryRepositoryProtocol {
    @Dependency(\.defaultDatabase)
    private var database

    @FetchAll(PasteboardHistory.all.order { $0.updateAt.desc() })
    private var histories

    func observeHistories() -> AnyPublisher<[PasteboardHistory], Never> {
        _histories.publisher.eraseToAnyPublisher()
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

        let matcher = try makeMatcher(for: query)
        let details = fetchAllHistoryDetails(
            ascending: query.sortOrder == .oldestFirst,
            includesThumbnailAsset: includesThumbnailAsset
        )
        let filteredDetails = details.filter { detail in
            if !query.types.isEmpty && Set(detail.history.pasteboardTypes).isDisjoint(with: query.types) {
                return false
            }
            return matcher(detail.history.title)
        }
        return Array(filteredDetails.dropFirst(max(0, offset)).prefix(limit))
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
}

private extension PasteboardHistoryRepository {
    func fetchAllHistoryDetails(
        ascending: Bool,
        includesThumbnailAsset: Bool
    ) -> [PasteboardHistoryDetail] {
        withErrorReporting {
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
        if let thumbnailImage = content.thumbnailImage, let thumbnailData = thumbnailImage.tiffRepresentation {
            asset = PasteboardHistoryThumbnailAsset(
                pasteboardHistoryID: id,
                kind: .image,
                data: thumbnailData
            )
        }
        if let colorCodeImage = content.colorCodeImage, let colorCodeData = colorCodeImage.tiffRepresentation {
            asset = PasteboardHistoryThumbnailAsset(
                pasteboardHistoryID: id,
                kind: .colorCode,
                data: colorCodeData
            )
        }
        return asset
    }
}

private enum PasteboardHistoryRepositoryKey: DependencyKey {
    static let liveValue: any PasteboardHistoryRepositoryProtocol = PasteboardHistoryRepository()
}

extension DependencyValues {
    var pasteboardHistoryRepository: PasteboardHistoryRepositoryProtocol {
        get { self[PasteboardHistoryRepositoryKey.self] }
        set { self[PasteboardHistoryRepositoryKey.self] = newValue }
    }
}
