// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

@main
struct VertepApp: App {
    // SwiftUI creates the app value once per launch, so the graph is built once too.
    private let root = CompositionRoot()

    var body: some Scene {
        WindowGroup {
            RootView()
                .task { await root.prepareLaunch() }
        }
    }
}
