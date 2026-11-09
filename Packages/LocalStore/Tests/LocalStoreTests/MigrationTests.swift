// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import GRDB
@testable import LocalStore
import Testing

@Suite struct MigrationTests {
    @Test func createsBothTablesOnAnEmptyDatabase() throws {
        let queue = try DatabaseQueue()
        let tablesBefore = try queue.read { db in
            try (db.tableExists("folder"), db.tableExists("folderItem"))
        }
        #expect(tablesBefore == (false, false))

        try Schema.migrator.migrate(queue)

        try queue.read { db in
            let folderColumns = try Set(db.columns(in: "folder").map(\.name))
            #expect(folderColumns == ["id", "kind", "name", "createdAt", "dirtyVersion"])

            let itemColumns = try Set(db.columns(in: "folderItem").map(\.name))
            #expect(itemColumns == [
                "folderId", "titleId", "mediaType", "isWatched", "watchedUpdatedAt", "addedAt",
                "updatedAt",
            ])

            #expect(try db.primaryKey("folderItem").columns == ["folderId", "titleId"])
            #expect(try Schema.migrator.hasCompletedMigrations(db))
        }
    }

    @Test func runningTheMigratorAgainChangesNothing() throws {
        let queue = try DatabaseQueue()
        try Schema.migrator.migrate(queue)
        try Schema.migrator.migrate(queue)
        let applied = try queue.read { db in try Schema.migrator.appliedIdentifiers(db) }
        #expect(applied == ["v1-folders"])
    }

    @Test func refusesASecondPersonalFolder() throws {
        let queue = try DatabaseQueue()
        try Schema.migrator.migrate(queue)
        let insert = """
            INSERT INTO folder (id, kind, name, createdAt) VALUES (?, 'personal', 'Test', '2026-01-01 00:00:00.000')
            """
        try queue.write { db in
            try db.execute(sql: insert, arguments: ["A"])
        }
        #expect(throws: DatabaseError.self) {
            try queue.write { db in try db.execute(sql: insert, arguments: ["B"]) }
        }
    }

    @Test(arguments: [
        ("tmdb:tv:12", "movie"),
        ("tmdb:movie:0", "movie"),
        ("tmdb:movie:12x", "movie"),
        ("imdb:movie:12", "movie"),
        ("tmdb:movie:12", "person"),
    ])
    func refusesATitleIDThatDoesNotMatchItsMediaType(titleID: String, mediaType: String) throws {
        let queue = try DatabaseQueue()
        try Schema.migrator.migrate(queue)
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO folder (id, kind, name, createdAt) VALUES ('F', 'personal', 'Test', '2026-01-01 00:00:00.000')
                """)
        }
        #expect(throws: DatabaseError.self) {
            try queue.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO folderItem (folderId, titleId, mediaType, watchedUpdatedAt, addedAt, updatedAt)
                        VALUES ('F', ?, ?, '2026-01-01 00:00:00.000', '2026-01-01 00:00:00.000', '2026-01-01 00:00:00.000')
                        """,
                    arguments: [titleID, mediaType]
                )
            }
        }
    }
}
