// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PuffyKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "PuffyKit", targets: ["PuffyKit"]),
    ],
    targets: [
        .target(
            name: "PuffyKit",
            resources: [.process("Resources")]
        ),
        // Lightweight assertion runner so domain logic can be verified with only the
        // Command Line Tools installed (no XCTest / Swift Testing available there).
        .executableTarget(
            name: "PuffyKitSelfTest",
            dependencies: ["PuffyKit"]
        ),
        .testTarget(
            name: "PuffyKitTests",
            dependencies: ["PuffyKit"]
        ),
    ]
)
