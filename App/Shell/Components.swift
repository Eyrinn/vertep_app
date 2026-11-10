// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import DesignSystem
import SwiftUI

/// The design's page indicator: one dot per screen, and a wider bar for the screen that
/// is shown. VoiceOver reads it as one adjustable element that moves between screens.
struct PageIndicator: View {
    @Binding var page: Page
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = ThemeTokens.forScheme(scheme)
        HStack(spacing: Primitives.Space._4 + Primitives.Space._2) {
            ForEach(Page.allCases) { item in
                Capsule()
                    .fill(item == page ? theme.textPrimary : theme.textTertiary)
                    .frame(width: item == page ? 18 : 6, height: 6)
            }
        }
        .padding(.vertical, Primitives.Space._8)
        .padding(.horizontal, Primitives.Space._12)
        .background(theme.materialChrome, in: Capsule())
        .overlay(Capsule().strokeBorder(theme.materialChromeStroke, lineWidth: 1))
        .animation(.easeInOut(duration: Primitives.Duration.fast), value: page)
        .accessibilityElement()
        .accessibilityLabel(Text("Screen", comment: "VoiceOver label of the page indicator."))
        .accessibilityValue(Text(page.title))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: move(by: 1)
            case .decrement: move(by: -1)
            @unknown default: break
            }
        }
    }

    private func move(by offset: Int) {
        guard let next = Page(rawValue: page.rawValue + offset) else { return }
        withAnimation { page = next }
    }
}

/// The round gear button on Home that opens the settings.
struct GearButton: View {
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = ThemeTokens.forScheme(scheme)
        Button(action: action) {
            Image("Gear")
                .renderingMode(.template)
                .foregroundStyle(theme.textPrimary)
                .frame(width: 44, height: 44)
                .background(theme.materialChrome, in: Circle())
                .overlay(Circle().strokeBorder(theme.materialChromeStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Settings", comment: "Title of the settings sheet, and the label of the gear that opens it."))
    }
}

/// The design's filled accent button.
struct AccentButton: View {
    /// The two sizes the design uses: the large button of a screen, and the compact one
    /// inside a card.
    enum Size {
        case large
        case compact
    }

    let title: Text
    var systemImage: String?
    var size: Size = .large
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = ThemeTokens.forScheme(scheme)
        Button(action: action) {
            HStack(spacing: size == .large ? Primitives.Space._8 : Primitives.Space._4) {
                title
                if let systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
            }
            .font(.system(size: size == .large ? 17 : 15, weight: .semibold))
            .foregroundStyle(theme.textOnAccent)
            .padding(.horizontal, size == .large ? Primitives.Space._24 : Primitives.Space._20)
            .frame(minHeight: size == .large ? 50 : 36)
            .background(theme.accentFill, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
