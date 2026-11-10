// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Core
import Foundation
import Search
import Testing

/// Runs the proxy search against the configured proxy, with Apple's App Attest service.
///
/// It runs only on a physical iPhone, because the Simulator cannot attest a key, and only
/// when Config/Local.xcconfig sets a proxy URL. The CI scheme does not include it: run the
/// VertepDeviceTests scheme on a device.
@Suite struct SearchDeviceTests {
    /// The proxy URL the app under test was built with.
    static let proxyBaseURL = SearchConfiguration(infoDictionary: Bundle.main.infoDictionary).proxyBaseURL

    @Test(
        .enabled(if: DeviceAppAttestation().isSupported, "App Attest runs only on a physical device"),
        .enabled(if: proxyBaseURL != nil, "Config/Local.xcconfig sets no proxy URL")
    )
    func attestsANewKeyOpensASessionAndFindsAMovieWithADirector() async throws {
        let baseURL = try #require(Self.proxyBaseURL)
        // An empty store makes the search attest a new key before it opens a session.
        let keys = InMemoryKeyIDStore()
        let search = ProxyTitleSearch(baseURL: baseURL, attestation: DeviceAppAttestation(), keyStore: keys)

        let results = try await search.search("Alien", language: .en)

        #expect(keys.load() != nil)
        #expect(results.contains { $0.mediaType == .movie && $0.director?.isEmpty == false })
    }
}
