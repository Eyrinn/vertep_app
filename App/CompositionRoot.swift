// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Core
import Foundation
import LocalStore
import os
import Search

/// Builds the app's object graph: it picks the implementation of every contract `Core`
/// declares and hands the rest of the app those contracts, never the implementations.
///
/// This is the only file that may check whether the optional private module is
/// available. No contract in `Core` has an optional implementation yet, so it wires the
/// open build alone, and a build with or without `Private/` gets the same graph.
@MainActor
final class CompositionRoot {
    let folderStore: any FolderStore
    let titleSearch: any TitleSearch
    /// The language a title search asks for: the language the app runs in.
    let searchLanguage = SearchLanguage(appLocalizations: Bundle.main.preferredLocalizations)

    private let logger = Logger(subsystem: "app.vertep.ios", category: "CompositionRoot")

    init() {
        titleSearch = Self.makeTitleSearch(
            SearchConfiguration(
                infoDictionary: Bundle.main.infoDictionary,
                readsPersonalKey: Self.readsPersonalKey
            ),
            logger: logger
        )
        let url = URL.applicationSupportDirectory.appending(path: "Vertep/Vertep.sqlite")
        do {
            folderStore = try LocalDatabase.open(at: url).folderStore
        } catch {
            // Without its database the app has nowhere to keep a folder. Stop with the
            // reason, rather than run on a store that would lose everything.
            fatalError("Could not open the local database at \(url.path): \(error)")
        }
    }

    /// Whether this build reads the personal TMDB key. Only a debug build does: a release
    /// build is given to people, and the key is a personal one.
    #if DEBUG
    private static let readsPersonalKey = true
    #else
    private static let readsPersonalKey = false
    #endif

    /// Picks the title search: the proxy when a proxy URL is configured and the device
    /// supports App Attest, otherwise TMDB directly when a debug build has a personal key,
    /// otherwise a search that reports that it is not configured.
    private static func makeTitleSearch(_ configuration: SearchConfiguration, logger: Logger) -> any TitleSearch {
        let attestation = DeviceAppAttestation()
        switch configuration.choice(appAttestSupported: attestation.isSupported) {
        case .proxy(let baseURL):
            logger.info("Title search goes through the proxy.")
            return ProxyTitleSearch(
                baseURL: baseURL,
                attestation: attestation,
                keyStore: KeychainKeyIDStore(service: "app.vertep.ios.app-attest")
            )
        case .direct(let apiKey):
            logger.info("Title search goes to TMDB directly.")
            return DirectTMDBTitleSearch(apiKey: apiKey)
        case .notConfigured:
            logger.info("Title search is not configured.")
            return NotConfiguredTitleSearch()
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
