// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ReelsCreatorCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ReelsCreatorCore",
            targets: ["ReelsCreatorCore"]
        )
    ],
    targets: [
        .target(
            name: "ReelsCreatorCore"
        ),
        .testTarget(
            name: "ReelsCreatorCoreTests",
            dependencies: ["ReelsCreatorCore"]
        )
    ]
)
