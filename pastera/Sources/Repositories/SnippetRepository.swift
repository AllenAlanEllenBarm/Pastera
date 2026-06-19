// 
//  SnippetRepository.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
// 
//  Created by Shunsuke Furubayashi on 2026/05/23.
// 
//  Copyright © 2015-2026 Clipy Project.
//

import Combine
import Dependencies
import Foundation
import SQLiteData

struct SnippetFolderSyncPayload: Codable, Equatable {
    let id: String
    let title: String
    let index: Int
    let isEnabled: Bool
    let updatedAt: Int
    let deviceID: String?

    init(
        id: String,
        title: String,
        index: Int,
        isEnabled: Bool,
        updatedAt: Int = 0,
        deviceID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.index = index
        self.isEnabled = isEnabled
        self.updatedAt = updatedAt
        self.deviceID = deviceID
    }

    init(folder: SnippetFolder) {
        self.init(
            id: folder.id.rawValue.uuidString,
            title: folder.title,
            index: folder.index,
            isEnabled: folder.isEnabled,
            updatedAt: folder.updatedAt,
            deviceID: folder.lastModifiedDeviceID
        )
    }
}

struct SnippetSyncPayload: Codable, Equatable {
    let id: String
    let folderID: String
    let title: String
    let content: String
    let index: Int
    let isEnabled: Bool
    let updatedAt: Int
    let deviceID: String?

    init(
        id: String,
        folderID: String,
        title: String,
        content: String,
        index: Int,
        isEnabled: Bool,
        updatedAt: Int = 0,
        deviceID: String? = nil
    ) {
        self.id = id
        self.folderID = folderID
        self.title = title
        self.content = content
        self.index = index
        self.isEnabled = isEnabled
        self.updatedAt = updatedAt
        self.deviceID = deviceID
    }

    init(snippet: Snippet) {
        self.init(
            id: snippet.id.rawValue.uuidString,
            folderID: snippet.folderID.rawValue.uuidString,
            title: snippet.title,
            content: snippet.content,
            index: snippet.index,
            isEnabled: snippet.isEnabled,
            updatedAt: snippet.updatedAt,
            deviceID: snippet.lastModifiedDeviceID
        )
    }
}

struct SnippetSyncSnapshot: Codable, Equatable {
    let folders: [SnippetFolderSyncPayload]
    let snippets: [SnippetSyncPayload]
}

protocol SnippetRepositoryProtocol {
    func observeFolders() -> AnyPublisher<[SnippetFolder], Never>
    func observeFolderDetails() -> AnyPublisher<[SnippetFolderDetail], Never>
    func fetchFolders() -> [SnippetFolder]
    func fetchFolderDetails() -> [SnippetFolderDetail]
    func fetchFolderDetail(id: SnippetFolder.ID) -> SnippetFolderDetail?
    func fetchSyncSnapshot() -> SnippetSyncSnapshot

    func insertFolder() -> SnippetFolder?
    func insertFolders(_ folders: [(title: String, snippets: [(title: String, content: String)])]) -> [SnippetFolderDetail]?
    @discardableResult
    func upsertSyncSnapshot(_ snapshot: SnippetSyncSnapshot) -> Int
    func updateFolderTitle(_ id: SnippetFolder.ID, title: String)
    func updateFolderIsEnabled(_ id: SnippetFolder.ID, isEnabled: Bool)
    func updateFolderIndexes(_ folderIDs: [SnippetFolder.ID])
    func deleteFolder(_ id: SnippetFolder.ID)

    func fetchSnippet(id: Snippet.ID) -> Snippet?
    func insertSnippet(to id: SnippetFolder.ID) -> Snippet?
    func updateSnippetTitle(_ id: Snippet.ID, title: String)
    func updateSnippetContent(_ id: Snippet.ID, content: String)
    func updateSnippetIsEnabled(_ id: Snippet.ID, isEnabled: Bool)
    func updateSnippetIndexes(_ snippetIDs: [Snippet.ID])
    func moveSnippet(_ id: Snippet.ID, to folderID: SnippetFolder.ID, snippetIDs: [Snippet.ID])
    func deleteSnippet(_ id: Snippet.ID)
}

extension SnippetRepositoryProtocol {
    func observeFolders() -> AnyPublisher<[SnippetFolder], Never> {
        observeFolderDetails()
            .map { $0.map(\.folder) }
            .eraseToAnyPublisher()
    }

    func fetchFolders() -> [SnippetFolder] {
        fetchFolderDetails().map(\.folder)
    }

}

final class SnippetRepository: SnippetRepositoryProtocol {
    private var database: any DatabaseWriter {
        @Dependency(\.defaultDatabase) var database
        return database
    }

