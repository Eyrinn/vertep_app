// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Core
import Foundation
import GRDB

/// `FolderStore` on the local database.
struct GRDBFolderStore: FolderStore {
    let writer: any DatabaseWriter

    func ensurePersonalFolder(defaultName: String) async throws -> Folder {
        try await writer.write { db in
            let personal = FolderRecord.filter(Column("kind") == FolderKind.personal.rawValue)
            if let existing = try personal.fetchOne(db) {
                return try existing.folder()
            }
            let folder = Folder(
                id: UUID(),
                kind: .personal,
                name: defaultName,
                createdAt: Date(),
                dirtyVersion: 0
            )
            try FolderRecord(folder).insert(db)
            // Read the row back, so the caller gets the values as stored: the database
            // keeps dates to the millisecond.
            return try personal.fetchOne(db)!.folder()
        }
    }

    func folders() async throws -> [Folder] {
        try await writer.read { db in
            try FolderRecord
                .order(Column("createdAt"), Column("id"))
                .fetchAll(db)
                .map { try $0.folder() }
        }
    }

    func items(in folderID: UUID) async throws -> [FolderItem] {
        try await writer.read { db in
            try FolderItemRecord
                .filter(Column("folderId") == folderID.uuidString && Column("deletedAt") == nil)
                .order(Column("addedAt"), Column("titleId"))
                .fetchAll(db)
                .map { try $0.item() }
        }
    }

    @discardableResult
    func insert(_ item: FolderItem) async throws -> Bool {
        try await writer.write { db in
            // A title already in the folder keeps its row; the new one is dropped.
            try FolderItemRecord(item).insert(db, onConflict: .ignore)
            return db.changesCount > 0
        }
    }

    @discardableResult
    func add(_ result: TitleSearchResult, language: SearchLanguage, to folderID: UUID, at date: Date) async throws -> Bool {
        try await writer.write { db in
            let key: StatementArguments = [folderID.uuidString, result.id.rawValue]
            let deletedAt = try Date?.fetchOne(
                db,
                sql: "SELECT deletedAt FROM folderItem WHERE folderId = ? AND titleId = ?",
                arguments: key
            )
            switch deletedAt {
            case .some(.some):
                // A removed title comes back as a new add, with its other fields kept.
                try db.execute(
                    sql: """
                        UPDATE folderItem SET deletedAt = NULL, addedAt = ?, updatedAt = ?
                        WHERE folderId = ? AND titleId = ?
                        """,
                    arguments: [date, date] + key
                )
            case .some(.none):
                // The title is in the folder already.
                return false
            case .none:
                let item = FolderItem(
                    folderID: folderID,
                    titleID: result.id,
                    isWatched: false,
                    watchedUpdatedAt: date,
                    addedAt: date,
                    updatedAt: date
                )
                try FolderItemRecord(item).insert(db)
            }
            try TitleMetadataRecord(TitleMetadata(result, language: language, fetchedAt: date))
                .insert(db, onConflict: .replace)
            return true
        }
    }

    @discardableResult
    func remove(_ titleID: TitleID, from folderID: UUID, at date: Date) async throws -> Bool {
        try await writer.write { db in
            try db.execute(
                sql: """
                    UPDATE folderItem SET deletedAt = ?
                    WHERE folderId = ? AND titleId = ? AND deletedAt IS NULL
                    """,
                arguments: [date, folderID.uuidString, titleID.rawValue]
            )
            return db.changesCount > 0
        }
    }

    @discardableResult
    func restore(_ titleID: TitleID, in folderID: UUID) async throws -> Bool {
        try await writer.write { db in
            try db.execute(
                sql: """
                    UPDATE folderItem SET deletedAt = NULL
                    WHERE folderId = ? AND titleId = ? AND deletedAt IS NOT NULL
                    """,
                arguments: [folderID.uuidString, titleID.rawValue]
            )
            return db.changesCount > 0
        }
    }

    @discardableResult
    func setWatched(_ isWatched: Bool, for titleID: TitleID, in folderID: UUID, at date: Date) async throws -> Bool {
        try await writer.write { db in
            try db.execute(
                sql: """
                    UPDATE folderItem SET isWatched = ?, watchedUpdatedAt = ?, updatedAt = ?
                    WHERE folderId = ? AND titleId = ? AND deletedAt IS NULL
                    """,
                arguments: [isWatched, date, date, folderID.uuidString, titleID.rawValue]
            )
            return db.changesCount > 0
        }
    }

    func metadata(for titleIDs: [TitleID], preferring language: SearchLanguage) async throws -> [TitleID: TitleMetadata] {
        try await writer.read { db in
            let rows = try TitleMetadataRecord
                .filter(titleIDs.map(\.rawValue).contains(Column("titleId")))
                .fetchAll(db)
                .map { try $0.metadata() }
            var chosen: [TitleID: TitleMetadata] = [:]
            for row in rows {
                guard let current = chosen[row.titleID] else {
                    chosen[row.titleID] = row
                    continue
                }
                if Self.prefers(row, over: current, language: language) {
                    chosen[row.titleID] = row
                }
            }
            return chosen
        }
    }

    func write(_ metadata: [TitleMetadata]) async throws {
        try await writer.write { db in
            for metadata in metadata {
                try TitleMetadataRecord(metadata).insert(db, onConflict: .replace)
            }
        }
    }

    /// Whether `row` is a better choice than `current`: the requested language first, then
    /// the metadata fetched last.
    private static func prefers(_ row: TitleMetadata, over current: TitleMetadata, language: SearchLanguage) -> Bool {
        let rowMatches = row.language == language
        let currentMatches = current.language == language
        if rowMatches != currentMatches { return rowMatches }
        return row.fetchedAt > current.fetchedAt
    }
}
