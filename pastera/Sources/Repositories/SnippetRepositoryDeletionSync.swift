//
//  SnippetRepositoryDeletionSync.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by OpenAI on 2026/06/26.
//
//  Copyright © 2015-2026 Clipy Project.
//

import Foundation
import SQLiteData

extension SnippetRepository {
    func upsertSyncSnapshot(_ snapshot: SnippetSyncSnapshot, database: Database) throws -> Int {
        _ = try removeDuplicateFoldersAndSnippets(database: database)
        var writtenCount = 0
        var folderIDMap = [String: SnippetFolder.ID]()
        writtenCount += try applyRemoteFolderDeletions(snapshot.deletedFolders, database: database)
        writtenCount += try applyRemoteSnippetDeletions(snapshot.deletedSnippets, database: database)
        writtenCount += try upsertFolderPayloads(snapshot.folders, folderIDMap: &folderIDMap, database: database)
        writtenCount += try upsertSnippetPayloads(snapshot.snippets, folderIDMap: folderIDMap, database: database)
        return writtenCount
    }

    func upsertFolderPayloads(
        _ payloads: [SnippetFolderSyncPayload],
        folderIDMap: inout [String: SnippetFolder.ID],
        database: Database
    ) throws -> Int {
        var writtenCount = 0
        for payload in payloads {
            guard let folder = payload.snippetFolder else { continue }
            if try hasBlockingFolderDeletion(payload: payload, database: database) {
                try suppress(kind: .snippetFolder, id: payload.id, database: database)
                continue
            }
            let hasStaleDeletion = try hasFolderDeletion(payload: payload, database: database)
            if try isSuppressed(kind: .snippetFolder, id: payload.id, database: database),
               !hasStaleDeletion {
                if let existingFolder = try self.folder(title: payload.title, database: database) {
                    folderIDMap[payload.id] = existingFolder.id
                }
                continue
            }
            if let existingFolder = try SnippetFolder.find(folder.id).fetchOne(database),
               payload.updatedAt <= existingFolder.updatedAt {
                folderIDMap[payload.id] = existingFolder.id
                continue
            }
            if let existingFolder = try self.folder(title: payload.title, excluding: folder.id, database: database) {
                folderIDMap[payload.id] = existingFolder.id
                if hasStaleDeletion {
                    try clearFolderDeletionTombstones(payload: payload, database: database)
                    try unsuppress(kind: .snippetFolder, id: payload.id, database: database)
                }
                try suppress(kind: .snippetFolder, id: payload.id, database: database)
                continue
            }
            if hasStaleDeletion {
                try clearFolderDeletionTombstones(payload: payload, database: database)
                try unsuppress(kind: .snippetFolder, id: payload.id, database: database)
            }
            try SnippetFolder.upsert { folder }.execute(database)
            folderIDMap[payload.id] = folder.id
            writtenCount += 1
        }
        return writtenCount
    }

    func upsertSnippetPayloads(
        _ payloads: [SnippetSyncPayload],
        folderIDMap: [String: SnippetFolder.ID],
        database: Database
    ) throws -> Int {
        var writtenCount = 0
        for payload in payloads {
            guard let snippet = payload.snippet else { continue }
            let targetFolderID = folderIDMap[payload.folderID] ?? snippet.folderID
            guard let targetFolder = try SnippetFolder.find(targetFolderID).fetchOne(database) else { continue }
            if try hasBlockingSnippetDeletion(
                payload: payload,
                targetFolderID: targetFolderID,
                folderTitle: targetFolder.title,
                database: database
            ) {
                try suppress(kind: .snippet, id: payload.id, database: database)
                continue
            }
            let hasStaleDeletion = try hasSnippetDeletion(
                payload: payload,
                targetFolderID: targetFolderID,
                folderTitle: targetFolder.title,
                database: database
            )
            if try isSuppressed(kind: .snippet, id: payload.id, database: database),
               !hasStaleDeletion {
                continue
            }
            let mappedSnippet = Snippet(
                id: snippet.id,
                folderID: targetFolderID,
                title: snippet.title,
                content: snippet.content,
                index: snippet.index,
                isEnabled: snippet.isEnabled,
                createdAt: snippet.createdAt,
                updatedAt: snippet.updatedAt,
                lastModifiedDeviceID: snippet.lastModifiedDeviceID
            )
            if let existingSnippet = try Snippet.find(snippet.id).fetchOne(database),
               payload.updatedAt <= existingSnippet.updatedAt {
                continue
            }
            if try hasSnippetContent(
                mappedSnippet.content,
                in: targetFolderID,
                excluding: mappedSnippet.id,
                database: database
            ) {
                try suppress(kind: .snippet, id: payload.id, database: database)
                if try Snippet.find(mappedSnippet.id).fetchOne(database) != nil {
                    try Snippet.delete().where { $0.id.eq(mappedSnippet.id) }.execute(database)
                }
                try clearStaleSnippetDeletion(
                    hasStaleDeletion,
                    payload: payload,
                    targetFolderID: targetFolderID,
                    folderTitle: targetFolder.title,
                    database: database
                )
                continue
            }
            try clearStaleSnippetDeletion(
                hasStaleDeletion,
                payload: payload,
                targetFolderID: targetFolderID,
                folderTitle: targetFolder.title,
                database: database
            )
            try Snippet.upsert { mappedSnippet }.execute(database)
            writtenCount += 1
        }
        return writtenCount
    }

