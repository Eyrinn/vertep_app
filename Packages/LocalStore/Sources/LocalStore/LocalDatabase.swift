// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Core
import Foundation
import GRDB

/// The app's local database. Opening it runs every migration it has not run yet.
///
/// The storage library stays behind this type: callers get the protocols `Core`
/// declares, and never a type of the library.
public struct LocalDatabase: Sendable {
    let writer: any DatabaseWriter

    private init(writer: any DatabaseWriter) throws {
        try Schema.migrator.migrate(writer)
        self.writer = writer
    }

    /// Opens the database file at `url`, and creates it and its directory when missing.
    public static func open(at url: URL) throws -> LocalDatabase {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return try LocalDatabase(writer: DatabasePool(path: url.path))
    }

    /// Opens a database that lives in memory only.
    ///
    /// Databases opened with the same `name` share their content while one of them is
    /// open, which lets a test open the same database twice. With no name, each call
    /// opens a database of its own.
    public static func inMemory(named name: String? = nil) throws -> LocalDatabase {
        let queue = try name.map { try DatabaseQueue(named: $0) } ?? DatabaseQueue()
        return try LocalDatabase(writer: queue)
    }

    /// The folders and the titles in them.
    public var folderStore: any FolderStore {
        GRDBFolderStore(writer: writer)
    }
}
