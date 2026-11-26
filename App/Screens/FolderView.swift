// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Core
import DesignSystem
import LocalStore
import SwiftUI

/// The folder screen, one swipe right of Home: the personal folder's tab with the number
/// of titles, and its titles, newest added first. While the folder has no title it shows
/// the design's empty folder card. A removal shows a toast that can undo it.
struct FolderView: View {
    let model: FolderModel
    let goHome: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = ThemeTokens.forScheme(scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: Primitives.Space._24) {
                FolderTab(count: model.rows.count)
                if model.showsEmptyState {
                    EmptyFolderCard(goHome: goHome)
                } else {
                    LazyVStack(spacing: Primitives.Space._12) {
                        ForEach(model.rows) { row in
                            FolderRowView(
                                row: row,
                                toggleWatched: { Task { await model.setWatched(!row.isWatched, for: row.id) } },
                                delete: { Task { await model.delete(row.id) } }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, Primitives.Space._24)
            .padding(.top, Primitives.Space._16)
            // Room for the toast, so it never covers the last row.
            .padding(.bottom, Primitives.Space._48 + Primitives.Space._32)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) {
            if model.pendingUndo != nil {
                Toast(
                    message: Text("Removed from the folder", comment: "Toast after a title is removed from the folder."),
                    actionTitle: Text("Undo", comment: "Button on the toast after a removal. It puts the title back in the folder."),
                    action: { Task { await model.undo() } }
                )
                .padding(.horizontal, Primitives.Space._16)
                .padding(.bottom, Primitives.Space._16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: Primitives.Duration.base), value: model.rows.map(\.id))
        .animation(.easeInOut(duration: Primitives.Duration.base), value: model.pendingUndo)
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
        // The selected tab is drawn in the other theme's colors, as the design shows it.
        let inverse = ThemeTokens.forScheme(scheme == .dark ? .light : .dark)
        HStack(spacing: Primitives.Space._4) {
            Text("My folder", comment: "Name of the personal folder the app creates on its first launch.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(inverse.textPrimary)
            Text(count, format: .number)
                .font(.system(size: 12))
                .foregroundStyle(inverse.textTertiary)
        }
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
                .foregroundStyle(Primitives.Color.curtain200)
            AccentButton(
                title: Text("To search", comment: "Button on the empty folder card. It goes to Home, where search starts."),
                systemImage: "arrow.right",
                size: .compact,
                action: goHome
            )
            .padding(.top, Primitives.Space._16)
        }
        .multilineTextAlignment(.center)
        .padding(.vertical, Primitives.Space._32)
        .padding(.horizontal, Primitives.Space._16)
        .frame(maxWidth: .infinity)
        .background(theme.bgBrand, in: RoundedRectangle(cornerRadius: Primitives.Radius._24, style: .continuous))
    }
}

#if DEBUG
extension FolderModel {
    /// A model on an empty in-memory database that sends no request, for previews.
    static func preview() -> FolderModel {
        FolderModel(
            store: try! LocalDatabase.inMemory().folderStore,
            details: NotConfiguredTitleDetailsProvider(),
            network: OfflineNetworkStatus(),
            language: .en,
            personalFolderName: "My folder"
        )
    }
}

/// A network status for previews: always offline, so a preview sends nothing.
private struct OfflineNetworkStatus: NetworkStatus {
    func isOnline() async -> Bool { false }
}
#endif

#Preview {
    let model = FolderModel.preview()
    FolderView(model: model, goHome: {})
        .task { await model.reload() }
}
