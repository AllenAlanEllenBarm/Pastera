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

struct SnippetFolderDeletionSyncPayload: Codable, Equatable {
    let id: String
    let title: String
    let deletedAt: Int
    let deviceID: String?

    init(
        id: String,
        title: String,
        deletedAt: Int,
        deviceID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.deletedAt = deletedAt
        self.deviceID = deviceID
    }
}

struct SnippetDeletionSyncPayload: Codable, Equatable {
    let id: String
    let folderID: String
    let folderTitle: String
    let content: String
    let deletedAt: Int
    let deviceID: String?

    init(
        id: String,
        folderID: String,
        folderTitle: String,
        content: String,
        deletedAt: Int,
        deviceID: String? = nil
    ) {
        self.id = id
        self.folderID = folderID
        self.folderTitle = folderTitle
        self.content = content
        self.deletedAt = deletedAt
        self.deviceID = deviceID
    }
}

struct SnippetSyncSnapshot: Codable, Equatable {
    let folders: [SnippetFolderSyncPayload]
    let snippets: [SnippetSyncPayload]
    let deletedFolders: [SnippetFolderDeletionSyncPayload]
    let deletedSnippets: [SnippetDeletionSyncPayload]

    init(
        folders: [SnippetFolderSyncPayload],
        snippets: [SnippetSyncPayload],
        deletedFolders: [SnippetFolderDeletionSyncPayload] = [],
        deletedSnippets: [SnippetDeletionSyncPayload] = []
    ) {
        self.folders = folders
        self.snippets = snippets
        self.deletedFolders = deletedFolders
        self.deletedSnippets = deletedSnippets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.folders = try container.decode([SnippetFolderSyncPayload].self, forKey: .folders)
        self.snippets = try container.decode([SnippetSyncPayload].self, forKey: .snippets)
        self.deletedFolders = try container.decodeIfPresent([SnippetFolderDeletionSyncPayload].self, forKey: .deletedFolders) ?? []
        self.deletedSnippets = try container.decodeIfPresent([SnippetDeletionSyncPayload].self, forKey: .deletedSnippets) ?? []
    }
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
    @discardableResult
    func removeDuplicateFoldersAndSnippets() -> Int
    @discardableResult
    func updateFolderTitle(_ id: SnippetFolder.ID, title: String) -> Bool
    func updateFolderIsEnabled(_ id: SnippetFolder.ID, isEnabled: Bool)
    func updateFolderIndexes(_ folderIDs: [SnippetFolder.ID])
    func reorderFolders(_ folderIDs: [SnippetFolder.ID]) -> Bool
    func deleteFolder(_ id: SnippetFolder.ID)

    func fetchSnippet(id: Snippet.ID) -> Snippet?
    func insertSnippet(to id: SnippetFolder.ID) -> Snippet?
    func updateSnippetTitle(_ id: Snippet.ID, title: String)
    @discardableResult
    func updateSnippetContent(_ id: Snippet.ID, content: String) -> Bool
    func updateSnippetIsEnabled(_ id: Snippet.ID, isEnabled: Bool)
    func updateSnippetIndexes(_ snippetIDs: [Snippet.ID])
    func moveSnippet(_ id: Snippet.ID, to folderID: SnippetFolder.ID, snippetIDs: [Snippet.ID])
    func moveSnippet(
        _ id: Snippet.ID,
        to folderID: SnippetFolder.ID,
        orderedSnippetIDsByFolder: [SnippetFolder.ID: [Snippet.ID]]
    ) -> Bool
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

    func reorderFolders(_ folderIDs: [SnippetFolder.ID]) -> Bool { false }

