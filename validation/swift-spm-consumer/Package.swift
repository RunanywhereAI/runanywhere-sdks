// swift-tools-version: 5.9
import PackageDescription

// =============================================================================
// Minimal Swift app to validate RunAnywhere SDK consumption via SPM.
// Separate from the main repo code — used to test Phase 2 GitHub Release.
// =============================================================================
// Usage: cd validation/swift-spm-consumer && swift build
// =============================================================================

let package = Package(
    name: "SwiftSPMConsumer",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    dependencies: [
        .package(url: "https://github.com/RunanywhereAI/runanywhere-sdks", from: "0.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "SwiftSPMConsumer",
            dependencies: [
                .product(name: "RunAnywhere", package: "runanywhere-sdks"),
                .product(name: "RunAnywhereLlamaCPP", package: "runanywhere-sdks"),
                .product(name: "RunAnywhereONNX", package: "runanywhere-sdks"),
            ],
            path: "Sources/SwiftSPMConsumer"
        ),
    ]
)
