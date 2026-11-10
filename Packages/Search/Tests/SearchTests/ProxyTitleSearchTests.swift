// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Core
import CryptoKit
import Foundation
import Search
import Testing

@Suite struct ProxyTitleSearchTests {
    let baseURL = URL(string: "https://proxy.example.com")!

    private func makeSearch(
        _ http: FakeHTTP,
        attestation: FakeAttestation = FakeAttestation(),
        keys: InMemoryKeyIDStore = InMemoryKeyIDStore(),
        baseURL: URL? = nil
    ) -> ProxyTitleSearch {
        ProxyTitleSearch(baseURL: baseURL ?? self.baseURL, attestation: attestation, keyStore: keys, transport: http)
    }

    private func hash(ofChallenge n: Int) -> Data {
        Data(SHA256.hash(data: Data("challenge-\(n)".utf8)))
    }

    // MARK: - Query rules

    @Test(arguments: ["", "a", "  a  ", "\n"])
    func aShortQuerySendsNothing(query: String) async throws {
        let http = FakeHTTP([:])
        let results = try await makeSearch(http).search(query, language: .en)
        #expect(results.isEmpty)
        #expect(http.requests.isEmpty)
    }

    @Test func theQueryIsTrimmedEncodedAndSentWithTheLanguage() async throws {
        let http = FakeHTTP([
            "/prefix/v1/challenge": [ProxyAnswers.challenge(1)],
            "/prefix/v1/sessions/attest": [ProxyAnswers.session("token-1")],
            "/prefix/v1/search": [ProxyAnswers.results],
        ])
        let search = makeSearch(http, baseURL: URL(string: "https://proxy.example.com/prefix/")!)
        _ = try await search.search("  a+b c&d  ", language: .uk)
        let request = try #require(http.requests(to: "/prefix/v1/search").first)
        #expect(request.url?.absoluteString == "https://proxy.example.com/prefix/v1/search?q=a%2Bb%20c%26d&lang=uk")
        #expect(request.httpMethod == "GET")
    }

    // MARK: - Attestation and sessions

