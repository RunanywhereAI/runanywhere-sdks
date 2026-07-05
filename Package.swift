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

// RunAnywhere SDK - Swift Package Manager Distribution
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
//          ./scripts/build/ios-xcframework.sh
//      This writes RACommons.xcframework, RABackendLLAMACPP.xcframework, and
//      RABackendONNX.xcframework into sdk/runanywhere-swift/Binaries/.
//   2. Ensure `useLocalNatives = true` below so the package resolves to
//      those on-disk XCFrameworks instead of the remote release URLs.
//   3. Open the example app (examples/ios/RunAnywhereAI) in Xcode — it
//      depends on this package via a relative path.
//

// BINARY TARGET CONFIGURATION
//
// useLocalNatives = true  → Use local XCFrameworks from sdk/runanywhere-swift/Binaries/
//                           For local development. Generate them with
//                           `./scripts/build/ios-xcframework.sh` at the repo
//                           root before building the SDK.
//
// useLocalNatives = false → Download XCFrameworks from GitHub releases (PRODUCTION).
//                           For external users via SPM. No local build needed.
//
// Toggling: this is a hand-edited flag. Release tooling sets it to `false`
// before tagging a release; local devs flip it back to `true` and run
// `./scripts/build/ios-xcframework.sh` to regenerate the on-disk binaries.
// The name `useLocalNatives` matches the equivalent toggle in the other
// client SDKs (Kotlin, Flutter, React Native).
let useLocalNatives = true // Toggle: false for release (default committed to main); local devs flip to true and run ./scripts/build/ios-xcframework.sh

// Version for remote XCFrameworks (used when useLocalNatives = false)
// Updated automatically by CI/CD during releases.
let sdkVersion = "0.19.13"

let package = Package(
    name: "runanywhere-sdks",
    platforms: [
        // iOS 17.5 / macOS 14.5 — latest minor of the LTS line, matches the
        // Xcode 15.4 baseline.
        .iOS("17.5"),
        .macOS("14.5"),
    ],
    products: [
        // Core SDK - always needed
        .library(
            name: "RunAnywhere",
            targets: ["RunAnywhere"]
        ),

        // ONNX Runtime Backend - adds STT/TTS/VAD capabilities
        .library(
            name: "RunAnywhereONNX",
            targets: ["ONNXRuntime"]
        ),

        // LlamaCPP Backend - adds LLM text generation
        .library(
            name: "RunAnywhereLlamaCPP",
            targets: ["LlamaCPPRuntime"]
        ),

    ],
    dependencies: [
        // SPM deps use `.upToNextMinor` (not open-ended `from:`) so a
        // silent upstream major bump can't land in `Package.resolved` without
        // a Package.swift edit. Version floors are mirrored in
        // sdk/runanywhere-swift/Sources/RunAnywhere/Generated/Versions.swift
        // (RAVersions) — keep both in sync via scripts/release/sync-versions.sh.
        .package(url: "https://github.com/apple/swift-crypto.git", .upToNextMinor(from: "3.15.1")),
        .package(url: "https://github.com/JohnSundell/Files.git", .upToNextMinor(from: "4.3.0")),
        .package(url: "https://github.com/devicekit/DeviceKit.git", .upToNextMinor(from: "5.8.0")),
        .package(url: "https://github.com/getsentry/sentry-cocoa", .upToNextMinor(from: "8.58.2")),
        // swift-protobuf for idl/*.proto generated types consumed by
        // sdk/runanywhere-swift/Sources/RunAnywhere/Generated/*.pb.swift.
        // Floor must stay >= 1.28.0: generated code uses
        // SwiftProtobuf._NameMap(bytecode:).
        .package(url: "https://github.com/apple/swift-protobuf.git", .upToNextMinor(from: "1.38.0")),
        //
        // grpc-swift intentionally NOT wired. The *.grpc.swift files under
        // Sources/RunAnywhere/Generated/ are excluded from the RunAnywhere
        // target below — gRPC client stubs were emitted by the codegen but
        // are not used at runtime. Frontends consume proto events via the
        // hand-written VoiceAgentStreamAdapter that wraps the in-process C
        // callback (see sdk/runanywhere-swift/Sources/RunAnywhere/Adapters/
        // VoiceAgentStreamAdapter.swift).
        //
    ],
    targets: [
        // C Bridge Module - Core Commons
        .target(
            name: "CRACommons",
            dependencies: ["RACommonsBinary"],
            path: "sdk/runanywhere-swift/Sources/RunAnywhere/CRACommons",
            publicHeadersPath: "include"
        ),

        // C Bridge Module - LlamaCPP Backend Headers
        .target(
            name: "LlamaCPPBackend",
            dependencies: [
                "CRACommons",
                "RABackendLlamaCPPBinary",
            ],
            path: "sdk/runanywhere-swift/Sources/LlamaCPPRuntime/include",
            publicHeadersPath: "."
        ),

        // C Bridge Module - ONNX Backend Headers
        //
        // ONNX Runtime is statically linked into RABackendONNX.a (since
        // v0.19.0) — no separate ONNXRuntime{iOS,macOS}Binary targets needed.
        //
        // The Sherpa-ONNX backend ships as a peer xcframework. It owns the
        // STT (Whisper / Zipformer / Paraformer), TTS (Piper / VITS) and
        // VAD (Silero) primitives under `framework == .sherpa`. ONNX owns
        // embeddings and generic ONNX Runtime services under
        // `framework == .onnx`. Both must be linked so the unified plugin
        // router can resolve either framework at load time.
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

        // Core SDK
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
                // `scripts/codegen/generate_swift.sh` does not emit *.grpc.swift
                // stubs. Swift consumes the same services through the
                // hand-written AsyncStream adapters (VoiceAgentStreamAdapter,
                // LLMStreamAdapter) that wrap the in-process C callback.
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

        // ONNX Runtime Backend
        //
        // Depends on both RABackendONNXBinary (embeddings + Silero VAD) and
        // RABackendSherpaBinary (Sherpa-ONNX STT/TTS/VAD). `ONNX.register()`
        // plumbs both plugins into the commons plugin registry at SDK boot.
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

        // LlamaCPP Runtime Backend
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

        // RunAnywhere unit tests (e.g. AudioCaptureManager – Issue #198)
        .testTarget(
            name: "RunAnywhereTests",
            dependencies: ["RunAnywhere"],
            path: "sdk/runanywhere-swift/Tests/RunAnywhereTests"
        ),

    ] + binaryTargets()
)

