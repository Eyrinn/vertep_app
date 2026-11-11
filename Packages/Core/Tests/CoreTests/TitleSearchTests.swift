// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Core
import Testing

/// A search that returns fixed results, as a test or a preview supplies one.
private struct FixedTitleSearch: TitleSearch {
    let results: [TitleSearchResult]

    func search(_ query: String, language: SearchLanguage) async throws(TitleSearchError) -> [TitleSearchResult] {
        results
    }
}

/// Code that knows only the contract.
private func firstTitle(in search: any TitleSearch, for query: String) async throws -> String? {
    try await search.search(query, language: .en).first?.title
}

@Suite struct TitleSearchTests {
    @Test func codeThatDependsOnlyOnCoreReceivesTheFakeResults() async throws {
        let id = try #require(TitleID(rawValue: "tmdb:movie:101"))
        let result = TitleSearchResult(
            id: id, title: "Example Movie", originalTitle: "Example Movie", year: 2001,
            posterPath: nil, director: "Example Director", creator: nil
        )
        let title = try await firstTitle(in: FixedTitleSearch(results: [result]), for: "example")
        #expect(title == "Example Movie")
    }

    @Test(arguments: ["", " ", "a", " a ", "\n\tb\t", "é"])
    func aQueryShorterThanTwoCharactersIsNotSent(raw: String) {
        #expect(SearchQuery(raw) == nil)
    }

    @Test(arguments: [("ab", "ab"), ("  ab  ", "ab"), ("Alien", "Alien"), (" two words ", "two words")])
    func aLongEnoughQueryIsTrimmed(raw: String, text: String) {
        #expect(SearchQuery(raw)?.text == text)
    }

    @Test func aCharacterIsAGraphemeCluster() {
        // One flag is one character, though it is two scalars.
        #expect(SearchQuery("🇺🇦") == nil)
        #expect(SearchQuery("🇺🇦🇺🇦")?.text == "🇺🇦🇺🇦")
    }

    @Test(arguments: [
        (["uk"], SearchLanguage.uk), (["uk-UA"], .uk), (["en"], .en), (["en-GB"], .en),
        (["de"], .en), ([], .en), (["en", "uk"], .en),
    ])
    func theLanguageFollowsTheApp(localizations: [String], language: SearchLanguage) {
        #expect(SearchLanguage(appLocalizations: localizations) == language)
    }

    @Test func nothingConfiguredReportsIt() async {
        await #expect(throws: TitleSearchError.notConfigured) {
            try await NotConfiguredTitleSearch().search("Alien", language: .en)
        }
    }

    @Test func nothingConfiguredGivesNothingForAShortQuery() async throws {
        #expect(try await NotConfiguredTitleSearch().search("a", language: .en).isEmpty)
    }
}
