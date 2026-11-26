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
            VStack(alignment: .leading, spacing: 0) {
                FolderTab(count: model.rows.count)
                if model.showsEmptyState {
                    EmptyFolderCard(goHome: goHome)
                        .padding(.top, Primitives.Space._32)
                } else if !model.rows.isEmpty {
                    summary
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textSecondary)
                        .padding(.top, Primitives.Space._8)
                    LazyVStack(spacing: 0) {
                        ForEach(model.rows) { row in
                            FolderRowView(
                                row: row,
                                toggleWatched: { Task { await model.setWatched(!row.isWatched, for: row.id) } },
                                delete: { Task { await model.delete(row.id) } }
                            )
                        }
                    }
                    .padding(.top, Primitives.Space._16)
                }
            }
            .padding(.horizontal, Primitives.Space._24)
            .padding(.top, Primitives.Space._16)
            // Room for the toast and the fade, so neither covers the last row.
            .padding(.bottom, Primitives.Space._48 + Primitives.Space._32)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                // The list fades into the canvas at the bottom of the screen.
                LinearGradient(colors: [theme.bgCanvas.opacity(0), theme.bgCanvas], startPoint: .top, endPoint: .bottom)
                    .frame(height: DesignValues.listFadeHeight)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                if model.pendingUndo != nil {
                    Toast(
                        message: Text("Removed from the folder", comment: "Toast after a title is removed from the folder."),
                        systemImage: "trash",
                        actionTitle: Text("Undo", comment: "Button on the toast after a removal. It puts the title back in the folder."),
                        action: { Task { await model.undo() } }
                    )
                    .padding(.horizontal, Primitives.Space._24)
                    // The design sets the toast 40 pt above the bottom edge of the screen.
                    .padding(.bottom, Primitives.Space._40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .animation(.easeInOut(duration: Primitives.Duration.base), value: model.rows.map(\.id))
        .animation(.easeInOut(duration: Primitives.Duration.base), value: model.pendingUndo)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bgCanvas)
    }

    /// The line under the tab: the number of titles and how many of them are watched.
    private var summary: Text {
        Text(
            "\(model.rows.count) titles · \(model.watchedCount) watched",
            comment: "Line under the folder tab: the number of titles in the folder, then how many of them are watched."
        )
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
        HStack(spacing: 6) {
            Text("My folder", comment: "Name of the personal folder the app creates on its first launch.")
                .font(.system(size: 15, weight: .semibold))
            Text(count, format: .number)
                .font(.system(size: 12, weight: .semibold))
                .opacity(0.7)
        }
        .foregroundStyle(inverse.textPrimary)
        .lineLimit(1)
        .padding(.horizontal, 14)
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
                .font(.system(size: 30))
                .foregroundStyle(DesignValues.emptyFolderIcon(scheme))
                .frame(width: 36, height: 36)
                .padding(.bottom, Primitives.Space._8)
                .accessibilityHidden(true)
            Text("The folder is empty", comment: "Title of the empty folder card.")
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundStyle(theme.textOnBrand)
                .accessibilityAddTraits(.isHeader)
            // The design sets the hint on a 19.6 pt line.
            Text("Add your first film", comment: "Hint on the empty folder card.")
                .font(.system(size: 14))
                .padding(.vertical, 1)
                .foregroundStyle(Primitives.Color.curtain200)
            AccentButton(
                title: Text("To search", comment: "Button on the empty folder card. It goes to Home, where search starts."),
                systemImage: "arrow.right",
                size: .compact,
                action: goHome
            )
            .padding(.top, Primitives.Space._12)
        }
        .multilineTextAlignment(.center)
        .padding(.vertical, Primitives.Space._20)
        .padding(.horizontal, Primitives.Space._16)
        .frame(maxWidth: .infinity, minHeight: 232)
        .background(theme.bgBrand, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
