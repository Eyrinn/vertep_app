// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import DesignSystem
import SwiftUI

/// The folder screen, one swipe right of Home. Until a title is added it shows the
/// personal folder's tab and the design's empty folder card.
struct FolderView: View {
    let goHome: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = ThemeTokens.forScheme(scheme)
        VStack(alignment: .leading, spacing: Primitives.Space._32) {
            FolderTab(count: 0)
            EmptyFolderCard(goHome: goHome)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Primitives.Space._24)
        .padding(.top, Primitives.Space._16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bgCanvas)
    }
}

/// The selected tab of the personal folder, with the number of titles in it.
private struct FolderTab: View {
    let count: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = ThemeTokens.forScheme(scheme)
        HStack(spacing: Primitives.Space._4) {
            Text("My folder", comment: "Name of the personal folder the app creates on its first launch.")
                .font(.system(size: 15, weight: .semibold))
            Text(count, format: .number)
                .font(.system(size: 12))
        }
        .foregroundStyle(theme.bgCanvas)
        .padding(.horizontal, Primitives.Space._16)
        .frame(height: 40)
        .background(theme.bgInverse, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isSelected)
    }
}

/// The design's empty folder card: a hint and a button that leads to search on Home.
private struct EmptyFolderCard: View {
    let goHome: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = ThemeTokens.forScheme(scheme)
        VStack(spacing: Primitives.Space._4) {
            Image(systemName: "folder")
                .font(.system(size: 28))
                .foregroundStyle(theme.textOnBrand)
                .padding(.bottom, Primitives.Space._8)
                .accessibilityHidden(true)
            Text("The folder is empty", comment: "Title of the empty folder card.")
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundStyle(theme.textOnBrand)
                .accessibilityAddTraits(.isHeader)
            Text("Add your first film", comment: "Hint on the empty folder card.")
                .font(.system(size: 13))
                .foregroundStyle(theme.textOnBrand)
            AccentButton(
                title: Text("To search", comment: "Button on the empty folder card. It goes to Home, where search starts."),
                systemImage: "arrow.right",
                action: goHome
            )
            .padding(.top, Primitives.Space._16)
        }
        .multilineTextAlignment(.center)
        .padding(.vertical, Primitives.Space._40)
        .padding(.horizontal, Primitives.Space._16)
        .frame(maxWidth: .infinity)
        .background(theme.bgBrand, in: RoundedRectangle(cornerRadius: Primitives.Radius._24, style: .continuous))
    }
}

#Preview {
    FolderView(goHome: {})
}
