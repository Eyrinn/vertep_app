// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import DesignSystem
import SwiftUI

@main
struct VertepApp: App {
    // SwiftUI creates the app value once per launch, so the graph is built once too.
    private let root = CompositionRoot()
    // The theme chosen in the settings. It is stored on this device only.
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system

    var body: some Scene {
        WindowGroup {
            RootView()
                .onChange(of: appearance, initial: true) { apply(appearance) }
                .task { await root.prepareLaunch() }
        }
    }

    /// Applies the theme to every window of the app, sheets included. Setting the window's
    /// interface style, rather than `preferredColorScheme`, lets System hand the
    /// appearance back to the device at once, without a restart.
    @MainActor
    private func apply(_ appearance: Appearance) {
        // No color scheme means System: `.unspecified` lets the device decide.
        let style = appearance.colorScheme.map(UIUserInterfaceStyle.init) ?? .unspecified
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}
