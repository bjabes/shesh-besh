// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "SheshBeshLedger",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "SheshBeshLedger",
            targets: ["SheshBeshLedger"]
        ),
    ],
    dependencies: [
        .package(path: "../SheshBeshGame"),
    ],
    targets: [
        .target(
            name: "SheshBeshLedger",
            dependencies: [
                .product(name: "SheshBeshGame", package: "SheshBeshGame"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "SheshBeshLedgerTests",
            dependencies: [
                "SheshBeshLedger",
                .product(name: "SheshBeshGame", package: "SheshBeshGame"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