    func moveSnippet(
        _ id: Snippet.ID,
        to folderID: SnippetFolder.ID,
        orderedSnippetIDsByFolder: [SnippetFolder.ID: [Snippet.ID]]
    ) -> Bool { false }

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
                let deletions = try SnippetSyncDeletion.all.fetchAll(database)
                return SnippetSyncSnapshot(
                    folders: folders,
                    snippets: snippets,
                    deletedFolders: Self.deletedFolderPayloads(from: deletions),
                    deletedSnippets: Self.deletedSnippetPayloads(from: deletions)
                )
            }
        } ?? SnippetSyncSnapshot(folders: [], snippets: [])
    }

    func insertFolder() -> SnippetFolder? {
        withErrorReporting {
            return try database.write { database in
                let lastIndex = try SnippetFolder.order { $0.index.desc() }
                    .select { $0.index }
                    .fetchOne(database) ?? -1
                let title = try availableFolderTitle(database: database)
                let folder = SnippetFolder.Draft(
                    title: title,
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
                    if let existingFolder = try folder(title: folders.title, database: database) {
                        _ = try insertMissingSnippets(
                            folders.snippets,
                            to: existingFolder.id,
                            startingAt: lastSnippetIndex(folderID: existingFolder.id, database: database) + 1,
                            database: database
                        )
                        let snippets = try Snippet.where { $0.folderID.eq(existingFolder.id) }
                            .order(by: \.index)
                            .fetchAll(database)
                        details.append(SnippetFolderDetail(folder: existingFolder, snippets: snippets))
                        return
                    }
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
                    let insertedSnippets = try insertMissingSnippets(
                        folders.snippets,
                        to: insertedFolder.id,
                        startingAt: 0,
                        database: database
                    )
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
                try upsertSyncSnapshot(snapshot, database: database)
            }
        } ?? 0
    }

    @discardableResult
    func removeDuplicateFoldersAndSnippets() -> Int {
        withErrorReporting {
            try database.write { database in
                try removeDuplicateFoldersAndSnippets(database: database)
            }
        } ?? 0
    }

    @discardableResult
    func updateFolderTitle(_ id: SnippetFolder.ID, title: String) -> Bool {
        withErrorReporting {
            try database.write { database in
                guard try folder(title: title, excluding: id, database: database) == nil else {
                    return false
                }
                try SnippetFolder.where { $0.id.eq(id) }
                    .update {
                        $0.title = title
                        $0.updatedAt = currentUnixTime()
                        $0.lastModifiedDeviceID = CPYUtilities.deviceID
                    }
                    .execute(database)
                return true
            }
        } ?? false
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
                guard let folder = try SnippetFolder.find(id).fetchOne(database) else {
                    return
                }
                let deletedAt = currentUnixTime()
                try recordFolderDeletion(
                    id: folder.id.rawValue.uuidString,
                    title: folder.title,
                    deletedAt: deletedAt,
                    deviceID: CPYUtilities.deviceID,
                    database: database
                )
                try suppress(kind: .snippetFolder, id: id.rawValue.uuidString, database: database)
                let snippets = try Snippet
                    .where { $0.folderID.eq(id) }
                    .fetchAll(database)
                try snippets.forEach { snippet in
                    try recordSnippetDeletion(
                        id: snippet.id.rawValue.uuidString,
                        folderID: folder.id.rawValue.uuidString,
                        folderTitle: folder.title,
                        content: snippet.content,
                        deletedAt: deletedAt,
                        deviceID: CPYUtilities.deviceID,
                        database: database
                    )
                    try suppress(kind: .snippet, id: snippet.id.rawValue.uuidString, database: database)
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

    @discardableResult
    func updateSnippetContent(_ id: Snippet.ID, content: String) -> Bool {
        withErrorReporting {
            try database.write { database in
                guard let snippet = try Snippet.find(id).fetchOne(database),
                      try !hasSnippetContent(content, in: snippet.folderID, excluding: id, database: database) else {
                    return false
                }
                try Snippet.where { $0.id.eq(id) }
                    .update {
                        $0.content = content
                        $0.updatedAt = currentUnixTime()
                        $0.lastModifiedDeviceID = CPYUtilities.deviceID
                    }
                    .execute(database)
                return true
            }
        } ?? false
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
                guard let snippet = try Snippet.find(id).fetchOne(database),
                      let folder = try SnippetFolder.find(snippet.folderID).fetchOne(database) else {
                    return
                }
                try recordSnippetDeletion(
                    id: snippet.id.rawValue.uuidString,
                    folderID: folder.id.rawValue.uuidString,
                    folderTitle: folder.title,
                    content: snippet.content,
                    deletedAt: currentUnixTime(),
                    deviceID: CPYUtilities.deviceID,
                    database: database
                )
                try suppress(kind: .snippet, id: id.rawValue.uuidString, database: database)
                try Snippet.delete().where { $0.id.eq(id) }.execute(database)
            }
        }
    }
}

