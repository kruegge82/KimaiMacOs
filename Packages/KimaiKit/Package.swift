// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KimaiKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KimaiKit", targets: ["KimaiKit"])
    ],
    targets: [
        .target(name: "KimaiKit"),
        .testTarget(name: "KimaiKitTests", dependencies: ["KimaiKit"])
    ]
)
