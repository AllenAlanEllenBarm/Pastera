//
//  SQLiteDataSchema.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Shunsuke Furubayashi on 2026/05/22.
//
//  Copyright © 2015-2026 Clipy Project.
//

import AppKit
import SQLiteData
import Tagged

@Table
struct PasteboardHistory: Identifiable, Equatable {
    typealias ID = Tagged<Self, String>

    @Column(primaryKey: true)
    let id: ID
    let title: String
    @Column(as: [NSPasteboard.PasteboardType].JSONRepresentation.self)
    let pasteboardTypes: [NSPasteboard.PasteboardType]
    let updateAt: Int
    let deviceID: String?

    var primaryType: NSPasteboard.PasteboardType? {
        pasteboardTypes.first
    }
}

@Table
struct PasteboardHistoryAsset: Identifiable, Equatable {
    typealias ID = Tagged<Self, UUID>

    @Column(primaryKey: true)
    let id: ID
    let pasteboardHistoryID: PasteboardHistory.ID
    let pasteboardType: NSPasteboard.PasteboardType
    let data: Data
}

@Table
struct PasteboardHistoryThumbnailAsset: Identifiable, Equatable {
    @Column(primaryKey: true)
    let pasteboardHistoryID: PasteboardHistory.ID
    let kind: Kind
    let data: Data
    var id: PasteboardHistory.ID { pasteboardHistoryID }

    enum Kind: String, QueryBindable {
        case image
        case colorCode
    }
}

@Table
struct PasteboardHistoryOCRText: Identifiable, Equatable {
    @Column(primaryKey: true)
    let pasteboardHistoryID: PasteboardHistory.ID
    let sourceHash: String
    let recognizedText: String
    let updatedAt: Int
    var id: PasteboardHistory.ID { pasteboardHistoryID }
}

@Table("scriptTransforms")
struct ScriptTransformRecord: Identifiable, Equatable {
    typealias ID = Tagged<Self, UUID>

    @Column(primaryKey: true)
    let id: ID
    let name: String
    let code: String
    let isEnabled: Bool
    let runOnCopy: Bool
    let runOnPaste: Bool
    let runManually: Bool
    let sortIndex: Int
    let createdAt: Int
    let updatedAt: Int
}

@Selection
struct PasteboardHistoryDetail: Equatable {
    let history: PasteboardHistory
    let thumbnailAsset: PasteboardHistoryThumbnailAsset?
}

@Table
struct SnippetFolder: Identifiable, Equatable {
    typealias ID = Tagged<Self, UUID>

    @Column(primaryKey: true)
    let id: ID
    let title: String
    let index: Int
    let isEnabled: Bool
    let createdAt: Int
    let updatedAt: Int
    let lastModifiedDeviceID: String?

    init(
        id: ID,
        title: String,
        index: Int,
        isEnabled: Bool,
        createdAt: Int = 0,
        updatedAt: Int = 0,
        lastModifiedDeviceID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.index = index
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastModifiedDeviceID = lastModifiedDeviceID
    }
}

@Table
struct Snippet: Identifiable, Equatable {
    typealias ID = Tagged<Self, UUID>

    @Column(primaryKey: true)
    let id: ID
    let folderID: SnippetFolder.ID
    let title: String
    let content: String
    let index: Int
    let isEnabled: Bool
    let createdAt: Int
    let updatedAt: Int
    let lastModifiedDeviceID: String?

    init(
        id: ID,
        folderID: SnippetFolder.ID,
        title: String,
        content: String,
        index: Int,
        isEnabled: Bool,
        createdAt: Int = 0,
        updatedAt: Int = 0,
        lastModifiedDeviceID: String? = nil
    ) {
        self.id = id
        self.folderID = folderID
        self.title = title
        self.content = content
        self.index = index
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastModifiedDeviceID = lastModifiedDeviceID
    }
}

@Table
struct SyncSuppression: Equatable {
    @Column(primaryKey: true)
    let syncIdentity: String
    let kind: SyncEntityKind
    let recordID: String
    let suppressedAt: Int
}

@Table
struct SnippetSyncDeletion: Equatable {
    @Column(primaryKey: true)
    let syncIdentity: String
    let kind: SyncEntityKind
    let recordID: String
    let folderID: String?
    let folderTitle: String
    let content: String
    let deletedAt: Int
    let deviceID: String?
}

extension NSPasteboard.PasteboardType: @retroactive SQLiteType {}
extension NSPasteboard.PasteboardType: @retroactive QueryBindable {}
extension NSPasteboard.PasteboardType: @retroactive Codable {}
extension PasteboardHistoryThumbnailAsset.Kind: Codable {}
extension SyncEntityKind: SQLiteType {}
extension SyncEntityKind: QueryBindable {}
