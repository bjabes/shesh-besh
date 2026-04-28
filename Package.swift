// swift-tools-version: 6.2

import PackageDescription

var products: [Product] = [
    .library(
        name: "SheshBeshGame",
        targets: ["SheshBeshGame"]
    ),
    .library(
        name: "SheshBeshLedger",
        targets: ["SheshBeshLedger"]
    ),
]

var targets: [Target] = [
    .target(
        name: "SheshBeshGame",
        path: "Packages/SheshBeshGame/Sources/SheshBeshGame",
        swiftSettings: [
            .swiftLanguageMode(.v6),
            .treatAllWarnings(as: .error),
        ]
    ),
    .target(
        name: "SheshBeshLedger",
        dependencies: ["SheshBeshGame"],
        path: "Packages/SheshBeshLedger/Sources/SheshBeshLedger",
        swiftSettings: [
            .swiftLanguageMode(.v6),
            .treatAllWarnings(as: .error),
        ]
    ),
    .testTarget(
        name: "SheshBeshGameTests",
        dependencies: ["SheshBeshGame"],
        path: "Packages/SheshBeshGame/Tests/SheshBeshGameTests",
        swiftSettings: [
            .swiftLanguageMode(.v6),
            .treatAllWarnings(as: .error),
        ]
    ),
    .testTarget(
        name: "SheshBeshLedgerTests",
        dependencies: ["SheshBeshLedger", "SheshBeshGame"],
        path: "Packages/SheshBeshLedger/Tests/SheshBeshLedgerTests",
        swiftSettings: [
            .swiftLanguageMode(.v6),
            .treatAllWarnings(as: .error),
        ]
    ),
]

#if !os(Linux)
products.append(
    .library(
        name: "SheshBeshApp",
        targets: ["SheshBeshApp"]
    )
)

targets.append(
    .target(
        name: "SheshBeshApp",
        dependencies: ["SheshBeshGame", "SheshBeshLedger"],
        path: "SheshBesh/Shared",
        swiftSettings: [
            .swiftLanguageMode(.v6),
            .treatAllWarnings(as: .error),
        ]
    )
)

targets.append(
    .testTarget(
        name: "SheshBeshAppTests",
        dependencies: ["SheshBeshApp", "SheshBeshGame", "SheshBeshLedger"],
        path: "SheshBeshTests",
        swiftSettings: [
            .swiftLanguageMode(.v6),
            .treatAllWarnings(as: .error),
        ]
    )
)
#endif

let package = Package(
    name: "SheshBesh",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: products,
    targets: targets
)
