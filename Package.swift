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
        ),
        .library(
            name: "ControllerKit",
            targets: ["Controller"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.119.2"),
        // 🗄 An ORM for SQL and NoSQL databases.
        .package(url: "https://github.com/vapor/fluent.git", from: "4.13.0"),
        // 🐬 Fluent driver for MySQL.
        .package(url: "https://github.com/vapor/fluent-mysql-driver.git", from: "4.8.0"),
        // open api generator
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.10.3"),
        .package(url: "https://github.com/swift-server/swift-openapi-vapor", from: "1.0.1"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.10.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.8.3"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.2.0"),
        // TCA and related
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.23.1"),
        .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.7.4"),
        // other stuff
        .package(url: "https://github.com/vapor/apns.git", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.4"),
        .package(url: "https://github.com/chrisaljoudi/swift-log-oslog.git", from: "0.2.2"),
        .package(url: "https://github.com/juliankahnert/TibberSwift.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-distributed-actors", revision: "0041f6a"),
//        .package(url: "https://github.com/swift-server-community/APNSwift", branch: "main")
        .package(url: "https://github.com/swift-server-community/APNSwift", from: "6.2.0")
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
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "LoggingOSLog", package: "swift-log-oslog", condition: .when(platforms: [.macOS, .iOS, .macCatalyst, .tvOS, .watchOS, .visionOS])),
            ]
        ),
        .target(
            name: "Adapter",
            dependencies: [
                "HAModels",
                "Shared",
                .product(name: "DistributedCluster", package: "swift-distributed-actors"),
            ]
        ),
        .target(
            name: "HAModels",
            dependencies: [
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
                "HAModels",
                "Shared"
            ]
        ),
        .target(
            name: "ServerClient",
            dependencies: [
                "HAModels",
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession")
            ],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        ),
        .target(
            name: "Controller",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Sharing", package: "swift-sharing"),
                "HAModels",
                "Shared",
                "ServerClient",
            ],
            path: "Sources/Controller"
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
        ),
        .testTarget(
            name: "ControllerTests",
            dependencies: ["Controller"],
            path: "Tests/ControllerTests"
        )
    ]
)
