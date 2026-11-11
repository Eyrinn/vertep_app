// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// What a build is configured to search with. The values come from the local build
/// configuration, which git does not track, through the app's Info.plist.
public struct SearchConfiguration: Sendable, Equatable {
    /// The Info.plist key of the proxy's base URL.
    public static let proxyBaseURLKey = "VertepProxyBaseURL"
    /// The Info.plist key of the personal TMDB API key.
    public static let tmdbAPIKeyKey = "VertepTMDBAPIKey"

    /// The base URL of a proxy that follows `docs/search-api.md`, or nil when none is
    /// configured.
    public var proxyBaseURL: URL?
    /// A personal TMDB API key, or nil when none is configured.
    public var tmdbAPIKey: String?

    public init(proxyBaseURL: URL?, tmdbAPIKey: String?) {
        self.proxyBaseURL = proxyBaseURL
        self.tmdbAPIKey = tmdbAPIKey
    }

    /// Reads the configuration from an Info.plist. An empty value, a value whose build
    /// setting was never expanded, and a base URL that is not an HTTPS URL with a host
    /// read as not configured.
    ///
    /// - Parameter readsPersonalKey: Whether to read the personal TMDB key. Only a debug
    ///   build reads it. When this is false, the key reads as not configured, whatever
    ///   the Info.plist holds.
    public init(infoDictionary: [String: Any]?, readsPersonalKey: Bool) {
        func value(_ key: String) -> String? {
            guard let text = (infoDictionary?[key] as? String)?.trimmingCharacters(in: .whitespaces),
                  !text.isEmpty, !text.contains("$(") else { return nil }
            return text
        }
        let url = value(Self.proxyBaseURLKey).flatMap(URL.init(string:))
        let isHTTPS = url?.scheme?.lowercased() == "https" && url?.host()?.isEmpty == false
        self.init(
            proxyBaseURL: isHTTPS ? url : nil,
            tmdbAPIKey: readsPersonalKey ? value(Self.tmdbAPIKeyKey) : nil
        )
    }

    /// Which search a build uses.
    public enum Choice: Sendable, Equatable {
        /// The proxy, at this base URL.
        case proxy(URL)
        /// TMDB directly, with this personal key.
        case direct(apiKey: String)
        /// No search: a search reports that it is not configured.
        case notConfigured
    }

    /// The proxy when a base URL is configured and the device supports App Attest;
    /// otherwise TMDB directly when a personal key is configured; otherwise no search.
    public func choice(appAttestSupported: Bool) -> Choice {
        if let proxyBaseURL, appAttestSupported { return .proxy(proxyBaseURL) }
        if let tmdbAPIKey { return .direct(apiKey: tmdbAPIKey) }
        return .notConfigured
    }
}
