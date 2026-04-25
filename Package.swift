// swift-tools-version: 6.3

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
    ],
    targets: [
        .target(
            name: "SheshBeshGame",
            path: "Packages/SheshBeshGame/Sources/SheshBeshGame",
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
    ]
)
