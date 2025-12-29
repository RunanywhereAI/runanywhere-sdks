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
// Set to `true` to use local XCFrameworks from Binaries/ directory (for local development/testing)
// Set to `false` to use remote XCFrameworks from GitHub releases (default for production use)
let testLocal = true  // Default to local for development during migration
// =============================================================================

let package = Package(
    name: "RunAnywhere",
    // NOTE: Platform minimums are set to support all modules.
    // Core SDK (RunAnywhere) has availability annotations for iOS 14+ / macOS 12+
    // Optional modules have higher requirements:
    //   - LlamaCPPRuntime: iOS 16+ / macOS 13+
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
        // Apple Foundation Models - Apple Intelligence (iOS 26+)
        // =================================================================
        .library(
            name: "RunAnywhereAppleAI",
            targets: ["FoundationModelsAdapter"]
        ),

    ],
    dependencies: [
        // Core SDK dependencies
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.9.0"),
        .package(url: "https://github.com/JohnSundell/Files.git", from: "4.3.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
        .package(url: "https://github.com/devicekit/DeviceKit.git", from: "5.6.0"),
        // Temporarily disabled to debug build issues
        // .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.57.1"),
        // SWCompression for pure Swift tar.bz2/tar.gz extraction
        .package(url: "https://github.com/tsolomko/SWCompression.git", from: "4.8.0"),
        // Sentry for crash reporting and error tracking
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.40.0"),
    ],
    targets: [
        // =================================================================
        // C Bridge Modules - Expose runanywhere-commons C APIs to Swift
        // =================================================================

        // CRACommons - Core commons C API bridge
        .target(
            name: "CRACommons",
            dependencies: ["RACommonsBinary"],
            path: "Sources/CRACommons",
            publicHeadersPath: "include"
        ),

        // CRABackendLlamaCPP - LlamaCPP backend C API bridge
        .target(
            name: "CRABackendLlamaCPP",
            dependencies: ["RABackendLlamaCPPBinary"],
            path: "Sources/CRABackendLlamaCPP",
            publicHeadersPath: "include"
        ),

        // CRABackendONNX - ONNX backend C API bridge
        .target(
            name: "CRABackendONNX",
            dependencies: ["RABackendONNXBinary", "ONNXRuntimeBinary"],
            path: "Sources/CRABackendONNX",
            publicHeadersPath: "include"
        ),

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
                .product(name: "DeviceKit", package: "DeviceKit"),
                .product(name: "SWCompression", package: "SWCompression"),
                .product(name: "Sentry", package: "sentry-cocoa"),
                // Link to new commons C bridge (RACommonsBinary is transitive via CRACommons)
                "CRACommons",
            ],
            path: "Sources/RunAnywhere",
            swiftSettings: [
                .define("SWIFT_PACKAGE")
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
            ]
        ),

        // =================================================================
        // ONNX Runtime Backend
        // Provides: STT (streaming), TTS, VAD
        // =================================================================
        .target(
            name: "ONNXRuntime",
            dependencies: [
                "RunAnywhere",
                "CRABackendONNX",
            ],
            path: "Sources/ONNXRuntime",
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedFramework("CoreML"),
                .linkedLibrary("archive"),
                .linkedLibrary("bz2"),
                // Use -ObjC instead of -all_load for smaller binary size
                .unsafeFlags(["-ObjC"]),
                // macOS requires linking against ONNX Runtime dylib (not statically included)
                .unsafeFlags([
                    "-L\(onnxRuntimeMacOSPath)",
                    "-lonnxruntime",
                    "-Wl,-rpath,\(onnxRuntimeMacOSPath)"
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
                "CRABackendLlamaCPP",
            ],
            path: "Sources/LlamaCPPRuntime",
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                // Use -ObjC instead of -all_load for smaller binary size
                .unsafeFlags(["-ObjC"])
            ]
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

    ] + binaryTargets()
)

// =============================================================================
// BINARY TARGET SELECTION
// =============================================================================
// This function returns the appropriate binary targets based on testLocal setting
func binaryTargets() -> [Target] {
    if testLocal {
        // Local development mode: Use XCFrameworks from Binaries/ directory
        // NOTE: You must build XCFrameworks using runanywhere-commons build scripts
        // or download from releases to use this mode
        return [
            // Core commons library (~1-2MB)
            .binaryTarget(
                name: "RACommonsBinary",
                path: "Binaries/RACommons.xcframework"
            ),
            // LlamaCPP backend (~30MB with all llama.cpp dependencies)
            .binaryTarget(
                name: "RABackendLlamaCPPBinary",
                path: "Binaries/RABackendLlamaCPP.xcframework"
            ),
            // ONNX backend wrapper (~400KB - links against ONNX Runtime)
            .binaryTarget(
                name: "RABackendONNXBinary",
                path: "Binaries/RABackendONNX.xcframework"
            ),
            // ONNX Runtime (~48MB - required for ONNX backend)
            .binaryTarget(
                name: "ONNXRuntimeBinary",
                path: "Binaries/onnxruntime.xcframework"
            ),
        ]
    } else {
        // Production mode (default): Download from GitHub releases
        // NOTE: Update URLs and checksums when new releases are published
        return [
            // Core commons library
            .binaryTarget(
                name: "RACommonsBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-binaries/releases/download/v2.0.0/RACommons.xcframework.zip",
                checksum: "PLACEHOLDER_CHECKSUM_RACommons"
            ),
            // LlamaCPP backend
            .binaryTarget(
                name: "RABackendLlamaCPPBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-binaries/releases/download/v2.0.0/RABackendLlamaCPP.xcframework.zip",
                checksum: "PLACEHOLDER_CHECKSUM_RABackendLlamaCPP"
            ),
            // ONNX backend wrapper
            .binaryTarget(
                name: "RABackendONNXBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-binaries/releases/download/v2.0.0/RABackendONNX.xcframework.zip",
                checksum: "PLACEHOLDER_CHECKSUM_RABackendONNX"
            ),
            // ONNX Runtime (required for ONNX backend)
            .binaryTarget(
                name: "ONNXRuntimeBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-binaries/releases/download/v2.0.0/onnxruntime.xcframework.zip",
                checksum: "PLACEHOLDER_CHECKSUM_ONNXRuntime"
            ),
        ]
    }
}
