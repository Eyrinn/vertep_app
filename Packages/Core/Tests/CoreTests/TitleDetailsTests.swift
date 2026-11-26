// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Core
import Testing

/// A details provider that knows a fixed set of titles, as a test or a preview supplies one.
private struct FixedTitleDetailsProvider: TitleDetailsProvider {
    let known: [TitleDetails]

    func details(_ request: TitleDetailsRequest) async throws(TitleDetailsError) -> TitleDetailsResponse {
        let found = request.ids.compactMap { id in known.first { $0.id == id } }
        let notFound = request.ids.filter { id in !known.contains { $0.id == id } }
        return TitleDetailsResponse(results: found, notFound: notFound)
    }
}

/// Code that knows only the contract.
private func overview(of id: TitleID, from provider: any TitleDetailsProvider) async throws -> String? {
    let request = try #require(TitleDetailsRequest(ids: [id], language: .en))
    return try await provider.details(request).results.first?.overview
}

@Suite struct TitleDetailsTests {
    private func id(_ raw: String) throws -> TitleID {
        try #require(TitleID(rawValue: raw))
    }

    @Test func codeThatDependsOnlyOnCoreReceivesTheFakeDetails() async throws {
        let movie = TitleDetails(
            id: try id("tmdb:movie:101"), title: "Example Movie", originalTitle: "Example Movie", year: 2001,
            posterPath: nil, director: "Example Director", creator: nil, cast: ["Example Actor"],
            overview: "An example overview.", overviewLanguage: .en,
            genres: [TitleGenre(id: 18, name: "Drama")], runtime: 101
        )
        let provider = FixedTitleDetailsProvider(known: [movie])

        #expect(try await overview(of: movie.id, from: provider) == "An example overview.")
        let unknown = try #require(TitleDetailsRequest(ids: [try id("tmdb:tv:9")], language: .en))
        #expect(try await provider.details(unknown) == TitleDetailsResponse(results: [], notFound: [try id("tmdb:tv:9")]))
    }

    @Test func aRequestAsksForEachIdOnceInTheOrderOfItsFirstAppearance() throws {
        let a = try id("tmdb:movie:1"), b = try id("tmdb:tv:1"), c = try id("tmdb:movie:2")
        let request = try #require(TitleDetailsRequest(ids: [a, b, a, c, b], language: .uk))
        #expect(request.ids == [a, b, c])
        #expect(request.language == .uk)
    }

    @Test func aRequestHoldsOneToTwentyIds() throws {
        let ids = try (1...21).map { try id("tmdb:movie:\($0)") }
        #expect(TitleDetailsRequest(ids: [], language: .en) == nil)
        #expect(TitleDetailsRequest(ids: Array(ids.prefix(20)), language: .en)?.ids.count == 20)
        #expect(TitleDetailsRequest(ids: ids, language: .en) == nil)
        // Repeated ids count once.
        #expect(TitleDetailsRequest(ids: Array(ids.prefix(20)) + [ids[0]], language: .en) != nil)
    }

    @Test func nothingConfiguredReportsIt() async throws {
        let request = try #require(TitleDetailsRequest(ids: [try id("tmdb:movie:1")], language: .en))
        await #expect(throws: TitleDetailsError.notConfigured) {
            try await NotConfiguredTitleDetailsProvider().details(request)
        }
    }
}
