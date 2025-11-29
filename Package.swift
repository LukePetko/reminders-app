// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "RemindersServer",
    platforms: [
       .macOS(.v11)
    ],
    dependencies: [
        // 💧 A server-side Swift web framework.
        .package(url: "https://github.com/vapor/vapor.git", from: "4.89.0"),
        // 🔵 Non-blocking, event-driven networking for Swift. Used for custom executors
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.62.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.0.0"),
        .package(url: "https://github.com/vapor/fluent-mysql-driver.git", from: "4.0.0"),
        .package(url: "https://github.com/MihaelIsaev/VaporCron.git", from: "2.6.0"),
        // Pin swift-collections to a version compatible with Swift 5.7
        .package(url: "https://github.com/apple/swift-collections.git", exact: "1.0.6")
    ],
    targets: [
        .executableTarget(
            name: "RemindersServer",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentMySQLDriver", package: "fluent-mysql-driver"),
                "VaporCron"
            ]
        ),
        .testTarget(
            name: "RemindersServerTests",
            dependencies: [
                .target(name: "RemindersServer"),
                .product(name: "XCTVapor", package: "vapor")
            ]
        )
    ]
)
