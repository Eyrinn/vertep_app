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
                    .listRowBackground(theme.bgElevated)
                } header: {
                    Text("App", comment: "Header of the settings section about the app itself.")
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.bgSheet)
            .navigationTitle(Text("Settings", comment: "Title of the settings sheet, and the label of the gear that opens it."))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(theme.textPrimary)
                    }
                    .accessibilityLabel(Text("Close", comment: "Button that closes the settings sheet."))
                }
            }
        }
        .tint(theme.textAccent)
        .presentationBackground(theme.bgSheet)
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
