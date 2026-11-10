// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Core
import Foundation
import Search
import Testing

@Suite struct DirectTMDBTitleSearchTests {
    /// A synthetic multi search answer: a movie, a person, a series, and a movie with
    /// empty fields.
    static let answer = FakeHTTP.Response.json(200, """
    {"page":1,"total_pages":1,"total_results":4,"results":[
      {"id":101,"media_type":"movie","title":"Example Movie","original_title":"Example Original",
       "release_date":"1999-05-21","poster_path":"/example-poster.jpg"},
      {"id":7,"media_type":"person","name":"Example Person"},
      {"id":202,"media_type":"tv","name":"Example Series","original_name":"Example Series",
       "first_air_date":"2008-01-20","poster_path":null},
      {"id":303,"media_type":"movie","title":"","original_title":"Untranslated",
       "release_date":"","poster_path":""}
    ]}
    """)

    @Test(arguments: ["", "a", " a "])
    func aShortQuerySendsNothing(query: String) async throws {
        let http = FakeHTTP([:])
        #expect(try await DirectTMDBTitleSearch(apiKey: "example-key", transport: http).search(query, language: .en).isEmpty)
        #expect(http.requests.isEmpty)
    }

    @Test(arguments: [(SearchLanguage.en, "en-US"), (.uk, "uk-UA")])
    func theRequestCarriesTheQueryTheLanguageAndTheKey(language: SearchLanguage, tmdbLanguage: String) async throws {
        let http = FakeHTTP(["/3/search/multi": [Self.answer]])
        _ = try await DirectTMDBTitleSearch(apiKey: "example-key", transport: http).search(" a+b c ", language: language)
        let request = try #require(http.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.themoviedb.org/3/search/multi"
            + "?query=a%2Bb%20c&language=\(tmdbLanguage)&include_adult=false&page=1&api_key=example-key")
    }

    @Test func peopleAreDroppedAndTitlesAreMapped() async throws {
        let http = FakeHTTP(["/3/search/multi": [Self.answer]])
        let results = try await DirectTMDBTitleSearch(apiKey: "example-key", transport: http).search("example", language: .en)
        #expect(results == [
            TitleSearchResult(
                id: TitleID(rawValue: "tmdb:movie:101")!, title: "Example Movie", originalTitle: "Example Original",
                year: 1999, posterPath: "/example-poster.jpg", director: nil, creator: nil
            ),
            TitleSearchResult(
                id: TitleID(rawValue: "tmdb:tv:202")!, title: "Example Series", originalTitle: "Example Series",
                year: 2008, posterPath: nil, director: nil, creator: nil
            ),
            TitleSearchResult(
                id: TitleID(rawValue: "tmdb:movie:303")!, title: "Untranslated", originalTitle: "Untranslated",
                year: nil, posterPath: nil, director: nil, creator: nil
            ),
        ])
    }

    @Test func resultsAreLimitedToTwenty() async throws {
        let items = (1...25).map { #"{"id":\#($0),"media_type":"movie","title":"Movie \#($0)","original_title":"Movie \#($0)"}"# }
        let http = FakeHTTP(["/3/search/multi": [.json(200, #"{"results":[\#(items.joined(separator: ","))]}"#)]])
        let results = try await DirectTMDBTitleSearch(apiKey: "example-key", transport: http).search("movie", language: .en)
        #expect(results.count == TitleSearchResult.maximumCount)
    }

    @Test(arguments: [
        (FakeHTTP.Response.json(401, #"{"status_code":7}"#), TitleSearchError.failed),
        (.json(404, "{}"), .failed),
        (.json(429, "{}"), .unavailable),
        (.json(503, "{}"), .unavailable),
        (.json(200, "not json"), .unavailable),
    ])
    func anErrorIsReported(answer: FakeHTTP.Response, error: TitleSearchError) async throws {
        let http = FakeHTTP(["/3/search/multi": [answer]])
        await #expect(throws: error) {
            try await DirectTMDBTitleSearch(apiKey: "example-key", transport: http).search("example", language: .en)
        }
        #expect(http.requests.count == 1)
    }

    @Test func aRequestWithNoResponseIsUnavailable() async throws {
        await #expect(throws: TitleSearchError.unavailable) {
            try await DirectTMDBTitleSearch(apiKey: "example-key", transport: FakeHTTP([:])).search("example", language: .en)
        }
    }
}
