// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Search
import Testing

@Suite struct SearchConfigurationTests {
    let proxy = URL(string: "https://proxy.example.com")!

    private func configuration(proxy: String?, key: String?, readsPersonalKey: Bool = true) -> SearchConfiguration {
        var info: [String: Any] = [:]
        info[SearchConfiguration.proxyBaseURLKey] = proxy
        info[SearchConfiguration.tmdbAPIKeyKey] = key
        return SearchConfiguration(infoDictionary: info, readsPersonalKey: readsPersonalKey)
    }

    @Test func valuesAreRead() {
        let read = configuration(proxy: " https://proxy.example.com/prefix ", key: "example-key")
        #expect(read == SearchConfiguration(
            proxyBaseURL: URL(string: "https://proxy.example.com/prefix"), tmdbAPIKey: "example-key"
        ))
    }

    @Test(arguments: [
        nil, "", "  ", "$(VERTEP_PROXY_BASE_URL)", "http://proxy.example.com", "proxy.example.com", "https://",
    ])
    func anUnusableProxyURLIsNotConfigured(raw: String?) {
        #expect(configuration(proxy: raw, key: nil).proxyBaseURL == nil)
    }

    @Test(arguments: [nil, "", " ", "$(VERTEP_TMDB_API_KEY)"])
    func anEmptyKeyIsNotConfigured(raw: String?) {
        #expect(configuration(proxy: nil, key: raw).tmdbAPIKey == nil)
    }

    @Test func noInfoDictionaryIsNotConfigured() {
        #expect(
            SearchConfiguration(infoDictionary: nil, readsPersonalKey: true)
                .choice(appAttestSupported: true) == .notConfigured
        )
    }

    @Test func aBuildThatDoesNotReadThePersonalKeyIgnoresIt() {
        let read = configuration(proxy: "https://proxy.example.com", key: "example-key", readsPersonalKey: false)
        #expect(read == SearchConfiguration(proxyBaseURL: proxy, tmdbAPIKey: nil))
    }

    @Test func aBuildThatDoesNotReadThePersonalKeyIsNotConfiguredWithoutAppAttest() {
        let read = configuration(proxy: "https://proxy.example.com", key: "example-key", readsPersonalKey: false)
        #expect(read.choice(appAttestSupported: false) == .notConfigured)
    }

    @Test func theProxyIsChosenWhenTheDeviceSupportsAppAttest() {
        let both = SearchConfiguration(proxyBaseURL: proxy, tmdbAPIKey: "example-key")
        #expect(both.choice(appAttestSupported: true) == .proxy(proxy))
    }

    @Test func theDirectSearchIsChosenWithoutAppAttest() {
        let both = SearchConfiguration(proxyBaseURL: proxy, tmdbAPIKey: "example-key")
        #expect(both.choice(appAttestSupported: false) == .direct(apiKey: "example-key"))
    }

    @Test func theDirectSearchIsChosenWithoutAProxy() {
        let key = SearchConfiguration(proxyBaseURL: nil, tmdbAPIKey: "example-key")
        #expect(key.choice(appAttestSupported: true) == .direct(apiKey: "example-key"))
    }

    @Test func aProxyWithoutAppAttestAndNoKeyIsNotConfigured() {
        let proxyOnly = SearchConfiguration(proxyBaseURL: proxy, tmdbAPIKey: nil)
        #expect(proxyOnly.choice(appAttestSupported: false) == .notConfigured)
    }

    @Test func nothingIsNotConfigured() {
        let nothing = SearchConfiguration(proxyBaseURL: nil, tmdbAPIKey: nil)
        #expect(nothing.choice(appAttestSupported: true) == .notConfigured)
    }
}
