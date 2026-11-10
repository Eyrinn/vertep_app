// swift-tools-version: 6.0
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import PackageDescription

// DesignSystem holds the design tokens exported from the Figma design, as DTCG JSON in
// tokens/, and Tokens.swift, which scripts/tokens.py generates from them.
let package = Package(
    name: "DesignSystem",
    platforms: [
        .iOS(.v18),
        // macOS only lets `swift build` and `swift test` run the package on a Mac.
        .macOS(.v15),
    ],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
    ],
    targets: [
        .target(name: "DesignSystem"),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
    ]
)
