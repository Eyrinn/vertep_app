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

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-folders", migrate: createFolderTables)
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
}
