// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RunAnywhereMLXCLI",
    platforms: [
        .macOS("14.5"),
    ],
    products: [
        .executable(name: "RunAnywhereMLXCLI", targets: ["RunAnywhereMLXCLI"]),
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "RunAnywhereMLXCLI",
            dependencies: [
                .product(name: "RunAnywhere", package: "runanywhere-swift"),
                .product(name: "RunAnywhereMLX", package: "runanywhere-swift"),
                // The macOS RACommons slice is built with RAC_STATIC_PLUGINS=ON,
                // so librac_commons.a's static-init stubs reference every
                // backend's register symbol. Link the llama.cpp and
                // ONNX/Sherpa/CoreML runtimes (they force_load the backend
                // archives and declare the required frameworks) to resolve
                // them — mirroring the root Package.swift RunAnywhereMLXCLI
                // target without pulling in the C++ RCLIHost host bridge.
                .product(name: "RunAnywhereLlamaCPP", package: "runanywhere-swift"),
                .product(name: "RunAnywhereONNX", package: "runanywhere-swift"),
            ],
            path: "Sources/RunAnywhereMLXCLI",
            linkerSettings: [
                .unsafeFlags(
                    [
                        "-Xlinker", "-force_load",
                        "-Xlinker", "../../Binaries/RACommons.xcframework/macos-arm64/librac_commons.a",
                    ],
                    .when(platforms: [.macOS])
                ),
            ]
        ),
    ]
)
