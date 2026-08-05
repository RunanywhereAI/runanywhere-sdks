// swift-tools-version: 6.2

import PackageDescription
import Foundation

let sdkVersion = "0.20.12"
let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

func runAnywhereBinaryTarget(name: String, checksum: String) -> Target {
    let relativePath = "Frameworks/\(name).xcframework"
    if FileManager.default.fileExists(
        atPath: packageRoot.appendingPathComponent(relativePath).path
    ) {
        return .binaryTarget(name: name, path: relativePath)
    }

    return .binaryTarget(
        name: name,
        url: "https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/\(name)-ios-v\(sdkVersion).zip",
        checksum: checksum
    )
}

let onnxTarget = runAnywhereBinaryTarget(
    name: "RABackendONNX",
    checksum: "0e548dcc59d8bb49446ff8d02c94b97130a1c6c7b18b6c768a9be4acc16edbf2"
)
let sherpaTarget = runAnywhereBinaryTarget(
    name: "RABackendSherpa",
    checksum: "36a0965157111f6f0b9b16a6c6d622b9ee537f1df2ecfa3558553233cff27a64"
)
// Apple CoreML Stable-Diffusion engine. RACommons references
// _rac_plugin_entry_neurt (0.20.10 enabled the CoreML backend in commons),
// so this archive must be co-linked or the iOS link fails with an Undefined
// symbol error — the same reason RABackendSherpa is vendored here. It also
// makes on-device image generation (diffusion.generateImage) routable.
let coremlTarget = runAnywhereBinaryTarget(
    name: "RABackendNeuRT",
    checksum: "93cb97b0a3e64dca8996214ebb85945202fa413e05907c260908fa6ab2b41e24"
)

let package = Package(
    name: "runanywhere_onnx",
    platforms: [
        .iOS("17.5"),
    ],
    products: [
        .library(
            name: "runanywhere-onnx",
            type: .static,
            targets: ["runanywhere_onnx"]
        ),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        onnxTarget,
        sherpaTarget,
        coremlTarget,
        .target(
            name: "runanywhere_onnx",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                "RABackendONNX",
                "RABackendSherpa",
                "RABackendNeuRT",
            ],
            path: "Sources/runanywhere_onnx",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-all_load"]),
                .linkedLibrary("c++"),
                .linkedLibrary("archive"),
                .linkedLibrary("bz2"),
                .linkedLibrary("z"),
                .linkedFramework("Foundation"),
                .linkedFramework("CoreML"),
                .linkedFramework("Accelerate"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("MetalPerformanceShaders"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
