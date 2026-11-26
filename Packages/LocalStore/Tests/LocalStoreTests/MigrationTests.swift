// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import GRDB
@testable import LocalStore
import Testing

@Suite struct MigrationTests {
    @Test func createsEveryTableOnAnEmptyDatabase() throws {
        let queue = try DatabaseQueue()
        let tablesBefore = try queue.read { db in
            try [db.tableExists("folder"), db.tableExists("folderItem"), db.tableExists("titleMetadata")]
        }
        #expect(tablesBefore == [false, false, false])

        try Schema.migrator.migrate(queue)

        try queue.read { db in
            let folderColumns = try Set(db.columns(in: "folder").map(\.name))
            #expect(folderColumns == ["id", "kind", "name", "createdAt", "dirtyVersion"])

            let itemColumns = try Set(db.columns(in: "folderItem").map(\.name))
            #expect(itemColumns == [
                "folderId", "titleId", "mediaType", "isWatched", "watchedUpdatedAt", "addedAt",
                "updatedAt", "deletedAt",
            ])

            let metadataColumns = try Set(db.columns(in: "titleMetadata").map(\.name))
            #expect(metadataColumns == [
                "titleId", "language", "title", "originalTitle", "year", "posterPath", "director",
                "creator", "castNames", "overview", "overviewLanguage", "genres", "runtime", "fetchedAt",
            ])

            #expect(try db.primaryKey("folderItem").columns == ["folderId", "titleId"])
            #expect(try db.primaryKey("titleMetadata").columns == ["titleId", "language"])
            #expect(try Schema.migrator.hasCompletedMigrations(db))
        }
    }

    @Test func runningTheMigratorAgainChangesNothing() throws {
        let queue = try DatabaseQueue()
        try Schema.migrator.migrate(queue)
        try Schema.migrator.migrate(queue)
        let applied = try queue.read { db in try Schema.migrator.appliedIdentifiers(db) }
        #expect(applied == ["v1-folders", "v2-title-metadata"])
    }

    @Test func theSecondVersionKeepsEveryFolderAndTitleOfTheFirst() async throws {
        let queue = try DatabaseQueue()
        try Schema.migrator.migrate(queue, upTo: "v1-folders")
        let folderID = UUID()
        try await queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO folder (id, kind, name, createdAt, dirtyVersion)
                    VALUES (?, 'personal', 'Test', '2026-01-01 00:00:00.000', 3)
                    """,
                arguments: [folderID.uuidString]
            )
            try db.execute(
                sql: """
                    INSERT INTO folderItem (folderId, titleId, mediaType, isWatched, watchedUpdatedAt, addedAt, updatedAt)
                    VALUES (?, 'tmdb:movie:603', 'movie', 1, '2026-01-02 00:00:00.000', '2026-01-01 00:00:00.000', '2026-01-02 00:00:00.000'),
                           (?, 'tmdb:tv:1399', 'tv', 0, '2026-01-03 00:00:00.000', '2026-01-03 00:00:00.000', '2026-01-03 00:00:00.000')
                    """,
                arguments: [folderID.uuidString, folderID.uuidString]
            )
        }

        try Schema.migrator.migrate(queue)

        let store = GRDBFolderStore(writer: queue)
        let folders = try await store.folders()
        #expect(folders.map(\.id) == [folderID])
        #expect(folders.first?.dirtyVersion == 3)
        let items = try await store.items(in: folderID)
        #expect(items.map(\.titleID.rawValue) == ["tmdb:movie:603", "tmdb:tv:1399"])
        #expect(items.map(\.isWatched) == [true, false])
        #expect(items.allSatisfy { $0.deletedAt == nil })
        #expect(items.first?.addedAt == Date(timeIntervalSince1970: 1_767_225_600))
    }

    @Test(arguments: [
        ("tmdb:movie:603", "de", "en"),
        ("tmdb:movie:603", "en", "de"),
        ("tmdb:movie:0", "en", "en"),
        ("tmdb:tv:12x", "en", "en"),
        ("imdb:movie:12", "en", "en"),
    ])
    func refusesMetadataWithAnInvalidTitleIDOrLanguage(titleID: String, language: String, overviewLanguage: String) throws {
        let queue = try DatabaseQueue()
        try Schema.migrator.migrate(queue)
        #expect(throws: DatabaseError.self) {
            try queue.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO titleMetadata (titleId, language, title, originalTitle, overviewLanguage, fetchedAt)
                        VALUES (?, ?, 'Example', 'Example', ?, '2026-01-01 00:00:00.000')
                        """,
                    arguments: [titleID, language, overviewLanguage]
                )
            }
        }
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
