// swift-tools-version: 6.2

import PackageDescription
import Foundation

let sdkVersion = "0.20.11"
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
    checksum: "5c837259d302f66aecc2c6d52332af0ee4fb43beeedbd6a3f3fd762147b37765"
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
