// swift-tools-version: 6.2

import PackageDescription
import Foundation

let sdkVersion = "0.19.15"
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

let raCommonsTarget = runAnywhereBinaryTarget(
    name: "RACommons",
    checksum: "02c3ab0dc3366391644ab2573d43eda14dc57e125cb6db52de4574e49785047b"
)

let package = Package(
    name: "runanywhere",
    platforms: [
        .iOS("17.5"),
    ],
    products: [
        .library(name: "runanywhere", type: .static, targets: ["runanywhere"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        raCommonsTarget,
        .target(
            name: "runanywhere_native",
            dependencies: ["RACommons"],
            path: "Sources/runanywhere_native",
            exclude: ["URLSessionHttpTransportImpl.inc.mm"],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("include"),
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedLibrary("archive"),
                .linkedLibrary("bz2"),
                .linkedLibrary("z"),
                .linkedFramework("Foundation"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreML"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("MetalPerformanceShaders"),
            ]
        ),
        .target(
            name: "runanywhere",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                "RACommons",
                "runanywhere_native",
            ],
            path: "Sources/runanywhere",
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-ObjC",
                    "-Xlinker", "-all_load",
                    "-Xlinker", "-export_dynamic",
                    "-Xlinker", "-no_dead_strip_inits_and_terms",
                ]),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
