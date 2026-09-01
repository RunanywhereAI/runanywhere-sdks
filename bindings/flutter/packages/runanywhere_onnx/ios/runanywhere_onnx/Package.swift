// swift-tools-version: 6.2

import PackageDescription
import Foundation

let sdkVersion = "0.20.32"
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
    checksum: "990dd26b4e743a63068c1c107e44e78fb83b234bef4806971da89defb34e2733"
)
let sherpaTarget = runAnywhereBinaryTarget(
    name: "RABackendSherpa",
    checksum: "976029f81edd3ba95cd398fc3c2e6e45b6382ce8d128b0d43f103babab6baa81"
)
// Apple CoreML Stable-Diffusion engine. RACommons references
// _rac_plugin_entry_neurt (0.20.10 enabled the CoreML backend in commons),
// so this archive must be co-linked or the iOS link fails with an Undefined
// symbol error — the same reason RABackendSherpa is vendored here. It also
// makes on-device image generation (diffusion.generateImage) routable.
let coremlTarget = runAnywhereBinaryTarget(
    name: "RABackendNeuRT",
    checksum: "57d9e8487acc77b02d07c426094ffb92719d1f0312cd2452402670c9cc6ddb39"
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
