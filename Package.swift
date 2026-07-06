// swift-tools-version: 5.9
// Attempted bump to 6.0 was rolled back. Bumping the manifest tools
// version forces Swift 6 language mode on all targets, which turns several
// pre-existing patterns in the SDK (mutable static registration flags,
// closure-captured locals in AVAudioConverter / URLSession callbacks,
// etc.) into hard build errors. Migrating those requires non-trivial
// source changes (sendable globals, actor isolation) that are out of
// scope for this dep-bump pass — see AGENTS.md "no source edits" rule.
// Re-attempt once the Swift 6 strict-concurrency migration lands.
import PackageDescription
import Foundation

// =============================================================================
// RunAnywhere SDK - Swift Package Manager Distribution
// =============================================================================
//
// This is the SINGLE Package.swift for both local development and SPM consumption.
//
// FOR EXTERNAL USERS (consuming via GitHub):
//   .package(url: "https://github.com/RunanywhereAI/runanywhere-sdks", from: "0.19.13")
//   Keep `useLocalNatives = false` so SPM downloads signed XCFrameworks from
//   the GitHub release.
//
// FOR LOCAL DEVELOPMENT:
//   1. Build native XCFrameworks from the repo root:
//          ./sdk/runanywhere-swift/scripts/build-core-xcframework.sh
//      This writes RACommons.xcframework, RABackendLLAMACPP.xcframework, and
//      RABackendONNX.xcframework into sdk/runanywhere-swift/Binaries/.
//   2. Ensure `useLocalNatives = true` below so the package resolves to
//      those on-disk XCFrameworks instead of the remote release URLs.
//   3. Open the example app (examples/ios/RunAnywhereAI) in Xcode — it
//      depends on this package via a relative path.
//
// =============================================================================

// =============================================================================
// BINARY TARGET CONFIGURATION
// =============================================================================
//
// useLocalNatives = true  → Use local XCFrameworks from sdk/runanywhere-swift/Binaries/
//                           For local development. Generate them with
//                           `./sdk/runanywhere-swift/scripts/build-core-xcframework.sh` at the repo
//                           root before building the SDK.
//
// useLocalNatives = false → Download XCFrameworks from GitHub releases (PRODUCTION).
//                           For external users via SPM. No local build needed.
//
// Toggling: this is a hand-edited flag. Release tooling sets it to `false`
// before tagging a release; local devs flip it back to `true` and run
// `./sdk/runanywhere-swift/scripts/build-core-xcframework.sh` to regenerate the on-disk binaries.
//
// Historical name: this used to be called `useLocalBinaries`. The concept is
// the same — it's been renamed to `useLocalNatives` for consistency with the
// equivalent toggle in the other client SDKs (Kotlin, Flutter, React Native).
// =============================================================================
let useLocalNatives = true // Toggle: false for release (default committed to main); local devs flip to true and run ./sdk/runanywhere-swift/scripts/build-core-xcframework.sh

// Version for remote XCFrameworks (used when useLocalNatives = false)
// Updated automatically by CI/CD during releases.
let sdkVersion = "0.19.13"

// mlx-audio-swift currently requires a Swift 6.2+ toolchain and has not cut a
// tag compatible with mlx-swift-lm 3.x. Pin current main so MLX STT/TTS are
// first-class in the Apple MLX runtime while upstream release tags catch up.
let mlxAudioPackageDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", revision: "580e952adda0cd6bdc5c04f402822adbb61525c8"),
]
let mlxAudioRuntimeDependencies: [Target.Dependency] = [
    .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
    .product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
]

