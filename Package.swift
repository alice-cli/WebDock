// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WebDock",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "WebDock",
            path: "Sources",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
