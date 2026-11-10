// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import DesignSystem
import SwiftUI

/// The three screens of the carousel, in the order they appear from left to right.
enum Page: Int, CaseIterable, Identifiable {
    case folder
    case home
    case random

    var id: Int { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .folder: LocalizedStringResource("Folder", comment: "Name of the folder screen, read by VoiceOver.")
        case .home: LocalizedStringResource("Home", comment: "Name of the home screen, read by VoiceOver.")
        case .random: LocalizedStringResource("Random", comment: "Name of the random pick screen, read by VoiceOver.")
        }
    }
}

/// The app's root: a paged carousel of Folder, Home and Random that starts on Home, with
/// the page indicator above it and the settings gear on Home.
struct RootView: View {
    @State private var page: Page = RootView.launchPage
    @State private var showsSettings = RootView.launchShowsSettings
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = ThemeTokens.forScheme(scheme)
        TabView(selection: $page) {
            FolderView(goHome: { withAnimation { page = .home } })
                .tag(Page.folder)
            HomeView()
                .tag(Page.home)
            RandomView(goHome: { withAnimation { page = .home } })
                .tag(Page.random)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .safeAreaInset(edge: .top, spacing: 0) {
            TopBar(page: $page, showsSettings: $showsSettings)
                .padding(.horizontal, Primitives.Space._24)
        }
        .background(theme.bgCanvas.ignoresSafeArea())
        .sheet(isPresented: $showsSettings) {
            SettingsSheet()
        }
    }
}

extension RootView {
    // Debug builds read two launch arguments, so a screenshot run can open any screen:
    // `-startPage folder|home|random` and `-showsSettings YES`. Release builds always
    // start on Home with the settings closed.
    #if DEBUG
    static var launchPage: Page {
        switch argument(after: "-startPage") {
        case "folder": .folder
        case "random": .random
        default: .home
        }
    }

    static var launchShowsSettings: Bool { argument(after: "-showsSettings") == "YES" }

    private static func argument(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
    #else
    static let launchPage: Page = .home
    static let launchShowsSettings = false
    #endif
}

/// The bar above the carousel: the gear on Home, and the page indicator in the middle.
private struct TopBar: View {
    @Binding var page: Page
    @Binding var showsSettings: Bool

    var body: some View {
        ZStack {
            PageIndicator(page: $page)
            HStack {
                if page == .home {
                    GearButton { showsSettings = true }
                        .transition(.opacity)
                }
                Spacer()
            }
        }
        .frame(height: 44)
        .animation(.easeInOut(duration: Primitives.Duration.fast), value: page)
    }
}

#Preview {
    RootView()
}
