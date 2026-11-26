// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Core
import Foundation
import LocalStore
import Testing
@testable import Vertep

/// Which titles the folder screen fetches details for, how it asks for them, and what it
/// stores.
@MainActor
@Suite struct FolderRefreshTests {
    private let now = Date(timeIntervalSince1970: 1_000_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    @Test func aTitleWith91DayOldMetadataGetsNewDetailsWhenTheFolderAppears() async throws {
        let store = try LocalDatabase.inMemory().folderStore
        let ids = try await FolderFixtures.addTitles(1...1, to: store)
        let result = try FolderFixtures.result(movie: 1)
        try await store.write([FolderFixtures.details(of: result, fetchedAt: now.addingTimeInterval(-91 * day))])
        let details = FakeTitleDetails()
        let model = FolderFixtures.model(store: store, details: details, now: now)

        await model.screenAppeared()

        #expect(await details.requestedIDs == [ids])
        let metadata = try #require(try await store.metadata(for: ids, preferring: .en)[ids[0]])
        #expect(metadata.fetchedAt == now)
        #expect(metadata.overview == FakeTitleDetails.overview)
        #expect(model.rows.first?.overview == FakeTitleDetails.overview)
    }

    @Test func aTitleAddedFromASearchAMinuteAgoGetsItsDetails() async throws {
        let store = try LocalDatabase.inMemory().folderStore
        let folder = try await store.ensurePersonalFolder(defaultName: FolderFixtures.folderName)
        let result = try FolderFixtures.result(movie: 7)
        try await store.add(result, language: .en, to: folder.id, at: now.addingTimeInterval(-60))
        let details = FakeTitleDetails()
        let model = FolderFixtures.model(store: store, details: details, now: now)

        await model.screenAppeared()

        #expect(await details.requestedIDs == [[result.id]])
        #expect(model.rows.first?.metadata?.hasDetails == true)
    }

    @Test func detailsYoungerThan90DaysInTheAppLanguageAreNotFetchedAgain() async throws {
        let store = try LocalDatabase.inMemory().folderStore
        _ = try await FolderFixtures.addTitles(1...1, to: store)
        let result = try FolderFixtures.result(movie: 1)
        try await store.write([FolderFixtures.details(of: result, fetchedAt: now.addingTimeInterval(-89 * day))])
        let details = FakeTitleDetails()
        let model = FolderFixtures.model(store: store, details: details, now: now)

        await model.screenAppeared()

        #expect(await details.requestedIDs.isEmpty)
    }

    @Test func detailsInAnotherLanguageThanTheAppsAreFetchedInTheAppLanguage() async throws {
        let store = try LocalDatabase.inMemory().folderStore
        let ids = try await FolderFixtures.addTitles(1...1, to: store)
        let result = try FolderFixtures.result(movie: 1)
        // addTitles stored the search fields in English; these are full details in English.
        try await store.write([FolderFixtures.details(of: result, fetchedAt: now.addingTimeInterval(-day))])
        let details = FakeTitleDetails()
        let model = FolderFixtures.model(store: store, details: details, language: .uk, now: now)

        await model.enteredForeground()

        #expect(await details.requests.map(\.language) == [.uk])
        #expect(await details.requestedIDs == [ids])
        #expect(model.rows.first?.metadata?.language == .uk)
    }

    @Test func outdatedTitlesAreAskedForInRequestsOfAtMost20() async throws {
        let store = try LocalDatabase.inMemory().folderStore
        _ = try await FolderFixtures.addTitles(1...25, to: store)
        let details = FakeTitleDetails()
        let model = FolderFixtures.model(store: store, details: details, now: now)

        await model.screenAppeared()

        #expect(await details.requestedIDs.map(\.count) == [20, 5])
        #expect(model.rows.allSatisfy { $0.metadata?.hasDetails == true })
    }

    @Test func nothingIsSentWhileTheDeviceIsOffline() async throws {
        let store = try LocalDatabase.inMemory().folderStore
        _ = try await FolderFixtures.addTitles(1...2, to: store)
        let details = FakeTitleDetails()
        let model = FolderFixtures.model(
            store: store,
            details: details,
            network: FakeNetworkStatus(online: false),
            now: now
        )

        await model.screenAppeared()
        await model.enteredForeground()

        #expect(await details.requestedIDs.isEmpty)
        #expect(model.rows.count == 2)
    }

    @Test func aTitleReportedAsNotFoundStaysWithItsStoredMetadata() async throws {
        let store = try LocalDatabase.inMemory().folderStore
        let ids = try await FolderFixtures.addTitles(1...2, to: store)
        let details = FakeTitleDetails(notFound: [ids[0]])
        let model = FolderFixtures.model(store: store, details: details, now: now)
        await model.reload()
        let stored = try #require(model.rows.first { $0.id == ids[0] }?.metadata)

        await model.screenAppeared()

        #expect(model.rows.map(\.id) == [ids[1], ids[0]])
        #expect(model.rows.first { $0.id == ids[0] }?.metadata == stored)
        #expect(model.rows.first { $0.id == ids[1] }?.metadata?.hasDetails == true)
    }

    @Test func aDetailsServiceThatCannotAnswerChangesNoRow() async throws {
        let store = try LocalDatabase.inMemory().folderStore
        _ = try await FolderFixtures.addTitles(1...2, to: store)
        let details = FakeTitleDetails(error: .unavailable)
        let model = FolderFixtures.model(store: store, details: details, now: now)
        await model.reload()
        let before = model.rows

        await model.screenAppeared()

        #expect(await details.requestedIDs.count == 1)
        #expect(model.rows == before)
    }
}

/// A network status that always gives the same answer.
struct FakeNetworkStatus: NetworkStatus {
    let online: Bool

    func isOnline() async -> Bool { online }
}

/// A details provider that never leaves the process. It knows every title except the
/// ones in `notFound`, and records each request.
actor FakeTitleDetails: TitleDetailsProvider {
    static let overview = "A synthetic overview from the details."

    private let notFound: Set<TitleID>
    private let error: TitleDetailsError?
    private(set) var requests: [TitleDetailsRequest] = []

    /// - Parameter error: when set, every request fails with it.
    init(notFound: Set<TitleID> = [], error: TitleDetailsError? = nil) {
        self.notFound = notFound
        self.error = error
    }

    var requestedIDs: [[TitleID]] { requests.map(\.ids) }

    func details(_ request: TitleDetailsRequest) async throws(TitleDetailsError) -> TitleDetailsResponse {
        requests.append(request)
        if let error { throw error }
        let results = request.ids.filter { !notFound.contains($0) }.map { id in
            TitleDetails(
                id: id,
                title: "Synthetic Film \(id.tmdbID)",
                originalTitle: "Synthetic Film \(id.tmdbID)",
                year: 2_000,
                posterPath: "/poster-\(id.tmdbID).jpg",
                director: "Ada Example",
                creator: nil,
                cast: ["Cy Sample"],
                overview: Self.overview,
                overviewLanguage: request.language,
                genres: [TitleGenre(id: 18, name: "Drama")],
                runtime: 100
            )
        }
        return TitleDetailsResponse(results: results, notFound: request.ids.filter { notFound.contains($0) })
    }
}