let package = Package(
    name: "runanywhere-sdks",
    platforms: [
        // Floor bumped from iOS 17.0 / macOS 14.0 → iOS 17.5 / macOS 14.5
        // (latest minor of the same LTS line, matches Xcode 15.4 baseline).
        .iOS("17.5"),
        .macOS("14.5"),
    ],
    products: [
        // =================================================================
        // Core SDK - always needed
        // =================================================================
        .library(
            name: "RunAnywhere",
            targets: ["RunAnywhere"]
        ),

        // =================================================================
        // ONNX Runtime Backend - adds STT/TTS/VAD capabilities
        // =================================================================
        .library(
            name: "RunAnywhereONNX",
            targets: ["ONNXRuntime"]
        ),

        // =================================================================
        // LlamaCPP Backend - adds LLM text generation
        // =================================================================
        .library(
            name: "RunAnywhereLlamaCPP",
            targets: ["LlamaCPPRuntime"]
        ),

        // =================================================================
        // MLX Backend - adds Apple MLX LLM/VLM/embedding/STT/TTS capabilities
        // =================================================================
        .library(
            name: "RunAnywhereMLX",
            targets: ["MLXRuntime"]
        ),

    ],
    dependencies: [
        // SPM deps use `.upToNextMinor` (not open-ended `from:`) so a
        // silent upstream major bump can't land in `Package.resolved` without
        // a Package.swift edit. Version floors are mirrored in
        // sdk/runanywhere-swift/Sources/RunAnywhere/Generated/Versions.swift
        // (RAVersions) — keep both in sync via scripts/release/sync-versions.sh.
        // Floor bumped 3.0.0 → 3.15.1 (latest stable 3.x at bump time).
        .package(url: "https://github.com/apple/swift-crypto.git", .upToNextMinor(from: "3.15.1")),
        .package(url: "https://github.com/JohnSundell/Files.git", .upToNextMinor(from: "4.3.0")),
        // Floor bumped 5.6.0 → 5.8.0 (latest stable at bump time).
        .package(url: "https://github.com/devicekit/DeviceKit.git", .upToNextMinor(from: "5.8.0")),
        // Floor bumped 8.40.0 → 8.58.2 (latest stable 8.x at bump time).
        .package(url: "https://github.com/getsentry/sentry-cocoa", .upToNextMinor(from: "8.58.2")),
        // swift-protobuf for idl/*.proto generated types consumed by
        // sdk/runanywhere-swift/Sources/RunAnywhere/Generated/*.pb.swift.
        // Floor bumped 1.27.0 → 1.38.0 (latest stable). The earlier
        // .upToNextMajor exception (needed because generated code uses
        // SwiftProtobuf._NameMap(bytecode:) from 1.28.0+) is now resolved by
        // floor >= 1.38.0, so we re-tighten to .upToNextMinor in line with
        // the policy applied to the other deps.
        .package(url: "https://github.com/apple/swift-protobuf.git", .upToNextMinor(from: "1.38.0")),
        .package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMinor(from: "0.31.6")),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMinor(from: "3.31.4")),
        // mlx-audio-swift requires Swift 6.2+ and enables MLX STT/TTS.
        .package(url: "https://github.com/huggingface/swift-transformers", .upToNextMinor(from: "1.3.0")),
        //
        // grpc-swift intentionally NOT wired. The *.grpc.swift files under
        // Sources/RunAnywhere/Generated/ are excluded from the RunAnywhere
        // target below — gRPC client stubs were emitted by the codegen but
        // are not used at runtime. Frontends consume proto events via the
        // hand-written VoiceAgentStreamAdapter that wraps the in-process C
        // callback (see sdk/runanywhere-swift/Sources/RunAnywhere/Adapters/
        // VoiceAgentStreamAdapter.swift).
        //
    ] + mlxAudioPackageDependencies,
    targets: [
        // =================================================================
        // C Bridge Module - Core Commons
        // =================================================================
        .target(
            name: "CRACommons",
            dependencies: ["RACommonsBinary"],
            path: "sdk/runanywhere-swift/Sources/RunAnywhere/CRACommons",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("../../../../runanywhere-commons/include"),
            ]
        ),

        // =================================================================
        // C Bridge Module - LlamaCPP Backend Headers
        // =================================================================
        .target(
            name: "LlamaCPPBackend",
            dependencies: [
                "CRACommons",
                "RABackendLlamaCPPBinary",
            ],
            path: "sdk/runanywhere-swift/Sources/LlamaCPPRuntime/include",
            publicHeadersPath: "."
        ),

        // =================================================================
        // C Bridge Module - ONNX Backend Headers
        //
        // ONNX Runtime is now statically linked into RABackendONNX.a — no
        // separate ONNXRuntime{iOS,macOS}Binary targets needed. They were
        // previously distributed as separate xcframeworks but are bundled
        // since v0.19.0.
        //
        // The Sherpa-ONNX backend ships as a peer xcframework. It owns the
        // STT (Whisper / Zipformer / Paraformer), TTS (Piper / VITS) and
        // VAD (Silero) primitives under `framework == .sherpa`. ONNX owns
        // embeddings and generic ONNX Runtime services under
        // `framework == .onnx`. Both must be linked so the unified plugin
        // router can resolve either framework at load time.
        // =================================================================
        .target(
            name: "ONNXBackend",
            dependencies: [
                "CRACommons",
                "RABackendONNXBinary",
                "RABackendSherpaBinary",
            ],
            path: "sdk/runanywhere-swift/Sources/ONNXRuntime/include",
            publicHeadersPath: "."
        ),

        // =================================================================
        // C Bridge Module - MLX Backend Headers
        // =================================================================
        .target(
            name: "MLXBackend",
            dependencies: [
                "CRACommons",
                "RABackendMLXBinary",
            ],
            path: "sdk/runanywhere-swift/Sources/MLXRuntime/include",
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("../../../../runanywhere-commons/include"),
            ]
        ),

        // =================================================================
        // Core SDK
        // =================================================================
        .target(
            name: "RunAnywhere",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Files", package: "Files"),
                .product(name: "DeviceKit", package: "DeviceKit"),
                .product(name: "Sentry", package: "sentry-cocoa"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                "CRACommons",
                "RACommonsBinary",
            ],
            path: "sdk/runanywhere-swift/Sources/RunAnywhere",
            exclude: [
                "CRACommons",
                "Generated/router.pb.swift",
                "Generated/diffusion_options.pb.swift",
                // The previously-excluded
                // `Generated/{voice_agent_service,llm_service,download_service}.grpc.swift`
                // files are no longer emitted by `idl/codegen/generate_swift.sh` and
                // have been removed from the repo. Swift consumes the same services
                // through the hand-written AsyncStream adapters (VoiceAgentStreamAdapter,
                // LLMStreamAdapter) that wrap the in-process C callback, so the gRPC
                // stubs would only be dead code on macOS 14 / iOS 17.
            ],
            swiftSettings: [
                .define("SWIFT_PACKAGE")
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedLibrary("z"),
                .linkedLibrary("bz2"),
                .linkedFramework("CFNetwork"),
                .linkedFramework("Security"),
                .linkedFramework("SystemConfiguration"),
            ]
        ),

        // =================================================================
        // ONNX Runtime Backend
        //
        // Depends on both RABackendONNXBinary (embeddings + Silero VAD) and
        // RABackendSherpaBinary (Sherpa-ONNX STT/TTS/VAD). `ONNX.register()`
        // plumbs both plugins into the commons plugin registry at SDK boot.
        // =================================================================
        .target(
            name: "ONNXRuntime",
            dependencies: [
                "RunAnywhere",
                "ONNXBackend",
                "RABackendONNXBinary",
                "RABackendSherpaBinary",
            ],
            path: "sdk/runanywhere-swift/Sources/ONNXRuntime",
            exclude: ["include"],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedFramework("CoreML"),
                .linkedLibrary("archive"),
                .linkedLibrary("bz2"),
            ]
        ),

        // =================================================================
        // LlamaCPP Runtime Backend
        // =================================================================
        .target(
            name: "LlamaCPPRuntime",
            dependencies: [
                "RunAnywhere",
                "LlamaCPPBackend",
                "RABackendLlamaCPPBinary",
            ],
            path: "sdk/runanywhere-swift/Sources/LlamaCPPRuntime",
            exclude: ["include"],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
            ]
        ),

        // =================================================================
        // MLX Runtime Backend
        // =================================================================
        .target(
            name: "MLXRuntime",
            dependencies: [
                "RunAnywhere",
                "MLXBackend",
                "RABackendMLXBinary",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXEmbedders", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ] + mlxAudioRuntimeDependencies,
            path: "sdk/runanywhere-swift/Sources/MLXRuntime",
            exclude: ["include"],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedFramework("CoreImage"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
            ]
        ),

        // =================================================================
        // RunAnywhere unit tests (e.g. AudioCaptureManager – Issue #198)
        // =================================================================
        .testTarget(
            name: "RunAnywhereTests",
            dependencies: ["RunAnywhere"],
            path: "sdk/runanywhere-swift/Tests/RunAnywhereTests"
        ),

    ] + binaryTargets()
)

