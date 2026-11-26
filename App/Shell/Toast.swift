// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import DesignSystem
import SwiftUI

/// The design's toast: a short message at the bottom of the screen with one action.
struct Toast: View {
    let message: Text
    let actionTitle: Text
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = ThemeTokens.forScheme(scheme)
        // The toast is drawn in the other theme's colors, so it stands out on the canvas.
        let inverse = ThemeTokens.forScheme(scheme == .dark ? .light : .dark)
        HStack(spacing: Primitives.Space._12) {
            message
                .font(.system(size: 15))
                .foregroundStyle(inverse.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: action) {
                actionTitle
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(inverse.textAccent)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, Primitives.Space._20)
        .padding(.trailing, Primitives.Space._16)
        .padding(.vertical, Primitives.Space._4)
        .background(theme.bgInverse, in: RoundedRectangle(cornerRadius: Primitives.Radius._16, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
