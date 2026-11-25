// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Gets the details of titles the app already knows by id: the fields a folder row shows
/// beyond what a search result carries.
///
/// A test supplies a fake, so that code built on this contract runs without a network.
public protocol TitleDetailsProvider: Sendable {
    /// Returns the details of every title in `request` that TMDB knows, and the ids of
    /// the titles it does not know.
    func details(_ request: TitleDetailsRequest) async throws(TitleDetailsError) -> TitleDetailsResponse
}

/// The titles one details request asks for, and the language it asks them in.
public struct TitleDetailsRequest: Sendable, Hashable {
    /// The most titles one request asks for.
    public static let maximumCount = 20

    /// The requested ids, each once, in the order of their first appearance.
    public let ids: [TitleID]
    public let language: SearchLanguage

    /// Returns nil when `ids` holds no id, or more than `maximumCount` different ids.
    /// An id that appears more than once is asked for once.
    public init?(ids: [TitleID], language: SearchLanguage) {
        var seen = Set<TitleID>()
        let unique = ids.filter { seen.insert($0).inserted }
        guard !unique.isEmpty, unique.count <= Self.maximumCount else { return nil }
        self.ids = unique
        self.language = language
    }
}

/// The answer to one details request. Every requested id is in exactly one of the two
/// lists.
public struct TitleDetailsResponse: Sendable, Hashable {
    /// The details of each requested title that TMDB knows, in the order of the request.
    public var results: [TitleDetails]
    /// The requested ids that TMDB does not know.
    public var notFound: [TitleID]

    public init(results: [TitleDetails], notFound: [TitleID]) {
        self.results = results
        self.notFound = notFound
    }
}

/// A genre as TMDB names it.
public struct TitleGenre: Sendable, Hashable, Codable {
    /// TMDB's id of the genre. It is the same in every language.
    public var id: Int
    /// The name of the genre in the requested language.
    public var name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

/// The details of one movie or series.
public struct TitleDetails: Sendable, Hashable, Identifiable {
    /// The most cast names a details result carries.
    public static let castCount = 10

    public var id: TitleID
    /// The title in the requested language, or the original title when no translation
    /// exists.
    public var title: String
    public var originalTitle: String
    /// The year of the first release or the first air date.
    public var year: Int?
    /// TMDB's path of the poster image.
    public var posterPath: String?
    /// For a movie, its director or directors. Always nil for a series.
    public var director: String?
    /// For a series, its creator or creators. Always nil for a movie.
    public var creator: String?
    /// The names of the cast in billing order, at most `castCount`.
    public var cast: [String]
    /// A short description of the title, or nil when TMDB has none in the requested
    /// language or in English.
    public var overview: String?
    /// The language of `overview`. A Ukrainian request gets the English overview when no
    /// Ukrainian one exists, and then this is `en`. Nil when `overview` is nil.
    public var overviewLanguage: SearchLanguage?
    public var genres: [TitleGenre]
    /// The runtime in minutes. For a series, the runtime of one episode.
    public var runtime: Int?

    public var mediaType: MediaType { id.mediaType }

    public init(
        id: TitleID,
        title: String,
        originalTitle: String,
        year: Int?,
        posterPath: String?,
        director: String?,
        creator: String?,
        cast: [String],
        overview: String?,
        overviewLanguage: SearchLanguage?,
        genres: [TitleGenre],
        runtime: Int?
    ) {
        self.id = id
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
    }
}

/// Why a details request gave no answer.
public enum TitleDetailsError: Error, Sendable, Hashable {
    /// Neither a proxy nor a personal TMDB key is configured in this build.
    case notConfigured
    /// The request failed and a retry would fail the same way.
    case failed
    /// The service cannot answer now. A later request can succeed.
    case unavailable
}

/// The details provider of a build in which nothing is configured. It sends nothing and
/// reports that it is not configured.
public struct NotConfiguredTitleDetailsProvider: TitleDetailsProvider {
    public init() {}

    public func details(_ request: TitleDetailsRequest) async throws(TitleDetailsError) -> TitleDetailsResponse {
        throw .notConfigured
    }
}
