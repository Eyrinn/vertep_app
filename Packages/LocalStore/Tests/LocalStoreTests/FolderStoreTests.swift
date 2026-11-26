// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Core
import Foundation
import LocalStore
import Testing

@Suite struct FolderStoreTests {
    private let name = "Test folder"

    @Test func firstLaunchCreatesOnePersonalFolder() async throws {
        let store = try LocalDatabase.inMemory().folderStore

        let folder = try await store.ensurePersonalFolder(defaultName: name)

        let folders = try await store.folders()
        #expect(folders == [folder])
        #expect(folder.kind == .personal)
        #expect(folder.name == name)
        #expect(folder.dirtyVersion == 0)
    }

    @Test func theNextLaunchKeepsTheSamePersonalFolder() async throws {
        // Two opens of one shared in-memory database stand in for two launches of the app.
        let databaseName = "launch-\(UUID().uuidString)"
        let firstLaunch = try LocalDatabase.inMemory(named: databaseName)
        let created = try await firstLaunch.folderStore.ensurePersonalFolder(defaultName: name)

        let nextLaunch = try LocalDatabase.inMemory(named: databaseName)
        let found = try await nextLaunch.folderStore.ensurePersonalFolder(defaultName: "Another name")

        #expect(found == created)
        #expect(try await nextLaunch.folderStore.folders() == [created])
    }

    @Test func insertingTheSameTitleTwiceKeepsItOnce() async throws {
        let store = try LocalDatabase.inMemory().folderStore
        let folder = try await store.ensurePersonalFolder(defaultName: name)
        let titleID = try #require(TitleID(mediaType: .movie, tmdbID: 603))
        let first = item(in: folder, titleID, at: Date(timeIntervalSince1970: 1_000))
        var second = first
        second.isWatched = true
        second.addedAt = Date(timeIntervalSince1970: 2_000)

        #expect(try await store.insert(first))
        #expect(try await store.insert(second) == false)

        #expect(try await store.items(in: folder.id) == [first])
    }

    @Test func aMovieAndAShowWithTheSameNumberAreTwoTitles() async throws {
        let store = try LocalDatabase.inMemory().folderStore
        let folder = try await store.ensurePersonalFolder(defaultName: name)
        let movie = item(in: folder, try #require(TitleID(mediaType: .movie, tmdbID: 42)), at: Date(timeIntervalSince1970: 1_000))
        let show = item(in: folder, try #require(TitleID(mediaType: .tv, tmdbID: 42)), at: Date(timeIntervalSince1970: 2_000))

        try await store.insert(movie)
        try await store.insert(show)

        #expect(try await store.items(in: folder.id) == [movie, show])
    }

    @Test func refusesATitleInAFolderThatDoesNotExist() async throws {
        let store = try LocalDatabase.inMemory().folderStore
        let missing = Folder(id: UUID(), kind: .personal, name: name, createdAt: Date(), dirtyVersion: 0)
        let titleID = try #require(TitleID(mediaType: .tv, tmdbID: 1399))

        await #expect(throws: (any Error).self) {
            try await store.insert(item(in: missing, titleID, at: Date()))
        }
    }

    @Test func aDatabaseFileKeepsItsFolderAcrossOpens() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store.sqlite")

        let created = try await LocalDatabase.open(at: url).folderStore.ensurePersonalFolder(defaultName: name)
        let found = try await LocalDatabase.open(at: url).folderStore.ensurePersonalFolder(defaultName: name)

        #expect(found == created)
    }

    // MARK: Adding from a search result

    @Test func addingAResultStoresItsMetadataWithTheTimeOfTheAdd() async throws {
        let store = try LocalDatabase.inMemory().folderStore
        let folder = try await store.ensurePersonalFolder(defaultName: name)
        let result = try searchResult("tmdb:movie:603", title: "Example Movie")
        let addedAt = Date(timeIntervalSince1970: 1_000)

        #expect(try await store.add(result, language: .en, to: folder.id, at: addedAt))

        let items = try await store.items(in: folder.id)
        #expect(items.map(\.titleID) == [result.id])
        #expect(items.first?.addedAt == addedAt)
        #expect(items.first?.isWatched == false)
        let metadata = try await store.metadata(for: [result.id], preferring: .en)
        #expect(metadata == [result.id: TitleMetadata(result, language: .en, fetchedAt: addedAt)])
        #expect(metadata[result.id]?.hasDetails == false)
    }

