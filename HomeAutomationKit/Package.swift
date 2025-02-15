// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

#warning("TODO: add tibber again")
let package = Package(
    name: "HomeAutomationKit",
    platforms: [.macOS(.v15), .iOS(.v18), .macCatalyst(.v18)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "HomeAutomationKit",
            targets: ["HAModels", "HAImplementations", "HAApplicationLayer"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
//        .package(url: "https://github.com/juliankahnert/TibberSwift.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-distributed-actors", branch: "main")
    ],
    targets: [
        .target(
            name: "HAModels",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
            ]
        ),
        .target(
            name: "HAImplementations",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                "HAModels",
//                "TibberSwift",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "DistributedCluster", package: "swift-distributed-actors")
            ]
        ),
        .target(
            name: "HAApplicationLayer",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                "HAModels",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
            ]
        ),
        .testTarget(
            name: "HomeAutomationKitTests",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                "HAModels",
                "HAImplementations",
                "HAApplicationLayer",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
            ]
        )
    ]
)
