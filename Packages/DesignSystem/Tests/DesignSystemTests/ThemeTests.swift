// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import DesignSystem
import SwiftUI
import Testing

struct ThemeTests {
    @Test func eachSchemeGetsItsOwnTheme() {
        #expect(ThemeTokens.forScheme(.light).bgCanvas == ThemeTokens.light.bgCanvas)
        #expect(ThemeTokens.forScheme(.dark).bgCanvas == ThemeTokens.dark.bgCanvas)
        #expect(ThemeTokens.light.bgCanvas != ThemeTokens.dark.bgCanvas)
    }

    @Test func systemFollowsTheDevice() {
        #expect(Appearance.system.colorScheme == nil)
        #expect(Appearance.light.colorScheme == .light)
        #expect(Appearance.dark.colorScheme == .dark)
    }

    @Test func theStoredValueReadsBack() {
        for appearance in Appearance.allCases {
            #expect(Appearance(rawValue: appearance.rawValue) == appearance)
        }
    }
}