    @Test func theFirstSearchAttestsANewKeyOpensASessionAndReturnsResults() async throws {
        let http = FakeHTTP([
            "/v1/challenge": [ProxyAnswers.challenge(1)],
            "/v1/sessions/attest": [ProxyAnswers.session("token-1")],
            "/v1/search": [ProxyAnswers.results],
        ])
        let attestation = FakeAttestation()
        let keys = InMemoryKeyIDStore()

        let results = try await makeSearch(http, attestation: attestation, keys: keys).search("example", language: .en)

        #expect(attestation.calls == [.generateKey, .attest(keyID: "key-1", clientDataHash: hash(ofChallenge: 1))])
        #expect(keys.load() == "key-1")
        #expect(http.requests.map { $0.url?.path() } == ["/v1/challenge", "/v1/sessions/attest", "/v1/search"])

        let attest = http.requests[1]
        #expect(attest.httpMethod == "POST")
        #expect(attest.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(attest.jsonBody == [
            "keyId": "key-1",
            "challenge": ProxyAnswers.challengeText(1),
            "attestation": Data("attestation-of-key-1".utf8).base64EncodedString(),
        ])
        #expect(http.requests[2].value(forHTTPHeaderField: "Authorization") == "Bearer token-1")

        #expect(results == [
            TitleSearchResult(
                id: TitleID(rawValue: "tmdb:movie:101")!, title: "Example Movie", originalTitle: "Example Original",
                year: 1999, posterPath: "/example-poster.jpg", director: "Example Director", creator: nil
            ),
            TitleSearchResult(
                id: TitleID(rawValue: "tmdb:tv:202")!, title: "Example Series", originalTitle: "Example Series",
                year: nil, posterPath: nil, director: nil, creator: "Example Creator"
            ),
        ])
    }

    @Test func aStoredKeyOpensASessionWithAnAssertion() async throws {
        let http = FakeHTTP([
            "/v1/challenge": [ProxyAnswers.challenge(1)],
            "/v1/sessions/assert": [ProxyAnswers.session("token-1")],
            "/v1/search": [ProxyAnswers.results],
        ])
        let attestation = FakeAttestation()

        let results = try await makeSearch(http, attestation: attestation, keys: InMemoryKeyIDStore(keyID: "stored-key"))
            .search("example", language: .en)

        #expect(results.count == 2)
        #expect(attestation.calls == [.assert(keyID: "stored-key", clientDataHash: hash(ofChallenge: 1))])
        #expect(http.requests[1].jsonBody == [
            "keyId": "stored-key",
            "challenge": ProxyAnswers.challengeText(1),
            "assertion": Data("assertion-by-stored-key".utf8).base64EncodedString(),
        ])
    }

    @Test func laterSearchesReuseTheSession() async throws {
        let http = FakeHTTP([
            "/v1/challenge": [ProxyAnswers.challenge(1)],
            "/v1/sessions/attest": [ProxyAnswers.session("token-1")],
            "/v1/search": [ProxyAnswers.results],
        ])
        let search = makeSearch(http)
        _ = try await search.search("first", language: .en)
        _ = try await search.search("second", language: .en)
        #expect(http.requests(to: "/v1/challenge").count == 1)
        #expect(http.requests(to: "/v1/search").map { $0.value(forHTTPHeaderField: "Authorization") }
            == ["Bearer token-1", "Bearer token-1"])
    }

    @Test func searchesStartedTogetherOpenOneSession() async throws {
        let http = FakeHTTP([
            "/v1/challenge": [ProxyAnswers.challenge(1)],
            "/v1/sessions/attest": [ProxyAnswers.session("token-1")],
            "/v1/search": [ProxyAnswers.results],
        ])
        let search = makeSearch(http)
        async let first = search.search("first", language: .en)
        async let second = search.search("second", language: .en)
        _ = try await (first, second)
        #expect(http.requests(to: "/v1/sessions/attest").count == 1)
        #expect(http.requests(to: "/v1/search").count == 2)
    }

    @Test func anExpiredSessionIsRenewedAndTheRetryReturnsResults() async throws {
        let http = FakeHTTP([
            "/v1/challenge": [ProxyAnswers.challenge(1), ProxyAnswers.challenge(2)],
            "/v1/sessions/attest": [ProxyAnswers.session("token-1")],
            "/v1/sessions/assert": [ProxyAnswers.session("token-2")],
            "/v1/search": [.error(401, "session_expired"), ProxyAnswers.results],
        ])
        let attestation = FakeAttestation()

        let results = try await makeSearch(http, attestation: attestation).search("example", language: .en)

        #expect(results.count == 2)
        // The renewal signs an assertion with the key the first session attested.
        #expect(attestation.calls == [
            .generateKey,
            .attest(keyID: "key-1", clientDataHash: hash(ofChallenge: 1)),
            .assert(keyID: "key-1", clientDataHash: hash(ofChallenge: 2)),
        ])
        #expect(http.requests(to: "/v1/search").map { $0.value(forHTTPHeaderField: "Authorization") }
            == ["Bearer token-1", "Bearer token-2"])
    }

    @Test func aSecondExpiredAnswerFailsTheSearch() async throws {
        let http = FakeHTTP([
            "/v1/challenge": [ProxyAnswers.challenge(1)],
            "/v1/sessions/assert": [ProxyAnswers.session("token-1")],
            "/v1/search": [.error(401, "session_expired")],
        ])
        let search = makeSearch(http, keys: InMemoryKeyIDStore(keyID: "stored-key"))
        await #expect(throws: TitleSearchError.unavailable) {
            try await search.search("example", language: .en)
        }
        #expect(http.requests(to: "/v1/search").count == 2)
    }

    @Test func aRejectedStoredKeyIsReplacedByANewAttestedKeyOnce() async throws {
        let http = FakeHTTP([
            "/v1/challenge": [ProxyAnswers.challenge(1), ProxyAnswers.challenge(2)],
            "/v1/sessions/assert": [.error(403, "key_rejected")],
            "/v1/sessions/attest": [ProxyAnswers.session("token-1")],
            "/v1/search": [ProxyAnswers.results],
        ])
        let attestation = FakeAttestation()
        let keys = InMemoryKeyIDStore(keyID: "stored-key")

        let results = try await makeSearch(http, attestation: attestation, keys: keys).search("example", language: .en)

        #expect(results.count == 2)
        #expect(attestation.calls == [
            .assert(keyID: "stored-key", clientDataHash: hash(ofChallenge: 1)),
            .generateKey,
            .attest(keyID: "key-1", clientDataHash: hash(ofChallenge: 2)),
        ])
        #expect(keys.load() == "key-1")
    }

    @Test func aKeyTheDeviceLostIsReplacedByANewAttestedKey() async throws {
        let http = FakeHTTP([
            "/v1/challenge": [ProxyAnswers.challenge(1), ProxyAnswers.challenge(2)],
            "/v1/sessions/attest": [ProxyAnswers.session("token-1")],
            "/v1/search": [ProxyAnswers.results],
        ])
        let attestation = FakeAttestation(invalidKeys: ["stored-key"])
        let keys = InMemoryKeyIDStore(keyID: "stored-key")

        let results = try await makeSearch(http, attestation: attestation, keys: keys).search("example", language: .en)

        #expect(results.count == 2)
        #expect(http.requests(to: "/v1/sessions/assert").isEmpty)
        #expect(keys.load() == "key-1")
    }

    @Test func aRejectedNewKeyFailsTheSearch() async throws {
        let http = FakeHTTP([
            "/v1/challenge": [ProxyAnswers.challenge(1)],
            "/v1/sessions/attest": [.error(403, "key_rejected")],
        ])
        let attestation = FakeAttestation()
        let keys = InMemoryKeyIDStore()
        await #expect(throws: TitleSearchError.failed) {
            try await makeSearch(http, attestation: attestation, keys: keys).search("example", language: .en)
        }
        #expect(attestation.calls.filter { $0 == .generateKey }.count == 1)
        #expect(keys.load() == nil)
        #expect(http.requests(to: "/v1/search").isEmpty)
    }

    @Test func aRejectedStoredKeyAndARejectedNewKeyFailAfterOneAttestation() async throws {
        let http = FakeHTTP([
            "/v1/challenge": [ProxyAnswers.challenge(1), ProxyAnswers.challenge(2)],
            "/v1/sessions/assert": [.error(403, "key_rejected")],
            "/v1/sessions/attest": [.error(403, "key_rejected")],
        ])
        let search = makeSearch(http, keys: InMemoryKeyIDStore(keyID: "stored-key"))
        await #expect(throws: TitleSearchError.failed) {
            try await search.search("example", language: .en)
        }
        #expect(http.requests(to: "/v1/sessions/assert").count == 1)
        #expect(http.requests(to: "/v1/sessions/attest").count == 1)
    }

    @Test func aRefusedChallengeIsReplacedOnce() async throws {
        let http = FakeHTTP([
            "/v1/challenge": [ProxyAnswers.challenge(1), ProxyAnswers.challenge(2)],
            "/v1/sessions/assert": [.error(400, "invalid_challenge"), ProxyAnswers.session("token-1")],
            "/v1/search": [ProxyAnswers.results],
        ])
        let search = makeSearch(http, keys: InMemoryKeyIDStore(keyID: "stored-key"))
        #expect(try await search.search("example", language: .en).count == 2)
        #expect(http.requests(to: "/v1/sessions/assert").map { $0.jsonBody?["challenge"] }
            == [ProxyAnswers.challengeText(1), ProxyAnswers.challengeText(2)])
    }

    @Test func aChallengeRefusedTwiceFailsTheSearch() async throws {
        let http = FakeHTTP([
            "/v1/challenge": [ProxyAnswers.challenge(1), ProxyAnswers.challenge(2)],
            "/v1/sessions/attest": [.error(400, "invalid_challenge")],
        ])
        await #expect(throws: TitleSearchError.failed) {
            try await makeSearch(http).search("example", language: .en)
        }
        #expect(http.requests(to: "/v1/challenge").count == 2)
        #expect(http.requests(to: "/v1/sessions/attest").count == 2)
    }

    // MARK: - Errors

    @Test(arguments: [
        (FakeHTTP.Response.error(400, "invalid_request"), TitleSearchError.failed),
        (.error(400, "invalid_query"), .failed),
        (.error(429, "too_many_requests"), .unavailable),
        (.error(503, "unavailable"), .unavailable),
        (.error(400, "an_unknown_code"), .unavailable),
        (.error(500, "invalid_query"), .unavailable),
        (.json(502, "<html>Bad gateway</html>"), .unavailable),
        (.json(200, "not json"), .unavailable),
    ])
    func aSearchErrorIsReported(answer: FakeHTTP.Response, error: TitleSearchError) async throws {
        let http = FakeHTTP([
            "/v1/challenge": [ProxyAnswers.challenge(1)],
            "/v1/sessions/assert": [ProxyAnswers.session("token-1")],
            "/v1/search": [answer],
        ])
        await #expect(throws: error) {
            try await makeSearch(http, keys: InMemoryKeyIDStore(keyID: "stored-key")).search("example", language: .en)
        }
        // None of these is retried.
        #expect(http.requests(to: "/v1/search").count == 1)
    }

    @Test(arguments: [
        (FakeHTTP.Response.error(429, "too_many_requests"), TitleSearchError.unavailable),
        (.error(503, "unavailable"), .unavailable),
        (.error(400, "invalid_request"), .failed),
        (.json(200, #"{"challenge":"not base64!"}"#), .unavailable),
    ])
    func aChallengeErrorIsReported(answer: FakeHTTP.Response, error: TitleSearchError) async throws {
        let http = FakeHTTP(["/v1/challenge": [answer]])
        await #expect(throws: error) {
            try await makeSearch(http).search("example", language: .en)
        }
        #expect(http.requests(to: "/v1/challenge").count == 1)
    }

    @Test func aRequestWithNoResponseIsUnavailable() async throws {
        let http = FakeHTTP([:])
        await #expect(throws: TitleSearchError.unavailable) {
            try await makeSearch(http).search("example", language: .en)
        }
    }

    // MARK: - Results

    @Test func resultsAreCheckedAndLimitedToTwenty() async throws {
        var results = (1...25).map { n in
            #"{"id":"tmdb:movie:\#(n)","type":"movie","title":"Movie \#(n)","originalTitle":"Movie \#(n)","year":2000,"posterPath":null,"director":"Director \#(n)","creator":"Not a series"}"#
        }
        // A result whose type does not agree with its id, and one whose id is not a TMDB id.
        results.insert(#"{"id":"tmdb:tv:9","type":"movie","title":"X","originalTitle":"X","year":null,"posterPath":null,"director":null,"creator":null}"#, at: 0)
        results.insert(#"{"id":"person:9","type":"movie","title":"Y","originalTitle":"Y","year":null,"posterPath":null,"director":null,"creator":null}"#, at: 0)
        let http = FakeHTTP([
            "/v1/challenge": [ProxyAnswers.challenge(1)],
            "/v1/sessions/assert": [ProxyAnswers.session("token-1")],
            "/v1/search": [.json(200, #"{"results":[\#(results.joined(separator: ","))]}"#)],
        ])

        let found = try await makeSearch(http, keys: InMemoryKeyIDStore(keyID: "stored-key")).search("movie", language: .en)

        #expect(found.count == TitleSearchResult.maximumCount)
        #expect(found.first?.id.rawValue == "tmdb:movie:1")
        #expect(found.allSatisfy { $0.creator == nil && $0.director != nil })
    }
}
