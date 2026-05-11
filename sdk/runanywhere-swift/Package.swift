// swift-tools-version: 5.9
import PackageDescription

// =============================================================================
// RunAnywhere Swift SDK — LOCAL development Package.swift
// =============================================================================
//
// This Package.swift lives inside `sdk/runanywhere-swift/` and uses LOCAL
// XCFrameworks from the sibling `Binaries/` directory. It is the counterpart
// to the root-level `Package.swift`, which is the one published to SPM
// consumers and downloads the XCFrameworks from GitHub releases.
//
// Paths in this file are relative to `sdk/runanywhere-swift/`, NOT to the
// repository root. For example `Sources/RunAnywhere` here is the same tree
// that the root-level package refers to as
// `sdk/runanywhere-swift/Sources/RunAnywhere`.
//
// Min platforms: iOS 17 / macOS 14 (matches the root package).
// =============================================================================

let package = Package(
    name: "RunAnywhere",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        // -------------------------------------------------------------------
        // Core SDK — always needed. The `RunAnywhere` library vends the core
        // target plus the two runtime backends so that a single product
        // import pulls in the whole stack for local example apps.
        // -------------------------------------------------------------------
        .library(
            name: "RunAnywhere",
            targets: [
                "RunAnywhere",
                "LlamaCPPRuntime",
                "ONNXRuntime",
            ]
        ),

        // Individual backend products (used by the example apps that only
        // want to link a subset of the runtimes).
        .library(name: "RunAnywhereCore", targets: ["RunAnywhere"]),
        .library(name: "RunAnywhereLlamaCPP", targets: ["LlamaCPPRuntime"]),
        .library(name: "RunAnywhereONNX", targets: ["ONNXRuntime"]),
    ],
    dependencies: [
        // Pins mirror `Package.resolved`.
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/JohnSundell/Files.git", from: "4.3.0"),
        .package(url: "https://github.com/devicekit/DeviceKit.git", from: "5.6.0"),
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.40.0"),
        // swift-protobuf is consumed by the pb.swift files generated from
        // idl/*.proto in Sources/RunAnywhere/Generated/.
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.27.0"),
    ],
    targets: [
        // -------------------------------------------------------------------
        // C Bridge Module — Core Commons
        // -------------------------------------------------------------------
        .target(
            name: "CRACommons",
            dependencies: ["RACommonsBinary"],
            path: "Sources/RunAnywhere/CRACommons",
            publicHeadersPath: "include"
        ),

        // -------------------------------------------------------------------
        // C Bridge Module — LlamaCPP Backend Headers
        //
        // Depends on CRACommons so the backend registration header can pull
        // `rac_types.h` / `rac_error.h` / `rac_llm.h` from the single source
        // of truth instead of carrying drifting local copies.
        // -------------------------------------------------------------------
        .target(
            name: "LlamaCPPBackend",
            dependencies: [
                "CRACommons",
                "RABackendLlamaCPPBinary",
            ],
            path: "Sources/LlamaCPPRuntime/include",
            publicHeadersPath: "."
        ),

        // -------------------------------------------------------------------
        // C Bridge Module — ONNX Backend Headers
        //
        // Depends on CRACommons so the registration header pulls `rac_types.h`
        // / `rac_result_t` from the single source of truth. The xcframework
        // dependencies (RABackendONNX + RABackendSherpa) carry the actual
        // symbol bodies.
        // -------------------------------------------------------------------
        .target(
            name: "ONNXBackend",
            dependencies: [
                "CRACommons",
                "RABackendONNXBinary",
                "RABackendSherpaBinary",
            ],
            path: "Sources/ONNXRuntime/include",
            publicHeadersPath: "."
        ),

        // -------------------------------------------------------------------
        // Core SDK target
        // -------------------------------------------------------------------
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
            path: "Sources/RunAnywhere",
            exclude: [
                // CRACommons is declared as its own sibling target above;
                // exclude from this target's source list to avoid a double
                // compile.
                "CRACommons",
                // SWF-grpc delete (Wave H-2): the previously-excluded
                // `Generated/{voice_agent_service,llm_service,download_service}.grpc.swift`
                // files are no longer emitted by `idl/codegen/generate_swift.sh` and
                // have been removed from the repo. The hand-written VoiceAgentStreamAdapter /
                // LLMStreamAdapter expose the same AsyncStream surface over the
                // in-process C callback, so no compilation target needs them.
                //
                // SWIFT-DUP-UNUSED-PROTO-TYPES (Wave 6A / T8): the two proto
                // schemas below are still emitted by codegen but have zero
                // consumers in the Swift SDK. Excluding them avoids compiling
                // ~2154 lines of dead generated code. Keep `pipeline.pb.swift`
                // and `solutions.pb.swift` — those are consumed via the
                // Solutions facade.
                "Generated/router.pb.swift",
                "Generated/diffusion_options.pb.swift",
            ],
            swiftSettings: [
                .define("SWIFT_PACKAGE"),
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

        // -------------------------------------------------------------------
        // LlamaCPP Runtime Backend
        // -------------------------------------------------------------------
        .target(
            name: "LlamaCPPRuntime",
            dependencies: [
                "RunAnywhere",
                "LlamaCPPBackend",
                "RABackendLlamaCPPBinary",
            ],
            path: "Sources/LlamaCPPRuntime",
            exclude: [
                "include",
                // Stray docs file picked up by SwiftPM as an unhandled
                // resource. Silence the "unhandled file(s)" warning.
                "README.md",
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
            ]
        ),

        // -------------------------------------------------------------------
        // ONNX Runtime Backend (STT/TTS/VAD)
        // -------------------------------------------------------------------
        .target(
            name: "ONNXRuntime",
            dependencies: [
                "RunAnywhere",
                "ONNXBackend",
                "RABackendONNXBinary",
                "RABackendSherpaBinary",
            ],
            path: "Sources/ONNXRuntime",
            exclude: [
                "include",
                // Stray docs file picked up by SwiftPM as an unhandled
                // resource. Silence the "unhandled file(s)" warning.
                "README.md",
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedFramework("CoreML"),
                .linkedLibrary("archive"),
                .linkedLibrary("bz2"),
            ]
        ),

        // -------------------------------------------------------------------
        // Unit tests (AudioCaptureManager — see Issue #198)
        // -------------------------------------------------------------------
        .testTarget(
            name: "RunAnywhereTests",
            dependencies: ["RunAnywhere"],
            path: "Tests/RunAnywhereTests"
        ),

        // -------------------------------------------------------------------
        // Binary targets (local XCFrameworks under Binaries/)
        // -------------------------------------------------------------------
        .binaryTarget(
            name: "RACommonsBinary",
            path: "Binaries/RACommons.xcframework"
        ),
        .binaryTarget(
            name: "RABackendLlamaCPPBinary",
            path: "Binaries/RABackendLLAMACPP.xcframework"
        ),
        .binaryTarget(
            name: "RABackendONNXBinary",
            path: "Binaries/RABackendONNX.xcframework"
        ),
        .binaryTarget(
            name: "RABackendSherpaBinary",
            path: "Binaries/RABackendSherpa.xcframework"
        ),
    ]
)
