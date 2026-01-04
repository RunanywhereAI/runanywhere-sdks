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
let testLocal = false  // PRODUCTION: download XCFrameworks from GitHub releases

// Version constants for remote XCFrameworks (must be defined before package)
let commonsVersion = "0.1.1"
let coreVersion = "0.2.4"
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
        // Note: RABackendONNX requires RunAnywhereCore for ra_create_backend symbols
        // =================================================================
        .target(
            name: "ONNXBackend",
            dependencies: onnxBackendDependencies(),
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
// HELPER FUNCTIONS
// =============================================================================

// ONNXBackend dependencies
// Note: RABackendONNX already includes runanywhere_bridge symbols (ra_create_backend, etc.)
// so we don't need to link RunAnywhereCore separately
func onnxBackendDependencies() -> [Target.Dependency] {
    return ["RABackendONNXBinary", "ONNXRuntimeBinary"]
}

// =============================================================================
// BINARY TARGET SELECTION
// =============================================================================
// This function returns the appropriate binary targets based on testLocal setting
// NOTE: When testLocal = true, only commons frameworks are local.
//       RunAnywhereCore and onnxruntime always come from remote releases.
func binaryTargets() -> [Target] {
    if testLocal {
        // Local development mode: All runanywhere frameworks are local
        // Only ONNX Runtime comes from official source
        return [
            // Local commons framework (built locally from runanywhere-commons)
            .binaryTarget(
                name: "RACommonsBinary",
                path: "Binaries/RACommons.xcframework"
            ),
            // LlamaCPP backend (built locally from runanywhere-core)
            .binaryTarget(
                name: "RABackendLlamaCPPBinary",
                path: "Binaries/RABackendLLAMACPP.xcframework"
            ),
            // ONNX backend (built locally from runanywhere-core)
            .binaryTarget(
                name: "RABackendONNXBinary",
                path: "Binaries/RABackendONNX.xcframework"
            ),
            // ONNX Runtime from official source
            .binaryTarget(
                name: "ONNXRuntimeBinary",
                url: "https://download.onnxruntime.ai/pod-archive-onnxruntime-c-1.17.1.zip",
                checksum: "9a2d54d4f503fbb82d2f86361a1d22d4fe015e2b5e9fb419767209cc9ab6372c"
            ),
        ]
    } else {
        // Production mode (default): Download from GitHub releases
        // Commons from runanywhere-sdks releases
        // Backend frameworks from runanywhere-binaries releases
        return [
            // =================================================================
            // RACommons - Core infrastructure library
            // Source: runanywhere-sdks/releases (commons-v*)
            // =================================================================
            .binaryTarget(
                name: "RACommonsBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/commons-v\(commonsVersion)/RACommons-ios-v\(commonsVersion).zip",
                checksum: "f515b4711d5e42003deb6dedbf969f437186945ec188e794c21a4b9e266b2780"
            ),
            // =================================================================
            // RABackendLlamaCPP - LLM text generation backend
            // Source: runanywhere-binaries/releases (core-v*)
            // =================================================================
            .binaryTarget(
                name: "RABackendLlamaCPPBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-binaries/releases/download/core-v\(coreVersion)/RABackendLlamaCPP-ios-v\(coreVersion).zip",
                checksum: "31a8b7e129ad6197e898d538a4c882a9f4717bad8a9694b842e49a676efd6142"
            ),
            // =================================================================
            // RABackendONNX - STT/TTS/VAD backend (includes Sherpa-ONNX)
            // Source: runanywhere-binaries/releases (core-v*)
            // =================================================================
            .binaryTarget(
                name: "RABackendONNXBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-binaries/releases/download/core-v\(coreVersion)/RABackendONNX-ios-v\(coreVersion).zip",
                checksum: "a2ada60f35c4a318d852ef04e08a1e5fdfbd646bcaf6058929203ced8ac98815"
            ),
            // =================================================================
            // ONNX Runtime - Required by RABackendONNX
            // Source: Official ONNX Runtime releases from onnxruntime.ai
            // Contains xcframework with CoreML support
            // =================================================================
            .binaryTarget(
                name: "ONNXRuntimeBinary",
                url: "https://download.onnxruntime.ai/pod-archive-onnxruntime-c-1.17.1.zip",
                checksum: "9a2d54d4f503fbb82d2f86361a1d22d4fe015e2b5e9fb419767209cc9ab6372c"
            ),
        ]
    }
}