    func observeFolders() -> AnyPublisher<[SnippetFolder], Never> {
        @FetchAll(SnippetFolder.all.order(by: \.index))
        var folders

        return $folders.publisher.eraseToAnyPublisher()
    }

    func observeFolderDetails() -> AnyPublisher<[SnippetFolderDetail], Never> {
        @FetchAll(SnippetFolder.all.order(by: \.index))
        var folders
        @FetchAll(Snippet.all.order(by: \.index))
        var snippets

        return Publishers.CombineLatest($folders.publisher, $snippets.publisher)
            .map { Self.folderDetails(folders: $0, snippets: $1) }
            .eraseToAnyPublisher()
    }

    func fetchFolders() -> [SnippetFolder] {
        withErrorReporting {
            try database.read { database in
                try SnippetFolder.all.order(by: \.index)
                    .fetchAll(database)
            }
        } ?? []
    }

    func fetchFolderDetails() -> [SnippetFolderDetail] {
        withErrorReporting {
            try database.read { database in
                let folders = try SnippetFolder.all.order(by: \.index)
                    .fetchAll(database)
                let snippets = try Snippet.all.order(by: \.index)
                    .fetchAll(database)
                return Self.folderDetails(folders: folders, snippets: snippets)
            }
        } ?? []
    }

    func fetchFolderDetail(id: SnippetFolder.ID) -> SnippetFolderDetail? {
        withErrorReporting {
            try database.read { database in
                guard let folder = try SnippetFolder.find(id).fetchOne(database) else {
                    return nil
                }
                let snippets = try Snippet.where { $0.folderID.eq(id) }.order(by: \.index).fetchAll(database)
                return SnippetFolderDetail(folder: folder, snippets: snippets)
            }
        }
    }

    func fetchSyncSnapshot() -> SnippetSyncSnapshot {
        withErrorReporting {
            try database.read { database in
                let folders = try SnippetFolder.all.order(by: \.index)
                    .fetchAll(database)
                    .map(SnippetFolderSyncPayload.init(folder:))
                let snippets = try Snippet.all.order(by: \.index)
                    .fetchAll(database)
                    .map(SnippetSyncPayload.init(snippet:))
                return SnippetSyncSnapshot(folders: folders, snippets: snippets)
            }
        } ?? SnippetSyncSnapshot(folders: [], snippets: [])
    }

    func insertFolder() -> SnippetFolder? {
        withErrorReporting {
            return try database.write { database in
                let lastIndex = try SnippetFolder.order { $0.index.desc() }
                    .select { $0.index }
                    .fetchOne(database) ?? -1
                let folder = SnippetFolder.Draft(
                    title: "untitled folder",
                    index: lastIndex + 1,
                    isEnabled: true,
                    createdAt: currentUnixTime(),
                    updatedAt: currentUnixTime(),
                    lastModifiedDeviceID: CPYUtilities.deviceID
                )
                return try SnippetFolder.insert { folder }.returning(\.self).fetchOne(database)
            }
        }
    }

    func insertFolders(_ folders: [(title: String, snippets: [(title: String, content: String)])]) -> [SnippetFolderDetail]? {
        withErrorReporting {
            try database.write { database in
                let lastIndex = try SnippetFolder.order { $0.index.desc() }
                    .select { $0.index }
                    .fetchOne(database) ?? -1
                var details = [SnippetFolderDetail]()
                try folders.enumerated().forEach { index, folders in
                    let folder = SnippetFolder.Draft(
                        title: folders.title,
                        index: lastIndex + index + 1,
                        isEnabled: true,
                        createdAt: currentUnixTime(),
                        updatedAt: currentUnixTime(),
                        lastModifiedDeviceID: CPYUtilities.deviceID
                    )
                    guard let insertedFolder = try SnippetFolder.insert(values: { folder }).returning(\.self).fetchOne(database) else {
                        return
                    }
                    let snippets = folders.snippets.enumerated().map { snippetIndex, snippet in
                        Snippet.Draft(
                            folderID: insertedFolder.id,
                            title: snippet.title,
                            content: snippet.content,
                            index: snippetIndex,
                            isEnabled: true,
                            createdAt: currentUnixTime(),
                            updatedAt: currentUnixTime(),
                            lastModifiedDeviceID: CPYUtilities.deviceID
                        )
                    }
                    let insertedSnippets = try Snippet.insert { snippets }.returning(\.self).fetchAll(database)
                    details.append(SnippetFolderDetail(folder: insertedFolder, snippets: insertedSnippets))
                }
                return details
            }
        }
    }

