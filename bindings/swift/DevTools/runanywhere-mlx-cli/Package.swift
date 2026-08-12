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
                .product(name: "RunAnywhere", package: "swift"),
                // RACommons' static provider registry references every linked
                // portable backend. Carry their archives in this standalone
                // CLI so the force-loaded commons library resolves cleanly.
                .product(name: "RunAnywhereLlamaCPP", package: "swift"),
                .product(name: "RunAnywhereONNX", package: "swift"),
                .product(name: "RunAnywhereMLX", package: "swift"),
            ],
            path: "Sources/RunAnywhereMLXCLI",
            linkerSettings: [
                .unsafeFlags(
                    [
                        "-Xlinker", "-force_load",
                        "-Xlinker", "../../Binaries/RACommons.xcframework/macos-arm64/librac_commons.a",
                        // The SDK reaches the proto-byte ABI through dlsym, so the
                        // linker sees no static reference and dead-strips those
                        // symbols — every rac_*_proto call then fails at runtime
                        // with "Native proto ABI is not exported". The app targets
                        // solve this with an exported-symbols list; this CLI just
                        // keeps the dynamic symbol table whole.
                        "-Xlinker", "-export_dynamic",
                    ],
                    .when(platforms: [.macOS])
                ),
            ]
        ),
    ]
)
