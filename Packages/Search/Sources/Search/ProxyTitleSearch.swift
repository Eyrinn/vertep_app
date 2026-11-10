// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Core
import CryptoKit
import Foundation

/// Searches titles through a proxy that follows `docs/search-api.md`.
///
/// The proxy answers a search only for a session, and opens a session only for an App
/// Attest key. The key id is kept in `keyStore`. The session token is kept in memory only,
/// so a new launch opens a new session with the stored key.
///
/// Each kind of failure is retried at most once per search: an expired session, a
/// challenge the proxy did not accept, and a stored key the proxy rejected or the device
/// lost. The session a search opens again after an expired session gets only the retries
/// that the first session left. A search that waits for a session another search is
/// opening counts the retries that opening used as its own. One search therefore sends a
/// bounded number of requests.
public actor ProxyTitleSearch: TitleSearch {
    private let baseURL: URL
    private let attestation: any AppAttestation
    private let keyStore: any KeyIDStore
    private let transport: any HTTPTransport

    private var sessionToken: String?
    /// The session being opened, which every search that needs a session waits for, so
    /// that searches started together open one session.
    private var opening: Task<OpenedSession, any Error>?

    /// The retries that one search can still make. The contract allows each kind once.
    private struct Retries: Sendable {
        /// A new challenge after the proxy did not accept one.
        var newChallenge = true
        /// A new key after the proxy rejected the stored key or the device lost it.
        var newKey = true

        /// The retries that are left when `other` is also left: a retry that either of
        /// them used is used.
        func intersection(_ other: Retries) -> Retries {
            Retries(newChallenge: newChallenge && other.newChallenge, newKey: newKey && other.newKey)
        }
    }

    /// A session that was opened, and the retries left to the search that opened it.
    private struct OpenedSession: Sendable {
        var token: String
        var retries: Retries
    }

    public init(
        baseURL: URL,
        attestation: any AppAttestation,
        keyStore: any KeyIDStore,
        transport: any HTTPTransport = URLSession.shared
    ) {
        self.baseURL = baseURL
        self.attestation = attestation
        self.keyStore = keyStore
        self.transport = transport
    }

    public func search(_ query: String, language: SearchLanguage) async throws(TitleSearchError) -> [TitleSearchResult] {
        guard let query = SearchQuery(query) else { return [] }
        var retries = Retries()
        let token = try await session(&retries)
        if let results = try await search(query, language: language, token: token) {
            return results
        }
        // The proxy no longer knows the session. Open a new one and search once more. The
        // new session gets only the retries that the first one left.
        discard(token)
        let renewed = try await session(&retries)
        if let results = try await search(query, language: language, token: renewed) {
            return results
        }
        discard(renewed)
        throw .unavailable
    }

    // MARK: - Search

    /// Returns nil when the proxy answers that the session expired.
    private func search(
        _ query: SearchQuery,
        language: SearchLanguage,
        token: String
    ) async throws(TitleSearchError) -> [TitleSearchResult]? {
        var request = URLRequest(url: try url("/v1/search", query: [("q", query.text), ("lang", language.rawValue)]))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        switch try await send(request) {
        case .success(let data):
            guard let body = try? JSONDecoder().decode(ProxyAPI.SearchResponse.self, from: data) else {
                throw .unavailable
            }
            return Array(body.results.compactMap(\.titleSearchResult).prefix(TitleSearchResult.maximumCount))
        case .failure(.sessionExpired):
            return nil
        case .failure(let code):
            throw code.searchError
        }
    }

    // MARK: - Session

    /// Returns the current session, or opens one with the retries this search has left.
    /// The retries that the opening used are removed from `retries`.
    private func session(_ retries: inout Retries) async throws(TitleSearchError) -> String {
        if let sessionToken { return sessionToken }
        let task: Task<OpenedSession, any Error>
        if let opening {
            task = opening
        } else {
            let allowed = retries
            task = Task { try await self.openAndKeepSession(allowed) }
            opening = task
        }
        do {
            let opened = try await task.value
            retries = retries.intersection(opened.retries)
            return opened.token
        } catch let error as TitleSearchError {
            throw error
        } catch {
            throw .unavailable
        }
    }

    private func discard(_ token: String) {
        if sessionToken == token { sessionToken = nil }
    }

    private func openAndKeepSession(_ allowed: Retries) async throws(TitleSearchError) -> OpenedSession {
        defer { opening = nil }
        var retries = allowed
        let token = try await openSession(&retries)
        sessionToken = token
        return OpenedSession(token: token, retries: retries)
    }

    /// Opens a session with the stored key. When there is none, attests a new key and
    /// opens a session with that. When the proxy rejects the stored key, or the device no
    /// longer has it, does the same if `retries` still allows a new key, and otherwise
    /// fails.
    private func openSession(_ retries: inout Retries) async throws(TitleSearchError) -> String {
        if let keyID = keyStore.load() {
            if let token = try await openSession(keyID: keyID, attestingKey: false, retries: &retries) {
                return token
            }
            keyStore.delete()
            // This search already replaced a key, and the proxy rejected the new one too.
            guard retries.newKey else { throw .failed }
            retries.newKey = false
        }
        let keyID: String
        do {
            keyID = try await attestation.generateKey()
        } catch {
            throw .unavailable
        }
        keyStore.save(keyID)
        if let token = try await openSession(keyID: keyID, attestingKey: true, retries: &retries) {
            return token
        }
        // The proxy rejected a key it has just seen attested. A retry would only repeat it.
        keyStore.delete()
        throw .failed
    }

    /// Attests the key, or signs an assertion with it, and opens a session. Returns nil
    /// when the proxy rejects the key or the device reports the key as invalid. Gets a new
    /// challenge once when the proxy does not accept one and `retries` still allows it.
    private func openSession(
        keyID: String,
        attestingKey: Bool,
        retries: inout Retries
    ) async throws(TitleSearchError) -> String? {
        while true {
            let challenge = try await challenge()
            let clientDataHash = Data(SHA256.hash(data: challenge.bytes))
            let proof: Data
            do {
                proof = attestingKey
                    ? try await attestation.attestKey(keyID, clientDataHash: clientDataHash)
                    : try await attestation.generateAssertion(keyID, clientDataHash: clientDataHash)
            } catch {
                if error == .invalidKey { return nil }
                throw .unavailable
            }

            let body: any Encodable = attestingKey
                ? ProxyAPI.AttestRequest(keyId: keyID, challenge: challenge.text, attestation: proof.base64EncodedString())
                : ProxyAPI.AssertRequest(keyId: keyID, challenge: challenge.text, assertion: proof.base64EncodedString())
            var request = URLRequest(url: try url(attestingKey ? "/v1/sessions/attest" : "/v1/sessions/assert"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(body)

            switch try await send(request) {
            case .success(let data):
                guard let session = try? JSONDecoder().decode(ProxyAPI.Session.self, from: data) else {
                    throw .unavailable
                }
                return session.sessionToken
            case .failure(.keyRejected):
                return nil
            case .failure(.invalidChallenge) where retries.newChallenge:
                retries.newChallenge = false
                continue
            case .failure(let code):
                throw code.searchError
            }
        }
    }

    /// Gets a new challenge: its text as the proxy sent it, and its bytes.
    private func challenge() async throws(TitleSearchError) -> (text: String, bytes: Data) {
        var request = URLRequest(url: try url("/v1/challenge"))
        request.httpMethod = "POST"
        switch try await send(request) {
        case .success(let data):
            guard let body = try? JSONDecoder().decode(ProxyAPI.Challenge.self, from: data),
                  let bytes = Data(base64Encoded: body.challenge) else {
                throw .unavailable
            }
            return (body.challenge, bytes)
        case .failure(let code):
            throw code.searchError
        }
    }

    // MARK: - HTTP

    private func url(_ path: String, query: [(String, String)] = []) throws(TitleSearchError) -> URL {
        guard let url = baseURL.appendingRawPath(path, query: query) else { throw .failed }
        return url
    }

    /// Sends a request. A response that is not a success is read as an error code of the
    /// contract. A request that gets no response is reported as `unavailable`.
    private func send(_ request: URLRequest) async throws(TitleSearchError) -> Result<Data, ProxyAPI.ErrorCode> {
        var request = request
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw .unavailable
        }
        if (200..<300).contains(response.statusCode) { return .success(data) }
        return .failure(ProxyAPI.ErrorCode(status: response.statusCode, body: data))
    }
}