    @Test func addingATitleThatIsInTheFolderChangesNothing() async throws {
        let store = try LocalDatabase.inMemory().folderStore
        let folder = try await store.ensurePersonalFolder(defaultName: name)
        let result = try searchResult("tmdb:tv:1399", title: "Example Series")
        try await store.add(result, language: .en, to: folder.id, at: Date(timeIntervalSince1970: 1_000))

        var renamed = result
        renamed.title = "Another title"
        #expect(try await store.add(renamed, language: .en, to: folder.id, at: Date(timeIntervalSince1970: 2_000)) == false)

        #expect(try await store.items(in: folder.id).map(\.addedAt) == [Date(timeIntervalSince1970: 1_000)])
        let metadata = try await store.metadata(for: [result.id], preferring: .en)
        #expect(metadata[result.id]?.title == "Example Series")
        #expect(metadata[result.id]?.fetchedAt == Date(timeIntervalSince1970: 1_000))
    }

    // MARK: Removing and restoring

    @Test func aRemovedAndRestoredTitleKeepsItsWatchedFlagAndAddedDate() async throws {
        let store = try LocalDatabase.inMemory().folderStore
        let folder = try await store.ensurePersonalFolder(defaultName: name)
        let result = try searchResult("tmdb:movie:603", title: "Example Movie")
        try await store.add(result, language: .en, to: folder.id, at: Date(timeIntervalSince1970: 1_000))
        try await store.setWatched(true, for: result.id, in: folder.id, at: Date(timeIntervalSince1970: 2_000))
        let before = try await store.items(in: folder.id)

        #expect(try await store.remove(result.id, from: folder.id, at: Date(timeIntervalSince1970: 3_000)))
        #expect(try await store.items(in: folder.id).isEmpty)

        #expect(try await store.restore(result.id, in: folder.id))
        let after = try await store.items(in: folder.id)
        #expect(after == before)
        #expect(after.first?.isWatched == true)
        #expect(after.first?.addedAt == Date(timeIntervalSince1970: 1_000))
    }

    @Test func aRemovedTitleAddedAgainAppearsOnceWithANewAddedDate() async throws {
        let store = try LocalDatabase.inMemory().folderStore
        let folder = try await store.ensurePersonalFolder(defaultName: name)
        let result = try searchResult("tmdb:movie:603", title: "Example Movie")
        try await store.add(result, language: .en, to: folder.id, at: Date(timeIntervalSince1970: 1_000))
        try await store.remove(result.id, from: folder.id, at: Date(timeIntervalSince1970: 2_000))

        #expect(try await store.add(result, language: .en, to: folder.id, at: Date(timeIntervalSince1970: 3_000)))

        let items = try await store.items(in: folder.id)
        #expect(items.map(\.titleID) == [result.id])
        #expect(items.first?.addedAt == Date(timeIntervalSince1970: 3_000))
        #expect(items.first?.deletedAt == nil)
    }

    @Test func removingOrRestoringATitleInAnotherStateChangesNothing() async throws {
        let store = try LocalDatabase.inMemory().folderStore
        let folder = try await store.ensurePersonalFolder(defaultName: name)
        let result = try searchResult("tmdb:movie:603", title: "Example Movie")
        let absent = try #require(TitleID(rawValue: "tmdb:movie:604"))
        try await store.add(result, language: .en, to: folder.id, at: Date(timeIntervalSince1970: 1_000))

        #expect(try await store.restore(result.id, in: folder.id) == false)
        #expect(try await store.remove(absent, from: folder.id, at: Date(timeIntervalSince1970: 2_000)) == false)
        try await store.remove(result.id, from: folder.id, at: Date(timeIntervalSince1970: 2_000))
        #expect(try await store.remove(result.id, from: folder.id, at: Date(timeIntervalSince1970: 3_000)) == false)
        // A removed title is still stored, so inserting it again keeps the stored row.
        #expect(try await store.insert(item(in: folder, result.id, at: Date(timeIntervalSince1970: 4_000))) == false)
        #expect(try await store.items(in: folder.id).isEmpty)
    }

    // MARK: Watched

