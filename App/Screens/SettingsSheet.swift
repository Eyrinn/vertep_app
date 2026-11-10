// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import DesignSystem
import SwiftUI

/// The settings sheet that the gear on Home opens. It has one section, with the theme.
/// The design draws it as one page of sections with no nested pages, so the theme is
/// chosen from a menu on its row.
struct SettingsSheet: View {
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = ThemeTokens.forScheme(scheme)
        // The design draws the rows as cards on a darker ground: the canvas in the light
        // theme and the elevated background in the dark theme.
        let ground = scheme == .dark ? theme.bgElevated : theme.bgCanvas
        ScrollView {
            VStack(spacing: Primitives.Space._12) {
                header(theme: theme)
                SettingsSection(title: Text("App", comment: "Header of the settings section about the app itself.")) {
                    Menu {
                        Picker(selection: $appearance) {
                            ForEach(Appearance.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        } label: {
                            EmptyView()
                        }
                    } label: {
                        SettingsRow(
                            icon: "ThemeIcon",
                            title: Text("Theme", comment: "Settings row that chooses the theme."),
                            value: Text(appearance.title)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Primitives.Space._20)
        }
        .background(ground)
        .presentationBackground(ground)
    }

    private func header(theme: ThemeTokens) -> some View {
        ZStack {
            Text("Settings", comment: "Title of the settings sheet, and the label of the gear that opens it.")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    // The design draws the cross in the primary text color in the light
                    // theme and in the tertiary one in the dark theme.
                    Image("Close")
                        .renderingMode(.template)
                        .foregroundStyle(scheme == .dark ? theme.textTertiary : theme.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(theme.materialChrome, in: Circle())
                        .overlay(Circle().strokeBorder(theme.materialChromeStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close", comment: "Button that closes the settings sheet."))
            }
        }
        .frame(height: 44)
    }
}

/// A titled group of settings rows on one card.
private struct SettingsSection<Rows: View>: View {
    let title: Text
    @ViewBuilder let rows: Rows
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = ThemeTokens.forScheme(scheme)
        VStack(alignment: .leading, spacing: Primitives.Space._8) {
            title
                .font(.system(size: 13))
                .textCase(.uppercase)
                .foregroundStyle(theme.textTertiary)
                .padding(.horizontal, Primitives.Space._16)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                rows
            }
            .background(theme.bgSheet, in: RoundedRectangle(cornerRadius: Primitives.Radius._24))
        }
    }
}

/// One settings row: an icon, a title, the current value and a chevron.
private struct SettingsRow: View {
    let icon: String
    let title: Text
    let value: Text
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = ThemeTokens.forScheme(scheme)
        HStack(spacing: Primitives.Space._12) {
            Image(icon)
                .renderingMode(.template)
                .foregroundStyle(theme.textAccent)
                .accessibilityHidden(true)
            title
                .foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            value
                .foregroundStyle(theme.textSecondary)
            Image("Chevron")
                .renderingMode(.template)
                .foregroundStyle(theme.textTertiary)
                .accessibilityHidden(true)
        }
        .font(.system(size: 17))
        .padding(Primitives.Space._16)
        .frame(minHeight: 53)
        .contentShape(Rectangle())
    }
}

extension Appearance {
    /// The name of the theme, as the settings show it.
    var title: LocalizedStringResource {
        switch self {
        case .system: LocalizedStringResource("System", comment: "Theme that follows the device appearance.")
        case .light: LocalizedStringResource("Light", comment: "The light theme.")
        case .dark: LocalizedStringResource("Dark", comment: "The dark theme.")
        }
    }
}

#Preview {
    SettingsSheet()
}
