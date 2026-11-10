// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import DesignSystem
import SwiftUI

/// Home, the screen the app starts on. Until a title exists it shows the design's prompt.
struct HomeView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = ThemeTokens.forScheme(scheme)
        VStack(spacing: Primitives.Space._12) {
            Image("Logo")
                .accessibilityHidden(true)
            Text("What shall we watch?", comment: "The prompt on Home while nothing has been searched.")
                .font(.system(size: 28, weight: .semibold, design: .serif))
                .foregroundStyle(theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(
                "A title, an actor or a mood, by text or by voice",
                comment: "The hint under the prompt on Home."
            )
            .font(.system(size: 15))
            .foregroundStyle(theme.textSecondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Primitives.Space._24 + Primitives.Space._24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bgCanvas)
    }
}

#Preview {
    HomeView()
}
