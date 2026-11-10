// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// What a folder is for. Each device has exactly one personal folder.
public enum FolderKind: String, Sendable, Hashable, CaseIterable, Codable {
    case personal
}

/// A list of titles.
public struct Folder: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var kind: FolderKind
    public var name: String
    public var createdAt: Date
    /// Goes up when the folder's content changes locally, so that a later sync can tell
    /// which folders changed since it last ran.
    public var dirtyVersion: Int64

    public init(id: UUID, kind: FolderKind, name: String, createdAt: Date, dirtyVersion: Int64) {
        self.id = id
        self.kind = kind
        self.name = name
        self.createdAt = createdAt
        self.dirtyVersion = dirtyVersion
    }
}

/// A title in a folder. A title is in a folder at most once.
///
/// Each field that can change after the item is added carries its own update date, so
/// that a later sync can merge changes field by field.
public struct FolderItem: Sendable, Hashable {
    public var folderID: UUID
    public var titleID: TitleID
    public var isWatched: Bool
    public var watchedUpdatedAt: Date
    public var addedAt: Date
    public var updatedAt: Date

    public var mediaType: MediaType { titleID.mediaType }

    public init(
        folderID: UUID,
        titleID: TitleID,
        isWatched: Bool,
        watchedUpdatedAt: Date,
        addedAt: Date,
        updatedAt: Date
    ) {
        self.folderID = folderID
        self.titleID = titleID
        self.isWatched = isWatched
        self.watchedUpdatedAt = watchedUpdatedAt
        self.addedAt = addedAt
        self.updatedAt = updatedAt
    }
}
