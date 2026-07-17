// swift-tools-version: 6.2
import PackageDescription
import Foundation

// =============================================================================
// RunAnywhere SDK - Swift Package Manager Distribution
// =============================================================================
//
// This is the SINGLE Package.swift for both local development and SPM consumption.
//
// FOR EXTERNAL USERS (consuming via GitHub):
//   .package(url: "https://github.com/RunanywhereAI/runanywhere-sdks", from: "0.20.11")
//   No environment override is needed. SPM downloads the checksum-verified
//   XCFramework archives from the GitHub release by default.
//
// FOR LOCAL DEVELOPMENT:
//   1. Build native XCFrameworks from the repo root:
//          ./sdk/runanywhere-swift/scripts/build-core-xcframework.sh
//      This writes the Commons, LlamaCPP, ONNX, Sherpa, and MLX XCFrameworks
//      into sdk/runanywhere-swift/Binaries/.
//   2. Export `RUNANYWHERE_USE_LOCAL_NATIVES=1` so the package resolves to
//      those on-disk XCFrameworks instead of the remote release URLs.
//   3. Open the example app (examples/ios/RunAnywhereAI) in Xcode — it
//      depends on this package via a relative path.
//
// =============================================================================

// =============================================================================
// BINARY TARGET CONFIGURATION
// =============================================================================
//
// RUNANYWHERE_USE_LOCAL_NATIVES=1 → use local XCFrameworks from
// sdk/runanywhere-swift/Binaries/. With the variable unset, download the
// checksum-verified release archives (the production/external-consumer path).
//
// Selection is fail-closed for distribution: remote release artifacts are the
// default. Local development/build lanes must explicitly export
// RUNANYWHERE_USE_LOCAL_NATIVES=1 after staging the XCFrameworks below. This
// avoids committing a local-only manifest or hand-editing it around a tag.
//
// =============================================================================
let localNativesMarkerPath = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent(".runanywhere-local-natives")
    .path
let useLocalNatives = ProcessInfo.processInfo.environment["RUNANYWHERE_USE_LOCAL_NATIVES"] == "1"
    || FileManager.default.fileExists(atPath: localNativesMarkerPath)

// Release tooling asks SwiftPM for a static product that contains the Swift
// MLX implementation and its MLX dependencies, but deliberately leaves the
// Commons/plugin symbols unresolved. CocoaPods then links this archive beside
// the package-owned RACommons and RABackendMLX archives so every frontend uses
// one process-wide plugin registry. Normal SwiftPM consumers use the canonical
// RunAnywhereMLX product below and do not see the packaging-only product.
let buildMLXDistributionFramework =
    ProcessInfo.processInfo.environment["RUNANYWHERE_BUILD_MLX_DISTRIBUTION_FRAMEWORK"] == "1"

let mlxDistributionProducts: [Product] = buildMLXDistributionFramework
    ? [
        .library(
            name: "RunAnywhereMLXRuntime",
            type: .static,
            targets: ["MLXRuntime"]
        ),
    ]
    : []

let commonsBridgeDependencies: [Target.Dependency] = buildMLXDistributionFramework
    ? []
    : ["RACommonsBinary"]

let mlxBackendBridgeDependencies: [Target.Dependency] = buildMLXDistributionFramework
    ? []
    : ["CRACommons", "RABackendMLXBinary"]

let mlxRuntimeNativeDependencies: [Target.Dependency] = buildMLXDistributionFramework
    ? ["MLXBackend"]
    : ["MLXBackend", "RABackendMLXBinary"]

let mlxRuntimeDistributionSwiftSettings: [SwiftSetting] = buildMLXDistributionFramework
    ? [
        // MLXBackend remains a header-only import in this lane. Point Clang at
        // the canonical ABI declarations without linking a second Commons
        // archive into the runtime artifact.
        .define("RUNANYWHERE_MLX_DISTRIBUTION"),
        .unsafeFlags(["-Xcc", "-Isdk/runanywhere-commons/include"]),
    ]
    : []

// Version for remote XCFrameworks (used unless local natives are explicitly enabled).
// Updated by scripts/release/sync-versions.sh during release preparation.
let sdkVersion = "0.20.11"

let homebrewPrefix = ProcessInfo.processInfo.environment["RUNANYWHERE_HOMEBREW_PREFIX"]
    ?? ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"]
    ?? "/opt/homebrew"

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

