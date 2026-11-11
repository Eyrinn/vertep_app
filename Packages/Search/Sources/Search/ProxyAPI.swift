// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Core
import Foundation

/// The requests and responses of `docs/search-api.md`, as they travel.
enum ProxyAPI {
    struct Challenge: Decodable {
        let challenge: String
    }

    struct AttestRequest: Encodable {
        let keyId: String
        let challenge: String
        let attestation: String
    }

    struct AssertRequest: Encodable {
        let keyId: String
        let challenge: String
        let assertion: String
    }

    struct Session: Decodable {
        let sessionToken: String
    }

    struct SearchResponse: Decodable {
        let results: [Result]
    }

    struct Result: Decodable {
        let id: String
        let type: String
        let title: String
        let originalTitle: String
        let year: Int?
        let posterPath: String?
        let director: String?
        let creator: String?

        /// The result as Core declares it, or nil when its id is not a TMDB id or does not
        /// agree with its type. A director is kept only for a movie and a creator only for
        /// a series.
        var titleSearchResult: TitleSearchResult? {
            guard let id = TitleID(rawValue: id), id.mediaType.rawValue == type else { return nil }
            return TitleSearchResult(
                id: id,
                title: title,
                originalTitle: originalTitle,
                year: year,
                posterPath: posterPath,
                director: id.mediaType == .movie ? director : nil,
                creator: id.mediaType == .tv ? creator : nil
            )
        }
    }

    struct ErrorBody: Decodable {
        struct Detail: Decodable {
            let code: String
        }

        let error: Detail
    }

    /// The error codes of the contract, each with the status code it comes with.
    enum ErrorCode: String, CaseIterable, Error {
        case invalidRequest = "invalid_request"
        case invalidQuery = "invalid_query"
        case invalidChallenge = "invalid_challenge"
        case sessionExpired = "session_expired"
        case keyRejected = "key_rejected"
        case tooManyRequests = "too_many_requests"
        case unavailable

        var status: Int {
            switch self {
            case .invalidRequest, .invalidQuery, .invalidChallenge: 400
            case .sessionExpired: 401
            case .keyRejected: 403
            case .tooManyRequests: 429
            case .unavailable: 503
            }
        }

        /// Reads an error response. A body that is not JSON, an unknown code, or a code
        /// with a status the contract does not give it, reads as `unavailable`.
        init(status: Int, body: Data) {
            guard let body = try? JSONDecoder().decode(ErrorBody.self, from: body),
                  let code = ErrorCode(rawValue: body.error.code),
                  code.status == status else {
                self = .unavailable
                return
            }
            self = code
        }

        /// What a search reports for this code when the client does not retry it.
        var searchError: TitleSearchError {
            switch self {
            case .invalidRequest, .invalidQuery, .invalidChallenge, .keyRejected: .failed
            case .sessionExpired, .tooManyRequests, .unavailable: .unavailable
            }
        }
    }
}
