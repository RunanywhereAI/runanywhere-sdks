// swift-tools-version: 5.9
// Modern SPM setup for RunAnywhere iOS Example App
// This Package.swift provides a clean dependency manifest for the iOS app.
// The app still uses the Xcode project for building, but dependencies are managed here.

import PackageDescription

let package = Package(
    name: "RunAnywhereAI",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),      // Minimum iOS 17 (required by FluidAudio)
        .macOS(.v14)     // Minimum macOS 14 (required by FluidAudio)
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
        // SINGLE SDK DEPENDENCY
        // ===================================
        // All modules are now consolidated in the main RunAnywhere SDK.
        // Users pick which products they need from this single package.
        .package(path: "../../../sdk/runanywhere-swift"),

        // ===================================
        // CRASH REPORTING - SENTRY
        // ===================================
        // Sentry for crash reporting. DSN is configured via environment
        // variable to keep secrets out of the open source repository.
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.43.0"),

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
        // Via Optional Modules:
        // - WhisperKit 0.13.1 (via RunAnywhereWhisperKit)
        // - FluidAudio (via RunAnywhereFluidAudio)
        // - ONNX Runtime binary (via RunAnywhereONNX)
        // - LlamaCPP binary (via RunAnywhereLlamaCPP)
        // ===================================
    ],
    targets: [
        .target(
            name: "RunAnywhereAI",
            dependencies: [
                // Core SDK (always needed)
                .product(name: "RunAnywhere", package: "runanywhere-swift"),

                // Optional modules - pick what you need:
                .product(name: "RunAnywhereONNX", package: "runanywhere-swift"),           // ONNX STT/TTS/VAD
                .product(name: "RunAnywhereLlamaCPP", package: "runanywhere-swift"),       // LlamaCPP LLM (runanywhere-core backend)
                .product(name: "RunAnywhereWhisperKit", package: "runanywhere-swift"),     // CoreML STT
                .product(name: "RunAnywhereFluidAudio", package: "runanywhere-swift"),     // Speaker Diarization
                .product(name: "RunAnywhereAppleAI", package: "runanywhere-swift"),        // Apple Intelligence (iOS 26+)

                // Crash Reporting
                .product(name: "Sentry", package: "sentry-cocoa"),
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
