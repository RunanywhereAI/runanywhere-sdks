// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ONNXRuntime",
    platforms: [
        .iOS(.v14),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "ONNXRuntime",
            targets: ["ONNXRuntime"]
        ),
    ],
    dependencies: [
        .package(name: "runanywhere-swift", path: "../../"),  // RunAnywhere SDK
    ],
    targets: [
        .target(
            name: "ONNXRuntime",
            dependencies: [
                "CRunAnywhereONNX",  // C wrapper
                "RunAnywhereONNX",   // XCFramework
                .product(name: "RunAnywhere", package: "runanywhere-swift"),
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedLibrary("archive"),
                .linkedLibrary("bz2")
            ]
        ),
        .target(
            name: "CRunAnywhereONNX",
            dependencies: [],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include")
            ]
        ),
        .binaryTarget(
            name: "RunAnywhereONNX",
            path: "../../XCFrameworks/RunAnywhereONNX.xcframework"
        )
    ]
)
