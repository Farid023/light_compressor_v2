// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "light_compressor_v2",
    platforms: [
        .macOS("10.15"),
    ],
    products: [
        .library(
            name: "light-compressor-v2",
            targets: ["light_compressor_v2"]
        )
    ],
    dependencies: [
        .package(
            name: "FlutterFramework",
            path: "../FlutterFramework"
        )
    ],
    targets: [
        .target(
            name: "light_compressor_v2",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            path: "Sources/light_compressor_v2"
        )
    ]
)