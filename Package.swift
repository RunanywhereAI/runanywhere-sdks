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
//   .package(url: "https://github.com/RunanywhereAI/runanywhere-swift.git", from: "0.20.23")
//
//   Consume the SWIFT DISTRIBUTION REPO, never this monorepo. Two reasons, and
//   the first one is fatal:
//
//   1. This repo's tags DO NOT COMPILE as a Swift package. The generated
//      protobuf Swift sources under bindings/swift/Sources/RunAnywhere/Generated/
//      are no longer committed (they are codegen output), so every tag cut after
//      that de-commit carries only Versions.swift there, where v0.20.17 carried
//      42 files. Resolving this URL by version yields ~347 errors of the form
//      "cannot find type 'RAModelInfo' in scope". The distribution repo is
//      generated WITH those sources, so it builds.
//   2. This monorepo is ~340 MB of C++, Kotlin, WASM and Dart. The distribution
//      repo is ~3 MB of Swift.
//
//   Both manifests declare the SAME remote binaryTargets with the SAME
//   checksums, pointing at the SAME release assets on runanywhere-sdks, so the
//   XCFrameworks are never duplicated or re-uploaded. No environment override is
//   needed; SPM downloads the checksum-verified archives from the GitHub release.
//
//   bindings/swift/scripts/sync-dist-repo.sh cuts that repo, and
//   scripts/validation/gates/check_swift_dist_repo_sync.sh fails every PR here
//   until it carries the matching tag.
//
// FOR LOCAL DEVELOPMENT:
//   1. Build native XCFrameworks from the repo root:
//          ./bindings/swift/scripts/build-core-xcframework.sh
//      This writes the Commons, LlamaCPP, ONNX, Sherpa, and MLX XCFrameworks
//      into bindings/swift/Binaries/.
//   2. Export `RUNANYWHERE_USE_LOCAL_NATIVES=1` so the package resolves to
//      those on-disk XCFrameworks instead of the remote release URLs.
//   3. Open the example app (github.com/RunanywhereAI/runanywhere-ios) in Xcode — it
//      depends on this package via a relative path.
//
// =============================================================================

// =============================================================================
// BINARY TARGET CONFIGURATION
// =============================================================================
//
// RUNANYWHERE_USE_LOCAL_NATIVES=1 → use local XCFrameworks from
// bindings/swift/Binaries/. With the variable unset, download the
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
        .unsafeFlags(["-Xcc", "-Icore/include"]),
    ]
    : []

// Version for remote XCFrameworks (used unless local natives are explicitly enabled).
// Updated by scripts/release/sync-versions.sh during release preparation.
// TEMP: pin to 0.20.19 until the v0.20.22 GitHub release assets are published.
// This release bumps the suite version only so the Electron packages can be
// republished carrying Windows x64 and ARM64 natives, and 0.20.22 fixes their
// packaging; none of v0.20.20, v0.20.21 or v0.20.22 exists as a tag with
// release assets, so the remote binaryTargets must keep resolving 0.20.19.
let sdkVersion = "0.20.23"

let homebrewPrefix = ProcessInfo.processInfo.environment["RUNANYWHERE_HOMEBREW_PREFIX"]
    ?? ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"]
    ?? "/opt/homebrew"

// The MLX stack is canonical-first: RunAnywhere forks track the current Apple
// and Blaizzy repositories and carry only the Bonsai/Prism kernels, native
// Maple graph, and dependency-identity alignment needed by this SDK. Exact
// fork-local tags ensure every direct and transitive SwiftPM edge resolves the
// same MLX core instead of silently substituting the public package identity.
let mlxAudioPackageDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/RunanywhereAI/mlx-audio-swift.git", exact: "0.1.5"),
]
let mlxAudioRuntimeDependencies: [Target.Dependency] = [
    .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
    .product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
    .product(name: "MLXAudioVAD", package: "mlx-audio-swift"),
]

