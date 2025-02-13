// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "dyld-shared-cache-extractor",
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "dyld-shared-cache-extractor",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)
