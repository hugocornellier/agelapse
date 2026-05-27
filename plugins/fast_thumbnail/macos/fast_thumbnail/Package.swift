// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "fast_thumbnail",
    platforms: [
        .macOS("10.14")
    ],
    products: [
        .library(name: "fast_thumbnail", targets: ["fast_thumbnail"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "fast_thumbnail",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
