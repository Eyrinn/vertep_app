// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

extension ThemeTokens {
    /// The tokens of the theme that matches a color scheme: dark for `.dark`, light
    /// otherwise.
    public static func forScheme(_ scheme: ColorScheme) -> ThemeTokens {
        scheme == .dark ? .dark : .light
    }
}

/// The theme a person chose in the settings. It is a preference of this device.
public enum Appearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    /// The color scheme the app applies to its windows. `nil` follows the device.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// The key the choice is stored under in `UserDefaults`.
    public static let storageKey = "appearance"
}
