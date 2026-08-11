// swift-tools-version: 6.2
import PackageDescription

// Minimal SwiftPM executable that consumes the RunAnywhere SDK from LOCAL
// source (the repo-root Package.swift), not a published release artifact.
//
// The root manifest fails closed to remote binaryTargets, so this package must
// be built and run with RUNANYWHERE_USE_LOCAL_NATIVES=1 after the XCFrameworks
// have been staged into sdk/runanywhere-swift/Binaries/. See README.md.
let package = Package(
    name: "runanywhere-minimal",
    platforms: [.macOS("14.5")],
    dependencies: [
        .package(path: "../../..")
    ],
    targets: [
        .executableTarget(
            name: "runanywhere-minimal",
            dependencies: [
                .product(name: "RunAnywhere", package: "runanywhere-sdks"),
                .product(name: "RunAnywhereLlamaCPP", package: "runanywhere-sdks")
            ],
            path: "Sources"
        )
    ]
)
