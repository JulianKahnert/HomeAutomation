// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "HomeAutomationServer",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        // 💧 A server-side Swift web framework.
        .package(url: "https://github.com/vapor/vapor.git", from: "4.113.2"),
        // 🗄 An ORM for SQL and NoSQL databases.
        .package(url: "https://github.com/vapor/fluent.git", from: "4.12.0"),
        // 🐬 Fluent driver for MySQL.
        .package(url: "https://github.com/vapor/fluent-mysql-driver.git", from: "4.7.0"),
        // 🔵 Non-blocking, event-driven networking for Swift. Used for custom executors
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
        // other stuff
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.2"),
        .package(path: "../HomeAutomationKit")
    ],
    targets: [
        .executableTarget(
            name: "Server",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentMySQLDriver", package: "fluent-mysql-driver"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "HomeAutomationKit", package: "HomeAutomationKit")
            ]
        )
    ]
)
