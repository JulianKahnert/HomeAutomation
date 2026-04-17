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
            targets: ["Adapter", "HAModels", "HAImplementations", "HAApplicationLayer", "Shared", "SharedDistributedCluster"]
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
        .package(url: "https://github.com/vapor/vapor.git", exact: "4.121.4"),
        // 🗄 An ORM for SQL and NoSQL databases.
        .package(url: "https://github.com/vapor/fluent.git", exact: "4.13.0"),
        // 🐬 Fluent driver for MySQL.
        .package(url: "https://github.com/vapor/fluent-mysql-driver.git", exact: "4.8.0"),
        // open api generator
        .package(url: "https://github.com/apple/swift-openapi-generator", exact: "1.11.1"),
        .package(url: "https://github.com/swift-server/swift-openapi-vapor", exact: "1.0.1"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.12.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", exact: "1.11.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", exact: "1.3.0"),
        // TCA and related
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture",
                 exact: "1.25.5",
                 traits: [
                    "ComposableArchitecture2Deprecations",
                    "ComposableArchitecture2DeprecationOverloads"
                 ]),
        .package(url: "https://github.com/pointfreeco/swift-sharing", exact: "2.8.0"),
        // other stuff
        .package(url: "https://github.com/vapor/apns.git", exact: "5.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", exact: "1.12.0"),
        .package(url: "https://github.com/chrisaljoudi/swift-log-oslog.git", exact: "0.2.2"),
        .package(url: "https://github.com/juliankahnert/TibberSwift.git", branch: "fix/linux-foundation-networking"),
        .package(url: "https://github.com/apple/swift-distributed-actors", revision: "0041f6a"),
        .package(url: "https://github.com/apple/swift-async-algorithms", exact: "1.1.3"),
        .package(url: "https://github.com/swift-server-community/APNSwift", exact: "6.5.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.7.1")
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
                "SharedDistributedCluster",
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
            name: "SharedDistributedCluster",
            dependencies: [
                "Shared",
                .product(name: "DistributedCluster", package: "swift-distributed-actors"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            ]
        ),
        .target(
            name: "Adapter",
            dependencies: [
                "HAModels",
                "Shared",
                "SharedDistributedCluster",
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
        )
    ]
)
