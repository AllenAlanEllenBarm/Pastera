//
//  SnippetRepositoryTests.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Shunsuke Furubayashi on 2026/05/26.
//
//  Copyright © 2015-2026 Clipy Project.
//

import Combine
import Dependencies
import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing
@testable import Pastera

@MainActor
@Suite(
    .dependencies {
        try $0.bootstrapDatabase()
    }
)
struct SnippetRepositoryTests {
    let repository: SnippetRepository

    init() {
        self.repository = SnippetRepository()
    }

    @Test(.timeLimit(.minutes(1)))
    func observeFolderDetails() async throws {
        var folderDetails = [[SnippetFolderDetail]]()
        let cancellable = repository.observeFolderDetails().sink { value in
            folderDetails.append(value)
        }
        defer { _ = cancellable }

        try await waitUntil { folderDetails.count >= 1 }

        let folder = try #require(repository.insertFolder())
        try await waitUntil { folderDetails.count >= 2 }

        let snippet = try #require(repository.insertSnippet(to: folder.id))
        try await waitUntil { folderDetails.count >= 3 }

        let snippet2 = try #require(repository.insertSnippet(to: folder.id))
        try await waitUntil { folderDetails.count >= 4 }

        let folder2 = try #require(repository.insertFolder())
        try await waitUntil { folderDetails.count >= 5 }

        #expect(
            folderDetails == [
                [],
                [SnippetFolderDetail(folder: folder, snippets: [])],
                [SnippetFolderDetail(folder: folder, snippets: [snippet])],
                [SnippetFolderDetail(folder: folder, snippets: [snippet, snippet2])],
                [SnippetFolderDetail(folder: folder, snippets: [snippet, snippet2]), SnippetFolderDetail(folder: folder2, snippets: [])]
            ]
        )
    }

    @Test
    func insertFoldersAndSnippetsMaintainsOrderedFolderDetails() throws {
        #expect(repository.fetchFolderDetails().isEmpty)

        let folder = try #require(repository.insertFolder())
        #expect(folder.title == "untitled folder")
        #expect(folder.index == 0)
        #expect(folder.isEnabled)

        #expect(repository.fetchFolderDetails() == [SnippetFolderDetail(folder: folder, snippets: [])])
        #expect(repository.fetchFolderDetail(id: folder.id) == SnippetFolderDetail(folder: folder, snippets: []))

        let snippet = try #require(repository.insertSnippet(to: folder.id))
        #expect(snippet.folderID == folder.id)
        #expect(snippet.title == "untitled snippet")
        #expect(snippet.content == "")
        #expect(snippet.index == 0)
        #expect(snippet.isEnabled)

        #expect(repository.fetchFolderDetails() == [SnippetFolderDetail(folder: folder, snippets: [snippet])])
        #expect(repository.fetchFolderDetail(id: folder.id) == SnippetFolderDetail(folder: folder, snippets: [snippet]))
        #expect(repository.fetchSnippet(id: snippet.id) == snippet)

        let snippet2 = try #require(repository.insertSnippet(to: folder.id))
        #expect(snippet2.folderID == folder.id)
        #expect(snippet2.title == "untitled snippet")
        #expect(snippet2.content == "")
        #expect(snippet2.index == 1)
        #expect(snippet2.isEnabled)

        #expect(repository.fetchFolderDetails() == [SnippetFolderDetail(folder: folder, snippets: [snippet, snippet2])])
        #expect(repository.fetchFolderDetail(id: folder.id) == SnippetFolderDetail(folder: folder, snippets: [snippet, snippet2]))
        #expect(repository.fetchSnippet(id: snippet2.id) == snippet2)

        let folder2 = try #require(repository.insertFolder())
        #expect(folder2.title == "untitled folder 2")
        #expect(folder2.index == 1)
        #expect(folder2.isEnabled)

        #expect(
            repository.fetchFolderDetails() == [
                SnippetFolderDetail(folder: folder, snippets: [snippet, snippet2]),
                SnippetFolderDetail(folder: folder2, snippets: [])
            ]
        )
        #expect(repository.fetchFolderDetail(id: folder2.id) == SnippetFolderDetail(folder: folder2, snippets: []))
    }

    @Test
    func insertFolderUsesNextAvailableDefaultTitle() throws {
        let folder = try #require(repository.insertFolder())
        let folder2 = try #require(repository.insertFolder())
        let folder3 = try #require(repository.insertFolder())

        #expect(folder.title == "untitled folder")
        #expect(folder2.title == "untitled folder 2")
        #expect(folder3.title == "untitled folder 3")
    }

    @Test
    func fetchFoldersReturnsOnlyOrderedFolderMetadata() throws {
        let folder = try #require(repository.insertFolder())
        _ = try #require(repository.insertSnippet(to: folder.id))
        let folder2 = try #require(repository.insertFolder())

        #expect(repository.fetchFolders() == [folder, folder2])
    }

    @Test(.timeLimit(.minutes(1)))
    func observeFoldersEmitsFolderMetadataChanges() async throws {
        var folders = [[SnippetFolder]]()
        let cancellable = repository.observeFolders().sink { value in
            folders.append(value)
        }
        defer { _ = cancellable }

        try await waitUntil { folders.count >= 1 }

        let folder = try #require(repository.insertFolder())
        try await waitUntil { folders.count >= 2 }

        _ = try #require(repository.insertSnippet(to: folder.id))
        try await Task.sleep(nanoseconds: 80_000_000)

        #expect(folders == [[], [folder]])
    }

    @Test
    func insertFolders() throws {
        let inserted = try #require(
            repository.insertFolders([
                (title: "Empty", snippets: []),
                (
                    title: "Filled",
                    snippets: [
                        (title: "First", content: "one"),
                        (title: "Second", content: "two")
                    ]
                )
            ])
        )
        #expect(inserted.count == 2)
        #expect(inserted.map(\.folder.title) == ["Empty", "Filled"])
        #expect(inserted.map(\.folder.index) == [0, 1])
        #expect(inserted[0].snippets.isEmpty)
        #expect(inserted[1].snippets.map(\.title) == ["First", "Second"])
        #expect(inserted[1].snippets.map(\.content) == ["one", "two"])
        #expect(inserted[1].snippets.map(\.index) == [0, 1])
    }

    @Test
    func updateFolder() throws {
        let folder = try #require(repository.insertFolder())

        #expect(repository.updateFolderTitle(folder.id, title: "Updated"))
        #expect(repository.fetchFolderDetail(id: folder.id)?.folder.title == "Updated")

        repository.updateFolderIsEnabled(folder.id, isEnabled: false)
        #expect(repository.fetchFolderDetail(id: folder.id)?.folder.isEnabled == false)

        let folder2 = try #require(repository.insertFolder())
        repository.updateFolderIndexes([folder2.id, folder.id])
        #expect(repository.fetchFolderDetail(id: folder2.id)?.folder.index == 0)
        #expect(repository.fetchFolderDetail(id: folder.id)?.folder.index == 1)
        #expect(repository.fetchFolderDetails().map(\.folder.id) == [folder2.id, folder.id])
    }

    @Test
    func updateFolderTitleRejectsExactDuplicateButAllowsCaseDifference() throws {
        let folder = try #require(repository.insertFolder())
        let folder2 = try #require(repository.insertFolder())

        #expect(repository.updateFolderTitle(folder.id, title: "AI Prompt"))
        #expect(!repository.updateFolderTitle(folder2.id, title: "AI Prompt"))
        #expect(repository.fetchFolderDetail(id: folder2.id)?.folder.title == "untitled folder 2")

        #expect(repository.updateFolderTitle(folder2.id, title: "ai prompt"))
        #expect(repository.fetchFolderDetails().map(\.folder.title) == ["AI Prompt", "ai prompt"])
    }

    @Test
    func deleteFolder() throws {
        let folder = try #require(repository.insertFolder())
        let snippet = try #require(repository.insertSnippet(to: folder.id))

        repository.deleteFolder(folder.id)
        #expect(repository.fetchFolderDetails().isEmpty)
        #expect(repository.fetchSnippet(id: snippet.id) == nil)
    }

    @Test
    func updateSnippet() throws {
        let folder = try #require(repository.insertFolder())
        let snippet = try #require(repository.insertSnippet(to: folder.id))

        repository.updateSnippetTitle(snippet.id, title: "Updated")
        #expect(repository.fetchSnippet(id: snippet.id)?.title == "Updated")

        #expect(repository.updateSnippetContent(snippet.id, content: "Updated Content"))
        #expect(repository.fetchSnippet(id: snippet.id)?.content == "Updated Content")

        repository.updateSnippetIsEnabled(snippet.id, isEnabled: false)
        #expect(repository.fetchSnippet(id: snippet.id)?.isEnabled == false)

        let snippet2 = try #require(repository.insertSnippet(to: folder.id))
        repository.updateSnippetIndexes([snippet2.id, snippet.id])
        #expect(repository.fetchSnippet(id: snippet2.id)?.index == 0)
        #expect(repository.fetchSnippet(id: snippet.id)?.index == 1)
        #expect(repository.fetchFolderDetail(id: folder.id)?.snippets.map(\.id) == [snippet2.id, snippet.id])
    }

    @Test
    func updateSnippetContentRejectsSameFolderDuplicateButAllowsOtherFolders() throws {
        let folder = try #require(repository.insertFolder())
        let snippet = try #require(repository.insertSnippet(to: folder.id))
        let snippet2 = try #require(repository.insertSnippet(to: folder.id))
        let folder2 = try #require(repository.insertFolder())
        let snippetInOtherFolder = try #require(repository.insertSnippet(to: folder2.id))

        #expect(repository.updateSnippetContent(snippet.id, content: "shared"))
        #expect(!repository.updateSnippetContent(snippet2.id, content: "shared"))
        #expect(repository.fetchSnippet(id: snippet2.id)?.content == "")

        #expect(repository.updateSnippetContent(snippetInOtherFolder.id, content: "shared"))
        #expect(repository.fetchSnippet(id: snippetInOtherFolder.id)?.content == "shared")
    }

    @Test
    func moveSnippet() throws {
        let folder = try #require(repository.insertFolder())
        let snippet = try #require(repository.insertSnippet(to: folder.id))
        let snippet2 = try #require(repository.insertSnippet(to: folder.id))

        let folder2 = try #require(repository.insertFolder())
        let snippet3 = try #require(repository.insertSnippet(to: folder2.id))
        let snippet4 = try #require(repository.insertSnippet(to: folder2.id))
        let snippet5 = try #require(repository.insertSnippet(to: folder2.id))

        repository.moveSnippet(snippet4.id, to: folder.id, snippetIDs: [snippet.id, snippet4.id, snippet2.id])
        #expect(repository.fetchFolderDetail(id: folder.id)?.snippets.map(\.id) == [snippet.id, snippet4.id, snippet2.id])
        #expect(repository.fetchFolderDetail(id: folder.id)?.snippets.map(\.index) == [0, 1, 2])
        #expect(repository.fetchFolderDetail(id: folder2.id)?.snippets.map(\.id) == [snippet3.id, snippet5.id])
        #expect(repository.fetchFolderDetail(id: folder2.id)?.snippets.map(\.index) == [0, 2])
    }

    @Test
    func deleteSnippet() throws {
        let folder = try #require(repository.insertFolder())
        let snippet = try #require(repository.insertSnippet(to: folder.id))

        repository.deleteSnippet(snippet.id)
        #expect(repository.fetchFolderDetail(id: folder.id) == SnippetFolderDetail(folder: folder, snippets: []))
        #expect(repository.fetchSnippet(id: snippet.id) == nil)
    }

}

