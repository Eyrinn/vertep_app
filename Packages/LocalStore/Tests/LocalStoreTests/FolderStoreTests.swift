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
