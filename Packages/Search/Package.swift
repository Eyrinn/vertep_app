// swift-tools-version: 6.0
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import PackageDescription

// Search implements the title search and the App Attest client that Core declares. It uses
// only Apple's frameworks, so it adds no package to the dependency graph.
let package = Package(
    name: "Search",
    platforms: [
        .iOS(.v18),
        // macOS only lets `swift build` and `swift test` run the package on a Mac.
        .macOS(.v15),
    ],
    products: [
        .library(name: "Search", targets: ["Search"]),
    ],
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        .target(
            name: "Search",
            dependencies: [.product(name: "Core", package: "Core")]
        ),
        .testTarget(
            name: "SearchTests",
            dependencies: ["Search", .product(name: "Core", package: "Core")]
        ),
    ]
)
