// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Core
import Foundation
import Search
import Testing

@Suite struct ProxyTitleDetailsTests {
    let baseURL = URL(string: "https://proxy.example.com")!

    /// A synthetic answer of the titles request: a movie, a series, and an unknown id.
    static let answer = FakeHTTP.Response.json(200, """
    {"results":[
      {"id":"tmdb:movie:101","type":"movie","title":"Example Movie","originalTitle":"Example Original",
       "year":1999,"posterPath":"/example-poster.jpg","director":"Example Director","creator":null,
       "cast":["Example Actor 1","Example Actor 2"],"overview":"An example overview.","overviewLanguage":"en",
       "genres":[{"id":27,"name":"Horror"},{"id":878,"name":"Science Fiction"}],"runtime":117},
      {"id":"tmdb:tv:202","type":"tv","title":"Example Series","originalTitle":"Example Series",
       "year":null,"posterPath":null,"director":null,"creator":"Example Creator",
       "cast":[],"overview":null,"overviewLanguage":null,"genres":[],"runtime":47}
    ],"notFound":["tmdb:movie:999999"]}
    """)

    static let movie = TitleDetails(
        id: TitleID(rawValue: "tmdb:movie:101")!, title: "Example Movie", originalTitle: "Example Original",
        year: 1999, posterPath: "/example-poster.jpg", director: "Example Director", creator: nil,
        cast: ["Example Actor 1", "Example Actor 2"], overview: "An example overview.", overviewLanguage: .en,
        genres: [TitleGenre(id: 27, name: "Horror"), TitleGenre(id: 878, name: "Science Fiction")], runtime: 117
    )

    static let series = TitleDetails(
        id: TitleID(rawValue: "tmdb:tv:202")!, title: "Example Series", originalTitle: "Example Series",
        year: nil, posterPath: nil, director: nil, creator: "Example Creator",
        cast: [], overview: nil, overviewLanguage: nil, genres: [], runtime: 47
    )

    static let unknown = TitleID(rawValue: "tmdb:movie:999999")!

    private func request(_ ids: [TitleID], _ language: SearchLanguage = .en) throws -> TitleDetailsRequest {
        try #require(TitleDetailsRequest(ids: ids, language: language))
    }

    private func makeDetails(_ http: FakeHTTP, keys: InMemoryKeyIDStore = InMemoryKeyIDStore(keyID: "stored-key")) -> ProxyTitleDetails {
        ProxyTitleDetails(session: ProxySession(baseURL: baseURL, attestation: FakeAttestation(), keyStore: keys, transport: http))
    }

