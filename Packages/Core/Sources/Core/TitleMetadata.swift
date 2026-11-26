// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// What the app stores about a title in one language, so that a folder row shows without
/// a network. Every folder reads the same metadata of a title.
///
/// A title added from a search result has only the fields a search result carries: its
/// details are nil until details for it are written.
public struct TitleMetadata: Sendable, Hashable, Identifiable {
    public var titleID: TitleID
    /// The language the fields were asked in.
    public var language: SearchLanguage
    public var title: String
    public var originalTitle: String
    public var year: Int?
    public var posterPath: String?
    /// For a movie, its director or directors. Always nil for a series.
    public var director: String?
    /// For a series, its creator or creators. Always nil for a movie.
    public var creator: String?
    /// The names of the cast in billing order. Nil until details are written; an empty
    /// list means that TMDB lists no cast.
    public var cast: [String]?
    public var overview: String?
    /// The language of `overview`, which can differ from `language`.
    public var overviewLanguage: SearchLanguage?
    /// Nil until details are written; an empty list means that TMDB lists no genre.
    public var genres: [TitleGenre]?
    /// The runtime in minutes. For a series, the runtime of one episode.
    public var runtime: Int?
    /// When the app got these fields.
    public var fetchedAt: Date

    public var id: TitleID { titleID }
    public var mediaType: MediaType { titleID.mediaType }

    /// Whether details were written, rather than only the fields of a search result.
    public var hasDetails: Bool { cast != nil && genres != nil }

    public init(
        titleID: TitleID,
        language: SearchLanguage,
        title: String,
        originalTitle: String,
        year: Int?,
        posterPath: String?,
        director: String?,
        creator: String?,
        cast: [String]?,
        overview: String?,
        overviewLanguage: SearchLanguage?,
        genres: [TitleGenre]?,
        runtime: Int?,
        fetchedAt: Date
    ) {
        self.titleID = titleID
        self.language = language
        self.title = title
        self.originalTitle = originalTitle
        self.year = year
        self.posterPath = posterPath
        self.director = director
        self.creator = creator
        self.cast = cast
        self.overview = overview
        self.overviewLanguage = overviewLanguage
        self.genres = genres
        self.runtime = runtime
        self.fetchedAt = fetchedAt
    }

    /// The fields of a search result in `language`, with no details.
    public init(_ result: TitleSearchResult, language: SearchLanguage, fetchedAt: Date) {
        self.init(
            titleID: result.id,
            language: language,
            title: result.title,
            originalTitle: result.originalTitle,
            year: result.year,
            posterPath: result.posterPath,
            director: result.director,
            creator: result.creator,
            cast: nil,
            overview: nil,
            overviewLanguage: nil,
            genres: nil,
            runtime: nil,
            fetchedAt: fetchedAt
        )
    }

    /// Every field of a details result in `language`, the language it was requested in.
    public init(_ details: TitleDetails, language: SearchLanguage, fetchedAt: Date) {
        self.init(
            titleID: details.id,
            language: language,
            title: details.title,
            originalTitle: details.originalTitle,
            year: details.year,
            posterPath: details.posterPath,
            director: details.director,
            creator: details.creator,
            cast: details.cast,
            overview: details.overview,
            overviewLanguage: details.overviewLanguage,
            genres: details.genres,
            runtime: details.runtime,
            fetchedAt: fetchedAt
        )
    }
}
