// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Core
import Foundation
import LocalStore
import Testing
@testable import Vertep

/// The folder screen's state on an in-memory database: the order of the rows, the
/// watched toggle, and a removal with its undo.
@MainActor
@Suite struct FolderModelTests {
    @Test func theLaterOfTwoAddedTitlesComesFirstWithEveryRowField() async throws {
        let store = try LocalDatabase.inMemory().folderStore
        let folder = try await store.ensurePersonalFolder(defaultName: FolderFixtures.folderName)
        let first = try FolderFixtures.result(movie: 1, title: "First Synthetic Film")
        let second = try FolderFixtures.result(movie: 2, title: "Second Synthetic Film")
        try await store.add(first, language: .en, to: folder.id, at: FolderFixtures.date(1_000))
        try await store.add(second, language: .en, to: folder.id, at: FolderFixtures.date(2_000))
        try await store.write([FolderFixtures.details(of: second, fetchedAt: FolderFixtures.date(2_000))])
        let model = FolderFixtures.model(store: store)

        await model.reload()

        #expect(model.rows.map(\.id) == [second.id, first.id])
        let row = try #require(model.rows.first)
        #expect(row.title == "Second Synthetic Film")
        #expect(row.detailsLine == "2001 · Drama · Ada Example")
        #expect(row.overview == "A synthetic overview of the second film.")
        #expect(row.castLine == "Ann Sample, Bo Sample")
        #expect(row.posterURL == URL(string: "https://image.tmdb.org/t/p/w185/poster-2.jpg"))
        #expect(model.showsEmptyState == false)
    }

    @Test func aFolderWithNoTitleShowsTheEmptyState() async throws {
        let model = FolderFixtures.model(store: try LocalDatabase.inMemory().folderStore)
        #expect(model.showsEmptyState == false)

        await model.reload()

        #expect(model.rows.isEmpty)
        #expect(model.showsEmptyState)
    }

    @Test func aTitleMarkedWatchedKeepsItsPlaceAndIsWatchedAfterARestart() async throws {
        // Two opens of one shared in-memory database stand in for two launches of the app.
        let databaseName = "restart-\(UUID().uuidString)"
        let store = try LocalDatabase.inMemory(named: databaseName).folderStore
        let ids = try await FolderFixtures.addTitles(1...3, to: store)
        let model = FolderFixtures.model(store: store, now: FolderFixtures.date(9_000))
        await model.reload()

        await model.setWatched(true, for: ids[1])

        #expect(model.rows.map(\.id) == ids.reversed())
        #expect(model.rows.map(\.isWatched) == [false, true, false])
        let item = try #require(model.rows.first { $0.id == ids[1] }?.item)
        #expect(item.watchedUpdatedAt == FolderFixtures.date(9_000))

        let restarted = FolderFixtures.model(store: try LocalDatabase.inMemory(named: databaseName).folderStore)
        await restarted.reload()
        #expect(restarted.rows.first { $0.id == ids[1] }?.isWatched == true)
        // A shared in-memory database lives while one of its stores is open. Using the
        // first store here keeps it open until the second one has read.
        _ = try await store.folders()
    }

    @Test func undoWithinTheHoldPutsTheRowBackInItsPlace() async throws {
        let store = try LocalDatabase.inMemory().folderStore
        let ids = try await FolderFixtures.addTitles(1...3, to: store)
        // The hold never ends by itself in this test.
        let model = FolderFixtures.model(store: store, sleep: { _ in try await Task.sleep(for: .seconds(3_600)) })
        await model.reload()
        await model.setWatched(true, for: ids[1])
        let before = model.rows

        await model.delete(ids[1])

        #expect(model.rows.map(\.id) == [ids[2], ids[0]])
        #expect(model.pendingUndo?.titleID == ids[1])

        await model.undo()

        #expect(model.rows == before)
        #expect(model.pendingUndo == nil)
    }

