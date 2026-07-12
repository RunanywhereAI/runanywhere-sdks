// swift-tools-version: 6.2

import PackageDescription
import Foundation

let sdkVersion = "0.20.0"
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

let llamaTarget = runAnywhereBinaryTarget(
    name: "RABackendLLAMACPP",
    checksum: "811bb7447c80d390a6d11bee334bac62d99ee4537ce6d01c0eb910294e29ca99"
)

let package = Package(
    name: "runanywhere_llamacpp",
    platforms: [
        .iOS("17.5"),
    ],
    products: [
        .library(
            name: "runanywhere-llamacpp",
            type: .static,
            targets: ["runanywhere_llamacpp"]
        ),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        llamaTarget,
        .target(
            name: "runanywhere_llamacpp",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                "RABackendLLAMACPP",
            ],
            path: "Sources/runanywhere_llamacpp",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-all_load"]),
                .linkedLibrary("c++"),
                .linkedFramework("Foundation"),
                .linkedFramework("CoreML"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("MetalPerformanceShaders"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
