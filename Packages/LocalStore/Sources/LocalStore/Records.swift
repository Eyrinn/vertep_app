// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Core
import Foundation
import GRDB

/// A row of the folder table. It stays inside this package; callers see `Folder`.
struct FolderRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = Schema.folderTable
    static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy {
        .uppercaseString
    }

    var id: UUID
    var kind: String
    var name: String
    var createdAt: Date
    var dirtyVersion: Int64

    init(_ folder: Folder) {
        id = folder.id
        kind = folder.kind.rawValue
        name = folder.name
        createdAt = folder.createdAt
        dirtyVersion = folder.dirtyVersion
    }

    func folder() throws -> Folder {
        guard let kind = FolderKind(rawValue: kind) else {
            throw LocalStoreError.unknownFolderKind(kind)
        }
        return Folder(id: id, kind: kind, name: name, createdAt: createdAt, dirtyVersion: dirtyVersion)
    }
}

/// A row of the folder item table. It stays inside this package; callers see `FolderItem`.
struct FolderItemRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = Schema.folderItemTable
    static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy {
        .uppercaseString
    }

    var folderId: UUID
    var titleId: String
    var mediaType: String
    var isWatched: Bool
    var watchedUpdatedAt: Date
    var addedAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(_ item: FolderItem) {
        folderId = item.folderID
        titleId = item.titleID.rawValue
        mediaType = item.mediaType.rawValue
        isWatched = item.isWatched
        watchedUpdatedAt = item.watchedUpdatedAt
        addedAt = item.addedAt
        updatedAt = item.updatedAt
        deletedAt = item.deletedAt
    }

    func item() throws -> FolderItem {
        guard let titleID = TitleID(rawValue: titleId), titleID.mediaType.rawValue == mediaType else {
            throw LocalStoreError.invalidTitleID(titleId)
        }
        return FolderItem(
            folderID: folderId,
            titleID: titleID,
            isWatched: isWatched,
            watchedUpdatedAt: watchedUpdatedAt,
            addedAt: addedAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }
}

/// A row of the title metadata table. It stays inside this package; callers see
/// `TitleMetadata`. The cast and the genres are stored as JSON.
struct TitleMetadataRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = Schema.titleMetadataTable

    var titleId: String
    var language: String
    var title: String
    var originalTitle: String
    var year: Int?
    var posterPath: String?
    var director: String?
    var creator: String?
    var castNames: [String]?
    var overview: String?
    var overviewLanguage: String?
    var genres: [TitleGenre]?
    var runtime: Int?
    var fetchedAt: Date

    init(_ metadata: TitleMetadata) {
        titleId = metadata.titleID.rawValue
        language = metadata.language.rawValue
        title = metadata.title
        originalTitle = metadata.originalTitle
        year = metadata.year
        posterPath = metadata.posterPath
        director = metadata.director
        creator = metadata.creator
        castNames = metadata.cast
        overview = metadata.overview
        overviewLanguage = metadata.overviewLanguage?.rawValue
        genres = metadata.genres
        runtime = metadata.runtime
        fetchedAt = metadata.fetchedAt
    }

    func metadata() throws -> TitleMetadata {
        guard let titleID = TitleID(rawValue: titleId) else {
            throw LocalStoreError.invalidTitleID(titleId)
        }
        guard let language = SearchLanguage(rawValue: language) else {
            throw LocalStoreError.unknownLanguage(language)
        }
        let overviewLanguage = try overviewLanguage.map { raw in
            guard let language = SearchLanguage(rawValue: raw) else { throw LocalStoreError.unknownLanguage(raw) }
            return language
        }
        return TitleMetadata(
            titleID: titleID,
            language: language,
            title: title,
            originalTitle: originalTitle,
            year: year,
            posterPath: posterPath,
            director: director,
            creator: creator,
            cast: castNames,
            overview: overview,
            overviewLanguage: overviewLanguage,
            genres: genres,
            runtime: runtime,
            fetchedAt: fetchedAt
        )
    }
}

/// A stored value this version of the app cannot read.
public enum LocalStoreError: Error, Equatable {
    case unknownFolderKind(String)
    case invalidTitleID(String)
    case unknownLanguage(String)
}
