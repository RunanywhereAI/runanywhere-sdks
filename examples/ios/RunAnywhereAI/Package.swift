// swift-tools-version: 5.9
// =============================================================================
// RunAnywhereAI - iOS Example App
// =============================================================================
//
// This example app demonstrates how to use the RunAnywhere SDK.
//
// SETUP (first time):
//   cd ../../sdk/runanywhere-swift
//   ./scripts/build-swift.sh --setup
//
// Then open this project in Xcode and build.
//
// =============================================================================

import PackageDescription

let package = Package(
    name: "RunAnywhereAI",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
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
        //   - RunAnywhereSdcpp (Diffusion / image generation)
        .package(path: "../../.."),
    ],
    targets: [
        .target(
            name: "RunAnywhereAI",
            dependencies: [
                // Core SDK (always needed)
                .product(name: "RunAnywhere", package: "runanywhere-sdks"),

                // Optional modules - pick what you need:
                .product(name: "RunAnywhereONNX", package: "runanywhere-sdks"),       // STT/TTS/VAD
                .product(name: "RunAnywhereLlamaCPP", package: "runanywhere-sdks"),   // LLM
                .product(name: "RunAnywhereSdcpp", package: "runanywhere-sdks"),      // Diffusion (sd.cpp)
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
