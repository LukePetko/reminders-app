// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RemindersServer",
    platforms: [
       .macOS(.v11)
    ],
    dependencies: [
        // A server-side Swift web framework.
        .package(url: "https://github.com/vapor/vapor.git", exact: "4.89.3"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.0.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.0.0"),
        .package(url: "https://github.com/MihaelIsaev/VaporCron.git", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "RemindersServer",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
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
