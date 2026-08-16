// swift-tools-version: 6.2

import PackageDescription
import Foundation

let sdkVersion = "0.20.23"
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
    checksum: "0597442fa030fe6eb69f2f01c63d098e090c0b60469847e2a2614bcf4d32210a"
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
