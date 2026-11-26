// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Stores folders, the titles in them, and the metadata of those titles.
///
/// Removing a title from a folder keeps its item, marked with the removal date, so that a
/// removal can be undone and a later sync can pass it on. Only the items that are not
/// removed are a folder's titles.
public protocol FolderStore: Sendable {
    /// Returns the personal folder, and creates it with `defaultName` when none exists.
    /// However often it is called, there is never more than one personal folder.
    func ensurePersonalFolder(defaultName: String) async throws -> Folder

    /// Every folder, oldest first.
    func folders() async throws -> [Folder]

    /// The titles in a folder, oldest first. A removed title is not among them.
    func items(in folderID: UUID) async throws -> [FolderItem]

    /// Adds a title to its folder. A title that is already stored in the folder, removed
    /// or not, keeps its stored fields. Returns false in that case.
    @discardableResult
    func insert(_ item: FolderItem) async throws -> Bool

    /// Adds the title of a search result to a folder at `date`, and stores the result's
    /// fields as the title's metadata in `language`, with `date` as the fetch date.
    ///
    /// A removed title comes back with `date` as its new added date and keeps its other
    /// fields. A title that is in the folder already stays as it is, its metadata too, and
    /// the call returns false.
    @discardableResult
    func add(_ result: TitleSearchResult, language: SearchLanguage, to folderID: UUID, at date: Date) async throws -> Bool

    /// Removes a title from a folder: sets its removal date to `date` and changes nothing
    /// else. Returns false when the folder holds no such title.
    @discardableResult
    func remove(_ titleID: TitleID, from folderID: UUID, at date: Date) async throws -> Bool

    /// Undoes a removal: clears the removal date and keeps every other field, the watched
    /// flag and the added date included. Returns false when the title is not removed.
    @discardableResult
    func restore(_ titleID: TitleID, in folderID: UUID) async throws -> Bool

    /// Sets the watched flag of a title, with `date` as the update date of the flag and of
    /// the item. Returns false when the folder holds no such title.
    @discardableResult
    func setWatched(_ isWatched: Bool, for titleID: TitleID, in folderID: UUID, at date: Date) async throws -> Bool

    /// The stored metadata of each title that has some: in `language` where it is stored
    /// in that language, and otherwise in the language fetched last. A title with no
    /// stored metadata is not in the result.
    func metadata(for titleIDs: [TitleID], preferring language: SearchLanguage) async throws -> [TitleID: TitleMetadata]

    /// Stores metadata. Each one replaces the metadata stored for its title in its
    /// language, with its fetch date.
    func write(_ metadata: [TitleMetadata]) async throws
}
