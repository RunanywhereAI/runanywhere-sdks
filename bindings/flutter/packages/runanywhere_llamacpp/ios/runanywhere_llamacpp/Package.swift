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

let llamaTarget = runAnywhereBinaryTarget(
    name: "RABackendLLAMACPP",
    checksum: "baab28bbe22de196b9442cb17895142b2a8a80fa951c8a796bf4d4eb3256e9c6"
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
