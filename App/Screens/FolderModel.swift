// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Core
import DesignSystem
import Foundation
import Observation
import os

/// One title of the folder screen: the folder item and what the app stored about the
/// title.
struct FolderRow: Identifiable, Hashable {
    var item: FolderItem
    /// Nil when the app stored nothing about the title.
    var metadata: TitleMetadata?

    var id: TitleID { item.titleID }
    var isWatched: Bool { item.isWatched }

    /// The title in the language the metadata was stored in.
    var title: String? { metadata?.title }

    /// The line under the title: the year, the first genre, and the director of a movie
    /// or the creator of a series, each one only when it is known.
    var detailsLine: String {
        [
            metadata?.year.map { String($0) },
            metadata?.genres?.first?.name,
            metadata?.director ?? metadata?.creator,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    var overview: String? { metadata?.overview }

    /// The cast names in billing order, or nil when none is known.
    var castLine: String? {
        guard let cast = metadata?.cast, !cast.isEmpty else { return nil }
        return cast.joined(separator: ", ")
    }

    /// The poster on TMDB's image service, at the size a row shows it.
    var posterURL: URL? {
        metadata?.posterPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w185\($0)") }
    }
}

/// A removal from the folder that can still be undone.
struct PendingUndo: Equatable {
    /// Tells two removals of the same title apart.
    let id = UUID()
    let titleID: TitleID
}

/// The state of the folder screen: the titles of the personal folder, newest added
/// first, the watched toggle, the removal with its undo, and the refresh of the stored
/// metadata.
@MainActor
@Observable
final class FolderModel {
    /// How long a removal can be undone. The design holds a toast this long.
    static let undoDuration: Duration = .seconds(Primitives.Duration.hold)
    /// Metadata older than this is fetched again.
    static let metadataMaximumAge: TimeInterval = 90 * 24 * 60 * 60

    /// The titles of the folder, the last added first. A watched title keeps its place.
    private(set) var rows: [FolderRow] = []
    /// Whether the folder was read at least once.
    private(set) var hasLoaded = false
    /// The last removal, while it can still be undone.
    private(set) var pendingUndo: PendingUndo?

    /// Whether the screen shows the empty folder state: the folder was read and holds no
    /// title.
    var showsEmptyState: Bool { hasLoaded && rows.isEmpty }

    @ObservationIgnored let store: any FolderStore
    @ObservationIgnored let details: any TitleDetailsProvider
    @ObservationIgnored let network: any NetworkStatus
    @ObservationIgnored let language: SearchLanguage
    @ObservationIgnored private let personalFolderName: String
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var folderID: UUID?
    /// Ends the undo of `pendingUndo` once `undoDuration` has passed.
    @ObservationIgnored private(set) var undoTimer: Task<Void, Never>?
    /// The refresh that runs now, if one does.
    @ObservationIgnored private var refresh: Task<Void, Never>?
    @ObservationIgnored let logger = Logger(subsystem: "app.vertep.ios", category: "FolderModel")

    /// - Parameters:
    ///   - details: gets the details of the titles whose metadata is out of date.
    ///   - network: tells whether a refresh can send requests.
    ///   - language: the language of the app, which rows and details are shown in.
    ///   - personalFolderName: the name the personal folder gets if the model has to
    ///     create it.
    ///   - now: the current time, which every change is stored with.
    ///   - sleep: waits for a duration; the undo of a removal ends when it returns.
    init(
        store: any FolderStore,
        details: any TitleDetailsProvider,
        network: any NetworkStatus,
        language: SearchLanguage,
        personalFolderName: String,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.store = store
        self.details = details
        self.network = network
        self.language = language
        self.personalFolderName = personalFolderName
        self.now = now
        self.sleep = sleep
    }

    /// Reads the folder and the stored metadata of its titles again.
    func reload() async {
        do {
            let folderID = try await personalFolderID()
            let items = try await store.items(in: folderID)
            let metadata = try await store.metadata(for: items.map(\.titleID), preferring: language)
            rows = items
                .sorted { ($0.addedAt, $0.titleID.rawValue) > ($1.addedAt, $1.titleID.rawValue) }
                .map { FolderRow(item: $0, metadata: metadata[$0.titleID]) }
            hasLoaded = true
        } catch {
            logger.error("Could not read the folder: \(String(describing: error), privacy: .public)")
        }
    }

    /// The folder screen appeared: reads the folder and refreshes the metadata that is out
    /// of date.
    func screenAppeared() async {
        await reload()
        await refreshMetadata()
    }

    /// The app entered the foreground: reads the folder and refreshes the metadata that is
    /// out of date.
    func enteredForeground() async {
        await reload()
        await refreshMetadata()
    }

    /// Whether the metadata of a title has to be fetched again: there is none, it has only
    /// the fields of a search result, it is older than `metadataMaximumAge`, or it is in
    /// another language than the app's.
    func needsRefresh(_ metadata: TitleMetadata?, at date: Date) -> Bool {
        guard let metadata else { return true }
        return !metadata.hasDetails
            || metadata.language != language
            || date.timeIntervalSince(metadata.fetchedAt) > Self.metadataMaximumAge
    }

    /// Gets new details for every row whose metadata is out of date, in requests of at
    /// most `TitleDetailsRequest.maximumCount` titles, and stores them. Sends nothing while
    /// the device is offline. A title the details report as not found keeps its stored
    /// metadata and stays in the folder. A call made while a refresh runs waits for it and
    /// starts no other.
    func refreshMetadata() async {
        if let refresh {
            await refresh.value
            return
        }
        let task = Task { await self.runRefresh() }
        refresh = task
        await task.value
        refresh = nil
    }

    private func runRefresh() async {
        let date = now()
        let outdated = rows.filter { needsRefresh($0.metadata, at: date) }.map(\.id)
        guard !outdated.isEmpty, await network.isOnline() else { return }
        var fetched = false
        for start in stride(from: 0, to: outdated.count, by: TitleDetailsRequest.maximumCount) {
            let batch = Array(outdated[start..<min(start + TitleDetailsRequest.maximumCount, outdated.count)])
            guard let request = TitleDetailsRequest(ids: batch, language: language) else { continue }
            let response: TitleDetailsResponse
            do {
                response = try await details.details(request)
            } catch {
                // The next appear or the next return to the foreground tries again.
                logger.info("Title details are not available now: \(String(describing: error), privacy: .public)")
                break
            }
            let fetchedAt = now()
            do {
                try await store.write(response.results.map { TitleMetadata($0, language: language, fetchedAt: fetchedAt) })
                fetched = true
            } catch {
                logger.error("Could not store title details: \(String(describing: error), privacy: .public)")
                break
            }
        }
        if fetched {
            await reload()
        }
    }

    /// Turns the watched flag of a title on or off. The title keeps its place.
    func setWatched(_ isWatched: Bool, for titleID: TitleID) async {
        do {
            let folderID = try await personalFolderID()
            try await store.setWatched(isWatched, for: titleID, in: folderID, at: now())
        } catch {
            logger.error("Could not change the watched flag: \(String(describing: error), privacy: .public)")
        }
        await reload()
    }

    /// Removes a title from the folder at once, and lets the removal be undone for
    /// `undoDuration`. A removal that is still undoable ends: only the last one can be
    /// undone.
    func delete(_ titleID: TitleID) async {
        do {
            let folderID = try await personalFolderID()
            guard try await store.remove(titleID, from: folderID, at: now()) else { return }
        } catch {
            logger.error("Could not remove a title: \(String(describing: error), privacy: .public)")
            return
        }
        await reload()
        let undo = PendingUndo(titleID: titleID)
        pendingUndo = undo
        startUndoTimer(for: undo)
    }

    /// Puts the title of the last removal back. It keeps its watched flag and its added
    /// date, so its row is back in its place.
    func undo() async {
        guard let undo = pendingUndo else { return }
        endUndo()
        do {
            let folderID = try await personalFolderID()
            try await store.restore(undo.titleID, in: folderID)
        } catch {
            logger.error("Could not restore a title: \(String(describing: error), privacy: .public)")
        }
        await reload()
    }

    private func startUndoTimer(for undo: PendingUndo) {
        undoTimer?.cancel()
        let sleep = self.sleep
        undoTimer = Task { [weak self] in
            do {
                try await sleep(Self.undoDuration)
            } catch {
                return
            }
            guard !Task.isCancelled, let self, self.pendingUndo == undo else { return }
            self.pendingUndo = nil
            self.undoTimer = nil
        }
    }

    private func endUndo() {
        undoTimer?.cancel()
        undoTimer = nil
        pendingUndo = nil
    }

    /// The id of the personal folder. The model creates the folder when it does not
    /// exist yet.
    func personalFolderID() async throws -> UUID {
        if let folderID { return folderID }
        let folder = try await store.ensurePersonalFolder(defaultName: personalFolderName)
        folderID = folder.id
        return folder.id
    }
}
