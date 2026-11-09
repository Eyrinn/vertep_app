// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// The kind of title a TMDB id refers to.
public enum MediaType: String, Sendable, Hashable, CaseIterable, Codable {
    case movie
    case tv
}

/// The identity of a title: `tmdb:movie:<id>` or `tmdb:tv:<id>`.
///
/// The media type is part of the identity, because TMDB numbers movies and TV shows
/// separately and the same number can name one of each.
public struct TitleID: Sendable, Hashable, RawRepresentable, CustomStringConvertible {
    public let mediaType: MediaType
    public let tmdbID: Int

    /// Returns nil when `tmdbID` is not a positive number.
    public init?(mediaType: MediaType, tmdbID: Int) {
        guard tmdbID > 0 else { return nil }
        self.mediaType = mediaType
        self.tmdbID = tmdbID
    }

    /// Parses `tmdb:<movie|tv>:<id>`, where the id is a positive decimal number with no
    /// sign and no leading zero. Returns nil for every other string.
    public init?(rawValue: String) {
        let parts = rawValue.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "tmdb",
              let mediaType = MediaType(rawValue: String(parts[1])) else { return nil }
        let digits = parts[2]
        guard let first = digits.first, first != "0",
              digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let tmdbID = Int(digits) else { return nil }
        self.init(mediaType: mediaType, tmdbID: tmdbID)
    }

    public var rawValue: String { "tmdb:\(mediaType.rawValue):\(tmdbID)" }

    public var description: String { rawValue }
}
