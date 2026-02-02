// swift-tools-version: 5.9
// SDKTestApp - Minimal iOS app to test RunAnywhere SDK integration.
// Depends on the repo root package (local path).

import PackageDescription

let package = Package(
    name: "SDKTestApp",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "SDKTestApp", targets: ["SDKTestApp"])
    ],
    dependencies: [
        .package(path: "../../.."),
    ],
    targets: [
        .target(
            name: "SDKTestApp",
            dependencies: [
                .product(name: "RunAnywhere", package: "runanywhere-sdks"),
                .product(name: "RunAnywhereONNX", package: "runanywhere-sdks"),
                .product(name: "RunAnywhereLlamaCPP", package: "runanywhere-sdks"),
            ],
            path: "SDKTestApp",
            exclude: ["Assets.xcassets", "SDKTestApp.entitlements"]
        ),
    ]
)
