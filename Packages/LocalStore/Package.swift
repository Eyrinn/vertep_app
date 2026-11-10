// swift-tools-version: 6.0
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import PackageDescription

let package = Package(
    name: "LocalStore",
    platforms: [
        .iOS(.v18),
        // macOS only lets `swift build` and `swift test` run the package on a Mac.
        .macOS(.v15),
    ],
    products: [
        .library(name: "LocalStore", targets: ["LocalStore"]),
    ],
    dependencies: [
        .package(path: "../Core"),
        // MIT license. Pinned to one exact release; see THIRD_PARTY_NOTICES.md.
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        .target(
            name: "LocalStore",
            dependencies: [
                .product(name: "Core", package: "Core"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "LocalStoreTests",
            dependencies: [
                "LocalStore",
                .product(name: "Core", package: "Core"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
    ]
)