    @discardableResult
    func upsertSyncSnapshot(_ snapshot: SnippetSyncSnapshot) -> Int {
        withErrorReporting {
            try database.write { database in
                var writtenCount = 0
                for payload in snapshot.folders {
                    guard try !isSuppressed(kind: .snippetFolder, id: payload.id, database: database),
                          let folder = payload.snippetFolder else {
                        continue
                    }
                    if let existingFolder = try SnippetFolder.find(folder.id).fetchOne(database),
                       payload.updatedAt <= existingFolder.updatedAt {
                        continue
                    }
                    try SnippetFolder.upsert { folder }.execute(database)
                    writtenCount += 1
                }
                for payload in snapshot.snippets {
                    guard try !isSuppressed(kind: .snippet, id: payload.id, database: database),
                          let snippet = payload.snippet else {
                        continue
                    }
                    if let existingSnippet = try Snippet.find(snippet.id).fetchOne(database),
                       payload.updatedAt <= existingSnippet.updatedAt {
                        continue
                    }
                    try Snippet.upsert { snippet }.execute(database)
                    writtenCount += 1
                }
                return writtenCount
            }
        } ?? 0
    }

    func updateFolderTitle(_ id: SnippetFolder.ID, title: String) {
        withErrorReporting {
            try database.write { database in
                try SnippetFolder.where { $0.id.eq(id) }
                    .update {
                        $0.title = title
                        $0.updatedAt = currentUnixTime()
                        $0.lastModifiedDeviceID = CPYUtilities.deviceID
                    }
                    .execute(database)
            }
        }
    }

    func updateFolderIsEnabled(_ id: SnippetFolder.ID, isEnabled: Bool) {
        withErrorReporting {
            try database.write { database in
                try SnippetFolder.where { $0.id.eq(id) }
                    .update {
                        $0.isEnabled = isEnabled
                        $0.updatedAt = currentUnixTime()
                        $0.lastModifiedDeviceID = CPYUtilities.deviceID
                    }
                    .execute(database)
            }
        }
    }

    func updateFolderIndexes(_ folderIDs: [SnippetFolder.ID]) {
        withErrorReporting {
            try database.write { database in
                try folderIDs.enumerated().forEach { index, folderID in
                    try SnippetFolder.where { $0.id.eq(folderID) }
                        .update {
                            $0.index = index
                            $0.updatedAt = currentUnixTime()
                            $0.lastModifiedDeviceID = CPYUtilities.deviceID
                        }
                        .execute(database)
                }
            }
        }
    }

    func deleteFolder(_ id: SnippetFolder.ID) {
        withErrorReporting {
            try database.write { database in
                try suppress(kind: .snippetFolder, id: id.rawValue.uuidString, database: database)
                let snippetIDs = try Snippet
                    .where { $0.folderID.eq(id) }
                    .select { $0.id }
                    .fetchAll(database)
                try snippetIDs.forEach { snippetID in
                    try suppress(kind: .snippet, id: snippetID.rawValue.uuidString, database: database)
                }
                try SnippetFolder.delete().where { $0.id.eq(id) }.execute(database)
            }
        }
    }

    func fetchSnippet(id: Snippet.ID) -> Snippet? {
        withErrorReporting {
            try database.read { database in
                try Snippet.find(id).fetchOne(database)
            }
        }
    }

    func insertSnippet(to id: SnippetFolder.ID) -> Snippet? {
        withErrorReporting {
            return try database.write { database in
                let lastIndex = try Snippet.where { $0.folderID.eq(id) }
                    .order { $0.index.desc() }
                    .select { $0.index }
                    .fetchOne(database) ?? -1
                let snippet = Snippet.Draft(
                    folderID: id,
                    title: "untitled snippet",
                    content: "",
                    index: lastIndex + 1,
                    isEnabled: true,
                    createdAt: currentUnixTime(),
                    updatedAt: currentUnixTime(),
                    lastModifiedDeviceID: CPYUtilities.deviceID
                )
                return try Snippet.insert { snippet }.returning(\.self).fetchOne(database)
            }
        }
    }

    func updateSnippetTitle(_ id: Snippet.ID, title: String) {
        withErrorReporting {
            try database.write { database in
                try Snippet.where { $0.id.eq(id) }
                    .update {
                        $0.title = title
                        $0.updatedAt = currentUnixTime()
                        $0.lastModifiedDeviceID = CPYUtilities.deviceID
                    }
                    .execute(database)
            }
        }
    }

    func updateSnippetContent(_ id: Snippet.ID, content: String) {
        withErrorReporting {
            try database.write { database in
                try Snippet.where { $0.id.eq(id) }
                    .update {
                        $0.content = content
                        $0.updatedAt = currentUnixTime()
                        $0.lastModifiedDeviceID = CPYUtilities.deviceID
                    }
                    .execute(database)
            }
        }
    }

