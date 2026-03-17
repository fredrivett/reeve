// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Reeve",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Reeve",
            path: "Sources/Reeve"
        )
    ]
)
