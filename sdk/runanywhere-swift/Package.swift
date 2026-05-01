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
        // target plus the four runtime backends so that a single product
        // import pulls in the whole stack for local example apps.
        // -------------------------------------------------------------------
        .library(
            name: "RunAnywhere",
            targets: [
                "RunAnywhere",
                "LlamaCPPRuntime",
                "ONNXRuntime",
                "MetalRTRuntime",
                "WhisperKitRuntime",
            ]
        ),

        // Individual backend products (used by the example apps that only
        // want to link a subset of the runtimes).
        .library(name: "RunAnywhereCore", targets: ["RunAnywhere"]),
        .library(name: "RunAnywhereLlamaCPP", targets: ["LlamaCPPRuntime"]),
        .library(name: "RunAnywhereONNX", targets: ["ONNXRuntime"]),
        .library(name: "RunAnywhereMetalRT", targets: ["MetalRTRuntime"]),
        .library(name: "RunAnywhereWhisperKit", targets: ["WhisperKitRuntime"]),
    ],
    dependencies: [
        // Pins mirror `Package.resolved`.
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/JohnSundell/Files.git", from: "4.3.0"),
        .package(url: "https://github.com/devicekit/DeviceKit.git", from: "5.6.0"),
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.40.0"),
        // ml-stable-diffusion powers the CoreML-based image generation path
        // imported as `StableDiffusion` from the RunAnywhere core target.
        .package(url: "https://github.com/apple/ml-stable-diffusion.git", from: "1.1.0"),
        // WhisperKit is referenced from WhisperKitRuntime/WhisperKitSTTService.swift
        // (`import WhisperKit`). Pin conservatively at 0.9.0+ to match the
        // root-level Package.swift.
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
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
        // -------------------------------------------------------------------
        .target(
            name: "LlamaCPPBackend",
            dependencies: ["RABackendLlamaCPPBinary"],
            path: "Sources/LlamaCPPRuntime/include",
            publicHeadersPath: "."
        ),

        // -------------------------------------------------------------------
        // C Bridge Module — ONNX Backend Headers
        // Depends on RABackendONNXBinary (ONNX Runtime now statically linked
        // into the xcframework, so no separate ort binaries needed) plus the
        // Sherpa-ONNX binary, which is consumed by the ONNX runtime target
        // for STT/TTS/VAD pipelines.
        // -------------------------------------------------------------------
        .target(
            name: "ONNXBackend",
            dependencies: [
                "RABackendONNXBinary",
                "RABackendSherpaBinary",
            ],
            path: "Sources/ONNXRuntime/include",
            publicHeadersPath: "."
        ),

        // -------------------------------------------------------------------
        // C Bridge Module — MetalRT Backend Headers
        // -------------------------------------------------------------------
        .target(
            name: "MetalRTBackend",
            dependencies: ["RABackendMetalRTBinary"],
            path: "Sources/MetalRTRuntime/include",
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
                .product(name: "StableDiffusion", package: "ml-stable-diffusion"),
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
                // *.grpc.swift imports GRPCCore/GRPCProtobuf and requires
                // macOS 15 / iOS 18. Our minimum platforms are macOS 14 /
                // iOS 17, so exclude the generated gRPC client stubs. The
                // hand-written VoiceAgentStreamAdapter exposes the same
                // AsyncStream surface without requiring grpc-swift v2.
                "Generated/voice_agent_service.grpc.swift",
                "Generated/llm_service.grpc.swift",
                "Generated/download_service.grpc.swift",
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
            exclude: ["include"],
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
            exclude: ["include"],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedFramework("CoreML"),
                .linkedLibrary("archive"),
                .linkedLibrary("bz2"),
            ]
        ),

        // -------------------------------------------------------------------
        // MetalRT Runtime Backend (custom Metal GPU kernels)
        // -------------------------------------------------------------------
        .target(
            name: "MetalRTRuntime",
            dependencies: [
                "RunAnywhere",
                "MetalRTBackend",
                "RABackendMetalRTBinary",
            ],
            path: "Sources/MetalRTRuntime",
            exclude: ["include"],
            resources: [
                .copy("Resources/default.metallib"),
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ImageIO"),
            ]
        ),

        // -------------------------------------------------------------------
        // WhisperKit Runtime Backend (Apple Neural Engine STT)
        // -------------------------------------------------------------------
        .target(
            name: "WhisperKitRuntime",
            dependencies: [
                "RunAnywhere",
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Sources/WhisperKitRuntime",
            linkerSettings: [
                .linkedFramework("CoreML"),
                .linkedFramework("Accelerate"),
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
            name: "RABackendMetalRTBinary",
            path: "Binaries/RABackendMetalRT.xcframework"
        ),
        .binaryTarget(
            name: "RABackendSherpaBinary",
            path: "Binaries/RABackendSherpa.xcframework"
        ),
    ]
)
