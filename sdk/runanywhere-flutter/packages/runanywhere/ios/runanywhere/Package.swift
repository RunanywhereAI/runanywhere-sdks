// swift-tools-version: 6.2

import PackageDescription

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
        .binaryTarget(
            name: "RACommons",
            path: "Frameworks/RACommons.xcframework"
        ),
        .target(
            name: "runanywhere_native",
            dependencies: ["RACommons"],
            path: "Sources/runanywhere_native",
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
