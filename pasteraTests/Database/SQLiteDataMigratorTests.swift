//
//  SQLiteDataMigratorTests.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Shunsuke Furubayashi on 2026/05/26.
//
//  Copyright © 2015-2026 Clipy Project.
//

import GRDB
import SQLiteData
import Testing
@testable import Pastera

@MainActor
@Suite
struct SQLiteDataMigratorTests {
    @Test
    func migrationV6AddsHistoryFacetsAndDurableOCRJobs() throws {
        let database = try DatabaseQueue()
        var baselineMigrator = DatabaseMigrator()
        baselineMigrator.registerMigrationV1()
        baselineMigrator.registerMigrationV2()
        baselineMigrator.registerMigrationV3()
        baselineMigrator.registerMigrationV4()
        baselineMigrator.registerMigrationV5()
        try baselineMigrator.migrate(database)

        try database.write { database in
            try database.execute(
                sql: """
                INSERT INTO pasteboardHistories (id, title, pasteboardTypes, updateAt)
                VALUES (?, '', ?, 1), (?, '', ?, 2), (?, '', ?, 3)
                """,
                arguments: [
                    "image", "[\"public.tiff\"]",
                    "file", "[\"public.file-url\"]",
                    "text", "[\"public.utf8-plain-text\"]"
                ]
            )
        }

        var migrator = DatabaseMigrator()
        migrator.registerMigrationV6()
        try migrator.migrate(database)

        try database.read { database in
            let facets = try Row.fetchAll(
                database,
                sql: """
                SELECT id, containsImage, containsFile, isTextSyncCandidate
                FROM pasteboardHistories ORDER BY id
                """
            )
            #expect(facets.count == 3)
            #expect(facets[0]["id"] as String == "file")
            #expect(facets[0]["containsFile"] as Bool)
            #expect(facets[1]["id"] as String == "image")
            #expect(facets[1]["containsImage"] as Bool)
            #expect(facets[2]["id"] as String == "text")
            #expect(facets[2]["isTextSyncCandidate"] as Bool)

            let indexes = try String.fetchAll(
                database,
                sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'index_pasteboardHistories_on_%'"
            )
            #expect(indexes.contains("index_pasteboardHistories_on_images_updateAt"))
            #expect(indexes.contains("index_pasteboardHistories_on_files_updateAt"))
            #expect(indexes.contains("index_pasteboardHistories_on_textSync_updateAt"))
        }

        try database.write { database in
            try database.execute(
                sql: "INSERT INTO pasteboardHistoryOCRJobs (pasteboardHistoryID, priority, enqueuedAt) VALUES ('image', 0, 1)"
            )
            try database.execute(sql: "DELETE FROM pasteboardHistories WHERE id = 'image'")
            let jobCount = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM pasteboardHistoryOCRJobs")
            #expect(jobCount == 0)
        }
    }

    @Test
    func registeredMigrationsAddSyncMetadata() throws {
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        migrator.registerMigration()
        try migrator.migrate(database)

        try database.read { database in
            let tables = try #sql(
                """
                SELECT "name"
                FROM "sqlite_master"
                WHERE "type" = 'table'
                ORDER BY "name"
                """,
                as: String.self
            )
            .fetchAll(database)
            #expect(tables.contains("syncSuppressions"))
            #expect(tables.contains("snippetSyncDeletions"))
            #expect(tables.contains("pasteboardHistoryOCRTexts"))
            #expect(tables.contains("scriptTransforms"))
        }

