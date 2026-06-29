//
//  SnippetRepositoryDeletionSyncTests.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by OpenAI on 2026/06/26.
//
//  Copyright © 2015-2026 Clipy Project.
//

import Dependencies
import DependenciesTestSupport
import Foundation
import Testing
@testable import Pastera

@MainActor
@Suite(
    .dependencies {
        try $0.bootstrapDatabase()
    }
)
struct SnippetRepositoryDeletionSyncTests {
    let repository: SnippetRepository

    init() {
        self.repository = SnippetRepository()
    }

    @Test
    func syncImportDeletesLocalSnippetWhenRemoteDeletionIsNewer() throws {
        let folder = try #require(repository.insertFolder())
        #expect(repository.updateFolderTitle(folder.id, title: "AI Prompt"))
        let snippet = try #require(repository.insertSnippet(to: folder.id))
        #expect(repository.updateSnippetContent(snippet.id, content: "shared"))
        let localSnippet = try #require(repository.fetchSnippet(id: snippet.id))

        let deletedAt = localSnippet.updatedAt + 10
        let writtenCount = repository.upsertSyncSnapshot(SnippetSyncSnapshot(
            folders: [],
            snippets: [],
            deletedSnippets: [
                SnippetDeletionSyncPayload(
                    id: snippet.id.rawValue.uuidString,
                    folderID: folder.id.rawValue.uuidString,
                    folderTitle: "AI Prompt",
                    content: "shared",
                    deletedAt: deletedAt,
                    deviceID: "remote-device"
                )
            ]
        ))

        #expect(writtenCount == 1)
        #expect(repository.fetchSnippet(id: snippet.id) == nil)
        #expect(repository.fetchFolderDetail(id: folder.id) != nil)
        let exportedDeletion = try #require(repository.fetchSyncSnapshot().deletedSnippets.first)
        #expect(exportedDeletion.id == snippet.id.rawValue.uuidString)
        #expect(exportedDeletion.folderTitle == "AI Prompt")
        #expect(exportedDeletion.content == "shared")
        #expect(exportedDeletion.deletedAt == deletedAt)
    }

    @Test
    func syncImportKeepsLocalSnippetWhenLocalUpdateIsNewerThanRemoteDeletion() throws {
        let folder = try #require(repository.insertFolder())
        #expect(repository.updateFolderTitle(folder.id, title: "AI Prompt"))
        let snippet = try #require(repository.insertSnippet(to: folder.id))
        #expect(repository.updateSnippetContent(snippet.id, content: "local wins"))
        let localSnippet = try #require(repository.fetchSnippet(id: snippet.id))

        let writtenCount = repository.upsertSyncSnapshot(SnippetSyncSnapshot(
            folders: [],
            snippets: [],
            deletedSnippets: [
                SnippetDeletionSyncPayload(
                    id: snippet.id.rawValue.uuidString,
                    folderID: folder.id.rawValue.uuidString,
                    folderTitle: "AI Prompt",
                    content: "local wins",
                    deletedAt: localSnippet.updatedAt - 1,
                    deviceID: "remote-device"
                )
            ]
        ))

        #expect(writtenCount == 0)
        #expect(repository.fetchSnippet(id: snippet.id)?.content == "local wins")
        #expect(repository.fetchSyncSnapshot().deletedSnippets.isEmpty)
    }

    @Test
    func deletingLocalSnippetExportsDeletionTombstone() throws {
        let folder = try #require(repository.insertFolder())
        #expect(repository.updateFolderTitle(folder.id, title: "AI Prompt"))
        let snippet = try #require(repository.insertSnippet(to: folder.id))
        #expect(repository.updateSnippetContent(snippet.id, content: "delete me"))

        repository.deleteSnippet(snippet.id)

        let snapshot = repository.fetchSyncSnapshot()
        #expect(snapshot.snippets.isEmpty)
        let deletion = try #require(snapshot.deletedSnippets.first)
        #expect(deletion.id == snippet.id.rawValue.uuidString)
        #expect(deletion.folderID == folder.id.rawValue.uuidString)
        #expect(deletion.folderTitle == "AI Prompt")
        #expect(deletion.content == "delete me")
        #expect(deletion.deviceID == CPYUtilities.deviceID)
    }
}
