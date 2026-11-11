// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Sends one HTTP request and returns the body and the response. A test supplies a fake
/// that answers from a script.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPTransport {
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

extension URL {
    /// Appends `path`, which starts with `/`, to this URL's text unchanged, after removing
    /// any trailing `/` of this URL. A base URL with a path prefix keeps the prefix.
    func appendingRawPath(_ path: String, query: [(String, String)] = []) -> URL? {
        var text = absoluteString
        while text.hasSuffix("/") { text.removeLast() }
        text += path
        if !query.isEmpty {
            text += "?" + query.map { "\($0.0.queryEncoded)=\($0.1.queryEncoded)" }.joined(separator: "&")
        }
        return URL(string: text)
    }
}

extension String {
    /// The ASCII letters and digits and `-._~` stay as they are; every other byte of the
    /// UTF-8 text is percent-encoded. A space becomes `%20` and `+` becomes `%2B`, so a
    /// server cannot read either one as the other.
    var queryEncoded: String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }
}
