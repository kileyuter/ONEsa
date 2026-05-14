// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ONEsa",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "ONEsa",
            targets: ["ONEsa"]
        )
    ],
    targets: [
        .executableTarget(
            name: "ONEsa",
            path: "Sources"
        )
    ]
)
