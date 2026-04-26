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
            name: "SheshBeshApp",
            targets: ["SheshBeshApp"]
        ),
        .executable(
            name: "SheshBesh",
            targets: ["SheshBesh"]
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
            name: "SheshBeshApp",
            dependencies: ["SheshBeshGame"],
            path: "SheshBesh/Shared",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "SheshBesh",
            dependencies: ["SheshBeshApp"],
            path: "SheshBesh/App",
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
            name: "SheshBeshAppTests",
            dependencies: ["SheshBeshApp"],
            path: "SheshBeshTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