    @Test func markingATitleWatchedSetsTheFlagAndItsUpdateDate() async throws {
        let store = try LocalDatabase.inMemory().folderStore
        let folder = try await store.ensurePersonalFolder(defaultName: name)
        let result = try searchResult("tmdb:movie:603", title: "Example Movie")
        try await store.add(result, language: .en, to: folder.id, at: Date(timeIntervalSince1970: 1_000))

        #expect(try await store.setWatched(true, for: result.id, in: folder.id, at: Date(timeIntervalSince1970: 2_000)))

        let item = try #require(try await store.items(in: folder.id).first)
        #expect(item.isWatched)
        #expect(item.watchedUpdatedAt == Date(timeIntervalSince1970: 2_000))
        #expect(item.updatedAt == Date(timeIntervalSince1970: 2_000))
        #expect(item.addedAt == Date(timeIntervalSince1970: 1_000))
    }

    @Test func aRemovedTitleCannotBeMarkedWatched() async throws {
        let store = try LocalDatabase.inMemory().folderStore
        let folder = try await store.ensurePersonalFolder(defaultName: name)
        let result = try searchResult("tmdb:movie:603", title: "Example Movie")
        try await store.add(result, language: .en, to: folder.id, at: Date(timeIntervalSince1970: 1_000))
        try await store.remove(result.id, from: folder.id, at: Date(timeIntervalSince1970: 2_000))

        #expect(try await store.setWatched(true, for: result.id, in: folder.id, at: Date(timeIntervalSince1970: 3_000)) == false)

        try await store.restore(result.id, in: folder.id)
        #expect(try await store.items(in: folder.id).first?.isWatched == false)
    }

    // MARK: Metadata

    @Test func newDetailsInTheSameLanguageReplaceTheMetadataAndItsFetchDate() async throws {
        let store = try LocalDatabase.inMemory().folderStore
        let folder = try await store.ensurePersonalFolder(defaultName: name)
        let result = try searchResult("tmdb:tv:1399", title: "Example Series")
        try await store.add(result, language: .uk, to: folder.id, at: Date(timeIntervalSince1970: 1_000))
        let details = TitleDetails(
            id: result.id, title: "Example Series", originalTitle: "Example Series", year: 2011,
            posterPath: "/example.jpg", director: nil, creator: "Example Creator",
            cast: ["Example Actor", "Another Actor"], overview: "An example overview.", overviewLanguage: .en,
            genres: [TitleGenre(id: 18, name: "Drama")], runtime: 60
        )
        let refreshed = TitleMetadata(details, language: .uk, fetchedAt: Date(timeIntervalSince1970: 2_000))

        try await store.write([refreshed])

        let metadata = try await store.metadata(for: [result.id], preferring: .uk)
        #expect(metadata == [result.id: refreshed])
        #expect(metadata[result.id]?.hasDetails == true)
        #expect(metadata[result.id]?.overviewLanguage == .en)
    }

    @Test func metadataIsReadInTheRequestedLanguageAndOtherwiseTheLatest() async throws {
        let store = try LocalDatabase.inMemory().folderStore
        let movie = try searchResult("tmdb:movie:603", title: "Example Movie")
        let series = try searchResult("tmdb:tv:1399", title: "Example Series")
        let missing = try #require(TitleID(rawValue: "tmdb:movie:1"))
        let movieInEnglish = TitleMetadata(movie, language: .en, fetchedAt: Date(timeIntervalSince1970: 3_000))
        var movieInUkrainian = TitleMetadata(movie, language: .uk, fetchedAt: Date(timeIntervalSince1970: 1_000))
        movieInUkrainian.title = "Example Movie in Ukrainian"
        let seriesInEnglish = TitleMetadata(series, language: .en, fetchedAt: Date(timeIntervalSince1970: 2_000))
        try await store.write([movieInEnglish, movieInUkrainian, seriesInEnglish])

        let metadata = try await store.metadata(for: [movie.id, series.id, missing], preferring: .uk)

        #expect(metadata == [movie.id: movieInUkrainian, series.id: seriesInEnglish])
        #expect(try await store.metadata(for: [movie.id], preferring: .en) == [movie.id: movieInEnglish])
    }

    private func searchResult(_ rawID: String, title: String) throws -> TitleSearchResult {
        let id = try #require(TitleID(rawValue: rawID))
        return TitleSearchResult(
            id: id,
            title: title,
            originalTitle: title,
            year: 1999,
            posterPath: "/example-poster.jpg",
            director: id.mediaType == .movie ? "Example Director" : nil,
            creator: id.mediaType == .tv ? "Example Creator" : nil
        )
    }

    private func item(in folder: Folder, _ titleID: TitleID, at date: Date) -> FolderItem {
        FolderItem(
            folderID: folder.id,
            titleID: titleID,
            isWatched: false,
            watchedUpdatedAt: date,
            addedAt: date,
            updatedAt: date
        )
    }
}
