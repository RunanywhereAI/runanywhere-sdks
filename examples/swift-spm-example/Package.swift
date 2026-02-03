// swift-tools-version: 5.9
import PackageDescription

// =============================================================================
// Swift SPM Example App
// =============================================================================
//
// Example app that consumes the RunAnywhere SDK via Swift Package Manager
// using **versioned** dependency (exact version). Use this to verify SDK
// consumption from a release tag.
//
// Usage:
//   cd examples/swift-spm-example
//   swift package update
//   swift build
//   # Or open in Xcode and run on iOS Simulator:
//   open Package.swift
//
// =============================================================================

let package = Package(
    name: "SwiftSPMExample",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    dependencies: [
        .package(url: "https://github.com/RunanywhereAI/runanywhere-sdks.git", exact: "0.17.5"),
    ],
    targets: [
        .executableTarget(
            name: "SwiftSPMExample",
            dependencies: [
                .product(name: "RunAnywhere", package: "runanywhere-sdks"),
                .product(name: "RunAnywhereLlamaCPP", package: "runanywhere-sdks"),
                .product(name: "RunAnywhereONNX", package: "runanywhere-sdks"),
            ],
            path: "Sources/SwiftSPMExample"
        ),
    ]
)
