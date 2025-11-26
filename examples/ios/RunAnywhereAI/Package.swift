// swift-tools-version: 5.9
// Modern SPM setup for RunAnywhere iOS Example App
// This Package.swift provides a clean dependency manifest for the iOS app.
// The app still uses the Xcode project for building, but dependencies are managed here.

import PackageDescription

let package = Package(
    name: "RunAnywhereAI",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v14),      // Minimum iOS 14 for broad compatibility
        .macOS(.v12)     // Minimum macOS 12
    ],
    products: [
        // The main app library
        .library(
            name: "RunAnywhereAI",
            targets: ["RunAnywhereAI"]
        )
    ],
    dependencies: [
        // ===================================
        // LOCAL SDK DEPENDENCIES (4 total)
        // ===================================

        // Core RunAnywhere SDK
        .package(path: "../../sdk/runanywhere-swift"),

        // AI Framework Modules (local plugins)
        .package(path: "../../sdk/runanywhere-swift/Modules/LLMSwift"),
        .package(path: "../../sdk/runanywhere-swift/Modules/WhisperKitTranscription"),
        .package(path: "../../sdk/runanywhere-swift/Modules/FluidAudioDiarization"),

        // ===================================
        // TRANSITIVE DEPENDENCIES (auto-included)
        // ===================================
        // The following dependencies are automatically pulled in
        // by the RunAnywhere SDK and its modules:
        //
        // Via RunAnywhere SDK:
        // - Alamofire 5.10.2 (networking)
        // - DeviceKit 5.6.0 (device info)
        // - Files 4.3.0 (file management)
        // - ZIPFoundation 0.9.19 (archive handling)
        // - GRDB 7.6.1 (database)
        // - swift-crypto 3.14.0 (cryptography)
        // - Pulse 4.2.7 (logging)
        //
        // Via AI Modules:
        // - LLM.swift 2.0.1 (via LLMSwift module)
        // - WhisperKit 0.13.1 (via WhisperKitTranscription module)
        // - FluidAudio (via FluidAudioDiarization module)
        // ===================================
    ],
    targets: [
        .target(
            name: "RunAnywhereAI",
            dependencies: [
                .product(name: "RunAnywhere", package: "runanywhere-swift"),
                .product(name: "LLMSwift", package: "LLMSwift"),
                .product(name: "WhisperKitTranscription", package: "WhisperKitTranscription"),
                .product(name: "FluidAudioDiarization", package: "FluidAudioDiarization"),
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
