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

// =============================================================================
// ONNX RUNTIME COEXISTENCE
// =============================================================================
// RABackendONNX.xcframework + onnxruntime-{ios,macos}.xcframework must ship
// TOGETHER because:
//
//   1. RABackendONNX statically embeds sherpa-onnx's C API symbols
//      (STT/Zipformer/Whisper decoders, Piper TTS phonemizer, Silero VAD).
//   2. Sherpa-onnx.xcframework leaves ONNX Runtime symbols UNDEFINED —
//      they're resolved at final app-link time against the separate
//      onnxruntime-{ios,macos}.xcframework.
//   3. Our own rac_backend_onnx code ALSO calls raw Ort::* directly for
//      wake-word detection (openWakeWord) and RAG embeddings (BERT), so
//      we'd need the ORT xcframework even if sherpa disappeared.
//
// The ORT version (sdk/runanywhere-commons/VERSIONS → ONNX_VERSION_*) is
// pinned to whatever sherpa-onnx was built against. LoadVersions.cmake
// hard-errors if the per-platform pins drift apart. Do not bump the
// onnxruntime-{ios,macos}-v<X>.zip artifacts independently of
// SHERPA_ONNX_VERSION_*.
//
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
let useLocalBinaries = true //  Toggle: true for local dev, false for release

// Version for remote XCFrameworks (used when testLocal = false)
// Updated automatically by CI/CD during releases
let sdkVersion = "0.19.7"

// MetalRT remote binary availability flag.
// Set to `false` until a real checksum for RABackendMetalRT-v<sdkVersion>.zip
// has been published. When `false`, the MetalRT product/targets are only
// exposed under `useLocalBinaries = true`, so SPM resolution will not fail
// for external consumers due to a placeholder checksum.
let metalrtRemoteBinaryAvailable = false

// In local-mode we additionally probe the filesystem. MetalRT is an optional
// backend and many local dev flows skip it (build-ios.sh --backend onnx, etc.)
// without producing the xcframework. Without this existence check, SPM
// resolution would fatal-error on "local binary target ... does not contain a
// binary artifact" — breaking the package graph whenever a dev builds fewer
// backends than the full set.
let metalrtLocalBinaryExists: Bool = {
    let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let frameworkPath = packageDir.appendingPathComponent(
        "sdk/runanywhere-swift/Binaries/RABackendMetalRT.xcframework"
    ).path
    return FileManager.default.fileExists(atPath: frameworkPath)
}()

let includeMetalRT = (useLocalBinaries && metalrtLocalBinaryExists) || metalrtRemoteBinaryAvailable

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

    ] + metalRTProducts(),
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.9.0"),
        .package(url: "https://github.com/JohnSundell/Files.git", from: "4.3.0"),
        .package(url: "https://github.com/devicekit/DeviceKit.git", from: "5.6.0"),
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
            dependencies: [
                "RABackendONNXBinary",
                .target(name: "ONNXRuntimeiOSBinary", condition: .when(platforms: [.iOS])),
                .target(name: "ONNXRuntimemacOSBinary", condition: .when(platforms: [.macOS])),
            ],
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
                .product(name: "DeviceKit", package: "DeviceKit"),
                .product(name: "Sentry", package: "sentry-cocoa"),
                .product(name: "StableDiffusion", package: "ml-stable-diffusion"),
                "CRACommons",
                "RACommonsBinary",
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
                "RABackendONNXBinary",
                .target(name: "ONNXRuntimeiOSBinary", condition: .when(platforms: [.iOS])),
                .target(name: "ONNXRuntimemacOSBinary", condition: .when(platforms: [.macOS])),
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
                "RABackendLlamaCPPBinary",
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

    ] + metalRTTargets() + binaryTargets()
)

// =============================================================================
// METALRT PRODUCT / TARGET GATING
// =============================================================================
// The RABackendMetalRT.xcframework is not yet published to GitHub releases
// with a real checksum. To avoid SPM resolution failures for external
// consumers due to a placeholder zero-checksum binary target, the MetalRT
// product and its dependent targets are only included when:
//   - `useLocalBinaries == true` (local dev with a checked-out xcframework), or
//   - `metalrtRemoteBinaryAvailable == true` (once a real checksum is wired in).
func metalRTProducts() -> [Product] {
    guard includeMetalRT else { return [] }
    return [
        .library(
            name: "RunAnywhereMetalRT",
            targets: ["MetalRTRuntime"]
        ),
    ]
}

