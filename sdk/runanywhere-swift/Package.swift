// swift-tools-version: 5.9
import PackageDescription
import Foundation

// =============================================================================
// PATH CONFIGURATION
// =============================================================================
// Get the package directory for relative path resolution
let packageDir = URL(fileURLWithPath: #file).deletingLastPathComponent().path

// Path to bundled ONNX Runtime dylib with CoreML support (for macOS)
let onnxRuntimeMacOSPath = "\(packageDir)/Binaries/onnxruntime-macos"

// =============================================================================
// BINARY TARGET CONFIGURATION
// =============================================================================
// Set to `true` to use local XCFramework from Binaries/ directory (for local development/testing)
// Set to `false` to use remote XCFramework from GitHub releases (default for production use)
let testLocal = false
// =============================================================================

let package = Package(
    name: "RunAnywhere",
    // NOTE: Platform minimums are set to support all modules.
    // Core SDK (RunAnywhere) has availability annotations for iOS 14+ / macOS 12+
    // Optional modules have higher requirements:
    //   - WhisperKit, LlamaCPPRuntime: iOS 16+ / macOS 13+
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
        // LlamaCPP Backend - adds LLM text generation
        // Uses GGUF models with Metal acceleration
        // =================================================================
        .library(
            name: "RunAnywhereLlamaCPP",
            targets: ["LlamaCPPRuntime"]
        ),

        // =================================================================
        // WhisperKit Backend - CoreML-based STT (iOS 16+)
        // =================================================================
        .library(
            name: "RunAnywhereWhisperKit",
            targets: ["WhisperKitTranscription"]
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
        // C Bridge Module - Exposes unified xcframework C APIs to Swift
        // =================================================================
        .target(
            name: "CRunAnywhereCore",
            dependencies: ["RunAnywhereCoreBinary"],
            path: "Sources/CRunAnywhereCore",
            publicHeadersPath: "include"
        ),

        // =================================================================
        // ONNX Runtime Backend
        // Provides: STT (streaming), TTS, VAD, Speaker Diarization
        // NOTE: For macOS, ONNX Runtime is dynamically linked (not in xcframework).
        //       For development: brew install onnxruntime
        //       For production: embed Binaries/onnxruntime-macos/libonnxruntime.dylib
        //                       in YourApp.app/Contents/Frameworks/
        // =================================================================
        .target(
            name: "ONNXRuntime",
            dependencies: [
                "RunAnywhere",
                "CRunAnywhereCore",
                "RunAnywhereCoreBinary",
            ],
            path: "Sources/ONNXRuntime",
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedLibrary("archive"),
                .linkedLibrary("bz2"),
                .unsafeFlags(["-ObjC", "-all_load"]),
                // macOS requires linking against ONNX Runtime dylib (not statically included)
                // Note: Homebrew version may not include CoreML provider
                // For production: embed libonnxruntime.dylib with CoreML support in YourApp.app/Contents/Frameworks/
                .unsafeFlags([
                    "-L\(onnxRuntimeMacOSPath)",
                    "-lonnxruntime",
                    "-Wl,-rpath,\(onnxRuntimeMacOSPath)",
                    // Allow undefined symbols to be resolved at runtime (for optional CoreML provider)
                    // This prevents linker errors when CoreML provider is not available
                    "-Wl,-undefined,dynamic_lookup"
                ], .when(platforms: [.macOS])),
            ]
        ),

        // =================================================================
        // LlamaCPP Runtime Backend
        // Provides: Text Generation (LLM) with GGUF models
        // =================================================================
        .target(
            name: "LlamaCPPRuntime",
            dependencies: [
                "RunAnywhere",
                "CRunAnywhereCore",
                "RunAnywhereCoreBinary",
            ],
            path: "Sources/LlamaCPPRuntime",
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .unsafeFlags(["-ObjC", "-all_load"])
            ]
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
    ] + binaryTargets()
)

// =============================================================================
// BINARY TARGET SELECTION
// =============================================================================
// This function returns the appropriate binary target based on testLocal setting
func binaryTargets() -> [Target] {
    if testLocal {
        // Local development mode: Use XCFramework from Binaries/ directory
        // NOTE: You must manually place RunAnywhereCore.xcframework in Binaries/
        // to use this mode (download from runanywhere-binaries releases)
        return [
            .binaryTarget(
                name: "RunAnywhereCoreBinary",
                path: "Binaries/RunAnywhereCore.xcframework"
            )
        ]
    } else {
        // Production mode (default): Download from GitHub releases
        return [
            .binaryTarget(
                name: "RunAnywhereCoreBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-binaries/releases/download/v0.0.1-dev.e6b7a2f/RunAnywhereCore.xcframework.zip",
                checksum: "0786d494553226820a3a19ba5ee573d4bedf4096b9ebfae9010b621952bb617b"
            )
        ]
    }
}
