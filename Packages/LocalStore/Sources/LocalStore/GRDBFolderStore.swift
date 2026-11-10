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
                .filter(Column("folderId") == folderID.uuidString)
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
}