let runAnywhereMLXSwiftVersion: Version = "0.31.8"
let runAnywhereMLXSwiftLMVersion: Version = "3.31.5"

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
            type: .static,
            targets: ["RunAnywhere"]
        ),

        // =================================================================
        // ONNX Runtime Backend - adds STT/TTS/VAD capabilities
        // =================================================================
        .library(
            name: "RunAnywhereONNX",
            type: .static,
            targets: ["ONNXRuntime"]
        ),

        // =================================================================
        // LlamaCPP Backend - adds LLM text generation
        // =================================================================
        .library(
            name: "RunAnywhereLlamaCPP",
            type: .static,
            targets: ["LlamaCPPRuntime"]
        ),

        // =================================================================
        // MLX Backend - adds Apple MLX LLM/VLM/embedding/STT/TTS capabilities
        // =================================================================
        .library(
            name: "RunAnywhereMLX",
            type: .static,
            targets: ["MLXRuntime"]
        ),

        // =================================================================
        // NeuRT Backend — Apple Neural Engine LLM + CoreML diffusion
        // =================================================================
        .library(
            name: "RunAnywhereNeuRT",
            type: .static,
            targets: ["NeuRTRuntime"]
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
        // bindings/swift/Sources/RunAnywhere/Generated/Versions.swift
        // (RAVersions) — keep both in sync via scripts/release/sync-versions.sh.
        // Floor bumped 3.0.0 → 3.15.1 (latest stable 3.x at bump time).
        .package(url: "https://github.com/apple/swift-crypto.git", .upToNextMinor(from: "3.15.1")),
        .package(url: "https://github.com/JohnSundell/Files.git", .upToNextMinor(from: "4.3.0")),
        // Floor bumped 5.6.0 → 5.8.0 (latest stable at bump time).
        .package(url: "https://github.com/devicekit/DeviceKit.git", .upToNextMinor(from: "5.8.0")),
        // swift-protobuf for idl/*.proto generated types consumed by
        // bindings/swift/Sources/RunAnywhere/Generated/*.pb.swift.
        // Floor bumped 1.27.0 → 1.38.0 (latest stable). The earlier
        // .upToNextMajor exception (needed because generated code uses
        // SwiftProtobuf._NameMap(bytecode:) from 1.28.0+) is now resolved by
        // floor >= 1.38.0, so we re-tighten to .upToNextMinor in line with
        // the policy applied to the other deps.
        .package(url: "https://github.com/apple/swift-protobuf.git", .upToNextMinor(from: "1.38.0")),
        .package(
            url: "https://github.com/RunanywhereAI/mlx-swift.git",
            exact: runAnywhereMLXSwiftVersion
        ),
        .package(
            url: "https://github.com/RunanywhereAI/mlx-swift-lm.git",
            exact: runAnywhereMLXSwiftLMVersion
        ),
        // mlx-audio-swift requires Swift 6.2+ and enables MLX STT/TTS/VAD/diarization.
        .package(url: "https://github.com/huggingface/swift-transformers", .upToNextMinor(from: "1.3.0")),
        //
        // grpc-swift intentionally NOT wired. The *.grpc.swift files under
        // Sources/RunAnywhere/Generated/ are excluded from the RunAnywhere
        // target below — gRPC client stubs were emitted by the codegen but
        // are not used at runtime. Frontends consume proto events via the
        // hand-written VoiceAgentStreamAdapter that wraps the in-process C
        // callback (see bindings/swift/Sources/RunAnywhere/Adapters/
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
            path: "bindings/swift/Sources/RunAnywhere/CRACommons",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("../../../../../core/include"),
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
            path: "bindings/swift/Sources/LlamaCPPRuntime/include",
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
            path: "bindings/swift/Sources/ONNXRuntime/include",
            publicHeadersPath: "."
        ),

        // =================================================================
        // C Bridge Module - NeuRT Backend Headers
        // =================================================================
        .target(
            name: "NeuRTBackend",
            dependencies: [
                "CRACommons",
                "RABackendNeuRTBinary",
            ],
            path: "bindings/swift/Sources/NeuRTRuntime/include",
            publicHeadersPath: "."
        ),

        // =================================================================
        // C Bridge Module - MLX Backend Headers
        // =================================================================
        .target(
            name: "MLXBackend",
            dependencies: mlxBackendBridgeDependencies,
            path: "bindings/swift/Sources/MLXRuntime/include",
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("../../../../../core/include"),
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
            path: "bindings/swift/Sources/RunAnywhere",
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
                "RABackendNeuRTBinary",
            ],
            path: "bindings/swift/Sources/ONNXRuntime",
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
        // NeuRT Runtime Backend — Apple Neural Engine LLM + CoreML diffusion
        //
        // Links RABackendNeuRTBinary and registers the `neurt` engine plugin
        // via `NeuRT.register()`. NeuRT is also bundled into ONNXRuntime (so
        // existing ONNX/diffusion consumers are unaffected); this standalone
        // product lets consumers opt into NeuRT directly.
        // =================================================================
        .target(
            name: "NeuRTRuntime",
            dependencies: [
                "RunAnywhere",
                "NeuRTBackend",
                "RABackendNeuRTBinary",
            ],
            path: "bindings/swift/Sources/NeuRTRuntime",
            exclude: ["include"],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedFramework("CoreML"),
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
            path: "bindings/swift/Sources/LlamaCPPRuntime",
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
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXEmbedders", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ] + mlxAudioRuntimeDependencies,
            path: "bindings/swift/Sources/MLXRuntime",
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
            // Path is src/ (not src/desktop/) so we can compile the desktop
            // device-manager TU that lives under infrastructure/device/. CMake
            // already groups both under RAC_DESKTOP_SOURCES; SPM must match or
            // RunAnywhereMLXCLI fails to link install_device_manager_provider /
            // rac_desktop_{platform_name,device_model,os_version}.
            path: "core/src",
            sources: [
                "desktop/desktop_adapter.cpp",
                "desktop/desktop_secure_store.cpp",
                "desktop/http_transport_curl.cpp",
                "infrastructure/device/rac_device_manager_desktop.cpp",
            ],
            publicHeadersPath: "desktop",
            cxxSettings: [
                .headerSearchPath("."),
                .headerSearchPath("../include"),
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
                "RABackendNeuRTBinary",
            ],
            path: "rcli",
            exclude: [
                "dist",
            ],
            sources: [
                "src/app.cpp",
                "src/bootstrap.cpp",
                "src/net/control_plane.cpp",
                "src/catalog/catalog.cpp",
                "src/catalog/model_ref.cpp",
                "src/commands/cmd_version.cpp",
                "src/commands/cmd_info.cpp",
                "src/commands/cmd_backends.cpp",
                "src/commands/cmd_list.cpp",
                "src/commands/cmd_lora.cpp",
                "src/commands/cmd_models.cpp",
                "src/commands/cmd_pull.cpp",
                "src/commands/cmd_rm.cpp",
                "src/commands/cmd_run.cpp",
                "src/commands/cmd_tool.cpp",
                "src/commands/cmd_serve.cpp",
                "src/commands/cmd_show.cpp",
                "src/commands/cmd_stt.cpp",
                "src/commands/cmd_embed.cpp",
                "src/commands/cmd_tts.cpp",
                "src/commands/cmd_vad.cpp",
                "src/commands/cmd_voice.cpp",
                "src/commands/cmd_image.cpp",
                "src/commands/cmd_segment.cpp",
                "src/commands/cmd_diarize.cpp",
                "src/commands/cmd_rag.cpp",
                "src/commands/cmd_rerank.cpp",
                "src/commands/cmd_bench.cpp",
                "src/commands/cmd_auth.cpp",
                "src/commands/cmd_telemetry.cpp",
                "src/commands/engine_options.cpp",
                "src/commands/model_setup.cpp",
                "src/config/cli_paths.cpp",
                "src/device_info.cpp",
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
                .define("RCLI_HAS_NEURT", to: "1"),
                .define("RCLI_VERSION", to: "\"\(sdkVersion)\""),
                .headerSearchPath("include"),
                .headerSearchPath("src"),
                .headerSearchPath("third_party/CLI11"),
                .headerSearchPath("third_party/linenoise"),
                .headerSearchPath("../core/include"),
                .headerSearchPath("../core/src"),
                .headerSearchPath("../core/src/generated"),
                .headerSearchPath("../core/src/generated/proto"),
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
                "ONNXRuntime",
                "RCLIHost",
            ],
            path: "bindings/swift/Sources/RunAnywhereMLXCLI"
        ),

        // =================================================================
        // RunAnywhere unit tests (e.g. AudioCaptureManager – Issue #198)
        // =================================================================
        .testTarget(
            name: "RunAnywhereTests",
            dependencies: [
                "RunAnywhere",
                // Backend runtimes so BackendRegistrationTests can exercise the
                // real plugin registry through each shipped XCFramework. MLX is
                // omitted: its MLXBackend module re-exposes commons headers whose
                // rac_vlm_result has drifted in the shipped RABackendMLX
                // xcframework, which clangs against CRACommons in one module.
                "LlamaCPPRuntime",
                "ONNXRuntime",
                "NeuRTRuntime",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "bindings/swift/Tests/RunAnywhereTests",
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
        // Use XCFrameworks from bindings/swift/Binaries/.
        // Regenerate them via: `./bindings/swift/scripts/build-core-xcframework.sh` at the
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
                path: "bindings/swift/Binaries/RACommons.xcframework"
            ),
            .binaryTarget(
                name: "RABackendLlamaCPPBinary",
                path: "bindings/swift/Binaries/RABackendLLAMACPP.xcframework"
            ),
            .binaryTarget(
                name: "RABackendONNXBinary",
                path: "bindings/swift/Binaries/RABackendONNX.xcframework"
            ),
            .binaryTarget(
                name: "RABackendSherpaBinary",
                path: "bindings/swift/Binaries/RABackendSherpa.xcframework"
            ),
            .binaryTarget(
                name: "RABackendNeuRTBinary",
                path: "bindings/swift/Binaries/RABackendNeuRT.xcframework"
            ),
            .binaryTarget(
                name: "RABackendMLXBinary",
                path: "bindings/swift/Binaries/RABackendMLX.xcframework"
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
        // a release. `bindings/swift/scripts/release-swift-binaries.sh` zips
        // `RABackendSherpa.xcframework` into `RABackendSherpa-ios-v<version>.zip`
        // and `bindings/swift/scripts/sync-checksums.sh` patches the checksum below.
        //
        // RELEASE PROCEDURE — checksums MUST be regenerated before tagging:
        //   1. Build XCFrameworks (CI native_ios job, or locally via
        //      `./bindings/swift/scripts/build-core-xcframework.sh`).
        //   2. Run `bindings/swift/scripts/sync-checksums.sh <zip_dir>` against the directory
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
        // `bindings/swift/scripts/sync-checksums.sh` and commit before re-tagging.
        // =====================================================================
        return [
            .binaryTarget(
                name: "RACommonsBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/RACommons-ios-v\(sdkVersion).zip",
                checksum: "928b55f04f91228840683766abfc9dfa33a315d269dd06482291ed6f294ba595"
            ),
            .binaryTarget(
                name: "RABackendLlamaCPPBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/RABackendLLAMACPP-ios-v\(sdkVersion).zip",
                checksum: "0597442fa030fe6eb69f2f01c63d098e090c0b60469847e2a2614bcf4d32210a"
            ),
            .binaryTarget(
                name: "RABackendONNXBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/RABackendONNX-ios-v\(sdkVersion).zip",
                checksum: "990dd26b4e743a63068c1c107e44e78fb83b234bef4806971da89defb34e2733"
            ),
            .binaryTarget(
                name: "RABackendSherpaBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/RABackendSherpa-ios-v\(sdkVersion).zip",
                checksum: "976029f81edd3ba95cd398fc3c2e6e45b6382ce8d128b0d43f103babab6baa81"
            ),
            // Apple CoreML Stable-Diffusion engine. `ONNXRuntime` declares an
            // unconditional dependency on this, so the remote list must carry it.
            // PLACEHOLDER checksum — `scripts/sync-checksums.sh` overwrites this
            // with the real SHA-256 of RABackendNeuRT-ios-v<version>.zip before
            // tagging (release choreography), exactly like the peers above.
            .binaryTarget(
                name: "RABackendNeuRTBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/RABackendNeuRT-ios-v\(sdkVersion).zip",
                checksum: "b85d91f0a6b24ffaa21affa5bc7cb9e5300451dfd2ae876af77c00972374e74d"
            ),
            .binaryTarget(
                name: "RABackendMLXBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/RABackendMLX-ios-v\(sdkVersion).zip",
                checksum: "0802fe58480c3e03e94498d46adb50fda7b9ade491807c7e0392a7fd68b83b59"
            ),
        ]
    }
}
