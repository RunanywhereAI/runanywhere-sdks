// swift-tools-version: 5.9
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
//          ./scripts/build-core-xcframework.sh
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
//                           `./scripts/build-core-xcframework.sh` at the repo
//                           root before building the SDK.
//
// useLocalNatives = false → Download XCFrameworks from GitHub releases (PRODUCTION).
//                           For external users via SPM. No local build needed.
//
// Toggling: this is a hand-edited flag. Release tooling sets it to `false`
// before tagging a release; local devs flip it back to `true` and run
// `./scripts/build-core-xcframework.sh` to regenerate the on-disk binaries.
//
// Historical name: this used to be called `useLocalBinaries`. The concept is
// the same — it's been renamed to `useLocalNatives` for consistency with the
// equivalent toggle in the other client SDKs (Kotlin, Flutter, React Native).
// =============================================================================
let useLocalNatives = true //  Toggle: true for local dev, false for release

// Version for remote XCFrameworks (used when useLocalNatives = false)
// Updated automatically by CI/CD during releases.
//
// v3.1.1: sdk minor bump. Remote XCFramework URLs expect
// `RACommons-ios-v3.1.1.zip` at the v3.1.1 GitHub release; consumers
// should set `useLocalNatives = true` until release automation publishes
// the v3.1.0
// artifacts.
let sdkVersion = "0.19.13"

let package = Package(
    name: "runanywhere-sdks",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
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

    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/JohnSundell/Files.git", from: "4.3.0"),
        .package(url: "https://github.com/devicekit/DeviceKit.git", from: "5.6.0"),
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.40.0"),
        // swift-protobuf for idl/*.proto generated types consumed by
        // sdk/runanywhere-swift/Sources/RunAnywhere/Generated/*.pb.swift
        // (see v2_gap_specs/GAP_01_IDL_AND_CODEGEN.md for rationale)
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.27.0"),
        //
        // grpc-swift intentionally NOT wired. The *.grpc.swift files under
        // Sources/RunAnywhere/Generated/ are excluded from the RunAnywhere
        // target below — gRPC client stubs were emitted by the codegen but
        // are not used at runtime. Frontends consume proto events via the
        // hand-written VoiceAgentStreamAdapter that wraps the in-process C
        // callback (see sdk/runanywhere-swift/Sources/RunAnywhere/Adapters/
        // VoiceAgentStreamAdapter.swift). v3.1 audit fix.
        //
    ],
    targets: [
        // =================================================================
        // C Bridge Module - Core Commons
        // =================================================================
        .target(
            name: "CRACommons",
            dependencies: ["RACommonsBinary"],
            path: "sdk/runanywhere-swift/Sources/RunAnywhere/CRACommons",
            publicHeadersPath: "include"
        ),

        // =================================================================
        // C Bridge Module - LlamaCPP Backend Headers
        // =================================================================
        .target(
            name: "LlamaCPPBackend",
            dependencies: ["RABackendLlamaCPPBinary"],
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
                "RABackendONNXBinary",
                "RABackendSherpaBinary",
            ],
            path: "sdk/runanywhere-swift/Sources/ONNXRuntime/include",
            publicHeadersPath: "."
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
                // SWF-grpc delete (Wave H-2): the previously-excluded
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
        // Regenerate them via: `./scripts/build-core-xcframework.sh` at the
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
        ]
    } else {
        // =====================================================================
        // PRODUCTION MODE (for external SPM consumers)
        // Download XCFrameworks from GitHub releases
        // All xcframeworks include iOS + macOS slices (v0.19.0+)
        // =====================================================================
        return [
            .binaryTarget(
                name: "RACommonsBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/RACommons-ios-v\(sdkVersion).zip",
                checksum: "a1caaf12186c896b49bfccc7348a71c3b3428b282e5ac3f5a3181a022b5401da"
            ),
            .binaryTarget(
                name: "RABackendLlamaCPPBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/RABackendLLAMACPP-ios-v\(sdkVersion).zip",
                checksum: "7ff978fbc87726423c682298f04354c7c11dfbfe9403b51f63d49df9c92e097a"
            ),
            .binaryTarget(
                name: "RABackendONNXBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/RABackendONNX-ios-v\(sdkVersion).zip",
                checksum: "0f8575559ac96a9a7b872bb3adca3608acef38fdec1ab8ccf9b0716a8d627c6c"
            ),
            // NOTE: Sherpa xcframework release URL + checksum TBD — once the
            // release pipeline publishes RABackendSherpa-ios-v<sdkVersion>.zip,
            // add a matching `.binaryTarget(name: "RABackendSherpaBinary", …)`
            // entry here so production consumers link the sherpa plugin too.
            // Until then external SPM consumers will be missing STT/TTS via
            // sherpa (LLM via llamacpp + embeddings via onnx continue to work).
        ]
    }
}
