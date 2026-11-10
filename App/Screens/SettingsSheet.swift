// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import DesignSystem
import SwiftUI

/// The settings sheet that the gear on Home opens. It has one section, with the theme.
struct SettingsSheet: View {
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = ThemeTokens.forScheme(scheme)
        // The design draws the rows as cards on a darker ground: the canvas in the light
        // theme and the elevated background in the dark theme.
        let ground = scheme == .dark ? theme.bgElevated : theme.bgCanvas
        NavigationStack {
            List {
                Section {
                    Picker(selection: $appearance) {
                        ForEach(Appearance.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    } label: {
                        Label {
                            Text("Theme", comment: "Settings row that chooses the theme.")
                        } icon: {
                            Image(systemName: "circle.lefthalf.filled")
                                .foregroundStyle(theme.textAccent)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .foregroundStyle(theme.textPrimary)
                    .listRowBackground(theme.bgSheet)
                } header: {
                    Text("App", comment: "Header of the settings section about the app itself.")
                        .font(.system(size: 13))
                        .textCase(.uppercase)
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(ground)
            .navigationTitle(Text("Settings", comment: "Title of the settings sheet, and the label of the gear that opens it."))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(theme.textPrimary)
                            .frame(width: 36, height: 36)
                            .background(theme.materialChrome, in: Circle())
                            .overlay(Circle().strokeBorder(theme.materialChromeStroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Close", comment: "Button that closes the settings sheet."))
                }
            }
        }
        .tint(theme.textAccent)
        .presentationBackground(ground)
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