// PrismML's Bonsai 1-bit weights require kernels that are not yet available
// in upstream mlx-swift. This revision is the maintained Prism delta applied
// directly on top of upstream mlx-swift 0.31.6, which keeps mlx-swift-lm
// 3.31.x API-compatible while enabling bits=1 / group_size=128 models.
let prismMLXSwiftRevision = "563961dfcfd4589755190d285555e4f9eface890"

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

        // =================================================================
        // macOS CLI host — registers real mlx-swift callbacks, then
        // delegates to the C++ rcli stack with llama.cpp + MLX both enabled.
        // =================================================================
        .executable(
            name: "RunAnywhereMLXCLI",
            targets: ["RunAnywhereMLXCLI"]
        ),

    ] + mlxDistributionProducts,
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
        // swift-protobuf for idl/*.proto generated types consumed by
        // sdk/runanywhere-swift/Sources/RunAnywhere/Generated/*.pb.swift.
        // Floor bumped 1.27.0 → 1.38.0 (latest stable). The earlier
        // .upToNextMajor exception (needed because generated code uses
        // SwiftProtobuf._NameMap(bytecode:) from 1.28.0+) is now resolved by
        // floor >= 1.38.0, so we re-tighten to .upToNextMinor in line with
        // the policy applied to the other deps.
        .package(url: "https://github.com/apple/swift-protobuf.git", .upToNextMinor(from: "1.38.0")),
        .package(
            url: "https://github.com/PrismML-Eng/mlx-swift.git",
            revision: prismMLXSwiftRevision
        ),
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
            dependencies: commonsBridgeDependencies,
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
            dependencies: mlxBackendBridgeDependencies,
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
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                "CRACommons",
                "RACommonsBinary",
            ],
            path: "sdk/runanywhere-swift/Sources/RunAnywhere",
            exclude: [
                "CRACommons",
                "Generated/router.pb.swift",
                // `diffusion_options.pb.swift` is compiled into the module: the
                // CoreML Stable-Diffusion facade (RunAnywhere+Diffusion /
                // CppBridge+Diffusion) consumes RADiffusionGenerationOptions /
                // RADiffusionResult / RADiffusionStreamEvent.
                //
                // The previously-excluded
                // `Generated/{voice_agent_service,llm_service,download_service}.grpc.swift`
                // files are no longer emitted by `idl/codegen/generate_swift.sh` and
                // have been removed from the repo. Swift consumes the same services
                // through the hand-written AsyncStream adapters (VoiceAgentStreamAdapter,
                // LLMStreamAdapter) that wrap the in-process C callback, so the gRPC
                // stubs would only be dead code on macOS 14 / iOS 17.
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
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
                // Apple CoreML Stable-Diffusion engine. `ONNX.register()`
                // bundles the Apple secondary backends, and this target already
                // links CoreML + Accelerate, so it is the natural home for the
                // diffusion engine archive. The coreml plugin auto-wins the
                // DIFFUSION slot (priority 100) once linked.
                "RABackendCoreMLBinary",
            ],
            path: "sdk/runanywhere-swift/Sources/ONNXRuntime",
            exclude: ["include", "README.md"],
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
            exclude: ["include", "README.md"],
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
            dependencies: mlxRuntimeNativeDependencies + [
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXEmbedders", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ] + mlxAudioRuntimeDependencies,
            path: "sdk/runanywhere-swift/Sources/MLXRuntime",
            exclude: ["include"],
            swiftSettings: mlxRuntimeDistributionSwiftSettings,
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedFramework("CoreImage"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
            ]
        ),

        // =================================================================
        // rcli host bridge for the macOS CLI executable (RunAnywhereMLXCLI).
        //
        // Release builds keep BOTH llama.cpp (GGUF) and MLX enabled. MLX
        // needs Swift runtime callbacks from MLXRuntime; llama.cpp registers
        // from C++ bootstrap via RCLI_HAS_LLAMACPP. Linux/Windows keep using
        // the CMake-built pure C++ rcli (llama.cpp; MLX is Apple-only).
        // =================================================================
        .target(
            name: "RADesktopHostAdapter",
            dependencies: [
                "CRACommons",
            ],
            path: "sdk/runanywhere-commons/src/desktop",
            sources: [
                "desktop_adapter.cpp",
                "desktop_secure_store.cpp",
                "http_transport_curl.cpp",
            ],
            publicHeadersPath: ".",
            cxxSettings: [
                .headerSearchPath(".."),
                .headerSearchPath("../../include"),
            ],
            linkerSettings: [
                .linkedLibrary("curl"),
                .linkedLibrary("z"),
            ]
        ),

        .target(
            name: "RCLIHost",
            dependencies: [
                "CRACommons",
                "RADesktopHostAdapter",
                "RABackendLlamaCPPBinary",
                "RABackendMLXBinary",
            ],
            path: "sdk/runanywhere-cli",
            exclude: [
                "dist",
            ],
            sources: [
                "src/app.cpp",
                "src/bootstrap.cpp",
                "src/catalog/catalog.cpp",
                "src/catalog/model_ref.cpp",
                "src/commands/cmd_version.cpp",
                "src/commands/cmd_info.cpp",
                "src/commands/cmd_backends.cpp",
                "src/commands/cmd_list.cpp",
                "src/commands/cmd_lora.cpp",
                "src/commands/cmd_pull.cpp",
                "src/commands/cmd_rm.cpp",
                "src/commands/cmd_run.cpp",
                "src/commands/cmd_serve.cpp",
                "src/commands/cmd_show.cpp",
                "src/commands/cmd_stt.cpp",
                "src/commands/cmd_embed.cpp",
                "src/commands/cmd_tts.cpp",
                "src/commands/cmd_vad.cpp",
                "src/commands/cmd_voice.cpp",
                "src/commands/cmd_image.cpp",
                "src/commands/engine_options.cpp",
                "src/commands/model_setup.cpp",
                "src/config/cli_paths.cpp",
                "src/io/wav_io.cpp",
                "src/io/image_io.cpp",
                "src/io/output.cpp",
                "src/progress/progress_bar.cpp",
                "src/repl/repl.cpp",
                "src/util/term.cpp",
                "third_party/linenoise/linenoise.c",
            ],
            publicHeadersPath: "include",
            cxxSettings: [
                .define("RAC_HAVE_PROTOBUF", to: "1"),
                // RACommons statically bundles its pinned protobuf runtime in
                // a private namespace. Every generated-proto consumer must
                // compile with the identical token rewrite.
                .define("google", to: "runanywhere_internal"),
                // CLI11's C++20 codecvt path uses APIs deprecated since C++17.
                // Select its current locale-conversion implementation.
                .define("CLI11_HAS_CODECVT", to: "0"),
                .define("RCLI_HAS_LLAMACPP", to: "1"),
                .define("RCLI_HAS_MLX", to: "1"),
                .define("RCLI_VERSION", to: "\"\(sdkVersion)\""),
                .headerSearchPath("include"),
                .headerSearchPath("src"),
                .headerSearchPath("third_party/CLI11"),
                .headerSearchPath("third_party/linenoise"),
                .headerSearchPath("../runanywhere-commons/include"),
                .headerSearchPath("../runanywhere-commons/src"),
                .headerSearchPath("../runanywhere-commons/src/generated"),
                .headerSearchPath("../runanywhere-commons/src/generated/proto"),
                .unsafeFlags([
                    "-I\(homebrewPrefix)/opt/protobuf/include",
                    "-I\(homebrewPrefix)/opt/abseil/include",
                ]),
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedLibrary("curl"),
                .linkedLibrary("archive"),
                .linkedLibrary("bz2"),
                .linkedLibrary("z"),
                .linkedFramework("Accelerate"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("Security"),
            ]
        ),

        .executableTarget(
            name: "RunAnywhereMLXCLI",
            dependencies: [
                "MLXRuntime",
                "RCLIHost",
            ],
            path: "sdk/runanywhere-swift/Sources/RunAnywhereMLXCLI"
        ),

        // =================================================================
        // RunAnywhere unit tests (e.g. AudioCaptureManager – Issue #198)
        // =================================================================
        .testTarget(
            name: "RunAnywhereTests",
            dependencies: [
                "RunAnywhere",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "sdk/runanywhere-swift/Tests/RunAnywhereTests",
            exclude: ["Fixtures"]
        ),

    ] + binaryTargets(),
    cxxLanguageStandard: .cxx20
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
                name: "RABackendCoreMLBinary",
                path: "sdk/runanywhere-swift/Binaries/RABackendCoreML.xcframework"
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
        //      that holds all eight Apple archives (seven XCFramework ZIPs
        //      plus the MLX resource ZIP). This
        //      overwrites each `checksum:` line below with the real SHA-256.
        //   3. The release workflow (`release.yml::publish`) verifies the
        //      rebuilt archives still match these tagged checksums and aborts
        //      rather than trying to mutate an immutable tag.
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
                checksum: "8c1129e2fb680a7d37b111d194191976055a6f276eda5562968f535ca02bee9f"
            ),
            .binaryTarget(
                name: "RABackendLlamaCPPBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/RABackendLLAMACPP-ios-v\(sdkVersion).zip",
                checksum: "5c837259d302f66aecc2c6d52332af0ee4fb43beeedbd6a3f3fd762147b37765"
            ),
            .binaryTarget(
                name: "RABackendONNXBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/RABackendONNX-ios-v\(sdkVersion).zip",
                checksum: "b50a9ebcf49a34f1cbefa6be445ced74cfa3ef47281fccfa7b1b272ba81aef79"
            ),
            .binaryTarget(
                name: "RABackendSherpaBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/RABackendSherpa-ios-v\(sdkVersion).zip",
                checksum: "75735609334d61180c623fbf2e09f8e74a2d990b84799b3ebde1334a5ac4f38c"
            ),
            // Apple CoreML Stable-Diffusion engine. `ONNXRuntime` declares an
            // unconditional dependency on this, so the remote list must carry it.
            // PLACEHOLDER checksum — `scripts/sync-checksums.sh` overwrites this
            // with the real SHA-256 of RABackendCoreML-ios-v<version>.zip before
            // tagging (release choreography), exactly like the peers above.
            .binaryTarget(
                name: "RABackendCoreMLBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/RABackendCoreML-ios-v\(sdkVersion).zip",
                checksum: "93cb97b0a3e64dca8996214ebb85945202fa413e05907c260908fa6ab2b41e24"
            ),
            .binaryTarget(
                name: "RABackendMLXBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/RABackendMLX-ios-v\(sdkVersion).zip",
                checksum: "b7532f4321d6f8726cd0e5b3cc2bd1c9fe031337217baf846e7e76fb98e6ba80"
            ),
        ]
    }
}
