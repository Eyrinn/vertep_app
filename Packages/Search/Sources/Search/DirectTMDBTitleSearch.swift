// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Core
import Foundation

/// Searches titles directly at TMDB with a personal API key, for the Simulator and for
/// forks that run no proxy.
///
/// It calls TMDB's multi search once per query, drops the people it finds, and returns the
/// same results as the proxy. TMDB's search does not name directors or creators, and this
/// search sends no further request for them, so both are always nil.
public struct DirectTMDBTitleSearch: TitleSearch {
    /// TMDB's API, version 3.
    static let apiBaseURL = URL(string: "https://api.themoviedb.org/3")!

    private let apiKey: String
    private let transport: any HTTPTransport

    /// `apiKey` is a personal TMDB API key from the local build configuration.
    public init(apiKey: String, transport: any HTTPTransport = URLSession.shared) {
        self.apiKey = apiKey
        self.transport = transport
    }

    public func search(_ query: String, language: SearchLanguage) async throws(TitleSearchError) -> [TitleSearchResult] {
        guard let query = SearchQuery(query) else { return [] }
        guard let url = Self.apiBaseURL.appendingRawPath("/search/multi", query: [
            ("query", query.text),
            ("language", language.tmdbLanguage),
            ("include_adult", "false"),
            ("page", "1"),
            ("api_key", apiKey),
        ]) else { throw .failed }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw .unavailable
        }
        switch response.statusCode {
        case 200..<300:
            break
        case 401, 404:
            // TMDB refused the key or the request. Sending it again would not change that.
            throw .failed
        default:
            throw .unavailable
        }
        guard let body = try? JSONDecoder().decode(MultiSearch.self, from: data) else { throw .unavailable }
        return Array(body.results.compactMap(\.titleSearchResult).prefix(TitleSearchResult.maximumCount))
    }
}

extension SearchLanguage {
    /// The language TMDB is asked for.
    var tmdbLanguage: String {
        switch self {
        case .uk: "uk-UA"
        case .en: "en-US"
        }
    }
}

/// The part of TMDB's multi search response that a result needs.
private struct MultiSearch: Decodable {
    struct Item: Decodable {
        let id: Int
        let mediaType: String
        let title: String?
        let originalTitle: String?
        let name: String?
        let originalName: String?
        let releaseDate: String?
        let firstAirDate: String?
        let posterPath: String?

        enum CodingKeys: String, CodingKey {
            case id
            case mediaType = "media_type"
            case title
            case originalTitle = "original_title"
            case name
            case originalName = "original_name"
            case releaseDate = "release_date"
            case firstAirDate = "first_air_date"
            case posterPath = "poster_path"
        }

        /// A movie or a series as a search result, or nil for a person or an item
        /// without an id or a title.
        var titleSearchResult: TitleSearchResult? {
            guard let mediaType = MediaType(rawValue: mediaType),
                  let id = TitleID(mediaType: mediaType, tmdbID: id) else { return nil }
            let isMovie = mediaType == .movie
            let original = (isMovie ? originalTitle : originalName).nonEmpty
            guard let title = (isMovie ? title : name).nonEmpty ?? original else { return nil }
            return TitleSearchResult(
                id: id,
                title: title,
                originalTitle: original ?? title,
                year: Self.year(of: isMovie ? releaseDate : firstAirDate),
                posterPath: posterPath.nonEmpty,
                director: nil,
                creator: nil
            )
        }

        /// The year of a date that TMDB writes as `YYYY-MM-DD`, or nil when it writes none.
        static func year(of date: String?) -> Int? {
            guard let date, date.count >= 4 else { return nil }
            return Int(date.prefix(4))
        }
    }

    let results: [Item]
}

private extension Optional where Wrapped == String {
    /// The string, or nil when it is empty.
    var nonEmpty: String? {
        switch self {
        case .some(let text) where !text.isEmpty: text
        default: nil
        }
    }
}
