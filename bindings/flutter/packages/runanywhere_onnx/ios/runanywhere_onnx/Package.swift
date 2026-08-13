// swift-tools-version: 6.2

import PackageDescription
import Foundation

let sdkVersion = "0.20.18"
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
    checksum: "49d2b74b7786d38fce5de360c1066a49f6ae427b90f2414cdd6e697b88a9d7f0"
)
let sherpaTarget = runAnywhereBinaryTarget(
    name: "RABackendSherpa",
    checksum: "95d0621fab7b99200acaca05cd3feceeaf36949751cceafc84e7a1bf7d3cf1ad"
)
// Apple CoreML Stable-Diffusion engine. RACommons references
// _rac_plugin_entry_neurt (0.20.10 enabled the CoreML backend in commons),
// so this archive must be co-linked or the iOS link fails with an Undefined
// symbol error — the same reason RABackendSherpa is vendored here. It also
// makes on-device image generation (diffusion.generateImage) routable.
let coremlTarget = runAnywhereBinaryTarget(
    name: "RABackendNeuRT",
    checksum: "b68886c1f954809c31b556ee7daaa2ddec52da942857164cc445224333feaa1c"
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
