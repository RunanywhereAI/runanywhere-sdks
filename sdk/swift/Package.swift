// swift-tools-version: 5.9
// RunAnywhereCore — Swift frontend for the new C++ core.
//
// Links the RACommonsCore xcframework (pre-built by
// `scripts/build-core-xcframework.sh`). Uses a struct-based C ABI so no
// protobuf runtime is needed at link time — proto3 in idl/*.proto remains
// the canonical IDL but is used for compile-time schema validation only.

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
    targets: [
        // Pre-built C core (libRACommonsCore.a + headers + modulemap).
        // Produced by `scripts/build-core-xcframework.sh`.
        .binaryTarget(
            name: "RACommonsCoreBinary",
            path: "Binaries/RACommonsCore.xcframework"
        ),
        .target(
            name: "RunAnywhereCore",
            dependencies: [
                "RACommonsCoreBinary",
            ],
            path: "Sources/RunAnywhere",
            exclude: [
                // Generated/ holds SwiftProtobuf codegen used for IDL
                // validation tests only; the runtime adapter uses the
                // struct-based C ABI and does not import these types.
                "Generated",
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
            ]
        ),
        .testTarget(
            name: "RunAnywhereCoreTests",
            dependencies: ["RunAnywhereCore"],
            path: "Tests/RunAnywhereTests"
        ),
    ]
)
