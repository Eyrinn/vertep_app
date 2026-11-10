// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import DesignSystem
import SwiftUI

/// The random pick screen, one swipe left of Home. Until there is an unwatched title it
/// shows the design's nothing-to-randomize state: the curtain in the light theme and the
/// put-out candle in the dark theme.
struct RandomView: View {
    let goHome: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = ThemeTokens.forScheme(scheme)
        let folderName = String(
            localized: "My folder",
            comment: "Name of the personal folder the app creates on its first launch."
        )
        VStack(spacing: Primitives.Space._4) {
            Image(scheme == .dark ? "EmptyRandomCandle" : "EmptyRandomCurtain")
                .padding(.bottom, Primitives.Space._16)
                .accessibilityHidden(true)
            Text("Nothing to randomize", comment: "Title of the random screen when no title can be picked.")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(
                "Everything in “\(folderName)” is already watched",
                comment: "Hint on the random screen when no title can be picked. The argument is the folder name."
            )
            .font(.system(size: 13))
            .foregroundStyle(theme.textSecondary)
            AccentButton(
                title: Text("Find a film", comment: "Button on the random screen. It goes to Home, where search starts."),
                action: goHome
            )
            .padding(.top, Primitives.Space._32)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Primitives.Space._24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bgCanvas)
    }
}

#Preview {
    RandomView(goHome: {})
}