extension SnippetRepository {
    func reorderFolders(_ folderIDs: [SnippetFolder.ID]) -> Bool {
        withErrorReporting {
            try database.write { database in
                let existingIDs = try SnippetFolder.all.fetchAll(database).map(\.id)
                guard folderIDs.count == existingIDs.count, Set(folderIDs) == Set(existingIDs) else {
                    return false
                }
                try folderIDs.enumerated().forEach { index, folderID in
                    try SnippetFolder.where { $0.id.eq(folderID) }
                        .update {
                            $0.index = index
                            $0.updatedAt = currentUnixTime()
                            $0.lastModifiedDeviceID = CPYUtilities.deviceID
                        }
                        .execute(database)
                }
                return true
            }
        } ?? false
    }

    func moveSnippet(
        _ id: Snippet.ID,
        to folderID: SnippetFolder.ID,
        orderedSnippetIDsByFolder: [SnippetFolder.ID: [Snippet.ID]]
    ) -> Bool {
        withErrorReporting {
            try database.write { database in
                guard let movingSnippet = try Snippet.find(id).fetchOne(database),
                      try SnippetFolder.find(folderID).fetchOne(database) != nil else {
                    return false
                }
                let sourceFolderID = movingSnippet.folderID
                let affectedFolderIDs: Set<SnippetFolder.ID> = [sourceFolderID, folderID]
                guard Set(orderedSnippetIDsByFolder.keys) == affectedFolderIDs else { return false }
                let existingSnippets = try Snippet.all.fetchAll(database)
                for affectedFolderID in affectedFolderIDs {
                    guard let orderedIDs = orderedSnippetIDsByFolder[affectedFolderID],
                          orderedIDs.count == Set(orderedIDs).count else {
                        return false
                    }
                    var expectedIDs = Set(existingSnippets.filter { $0.folderID == affectedFolderID }.map(\.id))
                    if sourceFolderID == affectedFolderID { expectedIDs.remove(id) }
                    if folderID == affectedFolderID { expectedIDs.insert(id) }
                    guard Set(orderedIDs) == expectedIDs else { return false }
                }
                try Snippet.where { $0.id.eq(id) }
                    .update {
                        $0.folderID = folderID
                        $0.updatedAt = currentUnixTime()
                        $0.lastModifiedDeviceID = CPYUtilities.deviceID
                    }
                    .execute(database)
                for orderedIDs in orderedSnippetIDsByFolder.values {
                    try orderedIDs.enumerated().forEach { index, snippetID in
                        try Snippet.where { $0.id.eq(snippetID) }
                            .update {
                                $0.index = index
                                $0.updatedAt = currentUnixTime()
                                $0.lastModifiedDeviceID = CPYUtilities.deviceID
                            }
                            .execute(database)
                    }
                }
                return true
            }
        } ?? false
    }
}

extension SnippetFolderSyncPayload {
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

extension SnippetSyncPayload {
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

extension SnippetFolder.ID {
    init?(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else { return nil }
        self.init(rawValue: uuid)
    }
}

extension Snippet.ID {
    init?(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else { return nil }
        self.init(rawValue: uuid)
    }
}

extension SnippetRepository {
    func availableFolderTitle(baseTitle: String = "untitled folder", database: Database) throws -> String {
        let titles = Set(try SnippetFolder.all.select { $0.title }.fetchAll(database))
        guard titles.contains(baseTitle) else { return baseTitle }

        var suffix = 2
        while titles.contains("\(baseTitle) \(suffix)") {
            suffix += 1
        }
        return "\(baseTitle) \(suffix)"
    }

    func folder(
        title: String,
        excluding excludedID: SnippetFolder.ID? = nil,
        database: Database
    ) throws -> SnippetFolder? {
        try SnippetFolder.where { $0.title.eq(title) }
            .fetchAll(database)
            .first { folder in
                guard let excludedID else { return true }
                return folder.id != excludedID
            }
    }

    func hasSnippetContent(
        _ content: String,
        in folderID: SnippetFolder.ID,
        excluding excludedID: Snippet.ID? = nil,
        database: Database
    ) throws -> Bool {
        try Snippet.where { $0.folderID.eq(folderID) }
            .fetchAll(database)
            .contains { snippet in
                guard snippet.content == content else { return false }
                guard let excludedID else { return true }
                return snippet.id != excludedID
            }
    }

    func lastSnippetIndex(folderID: SnippetFolder.ID, database: Database) throws -> Int {
        try Snippet.where { $0.folderID.eq(folderID) }
            .order { $0.index.desc() }
            .select { $0.index }
            .fetchOne(database) ?? -1
    }

