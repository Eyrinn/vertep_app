// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Core
import Foundation

/// Searches titles through a proxy that follows `docs/search-api.md`.
///
/// The session, its App Attest key and its retries are `ProxySession`'s. A search and a
/// details request that are given the same session share it.
public struct ProxyTitleSearch: TitleSearch {
    private let session: ProxySession

    public init(session: ProxySession) {
        self.session = session
    }

    /// A search with a session of its own.
    public init(
        baseURL: URL,
        attestation: any AppAttestation,
        keyStore: any KeyIDStore,
        transport: any HTTPTransport = URLSession.shared
    ) {
        self.init(session: ProxySession(baseURL: baseURL, attestation: attestation, keyStore: keyStore, transport: transport))
    }

    public func search(_ query: String, language: SearchLanguage) async throws(TitleSearchError) -> [TitleSearchResult] {
        guard let query = SearchQuery(query) else { return [] }
        let data: Data
        do {
            data = try await session.get("/v1/search", query: [("q", query.text), ("lang", language.rawValue)])
        } catch {
            throw error.searchError
        }
        guard let body = try? JSONDecoder().decode(ProxyAPI.SearchResponse.self, from: data) else {
            throw .unavailable
        }
        return Array(body.results.compactMap(\.titleSearchResult).prefix(TitleSearchResult.maximumCount))
    }
}
