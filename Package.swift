// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "SheshBesh",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "SheshBeshGame",
            targets: ["SheshBeshGame"]
        ),
        .library(
            name: "SheshBeshLedger",
            targets: ["SheshBeshLedger"]
        ),
        .library(
            name: "SheshBeshApp",
            targets: ["SheshBeshApp"]
        ),
    ],
    targets: [
        .target(
            name: "SheshBeshGame",
            path: "Packages/SheshBeshGame/Sources/SheshBeshGame",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .target(
            name: "SheshBeshLedger",
            dependencies: ["SheshBeshGame"],
            path: "Packages/SheshBeshLedger/Sources/SheshBeshLedger",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .target(
            name: "SheshBeshApp",
            dependencies: ["SheshBeshGame", "SheshBeshLedger"],
            path: "SheshBesh/Shared",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "SheshBeshGameTests",
            dependencies: ["SheshBeshGame"],
            path: "Packages/SheshBeshGame/Tests/SheshBeshGameTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "SheshBeshLedgerTests",
            dependencies: ["SheshBeshLedger", "SheshBeshGame"],
            path: "Packages/SheshBeshLedger/Tests/SheshBeshLedgerTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "SheshBeshAppTests",
            dependencies: ["SheshBeshApp", "SheshBeshGame", "SheshBeshLedger"],
            path: "SheshBeshTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
