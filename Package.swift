// swift-tools-version: 5.9
//
// =============================================================================
// RunAnywhere SDK - Swift Package Manager Distribution (post-v2 cutover)
// =============================================================================
//
// Single Package.swift for both local development and SPM consumption.
//
// FOR EXTERNAL USERS (consuming via GitHub):
//   .package(url: "https://github.com/RunanywhereAI/runanywhere-sdks", from: "2.0.0")
//
// FOR LOCAL DEVELOPMENT:
//   1. Build the C++ core XCFramework once:
//        scripts/build-core-xcframework.sh --platforms=macos
//      (or `--platforms=ios-device,ios-sim,macos` for full iOS slices)
//   2. Open the example app (examples/ios/RunAnywhereAI) in Xcode.
//   3. The app references this package via relative path.
//
// Engine modules:
//   * RunAnywhere          — core (sessions, catalog, voice agent, RAG, etc.)
//   * RunAnywhereLlamaCPP  — LlamaCPP.register() entry point (LLM)
//   * RunAnywhereONNX      — ONNX.register() entry point (LLM/STT/TTS/VAD/embed)
//   * RunAnywhereWhisperKit — WhisperKitSTT.register() entry point (Apple)
//   * RunAnywhereMetalRT   — MetalRT.register() entry point (Apple GPU runtime)
//   * RunAnywhereGenie     — Genie.register() entry point (Android/Snapdragon)
//
// All five backend products vend the same `Backends.swift` file from the new
// `sdk/swift/Sources/RunAnywhere/Adapter`, exposing the legacy-shaped
// `LlamaCPP.register(priority:)` / `ONNX.register(priority:)` / ... entry
// points. They re-export the core `RunAnywhere` module so a sample app's
// `import LlamaCPPRuntime` / `import ONNXRuntime` pulls everything in one go.
// =============================================================================

import PackageDescription

let package = Package(
    name: "runanywhere-sdks",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "RunAnywhere",            targets: ["RunAnywhere"]),
        .library(name: "RunAnywhereLlamaCPP",    targets: ["LlamaCPPRuntime"]),
        .library(name: "RunAnywhereONNX",        targets: ["ONNXRuntime"]),
        .library(name: "RunAnywhereWhisperKit",  targets: ["WhisperKitRuntime"]),
        .library(name: "RunAnywhereMetalRT",     targets: ["MetalRTRuntime"]),
        .library(name: "RunAnywhereGenie",       targets: ["GenieRuntime"]),
    ],
    dependencies: [],
    targets: [
        // -----------------------------------------------------------------
        // Pre-built C core XCFramework — produced by
        // scripts/build-core-xcframework.sh.
        // -----------------------------------------------------------------
        .binaryTarget(
            name: "RACommonsCoreBinary",
            path: "sdk/swift/Binaries/RACommonsCore.xcframework"
        ),

        // -----------------------------------------------------------------
        // Core Swift SDK (v2). Hosts every Public-API method, session
        // class, model catalog, EventBus, RAG / VLM / Diffusion glue.
        // -----------------------------------------------------------------
        .target(
            name: "RunAnywhere",
            dependencies: ["RACommonsCoreBinary"],
            path: "sdk/swift/Sources/RunAnywhere",
            exclude: ["Generated"],
            swiftSettings: [
                .define("RA_USE_NEW_CORE"),
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
            ]
        ),

        // -----------------------------------------------------------------
        // Backend register-entry-point shims. Each is a no-op Swift module
        // that re-exports the core RunAnywhere target so that the iOS
        // sample app's `import LlamaCPPRuntime` style imports keep working.
        // The underlying engine plugins are statically compiled into
        // RACommonsCore.xcframework and self-register at dynamic-init time.
        // -----------------------------------------------------------------
        .target(
            name: "LlamaCPPRuntime",
            dependencies: ["RunAnywhere"],
            path: "sdk/swift/Sources/Backends/LlamaCPPRuntime"
        ),
        .target(
            name: "ONNXRuntime",
            dependencies: ["RunAnywhere"],
            path: "sdk/swift/Sources/Backends/ONNXRuntime"
        ),
        .target(
            name: "WhisperKitRuntime",
            dependencies: ["RunAnywhere"],
            path: "sdk/swift/Sources/Backends/WhisperKitRuntime"
        ),
        .target(
            name: "MetalRTRuntime",
            dependencies: ["RunAnywhere"],
            path: "sdk/swift/Sources/Backends/MetalRTRuntime"
        ),
        .target(
            name: "GenieRuntime",
            dependencies: ["RunAnywhere"],
            path: "sdk/swift/Sources/Backends/GenieRuntime"
        ),

        // -----------------------------------------------------------------
        // Tests
        // -----------------------------------------------------------------
        .testTarget(
            name: "RunAnywhereTests",
            dependencies: ["RunAnywhere"],
            path: "sdk/swift/Tests/RunAnywhereTests"
        ),
    ],
    cxxLanguageStandard: .cxx20
)
