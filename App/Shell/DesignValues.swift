// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import DesignSystem
import SwiftUI

/// Values the design uses that no design system token holds. Each one names the Figma
/// variable it is made from.
enum DesignValues {
    /// The inner border of a watched folder row: `status/watched` at 28% in light, and
    /// at 30% in dark.
    static func watchedRowBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Primitives.Color.sage300.opacity(0.3)
            : Primitives.Color.sage700.opacity(0.28)
    }

    /// The fill of the toast: `color/paper/50` in light, and `color/ink/800` at 92% in
    /// dark.
    static func toastFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Primitives.Color.ink800.opacity(0.92)
            : Primitives.Color.paper50
    }

    /// The drop shadow of the toast: `color/ink/950` at 12% in light, and at 35% in dark.
    static func toastShadow(_ scheme: ColorScheme) -> Color {
        Primitives.Color.ink950.opacity(scheme == .dark ? 0.35 : 0.12)
    }

    /// The folder icon on the empty folder card: `color/paper/50` in light, and
    /// `color/paper/100` in dark.
    static func emptyFolderIcon(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Primitives.Color.paper100 : Primitives.Color.paper50
    }

    /// The height of the fade at the bottom of the folder list.
    static let listFadeHeight: CGFloat = 60
}
