// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "HomeAutomationKit",
    platforms: [.macOS(.v15), .iOS(.v18), .macCatalyst(.v18)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "HomeAutomationKit",
            targets: ["Adapter", "HAModels", "HAImplementations", "HAApplicationLayer", "Shared"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.117.0"),
        // 🗄 An ORM for SQL and NoSQL databases.
        .package(url: "https://github.com/vapor/fluent.git", from: "4.13.0"),
        // 🐬 Fluent driver for MySQL.
        .package(url: "https://github.com/vapor/fluent-mysql-driver.git", from: "4.8.0"),
        // open api generator
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.10.3"),
        .package(url: "https://github.com/swift-server/swift-openapi-vapor", from: "1.0.1"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.10.0"),
        // other stuff
        .package(url: "https://github.com/vapor/apns.git", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.4"),
        .package(url: "https://github.com/juliankahnert/TibberSwift.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-distributed-actors", revision: "0041f6a"),
//        .package(url: "https://github.com/swift-server-community/APNSwift", branch: "main")
        .package(url: "https://github.com/swift-server-community/APNSwift", from: "6.1.0")
    ],
    targets: [
        .executableTarget(
            name: "Server",
            dependencies: [
                "Adapter",
                "HAModels",
                "HAApplicationLayer",
                "HAImplementations",
                "Shared",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentMySQLDriver", package: "fluent-mysql-driver"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "OpenAPIVapor", package: "swift-openapi-vapor"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "VaporAPNS", package: "apns"),
                .product(name: "APNSCore", package: "APNSwift"),
                .product(name: "APNSURLSession", package: "APNSwift")
            ],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        ),
        .target(
            name: "Shared",
            dependencies: []
        ),
        .target(
            name: "Adapter",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                "HAModels",
                "Shared",
                .product(name: "DistributedCluster", package: "swift-distributed-actors")
            ]
        ),
        .target(
            name: "HAModels",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                "Shared"
            ]
        ),
        .target(
            name: "HAImplementations",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                "HAModels",
                "TibberSwift"
            ]
        ),
        .target(
            name: "HAApplicationLayer",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                "HAModels",
                "Shared"
            ]
        ),
        .testTarget(
            name: "SharedTests",
            dependencies: [
                "Shared"
            ]
        ),
        .testTarget(
            name: "HomeAutomationKitTests",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                "Adapter",
                "HAModels",
                "HAImplementations",
                "HAApplicationLayer"
            ]
        )
    ]
)
