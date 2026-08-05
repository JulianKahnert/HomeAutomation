// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "HomeAutomationKit",
    platforms: [.macOS(.v15), .iOS(.v18), .macCatalyst(.v18)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "HomeAutomationKit",
            targets: ["Adapter", "HAModels", "HAImplementations", "HAApplicationLayer", "Shared", "StarActorSystem"]
        ),
        .library(
            name: "HAShared",
            targets: ["HAModels", "HAImplementations"]
        ),
        .library(
            name: "ControllerKit",
            targets: ["Controller"]
        ),
        .executable(
            name: "home",
            targets: ["HomeCLI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", exact: "4.122.0"),
        // 🗄 An ORM for SQL and NoSQL databases.
        .package(url: "https://github.com/vapor/fluent.git", exact: "4.13.0"),
        // 🐬 Fluent driver for MySQL.
        .package(url: "https://github.com/vapor/fluent-mysql-driver.git", exact: "4.8.0"),
        // open api generator
        .package(url: "https://github.com/apple/swift-openapi-generator", exact: "1.13.0"),
        .package(url: "https://github.com/swift-server/swift-openapi-vapor", exact: "1.1.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.14.1"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", exact: "1.12.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", exact: "1.3.1"),
        // TCA and related
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture",
                 exact: "1.26.1",
                 traits: [
                    "ComposableArchitecture2Deprecations",
                    "ComposableArchitecture2DeprecationOverloads"
                 ]),
        .package(url: "https://github.com/pointfreeco/swift-sharing", exact: "2.9.1"),
        // other stuff
        .package(url: "https://github.com/vapor/apns.git", exact: "5.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", exact: "1.15.0"),
        .package(url: "https://github.com/chrisaljoudi/swift-log-oslog.git", exact: "0.2.2"),
        .package(url: "https://github.com/juliankahnert/TibberSwift.git", branch: "fix/linux-foundation-networking"),
        // Capped at 6.x: vapor/apns 5.0.0 requires apnswift 6.1.0..<7.0.0.
        .package(url: "https://github.com/swift-server-community/APNSwift", exact: "6.6.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.8.2")
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
                "StarActorSystem",
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
            name: "StarActorSystem",
            dependencies: [
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .target(
            name: "Adapter",
            dependencies: [
                "HAModels",
                "Shared",
                "StarActorSystem",
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
        .executableTarget(
            name: "HomeCLI",
            dependencies: [
                "Shared",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "SharedTests",
            dependencies: [
                "Shared",
                "HAModels"
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
        ),
        .testTarget(
            name: "ServerTests",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "XCTVapor", package: "vapor"),
                "Server",
                "HAModels"
            ],
            path: "Tests/ServerTests"
        ),
        .testTarget(
            name: "StarActorSystemTests",
            dependencies: [
                "StarActorSystem",
                // needed for the golden thunk-ID test of the receiver actors in module Adapter
                "Adapter",
                .product(name: "Logging", package: "swift-log")
            ]
        ),
    ]
)