    @Test func withoutUndoTheToastEndsAfterFiveSecondsAndTheTitleStaysDeleted() async throws {
        let store = try LocalDatabase.inMemory().folderStore
        let ids = try await FolderFixtures.addTitles(1...2, to: store)
        let sleeper = RecordingSleeper()
        let model = FolderFixtures.model(store: store, sleep: { try await sleeper.sleep(for: $0) })
        await model.reload()

        await model.delete(ids[0])
        await model.undoTimer?.value

        #expect(await sleeper.requested == [.seconds(5)])
        #expect(model.pendingUndo == nil)
        #expect(model.rows.map(\.id) == [ids[1]])
        let folderID = try await model.personalFolderID()
        #expect(try await store.items(in: folderID).map(\.titleID) == [ids[1]])
    }

    @Test func deletingTheLastTitleShowsTheEmptyState() async throws {
        let store = try LocalDatabase.inMemory().folderStore
        let ids = try await FolderFixtures.addTitles(1...1, to: store)
        let model = FolderFixtures.model(store: store, sleep: { _ in try await Task.sleep(for: .seconds(3_600)) })
        await model.reload()

        await model.delete(ids[0])

        #expect(model.showsEmptyState)
        #expect(model.pendingUndo?.titleID == ids[0])
    }

    @Test func aSecondDeleteEndsTheUndoOfTheFirst() async throws {
        let store = try LocalDatabase.inMemory().folderStore
        let ids = try await FolderFixtures.addTitles(1...3, to: store)
        let model = FolderFixtures.model(store: store, sleep: { _ in try await Task.sleep(for: .seconds(3_600)) })
        await model.reload()

        await model.delete(ids[0])
        await model.delete(ids[1])
        await model.undo()

        #expect(model.rows.map(\.id) == [ids[2], ids[1]])
        #expect(model.pendingUndo == nil)
    }
}

/// Records each wait it is asked for and returns at once.
actor RecordingSleeper {
    private(set) var requested: [Duration] = []

    func sleep(for duration: Duration) async throws {
        requested.append(duration)
    }
}

/// Synthetic titles and the models the folder tests build.
enum FolderFixtures {
    static let folderName = "Test folder"

    static func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    @MainActor
    static func model(
        store: any FolderStore,
        now: Date = date(10_000),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { _ in }
    ) -> FolderModel {
        FolderModel(
            store: store,
            language: .en,
            personalFolderName: folderName,
            now: { now },
            sleep: sleep
        )
    }

    static func result(movie number: Int, title: String? = nil) throws -> TitleSearchResult {
        let id = try #require(TitleID(mediaType: .movie, tmdbID: number))
        return TitleSearchResult(
            id: id,
            title: title ?? "Synthetic Film \(number)",
            originalTitle: title ?? "Synthetic Film \(number)",
            year: 2_000 + number - 1,
            posterPath: "/poster-\(number).jpg",
            director: "Ada Example",
            creator: nil
        )
    }

    static func details(
        of result: TitleSearchResult,
        language: SearchLanguage = .en,
        fetchedAt: Date
    ) -> TitleMetadata {
        TitleMetadata(
            titleID: result.id,
            language: language,
            title: result.title,
            originalTitle: result.originalTitle,
            year: result.year,
            posterPath: result.posterPath,
            director: result.director,
            creator: result.creator,
            cast: ["Ann Sample", "Bo Sample"],
            overview: "A synthetic overview of the second film.",
            overviewLanguage: language,
            genres: [TitleGenre(id: 18, name: "Drama"), TitleGenre(id: 35, name: "Comedy")],
            runtime: 120,
            fetchedAt: fetchedAt
        )
    }

    /// Adds one synthetic movie per number, a thousand seconds apart, and returns their
    /// ids in the order they were added.
    static func addTitles(_ numbers: ClosedRange<Int>, to store: any FolderStore) async throws -> [TitleID] {
        let folder = try await store.ensurePersonalFolder(defaultName: folderName)
        var ids: [TitleID] = []
        for number in numbers {
            let result = try result(movie: number)
            try await store.add(result, language: .en, to: folder.id, at: date(TimeInterval(number) * 1_000))
            ids.append(result.id)
        }
        return ids
    }
}
