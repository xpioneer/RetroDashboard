// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RetroDashboard",
    platforms: [
        .macOS(.v14) // 声明支持 macOS 14 及以上
    ],
    products: [
        .executable(
            name: "RetroDashboard",
            targets: ["RetroDashboard"]
        )
    ],
    targets: [
        .executableTarget(
            name: "RetroDashboard",
        )
    ]
)
