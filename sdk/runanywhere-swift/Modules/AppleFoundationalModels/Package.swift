// swift-tools-version: 5.9
import PackageDescription

// NOTE: Package name is "AppleFoundationalModels" to avoid conflict with Apple's native FoundationModels framework
let package = Package(
    name: "AppleFoundationalModels",
    platforms: [
        .iOS(.v16),      // Base requirement, but Foundation Models requires iOS 26+
        .macOS(.v13),    // Base requirement, but Foundation Models requires macOS 26+
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(
            name: "AppleFoundationalModels",
            targets: ["FoundationModelsAdapter"]
        ),
    ],
    dependencies: [
        // Reference to main SDK for protocols
        .package(path: "../../"),
    ],
    targets: [
        .target(
            name: "FoundationModelsAdapter",
            dependencies: [
                .product(name: "RunAnywhere", package: "runanywhere-swift")
            ],
            path: "Sources/FoundationModels"
        ),
        .testTarget(
            name: "FoundationModelsTests",
            dependencies: ["FoundationModelsAdapter"],
            path: "Tests/FoundationModelsTests"
        ),
    ]
)