func metalRTTargets() -> [Target] {
    guard includeMetalRT else { return [] }
    return [
        // MetalRT C Bridge Module - exposes rac_backend_metalrt_register()
        .target(
            name: "MetalRTBackend",
            dependencies: ["RABackendMetalRTBinary"],
            path: "sdk/runanywhere-swift/Sources/MetalRTRuntime/include",
            publicHeadersPath: "."
        ),
        // MetalRT Runtime Backend (custom Metal GPU kernels)
        .target(
            name: "MetalRTRuntime",
            dependencies: [
                "RunAnywhere",
                "MetalRTBackend",
                "RABackendMetalRTBinary",
            ],
            path: "sdk/runanywhere-swift/Sources/MetalRTRuntime",
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
    ]
}

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

        // MetalRT is optional. Only declare its binary target when the
        // xcframework is actually present locally — otherwise SPM resolution
        // fatal-errors with "does not contain a binary artifact" on any dev
        // flow that skipped metalrt (e.g. build-ios.sh --backend onnx).
        if metalrtLocalBinaryExists {
            targets.append(
                .binaryTarget(
                    name: "RABackendMetalRTBinary",
                    path: "sdk/runanywhere-swift/Binaries/RABackendMetalRT.xcframework"
                )
            )
        }

        // ONNX Runtime xcframeworks - split by platform
        // iOS: static library format (not embedded in app bundle)
        // macOS: dynamic framework format (embedded in app bundle)
        targets.append(contentsOf: [
            .binaryTarget(
                name: "ONNXRuntimeiOSBinary",
                path: "sdk/runanywhere-swift/Binaries/onnxruntime-ios.xcframework"
            ),
            .binaryTarget(
                name: "ONNXRuntimemacOSBinary",
                path: "sdk/runanywhere-swift/Binaries/onnxruntime-macos.xcframework"
            ),
        ])

        return targets
    } else {
        // =====================================================================
        // PRODUCTION MODE (for external SPM consumers)
        // Download XCFrameworks from GitHub releases
        // All xcframeworks include iOS + macOS slices (v0.19.0+)
        // =====================================================================
        var targets: [Target] = [
            .binaryTarget(
                name: "RACommonsBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/RACommons-v\(sdkVersion).zip",
                checksum: "40ea84cf054f59fbc65e87d92550d4acb2bcbf433041438822c6b30985e3db24"
            ),
            .binaryTarget(
                name: "RABackendLlamaCPPBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/RABackendLLAMACPP-v\(sdkVersion).zip",
                checksum: "314dddb242caf3d2d0b19c0f919c35187023c6c66cc861de741d071faddbf58b"
            ),
            .binaryTarget(
                name: "RABackendONNXBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/RABackendONNX-v\(sdkVersion).zip",
                checksum: "809e2510da49f71f6d019e77bcc0a7e12e967f3b739ba0b9eea7adb77936edc0"
            ),
            .binaryTarget(
                name: "ONNXRuntimeiOSBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/onnxruntime-ios-v\(sdkVersion).zip",
                checksum: "310022d76a16b2d2d106577a1aa84a9e608c721bb6221c4ba47bf962a88bd9fd"
            ),
            .binaryTarget(
                name: "ONNXRuntimemacOSBinary",
                url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/onnxruntime-macos-v\(sdkVersion).zip",
                checksum: "f73db9dc09012325b35fd3da74de794a75f4e9971d9b923af0805d6ab1dfc243"
            ),
        ]

        // MetalRT remote binary is only appended once a real checksum has been
        // published. Until then the MetalRT product/targets are omitted from
        // the package graph entirely (see metalRTProducts/metalRTTargets).
        if metalrtRemoteBinaryAvailable {
            targets.append(
                .binaryTarget(
                    name: "RABackendMetalRTBinary",
                    url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/RABackendMetalRT-v\(sdkVersion).zip",
                    checksum: "0000000000000000000000000000000000000000000000000000000000000000" // TODO: replace with real checksum
                )
            )
        }

        return targets
    }
}
