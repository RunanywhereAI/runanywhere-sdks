// swift-tools-version: 6.2

import PackageDescription
import Foundation

let sdkVersion = "0.20.36"
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
    checksum: "27294086efecacfe343b9f092e1bf0106397390376b93f16a0d051c1fedc9853"
)
let sherpaTarget = runAnywhereBinaryTarget(
    name: "RABackendSherpa",
    checksum: "3d307fe6baefea2eaf8d839fd877832294f1c9a0f05e0560a627978cd00103e5"
)
// Apple CoreML Stable-Diffusion engine. RACommons references
// _rac_plugin_entry_neurt (0.20.10 enabled the CoreML backend in commons),
// so this archive must be co-linked or the iOS link fails with an Undefined
// symbol error — the same reason RABackendSherpa is vendored here. It also
// makes on-device image generation (diffusion.generateImage) routable.
let coremlTarget = runAnywhereBinaryTarget(
    name: "RABackendNeuRT",
    checksum: "99baa8aefb5a18e1260c7bb02e358462c46ff268b2d6a40847ee823f487d61b2"
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