    func insertMissingSnippets(
        _ snippets: [(title: String, content: String)],
        to folderID: SnippetFolder.ID,
        startingAt index: Int,
        database: Database
    ) throws -> [Snippet] {
        var insertedSnippets = [Snippet]()
        var nextIndex = index
        for snippet in snippets {
            guard try !hasSnippetContent(snippet.content, in: folderID, database: database) else {
                continue
            }
            let draft = Snippet.Draft(
                folderID: folderID,
                title: snippet.title,
                content: snippet.content,
                index: nextIndex,
                isEnabled: true,
                createdAt: currentUnixTime(),
                updatedAt: currentUnixTime(),
                lastModifiedDeviceID: CPYUtilities.deviceID
            )
            if let insertedSnippet = try Snippet.insert { draft }.returning(\.self).fetchOne(database) {
                insertedSnippets.append(insertedSnippet)
                nextIndex += 1
            }
        }
        return insertedSnippets
    }

    func removeDuplicateFoldersAndSnippets(database: Database) throws -> Int {
        var changedCount = 0
        let folders = try SnippetFolder.all.order(by: \.index).fetchAll(database)
        let foldersByTitle = Dictionary(grouping: folders, by: \.title)
        for duplicateFolders in foldersByTitle.values where duplicateFolders.count > 1 {
            let canonicalFolder = duplicateFolders.sorted(by: isPreferredFolder).first
            guard let canonicalFolder else { continue }

            for duplicateFolder in duplicateFolders where duplicateFolder.id != canonicalFolder.id {
                try suppress(kind: .snippetFolder, id: duplicateFolder.id.rawValue.uuidString, database: database)
                let duplicateSnippets = try Snippet.where { $0.folderID.eq(duplicateFolder.id) }
                    .order(by: \.index)
                    .fetchAll(database)
                for snippet in duplicateSnippets {
                    if try hasSnippetContent(snippet.content, in: canonicalFolder.id, database: database) {
                        try suppress(kind: .snippet, id: snippet.id.rawValue.uuidString, database: database)
                        try Snippet.delete().where { $0.id.eq(snippet.id) }.execute(database)
                        changedCount += 1
                    } else {
                        let nextIndex = try lastSnippetIndex(folderID: canonicalFolder.id, database: database) + 1
                        try Snippet.where { $0.id.eq(snippet.id) }
                            .update {
                                $0.folderID = canonicalFolder.id
                                $0.index = nextIndex
                                $0.updatedAt = currentUnixTime()
                                $0.lastModifiedDeviceID = CPYUtilities.deviceID
                            }
                            .execute(database)
                    }
                }
                try SnippetFolder.delete().where { $0.id.eq(duplicateFolder.id) }.execute(database)
                changedCount += 1
            }
        }

        let remainingFolders = try SnippetFolder.all.fetchAll(database)
        for folder in remainingFolders {
            changedCount += try removeDuplicateSnippets(in: folder.id, database: database)
        }
        return changedCount
    }

    func removeDuplicateSnippets(in folderID: SnippetFolder.ID, database: Database) throws -> Int {
        var changedCount = 0
        let snippets = try Snippet.where { $0.folderID.eq(folderID) }
            .order(by: \.index)
            .fetchAll(database)
        let snippetsByContent = Dictionary(grouping: snippets, by: \.content)
        for duplicateSnippets in snippetsByContent.values where duplicateSnippets.count > 1 {
            let canonicalSnippet = duplicateSnippets.sorted(by: isPreferredSnippet).first
            guard let canonicalSnippet else { continue }
            for snippet in duplicateSnippets where snippet.id != canonicalSnippet.id {
                try suppress(kind: .snippet, id: snippet.id.rawValue.uuidString, database: database)
                try Snippet.delete().where { $0.id.eq(snippet.id) }.execute(database)
                changedCount += 1
            }
        }
        return changedCount
    }

    func isPreferredFolder(_ lhs: SnippetFolder, _ rhs: SnippetFolder) -> Bool {
        if lhs.index != rhs.index {
            return lhs.index < rhs.index
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
    }

    func isPreferredSnippet(_ lhs: Snippet, _ rhs: Snippet) -> Bool {
        if lhs.index != rhs.index {
            return lhs.index < rhs.index
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
    }

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

    func unsuppress(kind: SyncEntityKind, id: String, database: Database) throws {
        try SyncSuppression.delete()
            .where { $0.syncIdentity.eq(syncIdentity(kind: kind, id: id)) }
            .execute(database)
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
