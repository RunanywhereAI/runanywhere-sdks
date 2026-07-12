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
