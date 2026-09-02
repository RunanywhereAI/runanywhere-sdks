// swift-tools-version: 6.2

import PackageDescription
import Foundation

let sdkVersion = "0.20.35"
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
    checksum: "33aa8ebe41cfa07abdb55e1bfd693fadcfa1645a4aaf592e1222171de0323961"
)
let sherpaTarget = runAnywhereBinaryTarget(
    name: "RABackendSherpa",
    checksum: "64955f767e0302ced5f9b9283d48cf37a7c8d1a77fc066712ffdf471ee9715cc"
)
// Apple CoreML Stable-Diffusion engine. RACommons references
// _rac_plugin_entry_neurt (0.20.10 enabled the CoreML backend in commons),
// so this archive must be co-linked or the iOS link fails with an Undefined
// symbol error — the same reason RABackendSherpa is vendored here. It also
// makes on-device image generation (diffusion.generateImage) routable.
let coremlTarget = runAnywhereBinaryTarget(
    name: "RABackendNeuRT",
    checksum: "7fceb9ce9470c73cffa7db4193b6915da3e3df8695fe01b82f0b6a065224879e"
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
