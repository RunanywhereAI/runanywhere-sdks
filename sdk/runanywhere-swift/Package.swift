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
//
// testLocal = true  → Use local XCFrameworks from Binaries/ directory
//                     (for local development when building runanywhere-commons)
//
// testLocal = false → Download XCFrameworks from GitHub releases (PRODUCTION)
//                     (default for end users and CI/CD)
//
// =============================================================================
let testLocal = false
// =============================================================================

let package = Package(
    name: "RunAnywhere",
    // NOTE: Platform minimums are set to support all modules.
    // Core SDK (RunAnywhere) has availability annotations for iOS 14+ / macOS 12+
    // Optional modules have higher requirements:
    //   - LlamaCPPRuntime: iOS 16+ / macOS 13+
    //   - SystemFoundationModels: iOS 26+ runtime (builds on iOS 17+)
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
        // Single unified module (C headers + Swift)
        // =================================================================
        .library(
            name: "RunAnywhereONNX",
            targets: ["ONNXRuntime"]
        ),

        // =================================================================
        // LlamaCPP Backend - adds LLM text generation
        // Single unified module (C headers + Swift)
        // =================================================================
        .library(
            name: "RunAnywhereLlamaCPP",
            targets: ["LlamaCPPRuntime"]
        ),

    ],
    dependencies: [
        // Core SDK dependencies
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.9.0"),
        .package(url: "https://github.com/JohnSundell/Files.git", from: "4.3.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
        .package(url: "https://github.com/devicekit/DeviceKit.git", from: "5.6.0"),
        // SWCompression for pure Swift tar.bz2/tar.gz extraction
        .package(url: "https://github.com/tsolomko/SWCompression.git", from: "4.8.0"),
        // Sentry for crash reporting and error tracking
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.40.0"),
    ],
    targets: [
        // =================================================================
        // C Bridge Module - Core Commons
        // Exposes runanywhere-commons C APIs to Swift
        // =================================================================
        .target(
            name: "CRACommons",
            dependencies: ["RACommonsBinary"],
            path: "Sources/CRACommons",
            publicHeadersPath: "include"
        ),

        // =================================================================
        // C Bridge Module - LlamaCPP Backend Headers
        // Exposes LlamaCPP backend C APIs
        // =================================================================
        .target(
            name: "LlamaCPPBackend",
            dependencies: ["RABackendLlamaCPPBinary"],
            path: "Sources/LlamaCPPRuntime/include",
            publicHeadersPath: "."
        ),

        // =================================================================
        // C Bridge Module - ONNX Backend Headers
        // Exposes ONNX backend C APIs
        // =================================================================
        .target(
            name: "ONNXBackend",
            dependencies: ["RABackendONNXBinary", "ONNXRuntimeBinary"],
            path: "Sources/ONNXRuntime/include",
            publicHeadersPath: "."
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
                // Link to commons C bridge
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
        // ONNX Runtime Backend (Unified Module)
        // C headers in include/, Swift sources in root
        // Provides: STT (streaming), TTS, VAD
        // =================================================================
        .target(
            name: "ONNXRuntime",
            dependencies: [
                "RunAnywhere",
                "ONNXBackend",  // C headers
            ],
            path: "Sources/ONNXRuntime",
            exclude: ["include"],  // Exclude include/ from Swift sources
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
        // LlamaCPP Runtime Backend (Unified Module)
        // C headers in include/, Swift sources in root
        // Provides: Text Generation (LLM) with GGUF models
        // =================================================================
        .target(
            name: "LlamaCPPRuntime",
            dependencies: [
                "RunAnywhere",
                "LlamaCPPBackend",  // C headers
            ],
            path: "Sources/LlamaCPPRuntime",
            exclude: ["include"],  // Exclude include/ from Swift sources
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                // Use -ObjC instead of -all_load for smaller binary size
                .unsafeFlags(["-ObjC"])
            ]
        ),

    ] + binaryTargets()
)

// =============================================================================
// BINARY TARGET SELECTION
// =============================================================================
// Version constants for remote XCFrameworks
let commonsVersion = "0.1.0"
let coreVersion = "0.1.1-dev.03aacf9"

// This function returns the appropriate binary targets based on testLocal setting
func binaryTargets() -> [Target] {
    if testLocal {
        // Local development mode: Use XCFrameworks from Binaries/ directory
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
        // Commons frameworks from runanywhere-sdks releases
        // ONNX Runtime from runanywhere-binaries releases (core dependency)
        return [
            // Core commons library (~2MB)
            .binaryTarget(
                name: "RACommonsBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/commons-v\(commonsVersion)/RACommons-\(commonsVersion).zip",
                checksum: "9a0149da28fe348f6b9843ccb98d75a0046180a4471b887702d54ca60150a3d9"
            ),
            // LlamaCPP backend (~30MB with Metal)
            .binaryTarget(
                name: "RABackendLlamaCPPBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/commons-v\(commonsVersion)/RABackendLlamaCPP-\(commonsVersion).zip",
                checksum: "352774858112b97a41eacff2bf8c425b8ee3d135620af6673282777fc5626845"
            ),
            // ONNX backend wrapper (~12MB with Sherpa-ONNX)
            .binaryTarget(
                name: "RABackendONNXBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/commons-v\(commonsVersion)/RABackendONNX-\(commonsVersion).zip",
                checksum: "af91e45667c1a1786f124daf2be8790d48fa055027b62e018765d954afed84a6"
            ),
            // ONNX Runtime (~48MB - from runanywhere-binaries/core releases)
            .binaryTarget(
                name: "ONNXRuntimeBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-binaries/releases/download/core-v\(coreVersion)/onnxruntime-ios-v\(coreVersion).zip",
                checksum: "3c71a9065616371bdbd095ba8d7a10d86f474dd09a825c11b62efd92c58a0e47"
            ),
        ]
    }
}
