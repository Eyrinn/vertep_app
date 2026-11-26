// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Core
import Foundation
import os
import Search
import Testing
@testable import Vertep

/// The app picks its title search and its title details by one choice, so a folder row
/// gets its details from the same source the search found the title in.
@MainActor
@Suite struct CompositionRootTests {
    private let logger = Logger(subsystem: "app.vertep.ios.tests", category: "CompositionRootTests")

    @Test func aPersonalKeyWithNoProxyGoesToTMDBDirectlyForBoth() {
        let configuration = SearchConfiguration(proxyBaseURL: nil, tmdbAPIKey: "synthetic-test-key")

        let (search, details) = CompositionRoot.makeTitleServices(configuration, logger: logger)

        #expect(search is DirectTMDBTitleSearch)
        #expect(details is DirectTMDBTitleDetails)
    }

    @Test func nothingConfiguredReportsItForBoth() async throws {
        let configuration = SearchConfiguration(proxyBaseURL: nil, tmdbAPIKey: nil)

        let (search, details) = CompositionRoot.makeTitleServices(configuration, logger: logger)

        #expect(search is NotConfiguredTitleSearch)
        #expect(details is NotConfiguredTitleDetailsProvider)
        let id = try #require(TitleID(rawValue: "tmdb:movie:1"))
        let request = try #require(TitleDetailsRequest(ids: [id], language: .en))
        await #expect(throws: TitleDetailsError.notConfigured) {
            try await details.details(request)
        }
    }
}
