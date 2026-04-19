// swift-tools-version: 5.9
// RunAnywhereCore — Swift frontend adapter for the new C++ core.
//
// This package is independent of the legacy `sdk/runanywhere-swift` tree.
// During the migration window consumers wire both:
//
//   .package(name: "RunAnywhere",      path: "../runanywhere-sdks/sdk/runanywhere-swift"),
//   .package(name: "RunAnywhereCore",  path: "../runanywhere-sdks/frontends/swift"),
//
// The legacy package is removed once per-SDK migration lands.

import PackageDescription

let package = Package(
    name: "RunAnywhereCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .watchOS(.v9),
    ],
    products: [
        .library(
            name: "RunAnywhereCore",
            targets: ["RunAnywhereCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.26.0"),
    ],
    targets: [
        .target(
            name: "RunAnywhereCore",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "Sources/RunAnywhere",
            exclude: [
                // Generated/ is populated by idl/codegen/generate_swift.sh.
                // It is tracked in git — but during fresh clones before the
                // first codegen run, we skip it so the build still succeeds.
                "Generated/.gitkeep",
            ]
        ),
        .testTarget(
            name: "RunAnywhereCoreTests",
            dependencies: ["RunAnywhereCore"],
            path: "Tests/RunAnywhereTests"
        ),
    ]
)
