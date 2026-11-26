// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import DesignSystem
import SwiftUI

/// The design's folder row: the poster, the title, the line with the year, the first
/// genre and the director or creator, a two-line overview and the cast, with the watched
/// toggle and the delete control. A watched title keeps its place and shows the watched
/// look.
struct FolderRowView: View {
    let row: FolderRow
    let toggleWatched: () -> Void
    let delete: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = ThemeTokens.forScheme(scheme)
        HStack(alignment: .top, spacing: Primitives.Space._12) {
            Poster(url: row.posterURL, width: 56)
            VStack(alignment: .leading, spacing: 3) {
                title
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !row.detailsLine.isEmpty {
                    Text(verbatim: row.detailsLine)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
                if let overview = row.overview {
                    // The design sets the overview on a 20 pt line.
                    Text(verbatim: overview)
                        .font(.system(size: 15))
                        .lineSpacing(2)
                        .padding(.vertical, 1)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                }
                if row.isWatched || row.castLine != nil {
                    HStack(spacing: Primitives.Space._8) {
                        if row.isWatched {
                            WatchedBadge()
                        }
                        if let cast = row.castLine {
                            Text(verbatim: cast)
                                .font(.system(size: 12))
                                .foregroundStyle(theme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: Primitives.Space._4) {
                WatchedToggle(isWatched: row.isWatched, action: toggleWatched)
                DeleteButton(action: delete)
            }
        }
        .padding(Primitives.Space._12)
        .background {
            // A title that is not watched has no card; a watched one is tinted.
            if row.isWatched {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(theme.statusWatchedTint)
                    .overlay(
                        RoundedRectangle(cornerRadius: Primitives.Radius._16, style: .continuous)
                            .strokeBorder(DesignValues.watchedRowBorder(scheme), lineWidth: 1)
                    )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(
            row.isWatched
                ? Text("Watched", comment: "Mark on a folder row whose title is watched, and its VoiceOver value.")
                : Text(verbatim: "")
        )
        .accessibilityAction(named: watchedActionName, toggleWatched)
        .accessibilityAction(named: Text("Delete", comment: "Control on a folder row that removes the title from the folder, and its VoiceOver action."), delete)
    }

    private var title: Text {
        if let title = row.title {
            Text(verbatim: title)
        } else {
            Text("Unknown title", comment: "Title of a folder row while the app has stored nothing about the title.")
        }
    }

    private var watchedActionName: Text {
        row.isWatched
            ? Text("Mark as not watched", comment: "Control on a folder row that turns the watched mark off, and its VoiceOver action.")
            : Text("Mark as watched", comment: "Control on a folder row that turns the watched mark on, and its VoiceOver action.")
    }

    /// The title, then the line under it and the overview, as VoiceOver reads the row.
    private var accessibilityLabel: Text {
        var parts = [title]
        if !row.detailsLine.isEmpty { parts.append(Text(verbatim: row.detailsLine)) }
        if let overview = row.overview { parts.append(Text(verbatim: overview)) }
        if let cast = row.castLine { parts.append(Text(verbatim: cast)) }
        return parts.dropFirst().reduce(parts[0]) { label, part in label + Text(verbatim: ". ") + part }
    }
}

/// The watched badge before the cast of a watched row.
private struct WatchedBadge: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = ThemeTokens.forScheme(scheme)
        // The badge's text and icon take the other theme's primary text color.
        let inverse = ThemeTokens.forScheme(scheme == .dark ? .light : .dark)
        // The light frame pads the badge by 9 with a gap of 5, the dark frame by 8 and 4.
        let isDark = scheme == .dark
        HStack(spacing: isDark ? Primitives.Space._4 : 5) {
            Image(systemName: "checkmark")
                .font(.system(size: 7, weight: .bold))
                .frame(width: 8, height: 8)
            Text("Watched", comment: "Mark on a folder row whose title is watched, and its VoiceOver value.")
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)
        }
        .foregroundStyle(inverse.textPrimary)
        .padding(.horizontal, isDark ? Primitives.Space._8 : 9)
        .frame(height: 24)
        .background(theme.statusWatched, in: Capsule())
        .fixedSize()
        .accessibilityHidden(true)
    }
}

/// The round toggle of a folder row that marks its title watched.
private struct WatchedToggle: View {
    let isWatched: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = ThemeTokens.forScheme(scheme)
        let inverse = ThemeTokens.forScheme(scheme == .dark ? .light : .dark)
        Button(action: action) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isWatched ? inverse.textPrimary : theme.textTertiary)
                .frame(width: 30, height: 30)
                .background {
                    if isWatched {
                        Circle().fill(theme.statusWatched)
                    } else {
                        Circle().strokeBorder(theme.borderStrong, lineWidth: 1.5)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isWatched
                ? Text("Mark as not watched", comment: "Control on a folder row that turns the watched mark off, and its VoiceOver action.")
                : Text("Mark as watched", comment: "Control on a folder row that turns the watched mark on, and its VoiceOver action.")
        )
    }
}

/// The control of a folder row that removes its title from the folder.
private struct DeleteButton: View {
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = ThemeTokens.forScheme(scheme)
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 15))
                .foregroundStyle(theme.textTertiary)
                .frame(width: 16, height: 16)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Delete", comment: "Control on a folder row that removes the title from the folder, and its VoiceOver action."))
    }
}
