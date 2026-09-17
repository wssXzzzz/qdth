// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "InkflowCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "InkflowCore", targets: ["InkflowCore"])],
    targets: [
        .target(name: "InkflowCore", path: "Inkflow/Core"),
        .testTarget(name: "InkflowCoreTests", dependencies: ["InkflowCore"], path: "Tests")
    ]
)
