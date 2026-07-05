// swift-tools-version: 5.9
// =============================================================================
// RunAnywhereAI - iOS Example App
// =============================================================================
//
// This example app demonstrates how to use the RunAnywhere SDK.
//
// SETUP (first time):
//   ./scripts/build/ios-xcframework.sh
//
// Then open this project in Xcode and build.
//
// =============================================================================

import PackageDescription

let package = Package(
    name: "RunAnywhereAI",
    defaultLocalization: "en",
    platforms: [
        // Must be ≥ the root Package.swift platform floor so the local-path
        // dependency on RunAnywhere / RunAnywhereONNX / RunAnywhereLlamaCPP
        // resolves cleanly (root manifest was bumped to iOS 17.5 / macOS
        // 14.5 in T5.4).
        .iOS("17.5"),
        .macOS("14.5")
    ],
    products: [
        .library(
            name: "RunAnywhereAI",
            targets: ["RunAnywhereAI"]
        )
    ],
    dependencies: [
        // ===================================
        // RunAnywhere SDK (local path to repo root)
        // ===================================
        // Points to the root Package.swift which contains:
        //   - RunAnywhere (core)
        //   - RunAnywhereONNX (STT/TTS/VAD)
        //   - RunAnywhereLlamaCPP (LLM)
        .package(path: "../../.."),
    ],
    targets: [
        .target(
            name: "RunAnywhereAI",
            dependencies: [
                // Core SDK (always needed)
                .product(name: "RunAnywhere", package: "runanywhere-sdks"),

                // Optional modules - pick what you need:
                .product(name: "RunAnywhereONNX", package: "runanywhere-sdks"),         // STT/TTS/VAD (CPU via ONNX/Sherpa)
                .product(name: "RunAnywhereLlamaCPP", package: "runanywhere-sdks"),     // LLM
            ],
            path: "RunAnywhereAI",
            exclude: [
                "Info.plist",
                "Assets.xcassets",
                "Preview Content",
                "RunAnywhereAI.entitlements"
            ]
        ),
        .testTarget(
            name: "RunAnywhereAITests",
            dependencies: ["RunAnywhereAI"],
            path: "RunAnywhereAIUITests"
        )
    ]
)
