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
    dependencies: [],
    targets: [
        .target(
            name: "fast_thumbnail",
            dependencies: []
        )
    ]
)