        try database.read { database in
            let folderColumns = try #sql(
                """
                SELECT "name"
                FROM pragma_table_info('snippetFolders')
                ORDER BY "name"
                """,
                as: String.self
            )
            .fetchAll(database)
            #expect(folderColumns.contains("createdAt"))
            #expect(folderColumns.contains("updatedAt"))
            #expect(folderColumns.contains("lastModifiedDeviceID"))
        }

        try database.read { database in
            let snippetColumns = try #sql(
                """
                SELECT "name"
                FROM pragma_table_info('snippets')
                ORDER BY "name"
                """,
                as: String.self
            )
            .fetchAll(database)
            #expect(snippetColumns.contains("createdAt"))
            #expect(snippetColumns.contains("updatedAt"))
            #expect(snippetColumns.contains("lastModifiedDeviceID"))
        }

        try database.read { database in
            let deletionColumns = try #sql(
                """
                SELECT "name"
                FROM pragma_table_info('snippetSyncDeletions')
                ORDER BY "name"
                """,
                as: String.self
            )
            .fetchAll(database)
            #expect(deletionColumns.contains("recordID"))
            #expect(deletionColumns.contains("folderID"))
            #expect(deletionColumns.contains("folderTitle"))
            #expect(deletionColumns.contains("content"))
            #expect(deletionColumns.contains("deletedAt"))
        }

        try database.read { database in
            let ocrColumns = try #sql(
                """
                SELECT "name"
                FROM pragma_table_info('pasteboardHistoryOCRTexts')
                ORDER BY "name"
                """,
                as: String.self
            )
            .fetchAll(database)
            #expect(
                ocrColumns == [
                    "pasteboardHistoryID",
                    "recognizedText",
                    "sourceHash",
                    "updatedAt"
                ]
            )
        }

        try database.read { database in
            let ocrIndexes = try #sql(
                """
                SELECT "name"
                FROM "sqlite_master"
                WHERE "type" = 'index'
                AND "tbl_name" = 'pasteboardHistoryOCRTexts'
                ORDER BY "name"
                """,
                as: String.self
            )
            .fetchAll(database)
            #expect(ocrIndexes.contains("index_pasteboardHistoryOCRTexts_on_sourceHash"))
        }

        try database.read { database in
            let scriptColumns = try #sql(
                """
                SELECT "name"
                FROM pragma_table_info('scriptTransforms')
                ORDER BY "cid"
                """,
                as: String.self
            )
            .fetchAll(database)
            #expect(
                scriptColumns == [
                    "id",
                    "name",
                    "code",
                    "isEnabled",
                    "runOnCopy",
                    "runOnPaste",
                    "runManually",
                    "sortIndex",
                    "createdAt",
                    "updatedAt"
                ]
            )

            let scriptIndexes = try #sql(
                """
                SELECT "name"
                FROM "sqlite_master"
                WHERE "type" = 'index'
                AND "tbl_name" = 'scriptTransforms'
                ORDER BY "name"
                """,
                as: String.self
            )
            .fetchAll(database)
            #expect(scriptIndexes.contains("index_scriptTransforms_on_sortIndex_createdAt"))
        }
    }

    @Test
    func migrationV1() throws { // swiftlint:disable:this function_body_length
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        migrator.registerMigrationV1()
        try migrator.migrate(database)

        try database.read { database in
            let tables = try #sql(
                """
                SELECT "name"
                FROM "sqlite_master"
                WHERE "type" = 'table'
                ORDER BY "name"
                """,
                as: String.self
            )
            .fetchAll(database)
            #expect(
                tables == [
                    "grdb_migrations",
                    "pasteboardHistories",
                    "pasteboardHistoryAssets",
                    "pasteboardHistoryThumbnailAssets",
                    "snippetFolders",
                    "snippets"
                ]
            )
        }

        try database.read { database in
            let indexes = try #sql(
                """
                SELECT "name"
                FROM "sqlite_master"
                WHERE "type" = 'index'
                AND "name" GLOB 'index_*'
                ORDER BY "name"
                """,
                as: String.self
            )
            .fetchAll(database)
            #expect(
                indexes == [
                    "index_pasteboardHistories_on_updateAt",
                    "index_pasteboardHistoryAssets_on_pasteboardHistoryID",
                    "index_snippetFolders_on_index",
                    "index_snippets_on_folderID",
                    "index_snippets_on_folderID_index",
                    "index_snippets_on_index"
                ]
            )
        }

        try database.read { database in
            let columnNames = try #sql(
                """
                SELECT "name"
                FROM pragma_table_info('pasteboardHistories')
                ORDER BY "name"
                """,
                as: String.self
            )
            .fetchAll(database)
            #expect(
                columnNames == [
                    "deviceID",
                    "id",
                    "pasteboardTypes",
                    "title",
                    "updateAt"
                ]
            )
        }

        try database.read { database in
            let columnNames = try #sql(
                """
                SELECT "name"
                FROM pragma_table_info('pasteboardHistoryAssets')
                ORDER BY "name"
                """,
                as: String.self
            )
            .fetchAll(database)
            #expect(
                columnNames == [
                    "data",
                    "id",
                    "pasteboardHistoryID",
                    "pasteboardType"
                ]
            )
        }

        try database.read { database in
            let columnNames = try #sql(
                """
                SELECT "name"
                FROM pragma_table_info('pasteboardHistoryThumbnailAssets')
                ORDER BY "name"
                """,
                as: String.self
            )
            .fetchAll(database)
            #expect(
                columnNames == [
                    "data",
                    "kind",
                    "pasteboardHistoryID"
                ]
            )
        }

        try database.read { database in
            let columnNames = try #sql(
                """
                SELECT "name"
                FROM pragma_table_info('snippetFolders')
                ORDER BY "name"
                """,
                as: String.self
            )
            .fetchAll(database)
            #expect(
                columnNames == [
                    "id",
                    "index",
                    "isEnabled",
                    "title"
                ]
            )
        }

        try database.read { database in
            let columnNames = try #sql(
                """
                SELECT "name"
                FROM pragma_table_info('snippets')
                ORDER BY "name"
                """,
                as: String.self
            )
            .fetchAll(database)
            #expect(
                columnNames == [
                    "content",
                    "folderID",
                    "id",
                    "index",
                    "isEnabled",
                    "title"
                ]
            )
        }
    }
}