// =============================================================================
// BINARY TARGET SELECTION
// =============================================================================
// Returns local or remote binary targets based on useLocalNatives setting
func binaryTargets() -> [Target] {
    if useLocalNatives {
        // =====================================================================
        // LOCAL DEVELOPMENT MODE
        // Use XCFrameworks from sdk/runanywhere-swift/Binaries/.
        // Regenerate them via: `./sdk/runanywhere-swift/scripts/build-core-xcframework.sh` at the
        // repo root (builds iOS device + simulator + macOS slices into each
        // of the RACommons / RABackend* xcframeworks).
        // =====================================================================
        // ONNX Runtime is statically linked into RABackendONNX — no separate
        // local xcframework targets needed (v0.19.0+).
        //
        // Sherpa-ONNX ships as RABackendSherpa — owner of the `sherpa` engine
        // plugin (STT / TTS / VAD). `ONNXRuntime.register()` registers this
        // plugin's vtable via `rac_plugin_entry_sherpa()` at boot.
        return [
            .binaryTarget(
                name: "RACommonsBinary",
                path: "sdk/runanywhere-swift/Binaries/RACommons.xcframework"
            ),
            .binaryTarget(
                name: "RABackendLlamaCPPBinary",
                path: "sdk/runanywhere-swift/Binaries/RABackendLLAMACPP.xcframework"
            ),
            .binaryTarget(
                name: "RABackendONNXBinary",
                path: "sdk/runanywhere-swift/Binaries/RABackendONNX.xcframework"
            ),
            .binaryTarget(
                name: "RABackendSherpaBinary",
                path: "sdk/runanywhere-swift/Binaries/RABackendSherpa.xcframework"
            ),
            .binaryTarget(
                name: "RABackendMLXBinary",
                path: "sdk/runanywhere-swift/Binaries/RABackendMLX.xcframework"
            ),
        ]
    } else {
        // =====================================================================
        // PRODUCTION MODE (for external SPM consumers)
        // Download XCFrameworks from GitHub releases
        // All xcframeworks include iOS + macOS slices (v0.19.0+)
        //
        // ONNXBackend / ONNXRuntime hard-depend on RABackendSherpaBinary, so
        // it MUST appear in this list with a real URL + checksum before tagging
        // a release. `sdk/runanywhere-swift/scripts/release-swift-binaries.sh` zips
        // `RABackendSherpa.xcframework` into `RABackendSherpa-ios-v<version>.zip`
        // and `sdk/runanywhere-swift/scripts/sync-checksums.sh` patches the checksum below.
        //
        // RELEASE PROCEDURE — checksums MUST be regenerated before tagging:
        //   1. Build XCFrameworks (CI native_ios job, or locally via
        //      `./sdk/runanywhere-swift/scripts/build-core-xcframework.sh`).
        //   2. Run `sdk/runanywhere-swift/scripts/sync-checksums.sh <zip_dir>` against the directory
        //      that holds the five `*-ios-v<version>.zip` artifacts. This
        //      overwrites each `checksum:` line below with the real SHA-256.
        //   3. The release workflow (`release.yml::publish`) runs the
        //      checksum sync automatically right before creating the draft
        //      Release.
        //
        // Real SHA-256 checksums for the current `sdkVersion` ship on `main`
        // (committed alongside each release-bumping PR). A stale checkout that
        // points `sdkVersion` at a future tag whose zips have not yet been
        // refreshed by `sync-checksums.sh` will surface as a `swift package
        // resolve` "wrong checksum" error against the new release URL — which
        // means: the release tooling did not re-run on this tag commit. Re-run
        // `sdk/runanywhere-swift/scripts/sync-checksums.sh` and commit before re-tagging.
        // =====================================================================
        return [
            .binaryTarget(
                name: "RACommonsBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/RACommons-ios-v\(sdkVersion).zip",
                checksum: "b1fe74a812af389c6c42339dcd3f3019c1c47137837cfe0e4ea746b95b48613e"
            ),
            .binaryTarget(
                name: "RABackendLlamaCPPBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/RABackendLLAMACPP-ios-v\(sdkVersion).zip",
                checksum: "071e062573e792daa521b31b314e21a318423b01e0e2d30371cb7da77690624f"
            ),
            .binaryTarget(
                name: "RABackendONNXBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/RABackendONNX-ios-v\(sdkVersion).zip",
                checksum: "7a57fa3db9ed572a2b46d8d500549b1b9b06a78bc77927a0e2256a5ce01d1de1"
            ),
            .binaryTarget(
                name: "RABackendSherpaBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/RABackendSherpa-ios-v\(sdkVersion).zip",
                checksum: "e7c23219b47edcfeb1492441027af2f1295905db03a25f1efc1987ddd32f6cd2"
            ),
            .binaryTarget(
                name: "RABackendMLXBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/RABackendMLX-ios-v\(sdkVersion).zip",
                checksum: "0000000000000000000000000000000000000000000000000000000000000000"
            ),
        ]
    }
}