    func clearStaleSnippetDeletion(
        _ hasStaleDeletion: Bool,
        payload: SnippetSyncPayload,
        targetFolderID: SnippetFolder.ID,
        folderTitle: String,
        database: Database
    ) throws {
        guard hasStaleDeletion else { return }
        try clearSnippetDeletionTombstones(
            payload: payload,
            targetFolderID: targetFolderID,
            folderTitle: folderTitle,
            database: database
        )
        try unsuppress(kind: .snippet, id: payload.id, database: database)
    }

    func applyRemoteFolderDeletions(
        _ deletions: [SnippetFolderDeletionSyncPayload],
        database: Database
    ) throws -> Int {
        var writtenCount = 0
        for deletion in deletions {
            guard let folder = try folderForDeletion(deletion, database: database) else {
                try recordFolderDeletion(deletion, database: database)
                try suppress(kind: .snippetFolder, id: deletion.id, database: database)
                continue
            }
            guard folder.updatedAt <= deletion.deletedAt else { continue }

            try recordFolderDeletion(deletion, database: database)
            try recordFolderDeletion(
                id: folder.id.rawValue.uuidString,
                title: folder.title,
                deletedAt: deletion.deletedAt,
                deviceID: deletion.deviceID,
                database: database
            )
            try suppress(kind: .snippetFolder, id: deletion.id, database: database)
            try suppress(kind: .snippetFolder, id: folder.id.rawValue.uuidString, database: database)
            let snippets = try Snippet.where { $0.folderID.eq(folder.id) }.fetchAll(database)
            for snippet in snippets {
                try recordSnippetDeletion(
                    id: snippet.id.rawValue.uuidString,
                    folderID: folder.id.rawValue.uuidString,
                    folderTitle: folder.title,
                    content: snippet.content,
                    deletedAt: deletion.deletedAt,
                    deviceID: deletion.deviceID,
                    database: database
                )
                try suppress(kind: .snippet, id: snippet.id.rawValue.uuidString, database: database)
            }
            try SnippetFolder.delete().where { $0.id.eq(folder.id) }.execute(database)
            writtenCount += 1
        }
        return writtenCount
    }

    func applyRemoteSnippetDeletions(
        _ deletions: [SnippetDeletionSyncPayload],
        database: Database
    ) throws -> Int {
        var writtenCount = 0
        for deletion in deletions {
            let snippets = try snippetsForDeletion(deletion, database: database)
            guard !snippets.isEmpty else {
                try recordSnippetDeletion(deletion, database: database)
                try suppress(kind: .snippet, id: deletion.id, database: database)
                continue
            }
            var deletedAnySnippet = false
            for snippet in snippets {
                guard snippet.updatedAt <= deletion.deletedAt,
                      let folder = try SnippetFolder.find(snippet.folderID).fetchOne(database) else {
                    continue
                }
                try recordSnippetDeletion(deletion, database: database)
                try recordSnippetDeletion(
                    id: snippet.id.rawValue.uuidString,
                    folderID: folder.id.rawValue.uuidString,
                    folderTitle: folder.title,
                    content: snippet.content,
                    deletedAt: deletion.deletedAt,
                    deviceID: deletion.deviceID,
                    database: database
                )
                try suppress(kind: .snippet, id: deletion.id, database: database)
                try suppress(kind: .snippet, id: snippet.id.rawValue.uuidString, database: database)
                try Snippet.delete().where { $0.id.eq(snippet.id) }.execute(database)
                writtenCount += 1
                deletedAnySnippet = true
            }
            if !deletedAnySnippet {
                try unsuppress(kind: .snippet, id: deletion.id, database: database)
            }
        }
        return writtenCount
    }
}