    @Test func returnsAMovieAndASeriesAndReportsAnUnknownIdAsNotFound() async throws {
        let http = FakeHTTP([
            "/v1/challenge": [ProxyAnswers.challenge(1)],
            "/v1/sessions/assert": [ProxyAnswers.session("token-1")],
            "/v1/titles": [Self.answer],
        ])

        let response = try await makeDetails(http).details(try request([Self.movie.id, Self.series.id, Self.unknown], .uk))

        #expect(response == TitleDetailsResponse(results: [Self.movie, Self.series], notFound: [Self.unknown]))
        let sent = try #require(http.requests(to: "/v1/titles").first)
        #expect(sent.httpMethod == "GET")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
        #expect(sent.url?.absoluteString == "https://proxy.example.com/v1/titles"
            + "?ids=tmdb%3Amovie%3A101%2Ctmdb%3Atv%3A202%2Ctmdb%3Amovie%3A999999&lang=uk")
    }

    @Test func resultsFollowTheOrderOfTheRequest() async throws {
        let http = FakeHTTP([
            "/v1/challenge": [ProxyAnswers.challenge(1)],
            "/v1/sessions/assert": [ProxyAnswers.session("token-1")],
            "/v1/titles": [Self.answer],
        ])
        let response = try await makeDetails(http).details(try request([Self.unknown, Self.series.id, Self.movie.id]))
        #expect(response.results.map(\.id) == [Self.series.id, Self.movie.id])
    }

    @Test func anExpiredSessionIsRenewedAndTheRetryReturnsDetails() async throws {
        let http = FakeHTTP([
            "/v1/challenge": [ProxyAnswers.challenge(1), ProxyAnswers.challenge(2)],
            "/v1/sessions/assert": [ProxyAnswers.session("token-1"), ProxyAnswers.session("token-2")],
            "/v1/titles": [.error(401, "session_expired"), Self.answer],
        ])

        let response = try await makeDetails(http).details(try request([Self.movie.id, Self.series.id, Self.unknown]))

        #expect(response.results == [Self.movie, Self.series])
        #expect(http.requests(to: "/v1/titles").map { $0.value(forHTTPHeaderField: "Authorization") }
            == ["Bearer token-1", "Bearer token-2"])
    }

    @Test func aSecondExpiredAnswerFailsTheRequest() async throws {
        let http = FakeHTTP([
            "/v1/challenge": [ProxyAnswers.challenge(1)],
            "/v1/sessions/assert": [ProxyAnswers.session("token-1")],
            "/v1/titles": [.error(401, "session_expired")],
        ])
        await #expect(throws: TitleDetailsError.unavailable) {
            try await makeDetails(http).details(try request([Self.movie.id]))
        }
        #expect(http.requests(to: "/v1/titles").count == 2)
    }

    @Test func aSearchAndADetailsRequestShareOneSession() async throws {
        let http = FakeHTTP([
            "/v1/challenge": [ProxyAnswers.challenge(1)],
            "/v1/sessions/assert": [ProxyAnswers.session("token-1")],
            "/v1/search": [ProxyAnswers.results],
            "/v1/titles": [Self.answer],
        ])
        let session = ProxySession(
            baseURL: baseURL, attestation: FakeAttestation(), keyStore: InMemoryKeyIDStore(keyID: "stored-key"), transport: http
        )
        _ = try await ProxyTitleSearch(session: session).search("example", language: .en)
        _ = try await ProxyTitleDetails(session: session).details(try request([Self.movie.id, Self.series.id, Self.unknown]))
        #expect(http.requests(to: "/v1/sessions/assert").count == 1)
        #expect(http.requests(to: "/v1/titles").first?.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
    }

    @Test(arguments: [
        (FakeHTTP.Response.error(400, "invalid_request"), TitleDetailsError.failed),
        (.error(400, "invalid_query"), .failed),
        (.error(429, "too_many_requests"), .unavailable),
        (.error(503, "unavailable"), .unavailable),
        (.error(400, "an_unknown_code"), .unavailable),
        (.json(502, "<html>Bad gateway</html>"), .unavailable),
        (.json(200, "not json"), .unavailable),
        // An answer that leaves a requested id out of both lists.
        (.json(200, #"{"results":[],"notFound":[]}"#), .unavailable),
    ])
    func anErrorIsReported(answer: FakeHTTP.Response, error: TitleDetailsError) async throws {
        let http = FakeHTTP([
            "/v1/challenge": [ProxyAnswers.challenge(1)],
            "/v1/sessions/assert": [ProxyAnswers.session("token-1")],
            "/v1/titles": [answer],
        ])
        await #expect(throws: error) {
            try await makeDetails(http).details(try request([Self.movie.id]))
        }
        #expect(http.requests(to: "/v1/titles").count == 1)
    }

    @Test func aResultIsCheckedAndItsCastLimited() async throws {
        let cast = (1...15).map { #""Actor \#($0)""# }.joined(separator: ",")
        let http = FakeHTTP([
            "/v1/challenge": [ProxyAnswers.challenge(1)],
            "/v1/sessions/assert": [ProxyAnswers.session("token-1")],
            "/v1/titles": [.json(200, """
            {"results":[
              {"id":"tmdb:movie:5","type":"movie","title":"M","originalTitle":"M","year":null,"posterPath":null,
               "director":"D","creator":"Not a series","cast":[\(cast)],"overview":"","overviewLanguage":"en",
               "genres":[],"runtime":null},
              {"id":"tmdb:tv:6","type":"tv","title":"S","originalTitle":"S","year":null,"posterPath":null,
               "director":"Not a movie","creator":"C","cast":[],"overview":"An overview.","overviewLanguage":"de",
               "genres":[],"runtime":null}
            ],"notFound":[]}
            """)],
        ])
        let movie = try #require(TitleID(rawValue: "tmdb:movie:5"))
        let series = try #require(TitleID(rawValue: "tmdb:tv:6"))

        let results = try await makeDetails(http).details(try request([movie, series])).results

        #expect(results[0].cast.count == TitleDetails.castCount)
        #expect(results[0].creator == nil)
        // An empty overview is no overview, and has no language.
        #expect(results[0].overview == nil && results[0].overviewLanguage == nil)
        #expect(results[1].director == nil)
        #expect(results[1].overview == "An overview." && results[1].overviewLanguage == nil)
    }
}
