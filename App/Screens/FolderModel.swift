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
/// first, the watched toggle, and the removal with its undo.
@MainActor
@Observable
final class FolderModel {
    /// How long a removal can be undone. The design holds a toast this long.
    static let undoDuration: Duration = .seconds(Primitives.Duration.hold)

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
    @ObservationIgnored let language: SearchLanguage
    @ObservationIgnored private let personalFolderName: String
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var folderID: UUID?
    /// Ends the undo of `pendingUndo` once `undoDuration` has passed.
    @ObservationIgnored private(set) var undoTimer: Task<Void, Never>?
    @ObservationIgnored let logger = Logger(subsystem: "app.vertep.ios", category: "FolderModel")

    /// - Parameters:
    ///   - personalFolderName: the name the personal folder gets if the model has to
    ///     create it.
    ///   - now: the current time, which every change is stored with.
    ///   - sleep: waits for a duration; the undo of a removal ends when it returns.
    init(
        store: any FolderStore,
        language: SearchLanguage,
        personalFolderName: String,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.store = store
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
