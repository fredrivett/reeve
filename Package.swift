// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "reeve",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "0.12.0")
    ],
    targets: [
        .target(
            name: "ReeveLib",
            path: "Sources/Reeve"
        ),
        .executableTarget(
            name: "reeve",
            dependencies: ["ReeveLib"],
            path: "Sources/ReeveApp"
        ),
        .testTarget(
            name: "reeveTests",
            dependencies: [
                "ReeveLib",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/reeveTests"
        )
    ]
)
