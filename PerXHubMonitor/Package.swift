// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PerXHubMonitor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PerXHubMonitor", targets: ["PerXHubMonitor"]),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "PerXHubMonitor",
            dependencies: [],
            path: "Sources"
        ),
    ]
)
