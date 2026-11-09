// swift-tools-version: 6.0
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import PackageDescription

// Core declares the contracts the app is built against. It has no dependency, so it
// builds alone and no storage library reaches its dependency graph.
let package = Package(
    name: "Core",
    platforms: [
        .iOS(.v18),
        // macOS only lets `swift build` and `swift test` run the package on a Mac.
        .macOS(.v15),
    ],
    products: [
        .library(name: "Core", targets: ["Core"]),
    ],
    targets: [
        .target(name: "Core"),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
    ]
)
