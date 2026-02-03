// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PerXHub",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.89.0"),
        .package(path: "../PerXCore"),
    ],
    targets: [
        .executableTarget(
            name: "PerXHub",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                "PerXCore",
            ]
        ),
    ]
)
