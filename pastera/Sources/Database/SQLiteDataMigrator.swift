//
//  SQLiteDataMigrator.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Shunsuke Furubayashi on 2026/05/22.
//
//  Copyright © 2015-2026 Clipy Project.
//

import SQLiteData

extension DatabaseMigrator {
    mutating func registerMigration() {
        registerMigrationV1()
        registerMigrationV2()
        registerMigrationV3()
    }

    // swiftlint:disable:next function_body_length
    mutating func registerMigrationV1() {
        registerMigration("Create initial tables") { database in
            try #sql(
                """
                CREATE TABLE "pasteboardHistories" (
                  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                  "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
                  "pasteboardTypes" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '[]',
                  "deviceID" TEXT,
                  "updateAt" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT (unixepoch())
                ) STRICT
                """
            )
            .execute(database)

            try #sql(
                """
                CREATE INDEX "index_pasteboardHistories_on_updateAt"
                ON "pasteboardHistories" ("updateAt")
                """
            )
            .execute(database)

            try #sql(
                """
                CREATE TABLE "pasteboardHistoryAssets" (
                  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                  "pasteboardHistoryID" TEXT NOT NULL,
                  "pasteboardType" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
                  "data" BLOB NOT NULL,
                  FOREIGN KEY ("pasteboardHistoryID")
                    REFERENCES "pasteboardHistories" ("id")
                    ON DELETE CASCADE
                ) STRICT
                """
            )
            .execute(database)

            try #sql(
                """
                CREATE INDEX "index_pasteboardHistoryAssets_on_pasteboardHistoryID"
                ON "pasteboardHistoryAssets" ("pasteboardHistoryID")
                """
            )
            .execute(database)

            try #sql(
                """
                CREATE TABLE "pasteboardHistoryThumbnailAssets" (
                  "pasteboardHistoryID" TEXT PRIMARY KEY NOT NULL,
                  "kind" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
                  "data" BLOB NOT NULL,
                  FOREIGN KEY ("pasteboardHistoryID")
                    REFERENCES "pasteboardHistories" ("id")
                    ON DELETE CASCADE
                ) STRICT
                """
            )
            .execute(database)

            try #sql(
                """
                CREATE TABLE "snippetFolders" (
                  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                  "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
                  "index" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
                  "isEnabled" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 1
                ) STRICT
                """
            )
            .execute(database)

            try #sql(
                """
                CREATE TABLE "snippets" (
                  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                  "folderID" TEXT NOT NULL,
                  "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
                  "content" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
                  "index" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
                  "isEnabled" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 1,
                  FOREIGN KEY ("folderID")
                    REFERENCES "snippetFolders" ("id")
                    ON DELETE CASCADE
                ) STRICT
                """
            )
            .execute(database)

            try #sql(
                """
                CREATE INDEX "index_snippetFolders_on_index"
                ON "snippetFolders" ("index")
                """
            )
            .execute(database)

            try #sql(
                """
                CREATE INDEX "index_snippets_on_folderID"
                ON "snippets" ("folderID")
                """
            )
            .execute(database)

            try #sql(
                """
                CREATE INDEX "index_snippets_on_index"
                ON "snippets" ("index")
                """
            )
            .execute(database)

            try #sql(
                """
                CREATE INDEX "index_snippets_on_folderID_index"
                ON "snippets" ("folderID", "index")
                """
            )
            .execute(database)
        }
    }

    mutating func registerMigrationV2() {
        registerMigration("Add non-destructive sync metadata") { database in
            try #sql(
                """
                ALTER TABLE "snippetFolders"
                ADD COLUMN "createdAt" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0
                """
            )
            .execute(database)

            try #sql(
                """
                ALTER TABLE "snippetFolders"
                ADD COLUMN "updatedAt" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0
                """
            )
            .execute(database)

            try #sql(
                """
                ALTER TABLE "snippetFolders"
                ADD COLUMN "lastModifiedDeviceID" TEXT
                """
            )
            .execute(database)

            try #sql(
                """
                ALTER TABLE "snippets"
                ADD COLUMN "createdAt" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0
                """
            )
            .execute(database)

            try #sql(
                """
                ALTER TABLE "snippets"
                ADD COLUMN "updatedAt" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0
                """
            )
            .execute(database)

            try #sql(
                """
                ALTER TABLE "snippets"
                ADD COLUMN "lastModifiedDeviceID" TEXT
                """
            )
            .execute(database)

            try #sql(
                """
                CREATE TABLE "syncSuppressions" (
                  "syncIdentity" TEXT PRIMARY KEY NOT NULL,
                  "kind" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
                  "recordID" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
                  "suppressedAt" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT (unixepoch())
                ) STRICT
                """
            )
            .execute(database)

            try #sql(
                """
                CREATE INDEX "index_syncSuppressions_on_kind_recordID"
                ON "syncSuppressions" ("kind", "recordID")
                """
            )
            .execute(database)
        }
    }

    mutating func registerMigrationV3() {
        registerMigration("Add snippet deletion sync tombstones") { database in
            try #sql(
                """
                CREATE TABLE "snippetSyncDeletions" (
                  "syncIdentity" TEXT PRIMARY KEY NOT NULL,
                  "kind" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
                  "recordID" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
                  "folderID" TEXT,
                  "folderTitle" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
                  "content" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
                  "deletedAt" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
                  "deviceID" TEXT
                ) STRICT
                """
            )
            .execute(database)

            try #sql(
                """
                CREATE INDEX "index_snippetSyncDeletions_on_kind_recordID"
                ON "snippetSyncDeletions" ("kind", "recordID")
                """
            )
            .execute(database)
        }
    }
}