@MainActor
@Suite(
    .dependencies {
        try $0.bootstrapDatabase()
    }
)
struct SnippetRepositorySyncTests {
    let repository = SnippetRepository()

    @Test
    func syncSnapshotExportsStableFoldersAndSnippets() throws {
        let folder = try #require(repository.insertFolder())
        repository.updateFolderTitle(folder.id, title: "Remote folder")
        repository.updateFolderIsEnabled(folder.id, isEnabled: false)
        let snippet = try #require(repository.insertSnippet(to: folder.id))
        repository.updateSnippetTitle(snippet.id, title: "Remote snippet")
        repository.updateSnippetContent(snippet.id, content: "payload")

        let snapshot = repository.fetchSyncSnapshot()

        let folderPayload = try #require(snapshot.folders.first)
        #expect(snapshot.folders.count == 1)
        #expect(folderPayload.id == folder.id.rawValue.uuidString)
        #expect(folderPayload.title == "Remote folder")
        #expect(folderPayload.index == 0)
        #expect(folderPayload.isEnabled == false)
        #expect(folderPayload.updatedAt > 0)
        #expect(folderPayload.deviceID == CPYUtilities.deviceID)

        let snippetPayload = try #require(snapshot.snippets.first)
        #expect(snapshot.snippets.count == 1)
        #expect(snippetPayload.id == snippet.id.rawValue.uuidString)
        #expect(snippetPayload.folderID == folder.id.rawValue.uuidString)
        #expect(snippetPayload.title == "Remote snippet")
        #expect(snippetPayload.content == "payload")
        #expect(snippetPayload.index == 0)
        #expect(snippetPayload.isEnabled == true)
        #expect(snippetPayload.updatedAt > 0)
        #expect(snippetPayload.deviceID == CPYUtilities.deviceID)
    }

