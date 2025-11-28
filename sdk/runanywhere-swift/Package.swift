// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RunAnywhere",
    // NOTE: Platform minimums are set to support all modules.
    // Core SDK (RunAnywhere) has availability annotations for iOS 14+ / macOS 12+
    // Optional modules have higher requirements:
    //   - WhisperKit, LLMSwift: iOS 16+ / macOS 13+
    //   - FluidAudio: iOS 17+ / macOS 14+
    //   - AppleAI: iOS 26+ runtime (builds on iOS 16+)
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10)
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
        // Includes ~70MB binary download
        // =================================================================
        .library(
            name: "RunAnywhereONNX",
            targets: ["ONNXRuntime"]
        ),

        // =================================================================
        // WhisperKit Backend - CoreML-based STT (iOS 16+)
        // =================================================================
        .library(
            name: "RunAnywhereWhisperKit",
            targets: ["WhisperKitTranscription"]
        ),

        // =================================================================
        // LLM.swift Backend - Local LLM inference (iOS 16+)
        // =================================================================
        .library(
            name: "RunAnywhereLLM",
            targets: ["LLMSwift"]
        ),

        // =================================================================
        // Apple Foundation Models - Apple Intelligence (iOS 26+)
        // =================================================================
        .library(
            name: "RunAnywhereAppleAI",
            targets: ["FoundationModelsAdapter"]
        ),

        // =================================================================
        // FluidAudio - Speaker Diarization (iOS 17+)
        // =================================================================
        .library(
            name: "RunAnywhereFluidAudio",
            targets: ["FluidAudioDiarization"]
        ),
    ],
    dependencies: [
        // Core SDK dependencies
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.9.0"),
        .package(url: "https://github.com/JohnSundell/Files.git", from: "4.3.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.6.1"),
        .package(url: "https://github.com/devicekit/DeviceKit.git", from: "5.6.0"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.57.1"),
        .package(url: "https://github.com/kean/Pulse", from: "4.0.0"),

        // WhisperKit dependency
        .package(url: "https://github.com/argmaxinc/WhisperKit", exact: "0.13.1"),

        // LLM.swift dependency
        .package(url: "https://github.com/eastriverlee/LLM.swift", from: "2.0.1"),

        // FluidAudio dependency
        .package(url: "https://github.com/FluidInference/FluidAudio.git", branch: "main"),
    ],
    targets: [
        // =================================================================
        // Core SDK
        // =================================================================
        .target(
            name: "RunAnywhere",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "Files", package: "Files"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "DeviceKit", package: "DeviceKit"),
                .product(name: "Pulse", package: "Pulse"),
            ],
            path: "Sources/RunAnywhere",
            exclude: [
                "Data/README.md",
                "Data/Storage/Database/README.md"
            ],
            swiftSettings: [
                .define("SWIFT_PACKAGE")
            ]
        ),

        // =================================================================
        // ONNX Runtime Backend
        // Provides: STT (streaming), TTS, VAD, Speaker Diarization
        // =================================================================
        .target(
            name: "ONNXRuntime",
            dependencies: [
                "RunAnywhere",
                "CRunAnywhereONNX",
                "RunAnywhereONNXBinary",
            ],
            path: "Sources/ONNXRuntime",
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedLibrary("archive"),
                .linkedLibrary("bz2"),
                .unsafeFlags(["-ObjC", "-all_load"])
            ]
        ),

        // C bridge wrapper for ONNX (imports headers from xcframework)
        .target(
            name: "CRunAnywhereONNX",
            dependencies: [],
            path: "Sources/CRunAnywhereONNX",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include")
            ]
        ),

        // ONNX Runtime Binary (downloaded from runanywhere-binaries)
        // Includes: ONNX Runtime + Sherpa-ONNX + Bridge layer
        .binaryTarget(
            name: "RunAnywhereONNXBinary",
            url: "https://github.com/RunanywhereAI/runanywhere-binaries/releases/download/v0.0.1-dev.27a4832-sherpa/RunAnywhereONNX.xcframework.zip",
            checksum: "62b2887a6d53360ed8d96a5080a98419d3c486f6be94bfe5e9f82415bb6a1fbe"
        ),

        // =================================================================
        // WhisperKit Backend (iOS 16+, macOS 13+)
        // Provides: CoreML-based Speech-to-Text
        // =================================================================
        .target(
            name: "WhisperKitTranscription",
            dependencies: [
                "RunAnywhere",
                "WhisperKit",
            ],
            path: "Sources/WhisperKitTranscription"
        ),

        // =================================================================
        // LLM.swift Backend (iOS 16+, macOS 13+)
        // Provides: Local LLM inference with GGUF models
        // =================================================================
        .target(
            name: "LLMSwift",
            dependencies: [
                "RunAnywhere",
                .product(name: "LLM", package: "LLM.swift"),
            ],
            path: "Sources/LLMSwift"
        ),

        // =================================================================
        // Apple Foundation Models (iOS 16+ build, iOS 26+ runtime)
        // Provides: Apple Intelligence integration
        // =================================================================
        .target(
            name: "FoundationModelsAdapter",
            dependencies: [
                "RunAnywhere",
            ],
            path: "Sources/FoundationModelsAdapter"
        ),

        // =================================================================
        // FluidAudio Diarization (iOS 17+, macOS 14+)
        // Provides: Speaker diarization
        // =================================================================
        .target(
            name: "FluidAudioDiarization",
            dependencies: [
                "RunAnywhere",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/FluidAudioDiarization"
        ),
    ]
)
