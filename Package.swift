// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WebDock",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "WebDock",
            path: "Sources"
        )
    ]
)
