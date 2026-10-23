// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TRTCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TRTCore", targets: ["TRTCore"])
    ],
    targets: [
        .target(name: "TRTCore", resources: [.copy("Resources/compound-catalog.json")]),
        .testTarget(name: "TRTCoreTests", dependencies: ["TRTCore"])
    ]
)