extension SnippetRepository {
    func folderForDeletion(
        _ deletion: SnippetFolderDeletionSyncPayload,
        database: Database
    ) throws -> SnippetFolder? {
        if let id = SnippetFolder.ID(uuidString: deletion.id),
           let folder = try SnippetFolder.find(id).fetchOne(database) {
            return folder
        }
        return try folder(title: deletion.title, database: database)
    }

    func snippetsForDeletion(
        _ deletion: SnippetDeletionSyncPayload,
        database: Database
    ) throws -> [Snippet] {
        var snippets = [Snippet]()
        var ids = Set<String>()
        if let id = Snippet.ID(uuidString: deletion.id),
           let snippet = try Snippet.find(id).fetchOne(database) {
            snippets.append(snippet)
            ids.insert(snippet.id.rawValue.uuidString)
        }
        let folderID = try targetFolderID(
            remoteFolderID: deletion.folderID,
            folderTitle: deletion.folderTitle,
            database: database
        )
        guard let folderID else { return snippets }
        let contentMatches = try Snippet.where { $0.folderID.eq(folderID) }
            .fetchAll(database)
            .filter { $0.content == deletion.content }
        for snippet in contentMatches where !ids.contains(snippet.id.rawValue.uuidString) {
            snippets.append(snippet)
            ids.insert(snippet.id.rawValue.uuidString)
        }
        return snippets
    }

    func targetFolderID(
        remoteFolderID: String,
        folderTitle: String,
        database: Database
    ) throws -> SnippetFolder.ID? {
        if let id = SnippetFolder.ID(uuidString: remoteFolderID),
           try SnippetFolder.find(id).fetchOne(database) != nil {
            return id
        }
        return try folder(title: folderTitle, database: database)?.id
    }

    func hasBlockingFolderDeletion(
        payload: SnippetFolderSyncPayload,
        database: Database
    ) throws -> Bool {
        try folderDeletionRows(database: database).contains {
            isFolderDeletion($0, matchedBy: payload) && $0.deletedAt >= payload.updatedAt
        }
    }

    func hasFolderDeletion(
        payload: SnippetFolderSyncPayload,
        database: Database
    ) throws -> Bool {
        try folderDeletionRows(database: database).contains { isFolderDeletion($0, matchedBy: payload) }
    }

    func hasBlockingSnippetDeletion(
        payload: SnippetSyncPayload,
        targetFolderID: SnippetFolder.ID,
        folderTitle: String,
        database: Database
    ) throws -> Bool {
        try snippetDeletionRows(database: database).contains {
            isSnippetDeletion($0, matchedBy: payload, targetFolderID: targetFolderID, folderTitle: folderTitle)
                && $0.deletedAt >= payload.updatedAt
        }
    }

    func hasSnippetDeletion(
        payload: SnippetSyncPayload,
        targetFolderID: SnippetFolder.ID,
        folderTitle: String,
        database: Database
    ) throws -> Bool {
        try snippetDeletionRows(database: database).contains {
            isSnippetDeletion($0, matchedBy: payload, targetFolderID: targetFolderID, folderTitle: folderTitle)
        }
    }

    func isFolderDeletion(
        _ deletion: SnippetSyncDeletion,
        matchedBy payload: SnippetFolderSyncPayload
    ) -> Bool {
        deletion.recordID == payload.id || deletion.folderTitle == payload.title
    }

    func isSnippetDeletion(
        _ deletion: SnippetSyncDeletion,
        matchedBy payload: SnippetSyncPayload,
        targetFolderID: SnippetFolder.ID,
        folderTitle: String
    ) -> Bool {
        if deletion.recordID == payload.id {
            return true
        }
        let folderID = targetFolderID.rawValue.uuidString
        return deletion.content == payload.content
            && (deletion.folderID == folderID || deletion.folderTitle == folderTitle)
    }

    func folderDeletionRows(database: Database) throws -> [SnippetSyncDeletion] {
        try SnippetSyncDeletion.all.fetchAll(database).filter { $0.kind == .snippetFolder }
    }

