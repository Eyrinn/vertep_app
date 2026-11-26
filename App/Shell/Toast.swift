// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import DesignSystem
import SwiftUI

/// The design's toast: a capsule at the bottom of the screen with an icon, a short
/// message and one action.
struct Toast: View {
    let message: Text
    var systemImage: String?
    let actionTitle: Text
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = ThemeTokens.forScheme(scheme)
        HStack(spacing: Primitives.Space._12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            }
            message
                .font(.system(size: 15))
                .foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: action) {
                actionTitle
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.textAccent)
                    .padding(.horizontal, Primitives.Space._24)
                    .frame(height: 36)
                    // The button is 36 pt tall in the design; the touch target is 44.
                    .contentShape(Rectangle().inset(by: -Primitives.Space._4))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, Primitives.Space._16)
        .padding(.trailing, Primitives.Space._8)
        .padding(.vertical, Primitives.Space._12)
        .background {
            Capsule()
                .fill(DesignValues.toastFill(scheme))
                .shadow(color: DesignValues.toastShadow(scheme), radius: 12, x: 0, y: 8)
        }
        .overlay(Capsule().strokeBorder(theme.materialChromeStroke, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}
