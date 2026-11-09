// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Core
import Foundation
import LocalStore
import os

/// Builds the app's object graph: it picks the implementation of every contract `Core`
/// declares and hands the rest of the app those contracts, never the implementations.
///
/// This is the only file that may check whether the optional private module is
/// available. No contract in `Core` has an optional implementation yet, so it wires the
/// open build alone, and a build with or without `Private/` gets the same graph.
@MainActor
final class CompositionRoot {
    let folderStore: any FolderStore

    private let logger = Logger(subsystem: "app.vertep.Vertep", category: "CompositionRoot")

    init() {
        let url = URL.applicationSupportDirectory.appending(path: "Vertep/Vertep.sqlite")
        do {
            folderStore = try LocalDatabase.open(at: url).folderStore
        } catch {
            // Without its database the app has nowhere to keep a folder. Stop with the
            // reason, rather than run on a store that would lose everything.
            fatalError("Could not open the local database at \(url.path): \(error)")
        }
    }

    /// Runs once at every launch. The first launch creates the personal folder; every
    /// later launch finds it and creates nothing.
    func prepareLaunch() async {
        let defaultName = String(
            localized: "My folder",
            comment: "Name of the personal folder the app creates on its first launch."
        )
        do {
            _ = try await folderStore.ensurePersonalFolder(defaultName: defaultName)
        } catch {
            logger.error("Could not create the personal folder: \(String(describing: error), privacy: .public)")
        }
    }
}
