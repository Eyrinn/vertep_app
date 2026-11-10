// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Core
import Testing

@Suite struct TitleIDTests {
    @Test(arguments: [
        ("tmdb:movie:603", MediaType.movie, 603),
        ("tmdb:tv:1399", MediaType.tv, 1399),
    ])
    func parsesAValidID(raw: String, mediaType: MediaType, tmdbID: Int) throws {
        let id = try #require(TitleID(rawValue: raw))
        #expect(id.mediaType == mediaType)
        #expect(id.tmdbID == tmdbID)
        #expect(id.rawValue == raw)
    }

    @Test(arguments: [
        "", "tmdb:movie", "tmdb:movie:", "tmdb:person:1", "imdb:movie:1", "tmdb:movie:0",
        "tmdb:movie:007", "tmdb:movie:-1", "tmdb:movie:+1", "tmdb:movie:1a", "tmdb:movie:1:2",
        "TMDB:movie:1", "tmdb:Movie:1", "tmdb:movie:١٢",
    ])
    func rejectsAnInvalidID(raw: String) {
        #expect(TitleID(rawValue: raw) == nil)
    }

    @Test func rejectsANonPositiveNumber() {
        #expect(TitleID(mediaType: .movie, tmdbID: 0) == nil)
        #expect(TitleID(mediaType: .tv, tmdbID: -5) == nil)
    }

    @Test func theSameNumberNamesTwoTitles() throws {
        let movie = try #require(TitleID(mediaType: .movie, tmdbID: 42))
        let show = try #require(TitleID(mediaType: .tv, tmdbID: 42))
        #expect(movie != show)
    }
}
