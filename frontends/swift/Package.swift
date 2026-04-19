// swift-tools-version: 5.9
// RunAnywhere v2 — Swift frontend adapter.
//
// This package is independent of the legacy `sdk/runanywhere-swift` tree.
// Consumers wire BOTH during the v1→v2 migration window:
//
//   .package(name: "RunAnywhere",   path: "../runanywhere-sdks/sdk/runanywhere-swift"),
//   .package(name: "RunAnywhereV2", path: "../runanywhere-sdks/frontends/swift"),
//
// v1 is removed from clients after the v2 Phase 1 gate passes.

import PackageDescription

let package = Package(
    name: "RunAnywhereV2",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .watchOS(.v9),
    ],
    products: [
        .library(
            name: "RunAnywhereV2",
            targets: ["RunAnywhereV2"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.26.0"),
    ],
    targets: [
        .target(
            name: "RunAnywhereV2",
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
            name: "RunAnywhereV2Tests",
            dependencies: ["RunAnywhereV2"],
            path: "Tests/RunAnywhereTests"
        ),
    ]
)
