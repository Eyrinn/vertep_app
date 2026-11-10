// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Core
import Foundation
import Search
import Synchronization

/// An App Attest client that never leaves the process. It names keys `key-1`, `key-2`
/// and so on, and records every call.
final class FakeAttestation: AppAttestation {
    enum Call: Equatable {
        case generateKey
        case attest(keyID: String, clientDataHash: Data)
        case assert(keyID: String, clientDataHash: Data)
    }

    private struct State {
        var calls: [Call] = []
        var keysMade = 0
        var invalidKeys: Set<String> = []
    }

    private let state = Mutex(State())

    /// `invalidKeys` are keys the device reports as invalid, as after a reinstall.
    init(invalidKeys: Set<String> = []) {
        state.withLock { $0.invalidKeys = invalidKeys }
    }

    var calls: [Call] { state.withLock { $0.calls } }

    var isSupported: Bool { true }

    func generateKey() async throws(AppAttestationError) -> String {
        state.withLock {
            $0.calls.append(.generateKey)
            $0.keysMade += 1
            return "key-\($0.keysMade)"
        }
    }

    func attestKey(_ keyID: String, clientDataHash: Data) async throws(AppAttestationError) -> Data {
        try state.withLock { state throws(AppAttestationError) in
            state.calls.append(.attest(keyID: keyID, clientDataHash: clientDataHash))
            if state.invalidKeys.contains(keyID) { throw .invalidKey }
            return Data("attestation-of-\(keyID)".utf8)
        }
    }

    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws(AppAttestationError) -> Data {
        try state.withLock { state throws(AppAttestationError) in
            state.calls.append(.assert(keyID: keyID, clientDataHash: clientDataHash))
            if state.invalidKeys.contains(keyID) { throw .invalidKey }
            return Data("assertion-by-\(keyID)".utf8)
        }
    }
}

/// An HTTP server in a script: each path answers from its own list of responses, in order,
/// and repeats the last one when the list runs out. It records every request.
final class FakeHTTP: HTTPTransport {
    struct Response {
        var status: Int
        var body: Data

        static func json(_ status: Int, _ text: String) -> Response {
            Response(status: status, body: Data(text.utf8))
        }

        static func error(_ status: Int, _ code: String) -> Response {
            json(status, #"{"error":{"code":"\#(code)","message":"An example message."}}"#)
        }
    }

    struct Failure: Error {}

    private struct State {
        var script: [String: [Response]]
        var requests: [URLRequest] = []
    }

    private let state: Mutex<State>

    /// `script` maps a path, such as `/v1/search`, to its responses. A path the script does
    /// not name fails as a request that got no response.
    init(_ script: [String: [Response]]) {
        state = Mutex(State(script: script))
    }

    var requests: [URLRequest] { state.withLock { $0.requests } }

    func requests(to path: String) -> [URLRequest] {
        requests.filter { $0.url?.path() == path }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = state.withLock { state -> Response? in
            state.requests.append(request)
            guard let path = request.url?.path(), var queue = state.script[path], let first = queue.first else {
                return nil
            }
            if queue.count > 1 { queue.removeFirst() }
            state.script[path] = queue
            return first
        }
        guard let response, let url = request.url,
              let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: nil)
        else { throw Failure() }
        return (response.body, http)
    }
}

/// Synthetic answers of a proxy that follows `docs/search-api.md`.
enum ProxyAnswers {
    /// A challenge whose bytes are `challenge-<n>`.
    static func challenge(_ n: Int) -> FakeHTTP.Response {
        .json(200, #"{"challenge":"\#(challengeText(n))"}"#)
    }

    static func challengeText(_ n: Int) -> String {
        Data("challenge-\(n)".utf8).base64EncodedString()
    }

    static func session(_ token: String) -> FakeHTTP.Response {
        .json(200, #"{"sessionToken":"\#(token)"}"#)
    }

    static let results = FakeHTTP.Response.json(200, """
    {"results":[
      {"id":"tmdb:movie:101","type":"movie","title":"Example Movie","originalTitle":"Example Original",
       "year":1999,"posterPath":"/example-poster.jpg","director":"Example Director","creator":null},
      {"id":"tmdb:tv:202","type":"tv","title":"Example Series","originalTitle":"Example Series",
       "year":null,"posterPath":null,"director":null,"creator":"Example Creator"}
    ]}
    """)
}

extension URLRequest {
    var jsonBody: [String: String]? {
        httpBody.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
    }
}
