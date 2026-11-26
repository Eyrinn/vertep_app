// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

/// One of the design's icons from the asset catalog, drawn at its size in the design and
/// tinted by the foreground style around it.
struct DesignIcon: View {
    /// The name of the template image set in the asset catalog.
    let name: String
    /// The width and height of the icon in the design, in points.
    let size: CGFloat

    var body: some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .frame(width: size, height: size)
    }
}