    func snippetDeletionRows(database: Database) throws -> [SnippetSyncDeletion] {
        try SnippetSyncDeletion.all.fetchAll(database).filter { $0.kind == .snippet }
    }
}

extension SnippetRepository {
    func recordFolderDeletion(
        _ deletion: SnippetFolderDeletionSyncPayload,
        database: Database
    ) throws {
        try recordFolderDeletion(
            id: deletion.id,
            title: deletion.title,
            deletedAt: deletion.deletedAt,
            deviceID: deletion.deviceID,
            database: database
        )
    }

    func recordFolderDeletion(
        id: String,
        title: String,
        deletedAt: Int,
        deviceID: String?,
        database: Database
    ) throws {
        try SnippetSyncDeletion.upsert {
            SnippetSyncDeletion(
                syncIdentity: syncIdentity(kind: .snippetFolder, id: id),
                kind: .snippetFolder,
                recordID: id,
                folderID: nil,
                folderTitle: title,
                content: "",
                deletedAt: deletedAt,
                deviceID: deviceID
            )
        }
        .execute(database)
    }

    func recordSnippetDeletion(
        _ deletion: SnippetDeletionSyncPayload,
        database: Database
    ) throws {
        try recordSnippetDeletion(
            id: deletion.id,
            folderID: deletion.folderID,
            folderTitle: deletion.folderTitle,
            content: deletion.content,
            deletedAt: deletion.deletedAt,
            deviceID: deletion.deviceID,
            database: database
        )
    }

    func recordSnippetDeletion(
        id: String,
        folderID: String,
        folderTitle: String,
        content: String,
        deletedAt: Int,
        deviceID: String?,
        database: Database
    ) throws {
        try SnippetSyncDeletion.upsert {
            SnippetSyncDeletion(
                syncIdentity: syncIdentity(kind: .snippet, id: id),
                kind: .snippet,
                recordID: id,
                folderID: folderID,
                folderTitle: folderTitle,
                content: content,
                deletedAt: deletedAt,
                deviceID: deviceID
            )
        }
        .execute(database)
    }

    func clearFolderDeletionTombstones(
        payload: SnippetFolderSyncPayload,
        database: Database
    ) throws {
        for deletion in try folderDeletionRows(database: database) where isFolderDeletion(deletion, matchedBy: payload) {
            try deleteDeletion(deletion, database: database)
        }
    }

    func clearSnippetDeletionTombstones(
        payload: SnippetSyncPayload,
        targetFolderID: SnippetFolder.ID,
        folderTitle: String,
        database: Database
    ) throws {
        for deletion in try snippetDeletionRows(database: database) where isSnippetDeletion(
            deletion,
            matchedBy: payload,
            targetFolderID: targetFolderID,
            folderTitle: folderTitle
        ) {
            try deleteDeletion(deletion, database: database)
        }
    }

    func deleteDeletion(_ deletion: SnippetSyncDeletion, database: Database) throws {
        try SnippetSyncDeletion.delete()
            .where { $0.syncIdentity.eq(deletion.syncIdentity) }
            .execute(database)
    }
}

extension SnippetRepository {
    static func deletedFolderPayloads(
        from deletions: [SnippetSyncDeletion]
    ) -> [SnippetFolderDeletionSyncPayload] {
        deletions
            .filter { $0.kind == .snippetFolder }
            .sorted(by: isPreferredDeletion)
            .map {
                SnippetFolderDeletionSyncPayload(
                    id: $0.recordID,
                    title: $0.folderTitle,
                    deletedAt: $0.deletedAt,
                    deviceID: $0.deviceID
                )
            }
    }

    static func deletedSnippetPayloads(
        from deletions: [SnippetSyncDeletion]
    ) -> [SnippetDeletionSyncPayload] {
        deletions
            .filter { $0.kind == .snippet }
            .sorted(by: isPreferredDeletion)
            .map {
                SnippetDeletionSyncPayload(
                    id: $0.recordID,
                    folderID: $0.folderID ?? "",
                    folderTitle: $0.folderTitle,
                    content: $0.content,
                    deletedAt: $0.deletedAt,
                    deviceID: $0.deviceID
                )
            }
    }

    static func isPreferredDeletion(_ lhs: SnippetSyncDeletion, _ rhs: SnippetSyncDeletion) -> Bool {
        if lhs.deletedAt != rhs.deletedAt {
            return lhs.deletedAt < rhs.deletedAt
        }
        return lhs.recordID < rhs.recordID
    }
}
