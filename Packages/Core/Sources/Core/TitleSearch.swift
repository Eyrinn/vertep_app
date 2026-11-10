// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Searches titles by name.
///
/// Every implementation applies the same query rules: a query with fewer than
/// `SearchQuery.minimumLength` characters after trimming sends no request and gives an
/// empty result.
public protocol TitleSearch: Sendable {
    /// Returns at most `TitleSearchResult.maximumCount` movies and series that match
    /// `query`, with titles in `language` where a translation exists.
    func search(_ query: String, language: SearchLanguage) async throws(TitleSearchError) -> [TitleSearchResult]
}

/// The language a search asks titles in. It follows the app's language.
public enum SearchLanguage: String, Sendable, Hashable, CaseIterable, Codable {
    case uk
    case en

    /// The search language for the app's language. `localizations` is the list the app
    /// was launched in, most preferred first, as `Bundle.preferredLocalizations` gives it.
    /// Ukrainian gives `uk`, and every other language gives `en`.
    public init(appLocalizations localizations: [String]) {
        let first = localizations.first.map { Locale.Language(identifier: $0) }
        self = first?.languageCode == .ukrainian ? .uk : .en
    }
}

/// A query that is long enough to send.
public struct SearchQuery: Sendable, Hashable {
    /// The fewest characters a query has after trimming before it is sent.
    public static let minimumLength = 2

    /// The query without leading and trailing whitespace.
    public let text: String

    /// Trims `raw` and returns nil when fewer than `minimumLength` characters remain.
    /// A character is an extended grapheme cluster, as `String.count` counts it.
    public init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minimumLength else { return nil }
        text = trimmed
    }
}

/// One movie or series that a search found.
public struct TitleSearchResult: Sendable, Hashable, Identifiable {
    /// The most results one search returns.
    public static let maximumCount = 20

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

    public var mediaType: MediaType { id.mediaType }

    public init(
        id: TitleID,
        title: String,
        originalTitle: String,
        year: Int?,
        posterPath: String?,
        director: String?,
        creator: String?
    ) {
        self.id = id
        self.title = title
        self.originalTitle = originalTitle
        self.year = year
        self.posterPath = posterPath
        self.director = director
        self.creator = creator
    }
}

/// Why a search gave no results.
public enum TitleSearchError: Error, Sendable, Hashable {
    /// Neither a proxy nor a personal TMDB key is configured in this build.
    case notConfigured
    /// The search failed and a retry would fail the same way.
    case failed
    /// The search service cannot answer now. A later search can succeed.
    case unavailable
}

/// The search of a build in which nothing is configured. It sends nothing and reports
/// that search is not configured.
public struct NotConfiguredTitleSearch: TitleSearch {
    public init() {}

    public func search(_ query: String, language: SearchLanguage) async throws(TitleSearchError) -> [TitleSearchResult] {
        guard SearchQuery(query) != nil else { return [] }
        throw .notConfigured
    }
}
