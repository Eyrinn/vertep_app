// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Core
import Foundation

/// Gets title details through a proxy that follows `docs/search-api.md`.
///
/// It sends one titles request per details request, which holds at most 20 ids, and asks
/// for the proxy's default number of cast names. The session, its App Attest key and its
/// retries are `ProxySession`'s, so a search and a details request given the same session
/// share it.
public struct ProxyTitleDetails: TitleDetailsProvider {
    private let session: ProxySession

    public init(session: ProxySession) {
        self.session = session
    }

    /// Returns the details in the order of the request. An answer that leaves a requested
    /// id out of both lists, or whose body cannot be read, is reported as `unavailable`.
    public func details(_ request: TitleDetailsRequest) async throws(TitleDetailsError) -> TitleDetailsResponse {
        let data: Data
        do {
            data = try await session.get("/v1/titles", query: [
                ("ids", request.ids.map(\.rawValue).joined(separator: ",")),
                ("lang", request.language.rawValue),
            ])
        } catch {
            throw error.detailsError
        }
        guard let body = try? JSONDecoder().decode(ProxyAPI.DetailsResponse.self, from: data) else {
            throw .unavailable
        }
        var found: [TitleID: TitleDetails] = [:]
        for details in body.results.compactMap(\.titleDetails) where found[details.id] == nil {
            found[details.id] = details
        }
        let notFound = Set(body.notFound.compactMap(TitleID.init(rawValue:)))

        var response = TitleDetailsResponse(results: [], notFound: [])
        for id in request.ids {
            if let details = found[id] {
                response.results.append(details)
            } else if notFound.contains(id) {
                response.notFound.append(id)
            } else {
                throw .unavailable
            }
        }
        return response
    }
}
