// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "dyld-shared-cache-extractor",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .watchOS(.v6),
        .tvOS(.v13),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "https://github.com/p-x9/MachOKit.git", from: "0.42.0"),
        .package(url: "https://github.com/p-x9/swift-fileio.git", from: "0.12.0")
    ],
    targets: [
        .executableTarget(
            name: "dyld-shared-cache-extractor",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "MachOKit", package: "MachOKit"),
                .product(name: "FileIO", package: "swift-fileio")
            ]
        ),
    ]
)