    @Test
    func syncUpsertKeepsLocalDataWhenRemoteSnapshotOmitsItems() throws {
        let folder = try #require(repository.insertFolder())
        let snippet = try #require(repository.insertSnippet(to: folder.id))
        let omittedFolder = try #require(repository.insertFolder())
        let omittedSnippet = try #require(repository.insertSnippet(to: omittedFolder.id))
        let remoteUpdatedAt = max(folder.updatedAt, snippet.updatedAt) + 1

        repository.upsertSyncSnapshot(
            SnippetSyncSnapshot(
                folders: [
                    SnippetFolderSyncPayload(
                        id: folder.id.rawValue.uuidString,
                        title: "Synced folder",
                        index: 3,
                        isEnabled: false,
                        updatedAt: remoteUpdatedAt
                    )
                ],
                snippets: [
                    SnippetSyncPayload(
                        id: snippet.id.rawValue.uuidString,
                        folderID: folder.id.rawValue.uuidString,
                        title: "Synced snippet",
                        content: "synced content",
                        index: 4,
                        isEnabled: false,
                        updatedAt: remoteUpdatedAt
                    )
                ]
            )
        )

        let syncedFolder = try #require(repository.fetchFolderDetail(id: folder.id)?.folder)
        let syncedSnippet = try #require(repository.fetchSnippet(id: snippet.id))
        #expect(syncedFolder.title == "Synced folder")
        #expect(syncedFolder.index == 3)
        #expect(syncedFolder.isEnabled == false)
        #expect(syncedSnippet.title == "Synced snippet")
        #expect(syncedSnippet.content == "synced content")
        #expect(syncedSnippet.index == 4)
        #expect(syncedSnippet.isEnabled == false)

        #expect(repository.fetchSnippet(id: snippet.id) != nil)
        #expect(repository.fetchFolderDetail(id: folder.id) != nil)
        #expect(repository.fetchSnippet(id: omittedSnippet.id) != nil)
        #expect(repository.fetchFolderDetail(id: omittedFolder.id) != nil)
    }

