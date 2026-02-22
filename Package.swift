// swift-tools-version: 5.9
import PackageDescription
import Foundation

// =============================================================================
// RunAnywhere SDK - Swift Package Manager Distribution
// =============================================================================
//
// This is the SINGLE Package.swift for both local development and SPM consumption.
//
// FOR EXTERNAL USERS (consuming via GitHub):
//   .package(url: "https://github.com/RunanywhereAI/runanywhere-sdks", from: "0.17.0")
//
// FOR LOCAL DEVELOPMENT:
//   1. Run: cd sdk/runanywhere-swift && ./scripts/build-swift.sh --setup
//   2. Open the example app in Xcode
//   3. The app references this package via relative path
//
// =============================================================================

// Combined ONNX Runtime xcframework (local dev) is created by:
//   cd sdk/runanywhere-swift && ./scripts/create-onnxruntime-xcframework.sh

// =============================================================================
// BINARY TARGET CONFIGURATION
// =============================================================================
//
// useLocalBinaries = true  → Use local XCFrameworks from sdk/runanywhere-swift/Binaries/
//                            For local development. Run first-time setup:
//                              cd sdk/runanywhere-swift && ./scripts/build-swift.sh --setup
//
// useLocalBinaries = false → Download XCFrameworks from GitHub releases (PRODUCTION)
//                            For external users via SPM. No setup needed.
//
// To toggle this value, use:
//   ./scripts/build-swift.sh --set-local   (sets useLocalBinaries = true)
//   ./scripts/build-swift.sh --set-remote  (sets useLocalBinaries = false)
//
// =============================================================================
let useLocalBinaries = false //  Toggle: true for local dev, false for release

// Version for remote XCFrameworks (used when testLocal = false)
// Updated automatically by CI/CD during releases
let sdkVersion = "0.19.2"

let package = Package(
    name: "runanywhere-sdks",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
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
        // WhisperKit Backend - adds STT via Apple Neural Engine
        // =================================================================
        .library(
            name: "RunAnywhereWhisperKit",
            targets: ["WhisperKitRuntime"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.9.0"),
        .package(url: "https://github.com/JohnSundell/Files.git", from: "4.3.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
        .package(url: "https://github.com/devicekit/DeviceKit.git", from: "5.6.0"),
        .package(url: "https://github.com/tsolomko/SWCompression.git", from: "4.8.0"),
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.40.0"),
        // ml-stable-diffusion for CoreML-based image generation
        .package(url: "https://github.com/apple/ml-stable-diffusion.git", from: "1.1.0"),
        // WhisperKit for Neural Engine STT
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        // =================================================================
        // C Bridge Module - Core Commons
        // =================================================================
        .target(
            name: "CRACommons",
            dependencies: ["RACommonsBinary"],
            path: "sdk/runanywhere-swift/Sources/RunAnywhere/CRACommons",
            publicHeadersPath: "include"
        ),

        // =================================================================
        // C Bridge Module - LlamaCPP Backend Headers
        // =================================================================
        .target(
            name: "LlamaCPPBackend",
            dependencies: ["RABackendLlamaCPPBinary"],
            path: "sdk/runanywhere-swift/Sources/LlamaCPPRuntime/include",
            publicHeadersPath: "."
        ),

        // =================================================================
        // C Bridge Module - ONNX Backend Headers
        // =================================================================
        .target(
            name: "ONNXBackend",
            dependencies: ["RABackendONNXBinary", "ONNXRuntimeBinary"],
            path: "sdk/runanywhere-swift/Sources/ONNXRuntime/include",
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
                .product(name: "StableDiffusion", package: "ml-stable-diffusion"),
                "CRACommons",
            ],
            path: "sdk/runanywhere-swift/Sources/RunAnywhere",
            exclude: ["CRACommons"],
            swiftSettings: [
                .define("SWIFT_PACKAGE")
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
            ]
        ),

        // =================================================================
        // ONNX Runtime Backend
        // =================================================================
        .target(
            name: "ONNXRuntime",
            dependencies: [
                "RunAnywhere",
                "ONNXBackend",
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

        // =================================================================
        // LlamaCPP Runtime Backend
        // =================================================================
        .target(
            name: "LlamaCPPRuntime",
            dependencies: [
                "RunAnywhere",
                "LlamaCPPBackend",
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

        // =================================================================
        // WhisperKit Runtime Backend (Apple Neural Engine STT)
        // =================================================================
        .target(
            name: "WhisperKitRuntime",
            dependencies: [
                "RunAnywhere",
                .product(name: "WhisperKit", package: "whisperkit"),
            ],
            path: "sdk/runanywhere-swift/Sources/WhisperKitRuntime",
            linkerSettings: [
                .linkedFramework("CoreML"),
                .linkedFramework("Accelerate"),
            ]
        ),

        // =================================================================
        // RunAnywhere unit tests (e.g. AudioCaptureManager – Issue #198)
        // =================================================================
        .testTarget(
            name: "RunAnywhereTests",
            dependencies: ["RunAnywhere"],
            path: "sdk/runanywhere-swift/Tests/RunAnywhereTests"
        ),

    ] + binaryTargets()
)

// =============================================================================
// BINARY TARGET SELECTION
// =============================================================================
// Returns local or remote binary targets based on useLocalBinaries setting
func binaryTargets() -> [Target] {
    if useLocalBinaries {
        // =====================================================================
        // LOCAL DEVELOPMENT MODE
        // Use XCFrameworks from sdk/runanywhere-swift/Binaries/
        // Run: cd sdk/runanywhere-swift && ./scripts/build-swift.sh --setup
        //
        // For macOS support, build with --include-macos:
        //   ./scripts/build-swift.sh --setup --include-macos
        // =====================================================================
        var targets: [Target] = [
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
        ]

        // Local combined ONNX Runtime xcframework (iOS + macOS)
        // Created by: cd sdk/runanywhere-swift && ./scripts/create-onnxruntime-xcframework.sh
        targets.append(
            .binaryTarget(
                name: "ONNXRuntimeBinary",
                path: "sdk/runanywhere-swift/Binaries/onnxruntime.xcframework"
            )
        )

        return targets
    } else {
        // =====================================================================
        // PRODUCTION MODE (for external SPM consumers)
        // Download XCFrameworks from GitHub releases
        // All xcframeworks include iOS + macOS slices (v0.19.0+)
        // =====================================================================
        return [
            .binaryTarget(
                name: "RACommonsBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/RACommons-v\(sdkVersion).zip",
                checksum: "ab6b15e52983f7f5706fc167ae79f5935042a23915a3ff56af49a19a92d48ebb"
            ),
            .binaryTarget(
                name: "RABackendLlamaCPPBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/RABackendLLAMACPP-v\(sdkVersion).zip",
                checksum: "063e4c53718e9b5367b58009039b9f3c401c0ffde8f8646036bb0b55a2625a3e"
            ),
            .binaryTarget(
                name: "RABackendONNXBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/RABackendONNX-v\(sdkVersion).zip",
                checksum: "108b897dbb6c51a372641c0a46e2c8db8419724cf3ad3388dc886b8c121036bf"
            ),
            .binaryTarget(
                name: "ONNXRuntimeBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/onnxruntime-v\(sdkVersion).zip",
                checksum: "394550455ac5f0c2ac0fa8f7a93be5a4eaec43a9c52772ed83179f3ae151dd6a"
            ),
        ]
    }
}