    func updateSnippetIsEnabled(_ id: Snippet.ID, isEnabled: Bool) {
        withErrorReporting {
            try database.write { database in
                try Snippet.where { $0.id.eq(id) }
                    .update {
                        $0.isEnabled = isEnabled
                        $0.updatedAt = currentUnixTime()
                        $0.lastModifiedDeviceID = CPYUtilities.deviceID
                    }
                    .execute(database)
            }
        }
    }

    func updateSnippetIndexes(_ snippetIDs: [Snippet.ID]) {
        withErrorReporting {
            try database.write { database in
                try snippetIDs.enumerated().forEach { index, snippetID in
                    try Snippet.where { $0.id.eq(snippetID) }
                        .update {
                            $0.index = index
                            $0.updatedAt = currentUnixTime()
                            $0.lastModifiedDeviceID = CPYUtilities.deviceID
                        }
                        .execute(database)
                }
            }
        }
    }

    func moveSnippet(_ id: Snippet.ID, to folderID: SnippetFolder.ID, snippetIDs: [Snippet.ID]) {
        withErrorReporting {
            try database.write { database in
                try Snippet.where { $0.id.eq(id) }
                    .update {
                        $0.folderID = folderID
                        $0.updatedAt = currentUnixTime()
                        $0.lastModifiedDeviceID = CPYUtilities.deviceID
                    }
                    .execute(database)
                try snippetIDs.enumerated().forEach { index, snippetID in
                    try Snippet.where { $0.id.eq(snippetID) }
                        .update {
                            $0.index = index
                            $0.updatedAt = currentUnixTime()
                            $0.lastModifiedDeviceID = CPYUtilities.deviceID
                        }
                        .execute(database)
                }
            }
        }
    }

    func deleteSnippet(_ id: Snippet.ID) {
        withErrorReporting {
            try database.write { database in
                try suppress(kind: .snippet, id: id.rawValue.uuidString, database: database)
                try Snippet.delete().where { $0.id.eq(id) }.execute(database)
            }
        }
    }
}

private extension SnippetFolderSyncPayload {
    var snippetFolder: SnippetFolder? {
        guard let id = SnippetFolder.ID(uuidString: id) else { return nil }
        return SnippetFolder(
            id: id,
            title: title,
            index: index,
            isEnabled: isEnabled,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            lastModifiedDeviceID: deviceID
        )
    }
}

private extension SnippetSyncPayload {
    var snippet: Snippet? {
        guard let id = Snippet.ID(uuidString: id), let folderID = SnippetFolder.ID(uuidString: folderID) else {
            return nil
        }
        return Snippet(
            id: id,
            folderID: folderID,
            title: title,
            content: content,
            index: index,
            isEnabled: isEnabled,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            lastModifiedDeviceID: deviceID
        )
    }
}

private extension SnippetFolder.ID {
    init?(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else { return nil }
        self.init(rawValue: uuid)
    }
}

private extension Snippet.ID {
    init?(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else { return nil }
        self.init(rawValue: uuid)
    }
}

private extension SnippetRepository {
    func currentUnixTime() -> Int {
        Int(Date().timeIntervalSince1970)
    }

    func suppress(kind: SyncEntityKind, id: String, database: Database) throws {
        try SyncSuppression.upsert {
            SyncSuppression(
                syncIdentity: syncIdentity(kind: kind, id: id),
                kind: kind,
                recordID: id,
                suppressedAt: currentUnixTime()
            )
        }
        .execute(database)
    }

    func isSuppressed(kind: SyncEntityKind, id: String, database: Database) throws -> Bool {
        try SyncSuppression
            .find(syncIdentity(kind: kind, id: id))
            .fetchOne(database) != nil
    }

    func syncIdentity(kind: SyncEntityKind, id: String) -> String {
        "\(kind.rawValue):\(id)"
    }

    static func folderDetails(folders: [SnippetFolder], snippets: [Snippet]) -> [SnippetFolderDetail] {
        let snippetsByFolderID = Dictionary(grouping: snippets, by: \.folderID)
        return folders.map { folder in
            SnippetFolderDetail(
                folder: folder,
                snippets: snippetsByFolderID[folder.id] ?? []
            )
        }
    }
}

private enum SnippetRepositoryKey: DependencyKey {
    static var liveValue: any SnippetRepositoryProtocol { SnippetRepository() }
}

extension DependencyValues {
    var snippetRepository: SnippetRepositoryProtocol {
        get { self[SnippetRepositoryKey.self] }
        set { self[SnippetRepositoryKey.self] = newValue }
    }
}
