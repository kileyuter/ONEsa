// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "OpenClawFloatingClient",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "OpenClawFloatingClient",
            targets: ["OpenClawFloatingClient"]
        )
    ],
    targets: [
        .executableTarget(
            name: "OpenClawFloatingClient",
            path: "Sources"
        )
    ]
)
