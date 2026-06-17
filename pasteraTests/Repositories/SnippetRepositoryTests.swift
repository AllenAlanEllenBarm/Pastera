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
        #expect(folder2.title == "untitled folder")
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

        repository.updateFolderTitle(folder.id, title: "Updated")
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

        repository.updateSnippetContent(snippet.id, content: "Updated Content")
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
    func syncUpsertKeepsLocalDataWhenRemoteTombstonesArrive() throws {
        let folder = try #require(repository.insertFolder())
        let snippet = try #require(repository.insertSnippet(to: folder.id))
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

        repository.mergeSyncTombstones([
            SyncRecord.plaintextFixture(id: snippet.id.rawValue.uuidString, kind: .snippet, deletedAt: 20),
            SyncRecord.plaintextFixture(id: folder.id.rawValue.uuidString, kind: .snippetFolder, deletedAt: 21)
        ])

        #expect(repository.fetchSnippet(id: snippet.id) != nil)
        #expect(repository.fetchFolderDetail(id: folder.id) != nil)
    }

    @Test
    func syncSnapshotExportsOnlyCurrentDeviceChangesAfterCutoff() throws {
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

        let snapshot = repository.fetchSyncSnapshot(
            currentDeviceID: CPYUtilities.deviceID,
            updatedAtOrAfter: 0
        )

        #expect(snapshot.folders.map(\.id) == [localFolder.id.rawValue.uuidString])
        #expect(snapshot.folders.first?.deviceID == CPYUtilities.deviceID)
        #expect(snapshot.snippets.map(\.id) == [localSnippet.id.rawValue.uuidString])
        #expect(snapshot.snippets.first?.deviceID == CPYUtilities.deviceID)
        #expect(repository.fetchSyncSnapshot(currentDeviceID: CPYUtilities.deviceID, updatedAtOrAfter: Int.max).folders.isEmpty)
        #expect(repository.fetchSyncSnapshot(currentDeviceID: CPYUtilities.deviceID, updatedAtOrAfter: Int.max).snippets.isEmpty)
    }

    @Test
    func syncSnapshotIncludesParentFolderForChangedSnippetWithoutBumpingFolderTimestamp() throws {
        let folderID = UUID()
        let snippetID = UUID()
        repository.upsertSyncSnapshot(
            SnippetSyncSnapshot(
                folders: [
                    SnippetFolderSyncPayload(
                        id: folderID.uuidString,
                        title: "Existing folder",
                        index: 0,
                        isEnabled: true,
                        updatedAt: 10,
                        deviceID: CPYUtilities.deviceID
                    )
                ],
                snippets: [
                    SnippetSyncPayload(
                        id: snippetID.uuidString,
                        folderID: folderID.uuidString,
                        title: "Changed snippet",
                        content: "changed",
                        index: 0,
                        isEnabled: true,
                        updatedAt: 30,
                        deviceID: CPYUtilities.deviceID
                    )
                ]
            )
        )

        let snapshot = repository.fetchSyncSnapshot(
            currentDeviceID: CPYUtilities.deviceID,
            updatedAtOrAfter: 20
        )

        #expect(snapshot.snippets.map(\.id) == [snippetID.uuidString])
        #expect(snapshot.folders.map(\.id) == [folderID.uuidString])
        #expect(snapshot.folders.first?.updatedAt == 10)
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
    func syncImportDoesNotApplyRemoteDeletesAndLocalSuppressionPreventsReimport() throws {
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
        repository.mergeSyncTombstones([
            SyncRecord.plaintextFixture(id: snippetID.uuidString, kind: .snippet, deletedAt: 21),
            SyncRecord.plaintextFixture(id: folderID.uuidString, kind: .snippetFolder, deletedAt: 21)
        ])

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

private extension SyncRecord {
    static func plaintextFixture(
        id: String,
        kind: SyncRecord.Kind,
        updatedAt: Int = 10,
        deletedAt: Int? = nil,
        payload: SyncJSONValue = .object([:])
    ) -> SyncRecord {
        return SyncRecord(
            id: id,
            kind: kind,
            deviceID: "device-a",
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            payload: payload,
            schemaVersion: 1
        )
    }
}
