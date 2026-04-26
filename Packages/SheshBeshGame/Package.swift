// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "SheshBeshGame",
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
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "SheshBeshGameTests",
            dependencies: ["SheshBeshGame"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
