// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Stores folders and the titles in them.
public protocol FolderStore: Sendable {
    /// Returns the personal folder, and creates it with `defaultName` when none exists.
    /// However often it is called, there is never more than one personal folder.
    func ensurePersonalFolder(defaultName: String) async throws -> Folder

    /// Every folder, oldest first.
    func folders() async throws -> [Folder]

    /// The titles in a folder, oldest first.
    func items(in folderID: UUID) async throws -> [FolderItem]

    /// Adds a title to its folder. A title that is already in the folder stays there once
    /// and keeps its stored fields. Returns false in that case.
    @discardableResult
    func insert(_ item: FolderItem) async throws -> Bool
}
