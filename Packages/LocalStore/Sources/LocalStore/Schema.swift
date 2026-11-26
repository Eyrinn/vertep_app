// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import GRDB

/// The database schema, as an ordered list of migrations.
///
/// A migration that has shipped is never edited: a schema change is a new migration
/// appended after the last one.
enum Schema {
    static let folderTable = "folder"
    static let folderItemTable = "folderItem"
    static let titleMetadataTable = "titleMetadata"

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-folders", migrate: createFolderTables)
        migrator.registerMigration("v2-title-metadata", migrate: addTitleMetadata)
        return migrator
    }

    private static func createFolderTables(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE folder (
                id TEXT PRIMARY KEY NOT NULL,
                kind TEXT NOT NULL CHECK (kind IN ('personal')),
                name TEXT NOT NULL,
                createdAt DATETIME NOT NULL,
                dirtyVersion INTEGER NOT NULL DEFAULT 0
            );

            -- A device has one personal folder at most.
            CREATE UNIQUE INDEX folder_onePersonal ON folder(kind) WHERE kind = 'personal';

            CREATE TABLE folderItem (
                folderId TEXT NOT NULL REFERENCES folder(id) ON DELETE CASCADE,
                titleId TEXT NOT NULL,
                mediaType TEXT NOT NULL CHECK (mediaType IN ('movie', 'tv')),
                isWatched BOOLEAN NOT NULL DEFAULT 0,
                watchedUpdatedAt DATETIME NOT NULL,
                addedAt DATETIME NOT NULL,
                updatedAt DATETIME NOT NULL,
                -- A title is in a folder at most once.
                PRIMARY KEY (folderId, titleId),
                -- The title id names its own media type: tmdb:<mediaType>:<positive id>.
                CHECK (titleId GLOB 'tmdb:' || mediaType || ':[1-9]*'
                       AND substr(titleId, length('tmdb:' || mediaType || ':') + 1) NOT GLOB '*[^0-9]*')
            );
            """)
    }

    /// Adds the removal date of folder items and the title metadata table. Every folder
    /// and folder item of the first version stays as it is, and no item is removed.
    private static func addTitleMetadata(_ db: Database) throws {
        try db.execute(sql: """
            ALTER TABLE folderItem ADD COLUMN deletedAt DATETIME;

            -- One row per title and language, which every folder reads. The cast and the
            -- genres are JSON lists, and NULL until details of the title are stored.
            CREATE TABLE titleMetadata (
                titleId TEXT NOT NULL,
                language TEXT NOT NULL CHECK (language IN ('uk', 'en')),
                title TEXT NOT NULL,
                originalTitle TEXT NOT NULL,
                year INTEGER,
                posterPath TEXT,
                director TEXT,
                creator TEXT,
                castNames TEXT,
                overview TEXT,
                overviewLanguage TEXT CHECK (overviewLanguage IN ('uk', 'en')),
                genres TEXT,
                runtime INTEGER,
                fetchedAt DATETIME NOT NULL,
                PRIMARY KEY (titleId, language),
                -- The title id is tmdb:movie:<positive id> or tmdb:tv:<positive id>.
                CHECK ((titleId GLOB 'tmdb:movie:[1-9]*'
                        AND substr(titleId, length('tmdb:movie:') + 1) NOT GLOB '*[^0-9]*')
                       OR (titleId GLOB 'tmdb:tv:[1-9]*'
                           AND substr(titleId, length('tmdb:tv:') + 1) NOT GLOB '*[^0-9]*'))
            );
            """)
    }
}
