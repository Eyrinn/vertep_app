// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Core
import Foundation
import Search
import Testing

@Suite struct DirectTMDBTitleDetailsTests {
    /// Synthetic movie details with credits, in the language the test names.
    static func movie(overview: String) -> FakeHTTP.Response {
        .json(200, """
        {"id":101,"title":"Example Movie","original_title":"Example Original","release_date":"1999-05-21",
         "poster_path":"/example-poster.jpg","overview":"\(overview)","runtime":117,
         "genres":[{"id":27,"name":"Horror"},{"id":878,"name":"Science Fiction"}],
         "credits":{
           "cast":[{"name":"Example Actor 2","order":1},{"name":"Example Actor 1","order":0}],
           "crew":[{"name":"Example Writer","job":"Screenplay"},{"name":"Example Director","job":"Director"},
                   {"name":"Example Director","job":"Director"},{"name":"Second Director","job":"Director"}]}}
        """)
    }

    /// Synthetic series details with credits.
    static let series = FakeHTTP.Response.json(200, """
    {"id":202,"name":"Example Series","original_name":"Example Original Series","first_air_date":"2008-01-20",
     "poster_path":null,"overview":"","episode_run_time":[],"last_episode_to_air":{"runtime":47},
     "genres":[{"id":18,"name":"Drama"}],"created_by":[{"name":"Example Creator"}],
     "credits":{"cast":[{"name":"Example Actor 3","order":0}],"crew":[{"name":"Not a Director","job":"Director"}]}}
    """)

    static let movieID = TitleID(rawValue: "tmdb:movie:101")!
    static let seriesID = TitleID(rawValue: "tmdb:tv:202")!
    static let unknownID = TitleID(rawValue: "tmdb:movie:999999")!

    private func details(
        _ ids: [TitleID],
        _ language: SearchLanguage,
        _ http: FakeHTTP
    ) async throws -> TitleDetailsResponse {
        let request = try #require(TitleDetailsRequest(ids: ids, language: language))
        return try await DirectTMDBTitleDetails(apiKey: "example-key", transport: http).details(request)
    }

    @Test func aMovieAndASeriesAreMappedAndAnUnknownIdIsNotFound() async throws {
        let http = FakeHTTP([
            "/3/movie/101": [Self.movie(overview: "An example overview.")],
            "/3/tv/202": [Self.series],
            "/3/movie/999999": [.json(404, #"{"status_code":34}"#)],
        ])

        let response = try await details([Self.movieID, Self.seriesID, Self.unknownID], .en, http)

        #expect(response == TitleDetailsResponse(
            results: [
                TitleDetails(
                    id: Self.movieID, title: "Example Movie", originalTitle: "Example Original", year: 1999,
                    posterPath: "/example-poster.jpg", director: "Example Director, Second Director", creator: nil,
                    cast: ["Example Actor 1", "Example Actor 2"], overview: "An example overview.", overviewLanguage: .en,
                    genres: [TitleGenre(id: 27, name: "Horror"), TitleGenre(id: 878, name: "Science Fiction")], runtime: 117
                ),
                TitleDetails(
                    id: Self.seriesID, title: "Example Series", originalTitle: "Example Original Series", year: 2008,
                    posterPath: nil, director: nil, creator: "Example Creator",
                    cast: ["Example Actor 3"], overview: nil, overviewLanguage: nil,
                    genres: [TitleGenre(id: 18, name: "Drama")], runtime: 47
                ),
            ],
            notFound: [Self.unknownID]
        ))
        let request = try #require(http.requests(to: "/3/movie/101").first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.themoviedb.org/3/movie/101"
            + "?language=en-US&append_to_response=credits&api_key=example-key")
        // An English request asks for no other language, even without an overview.
        #expect(http.requests(to: "/3/tv/202").count == 1)
    }

    @Test func aUkrainianRequestWithNoUkrainianOverviewGetsTheEnglishOneMarkedEnglish() async throws {
        let http = FakeHTTP(["/3/movie/101": [Self.movie(overview: ""), Self.movie(overview: "An English overview.")]])

        let movie = try #require(try await details([Self.movieID], .uk, http).results.first)

        #expect(movie.overview == "An English overview.")
        #expect(movie.overviewLanguage == .en)
        #expect(http.requests(to: "/3/movie/101").map { $0.url?.query() } == [
            "language=uk-UA&append_to_response=credits&api_key=example-key",
            "language=en-US&api_key=example-key",
        ])
    }

    @Test func aUkrainianOverviewIsMarkedUkrainian() async throws {
        let http = FakeHTTP(["/3/movie/101": [Self.movie(overview: "An overview in Ukrainian.")]])
        let movie = try #require(try await details([Self.movieID], .uk, http).results.first)
        #expect(movie.overview == "An overview in Ukrainian.")
        #expect(movie.overviewLanguage == .uk)
        #expect(http.requests.count == 1)
    }

    @Test func aTitleWithNoOverviewInEitherLanguageHasNone() async throws {
        let http = FakeHTTP(["/3/movie/101": [Self.movie(overview: "")]])
        let movie = try #require(try await details([Self.movieID], .uk, http).results.first)
        #expect(movie.overview == nil)
        #expect(movie.overviewLanguage == nil)
    }

    @Test(arguments: [
        (FakeHTTP.Response.json(401, #"{"status_code":7}"#), TitleDetailsError.failed),
        (.json(429, "{}"), .unavailable),
        (.json(503, "{}"), .unavailable),
        (.json(200, "not json"), .unavailable),
    ])
    func aFailedTitleFailsTheRequest(answer: FakeHTTP.Response, error: TitleDetailsError) async throws {
        let http = FakeHTTP(["/3/movie/101": [Self.movie(overview: "An overview.")], "/3/tv/202": [answer]])
        await #expect(throws: error) {
            try await details([Self.movieID, Self.seriesID], .en, http)
        }
    }

    @Test func aRequestWithNoResponseIsUnavailable() async throws {
        await #expect(throws: TitleDetailsError.unavailable) {
            try await details([Self.movieID], .en, FakeHTTP([:]))
        }
    }
}
