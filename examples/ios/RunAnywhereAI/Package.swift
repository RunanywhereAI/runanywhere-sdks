// swift-tools-version: 6.2
// =============================================================================
// RunAnywhereAI - iOS Example App
// =============================================================================
//
// This example app demonstrates how to use the RunAnywhere SDK.
//
// The SDK is consumed entirely from the published GitHub release — no local
// checkout of the monorepo and no pre-built XCFrameworks are required.
// SwiftPM downloads the checksum-verified binary artifacts on resolve.
//
// SETUP (first time):
//   swift package resolve      # or just open the project in Xcode
//
// =============================================================================

import PackageDescription

let package = Package(
    name: "RunAnywhereAI",
    defaultLocalization: "en",
    platforms: [
        // Must be ≥ the RunAnywhere SDK platform floor so the remote
        // dependency on RunAnywhere / RunAnywhereONNX / RunAnywhereLlamaCPP
        // resolves cleanly (the SDK floor is iOS 17.5 / macOS 14.5).
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
        // RunAnywhere SDK (published GitHub release)
        // ===================================
        // The `runanywhere-sdks` package publishes:
        //   - RunAnywhere (core)
        //   - RunAnywhereONNX (STT/TTS/VAD)
        //   - RunAnywhereLlamaCPP (LLM)
        //   - RunAnywhereMLX (Apple MLX)
        //   - RunAnywhereNeuRT (Apple Neural Engine)
        //
        // WHY `revision:` AND NOT `from: "0.20.15"`
        // -----------------------------------------
        // The v0.20.15 SDK manifest pins mlx-swift and mlx-audio-swift by git
        // revision (upstream has no Swift 6.2-compatible tag yet). SwiftPM
        // refuses to resolve *any* version-based requirement against a package
        // whose manifest carries revision-pinned dependencies:
        //
        //   error: package 'runanywhere-sdks' is required using a
        //          stable-version but 'runanywhere-sdks' depends on an
        //          unstable-version package 'mlx-swift'
        //
        // Mirroring those revisions in this root manifest does NOT lift the
        // restriction — SwiftPM raises the incompatibility before it consults
        // root overrides. Pinning the SDK itself by revision is therefore the
        // only remote-only option. The revision below is the exact commit that
        // tag v0.20.15 points at, so this is byte-identical to the release and
        // still downloads the checksum-verified XCFramework archives from
        // https://github.com/RunanywhereAI/runanywhere-sdks/releases/tag/v0.20.15
        //
        // Switch back to `from: "<version>"` once the SDK ships a release whose
        // manifest has no revision-pinned dependencies.
        .package(
            url: "https://github.com/RunanywhereAI/runanywhere-sdks.git",
            revision: "fe6adea31dcf91fb2315a0406edcd2dca4d71370" // tag v0.20.15
        ),
    ],
    targets: [
        .target(
            name: "RunAnywhereAI",
            dependencies: [
                // Core SDK (always needed)
                .product(name: "RunAnywhere", package: "runanywhere-sdks"),

                // Optional modules - pick what you need:
                // All native backend XCFrameworks now carry macOS arm64 slices,
                // so the shared example exposes the same portable providers on
                // iOS and macOS instead of compiling them out on Mac.
                .product(name: "RunAnywhereONNX", package: "runanywhere-sdks"),
                .product(name: "RunAnywhereLlamaCPP", package: "runanywhere-sdks"),
                .product(name: "RunAnywhereMLX", package: "runanywhere-sdks"),
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
