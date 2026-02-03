// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PerXCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "PerXCore", targets: ["PerXCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.14.0"),
    ],
    targets: [
        .target(
            name: "PerXCore",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
            ],
            path: "Sources/PerXCore"
        ),
    ]
)
