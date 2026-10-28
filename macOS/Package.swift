// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SchwungPocketMac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SchwungPocketMac", targets: ["SchwungPocketMac"])
    ],
    targets: [
        .executableTarget(
            name: "SchwungPocketMac",
            path: "Sources/SchwungPocketMac"
        )
    ]
)