    @Test
    func syncSnapshotExportsFullSnapshotAcrossDevices() throws {
        let remoteFolderID = UUID()
        let remoteSnippetID = UUID()
        repository.upsertSyncSnapshot(
            SnippetSyncSnapshot(
                folders: [
                    SnippetFolderSyncPayload(
                        id: remoteFolderID.uuidString,
                        title: "Remote folder",
                        index: 0,
                        isEnabled: true,
                        updatedAt: 20,
                        deviceID: "remote-device"
                    )
                ],
                snippets: [
                    SnippetSyncPayload(
                        id: remoteSnippetID.uuidString,
                        folderID: remoteFolderID.uuidString,
                        title: "Remote snippet",
                        content: "remote",
                        index: 0,
                        isEnabled: true,
                        updatedAt: 20,
                        deviceID: "remote-device"
                    )
                ]
            )
        )
        let localFolder = try #require(repository.insertFolder())
        let localSnippet = try #require(repository.insertSnippet(to: localFolder.id))

        let snapshot = repository.fetchSyncSnapshot()

        #expect(Set(snapshot.folders.map(\.id)) == [
            remoteFolderID.uuidString,
            localFolder.id.rawValue.uuidString
        ])
        #expect(Set(snapshot.snippets.map(\.id)) == [
            remoteSnippetID.uuidString,
            localSnippet.id.rawValue.uuidString
        ])
        #expect(snapshot.folders.first { $0.id == remoteFolderID.uuidString }?.deviceID == "remote-device")
        #expect(snapshot.folders.first { $0.id == localFolder.id.rawValue.uuidString }?.deviceID == CPYUtilities.deviceID)
        #expect(snapshot.snippets.first { $0.id == remoteSnippetID.uuidString }?.deviceID == "remote-device")
        #expect(snapshot.snippets.first { $0.id == localSnippet.id.rawValue.uuidString }?.deviceID == CPYUtilities.deviceID)
    }

    @Test
    func syncImportUsesLastWriteWinsAndReportsActualSnippetWrites() throws {
        let folderID = UUID()
        let snippetID = UUID()
        repository.upsertSyncSnapshot(
            SnippetSyncSnapshot(
                folders: [
                    SnippetFolderSyncPayload(
                        id: folderID.uuidString,
                        title: "Local folder",
                        index: 0,
                        isEnabled: true,
                        updatedAt: 30,
                        deviceID: CPYUtilities.deviceID
                    )
                ],
                snippets: [
                    SnippetSyncPayload(
                        id: snippetID.uuidString,
                        folderID: folderID.uuidString,
                        title: "Local snippet",
                        content: "local",
                        index: 0,
                        isEnabled: true,
                        updatedAt: 30,
                        deviceID: CPYUtilities.deviceID
                    )
                ]
            )
        )

        let olderRemote = SnippetSyncSnapshot(
            folders: [
                SnippetFolderSyncPayload(
                    id: folderID.uuidString,
                    title: "Remote older folder",
                    index: 1,
                    isEnabled: false,
                    updatedAt: 20,
                    deviceID: "remote-device"
                )
            ],
            snippets: [
                SnippetSyncPayload(
                    id: snippetID.uuidString,
                    folderID: folderID.uuidString,
                    title: "Remote older snippet",
                    content: "remote older",
                    index: 1,
                    isEnabled: false,
                    updatedAt: 20,
                    deviceID: "remote-device"
                )
            ]
        )
        let newerRemote = SnippetSyncSnapshot(
            folders: [
                SnippetFolderSyncPayload(
                    id: folderID.uuidString,
                    title: "Remote newer folder",
                    index: 2,
                    isEnabled: false,
                    updatedAt: 40,
                    deviceID: "remote-device"
                )
            ],
            snippets: [
                SnippetSyncPayload(
                    id: snippetID.uuidString,
                    folderID: folderID.uuidString,
                    title: "Remote newer snippet",
                    content: "remote newer",
                    index: 2,
                    isEnabled: false,
                    updatedAt: 40,
                    deviceID: "remote-device"
                )
            ]
        )

        #expect(repository.upsertSyncSnapshot(olderRemote) == 0)
        #expect(repository.fetchFolderDetail(id: SnippetFolder.ID(rawValue: folderID))?.folder.title == "Local folder")
        #expect(repository.fetchSnippet(id: Snippet.ID(rawValue: snippetID))?.title == "Local snippet")

        #expect(repository.upsertSyncSnapshot(newerRemote) == 2)
        #expect(repository.fetchFolderDetail(id: SnippetFolder.ID(rawValue: folderID))?.folder.title == "Remote newer folder")
        #expect(repository.fetchSnippet(id: Snippet.ID(rawValue: snippetID))?.title == "Remote newer snippet")
    }

    @Test
    func syncImportLocalSuppressionPreventsReimport() throws {
        let folderID = UUID()
        let snippetID = UUID()
        let snapshot = SnippetSyncSnapshot(
            folders: [
                SnippetFolderSyncPayload(
                    id: folderID.uuidString,
                    title: "Remote folder",
                    index: 0,
                    isEnabled: true,
                    updatedAt: 20,
                    deviceID: "remote-device"
                )
            ],
            snippets: [
                SnippetSyncPayload(
                    id: snippetID.uuidString,
                    folderID: folderID.uuidString,
                    title: "Remote snippet",
                    content: "remote",
                    index: 0,
                    isEnabled: true,
                    updatedAt: 20,
                    deviceID: "remote-device"
                )
            ]
        )

        repository.upsertSyncSnapshot(snapshot)

        let syncedFolderID = SnippetFolder.ID(rawValue: folderID)
        let syncedSnippetID = Snippet.ID(rawValue: snippetID)
        #expect(repository.fetchFolderDetail(id: syncedFolderID) != nil)
        #expect(repository.fetchSnippet(id: syncedSnippetID) != nil)

        repository.deleteSnippet(syncedSnippetID)
        repository.deleteFolder(syncedFolderID)
        repository.upsertSyncSnapshot(snapshot)

        #expect(repository.fetchFolderDetail(id: syncedFolderID) == nil)
        #expect(repository.fetchSnippet(id: syncedSnippetID) == nil)
    }

    @Test
    func syncImportMergesSameTitleFolderIDsAndDeduplicatesSameFolderContent() throws {
        let localFolder = try #require(repository.insertFolder())
        #expect(repository.updateFolderTitle(localFolder.id, title: "AI Prompt"))
        let localSnippet = try #require(repository.insertSnippet(to: localFolder.id))
        #expect(repository.updateSnippetContent(localSnippet.id, content: "shared"))

        let remoteFolderID = UUID()
        let remoteDuplicateSnippetID = UUID()
        let remoteUniqueSnippetID = UUID()
        let snapshot = SnippetSyncSnapshot(
            folders: [
                SnippetFolderSyncPayload(
                    id: remoteFolderID.uuidString,
                    title: "AI Prompt",
                    index: 0,
                    isEnabled: true,
                    updatedAt: localFolder.updatedAt + 10,
                    deviceID: "remote-device"
                )
            ],
            snippets: [
                SnippetSyncPayload(
                    id: remoteDuplicateSnippetID.uuidString,
                    folderID: remoteFolderID.uuidString,
                    title: "Duplicate content",
                    content: "shared",
                    index: 0,
                    isEnabled: true,
                    updatedAt: localFolder.updatedAt + 10,
                    deviceID: "remote-device"
                ),
                SnippetSyncPayload(
                    id: remoteUniqueSnippetID.uuidString,
                    folderID: remoteFolderID.uuidString,
                    title: "Unique content",
                    content: "unique",
                    index: 1,
                    isEnabled: true,
                    updatedAt: localFolder.updatedAt + 10,
                    deviceID: "remote-device"
                )
            ]
        )

        #expect(repository.upsertSyncSnapshot(snapshot) == 1)
        #expect(repository.fetchFolderDetails().map(\.folder.title) == ["AI Prompt"])
        let detail = try #require(repository.fetchFolderDetail(id: localFolder.id))
        #expect(Set(detail.snippets.map(\.content)) == ["shared", "unique"])
        #expect(repository.fetchFolderDetail(id: SnippetFolder.ID(rawValue: remoteFolderID)) == nil)
        #expect(repository.fetchSnippet(id: Snippet.ID(rawValue: remoteDuplicateSnippetID)) == nil)
        #expect(repository.fetchSnippet(id: Snippet.ID(rawValue: remoteUniqueSnippetID)) != nil)

        #expect(repository.upsertSyncSnapshot(snapshot) == 0)
    }

    @Test
    func syncImportAllowsSameContentInDifferentFolders() throws {
        let folderID = UUID()
        let folder2ID = UUID()
        let snippetID = UUID()
        let snippet2ID = UUID()

        #expect(repository.upsertSyncSnapshot(SnippetSyncSnapshot(
            folders: [
                SnippetFolderSyncPayload(id: folderID.uuidString, title: "A", index: 0, isEnabled: true, updatedAt: 10),
                SnippetFolderSyncPayload(id: folder2ID.uuidString, title: "B", index: 1, isEnabled: true, updatedAt: 10)
            ],
            snippets: [
                SnippetSyncPayload(id: snippetID.uuidString, folderID: folderID.uuidString, title: "Shared", content: "same", index: 0, isEnabled: true, updatedAt: 10),
                SnippetSyncPayload(id: snippet2ID.uuidString, folderID: folder2ID.uuidString, title: "Shared", content: "same", index: 0, isEnabled: true, updatedAt: 10)
            ]
        )) == 4)

        #expect(repository.fetchFolderDetails().count == 2)
        #expect(repository.fetchFolderDetails().flatMap(\.snippets).map(\.content) == ["same", "same"])
    }

    @Test
    func removeDuplicateFoldersAndSnippetsMergesExistingBadData() throws {
        let olderFolderID = SnippetFolder.ID(rawValue: UUID())
        let canonicalFolderID = SnippetFolder.ID(rawValue: UUID())
        let lowerCaseFolderID = SnippetFolder.ID(rawValue: UUID())
        let olderSharedSnippetID = Snippet.ID(rawValue: UUID())
        let olderUniqueSnippetID = Snippet.ID(rawValue: UUID())
        let canonicalSharedSnippetID = Snippet.ID(rawValue: UUID())
        let canonicalUniqueSnippetID = Snippet.ID(rawValue: UUID())
        try insertDuplicateFixture(
            folders: [
                SnippetFolder(id: olderFolderID, title: "AI Prompt", index: 0, isEnabled: true, updatedAt: 10),
                SnippetFolder(id: canonicalFolderID, title: "AI Prompt", index: 0, isEnabled: true, updatedAt: 20),
                SnippetFolder(id: lowerCaseFolderID, title: "ai prompt", index: 1, isEnabled: true, updatedAt: 30)
            ],
            snippets: [
                Snippet(id: olderSharedSnippetID, folderID: olderFolderID, title: "Old shared", content: "shared", index: 0, isEnabled: true, updatedAt: 10),
                Snippet(id: olderUniqueSnippetID, folderID: olderFolderID, title: "Old unique", content: "old", index: 1, isEnabled: true, updatedAt: 10),
                Snippet(id: canonicalSharedSnippetID, folderID: canonicalFolderID, title: "New shared", content: "shared", index: 0, isEnabled: true, updatedAt: 20),
                Snippet(id: canonicalUniqueSnippetID, folderID: canonicalFolderID, title: "New unique", content: "new", index: 1, isEnabled: true, updatedAt: 20)
            ]
        )

        #expect(repository.removeDuplicateFoldersAndSnippets() == 2)

        #expect(repository.fetchFolderDetail(id: olderFolderID) == nil)
        let canonicalDetail = try #require(repository.fetchFolderDetail(id: canonicalFolderID))
        #expect(repository.fetchFolderDetail(id: lowerCaseFolderID) != nil)
        #expect(Set(canonicalDetail.snippets.map(\.content)) == ["shared", "old", "new"])
        #expect(repository.fetchSnippet(id: olderSharedSnippetID) == nil)
        #expect(repository.fetchSnippet(id: olderUniqueSnippetID)?.folderID == canonicalFolderID)
        #expect(repository.fetchSnippet(id: canonicalSharedSnippetID) != nil)
    }
}

private func insertDuplicateFixture(folders: [SnippetFolder], snippets: [Snippet]) throws {
    @Dependency(\.defaultDatabase) var database
    try database.write { database in
        for folder in folders {
            try SnippetFolder.upsert { folder }.execute(database)
        }
        for snippet in snippets {
            try Snippet.upsert { snippet }.execute(database)
        }
    }
}

private func waitUntil(condition: @escaping @MainActor () async -> Bool) async throws {
    try await confirmation { confirmation in
        while true {
            if await condition() {
                confirmation()
                return
            } else {
                try await Task.sleep(for: .seconds(0.01))
            }
        }
    }
}