// BINARY TARGET SELECTION
// Returns local or remote binary targets based on useLocalNatives setting
func binaryTargets() -> [Target] {
    if useLocalNatives {
        // LOCAL DEVELOPMENT MODE
        // Use XCFrameworks from sdk/runanywhere-swift/Binaries/.
        // Regenerate them via: `./scripts/build/ios-xcframework.sh` at the
        // repo root (builds iOS device + simulator + macOS slices into each
        // of the RACommons / RABackend* xcframeworks).
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
        // PRODUCTION MODE (for external SPM consumers)
        // Download XCFrameworks from GitHub releases
        // All xcframeworks include iOS + macOS slices (v0.19.0+)
        //
        // ONNXBackend / ONNXRuntime hard-depend on RABackendSherpaBinary, so
        // it MUST appear in this list with a real URL + checksum before tagging
        // a release. `scripts/release/swift-binaries.sh` zips
        // `RABackendSherpa.xcframework` into `RABackendSherpa-ios-v<version>.zip`
        // and `scripts/release/sync-checksums.sh` patches the checksum below.
        //
        // RELEASE PROCEDURE — checksums MUST be regenerated before tagging:
        //   1. Build XCFrameworks (CI native_ios job, or locally via
        //      `./scripts/build/ios-xcframework.sh`).
        //   2. Run `scripts/release/sync-checksums.sh <zip_dir>` against the directory
        //      that holds the four `*-ios-v<version>.zip` artifacts. This
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
        // `scripts/release/sync-checksums.sh` and commit before re-tagging.
        return [
            .binaryTarget(
                name: "RACommonsBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/RACommons-ios-v\(sdkVersion).zip",
                checksum: "1685832e2b3a40b04ae27ad8d600e8f483bc355480677395241e0ab4ecdbd6fe"
            ),
            .binaryTarget(
                name: "RABackendLlamaCPPBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/RABackendLLAMACPP-ios-v\(sdkVersion).zip",
                checksum: "a551a2218e0fda0dab5aca8d803982db3ad7185021a0db16300b3d996ac1910d"
            ),
            .binaryTarget(
                name: "RABackendONNXBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/RABackendONNX-ios-v\(sdkVersion).zip",
                checksum: "cf2608b6f85622edf33ea23c73e5e6ddf9ef7f967050767c8b578428578d78c7"
            ),
            .binaryTarget(
                name: "RABackendSherpaBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/RABackendSherpa-ios-v\(sdkVersion).zip",
                checksum: "771b6d4273a2b3b7b1f459aaa5d29b4f42f7f341eed9018a8031cd80143556bb"
            ),
        ]
    }
}
