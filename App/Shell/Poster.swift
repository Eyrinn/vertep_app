// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import DesignSystem
import SwiftUI

/// A title's poster from TMDB's image service, with a plain card in its place while it
/// loads, when it fails, or when the title has no poster.
struct Poster: View {
    let url: URL?
    var width: CGFloat = 56
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = ThemeTokens.forScheme(scheme)
        let shape = RoundedRectangle(cornerRadius: Primitives.Radius._8, style: .continuous)
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                theme.bgSunken
                    .overlay {
                        Image(systemName: "film")
                            .foregroundStyle(theme.textTertiary)
                    }
            }
        }
        .frame(width: width, height: width * 3 / 2)
        // The light design warms the poster with the tint, multiplied; the dark design
        // shows it untinted.
        .overlay {
            if scheme == .light {
                theme.posterTint.blendMode(.multiply)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(theme.posterRing, lineWidth: 1))
        .accessibilityHidden(true)
    }
}
