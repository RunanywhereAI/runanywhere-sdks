// swift-tools-version: 6.2
import PackageDescription

// Shared decision-model parity CLI.
//
// One command runs the canonical ticket example through whichever decision
// backend is registered (llamacpp for GGUF checkpoints, MLX for safetensors
// directories) so the cross-engine parity check is:
//
//   decision-cli run --framework llamacpp --model /path/to/Clef-Flash-Q4_K_M.gguf
//   decision-cli run --framework mlx      --model /path/to/clef-flash-4bit
//
// Both invocations must print the same choice / probabilities within bf16
// noise. See README.md for the expected reference numbers.
//
// Local SDK source only: build with RUNANYWHERE_USE_LOCAL_NATIVES=1 after
// staging Binaries/ via bindings/swift/scripts/build-core-xcframework.sh.
let package = Package(
    name: "decision-cli",
    platforms: [.macOS("14.5")],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "DecisionCLI",
            dependencies: [
                .product(name: "RunAnywhere", package: "runanywhere-sdks"),
                .product(name: "RunAnywhereMLX", package: "runanywhere-sdks"),
                .product(name: "RunAnywhereLlamaCPP", package: "runanywhere-sdks"),
                .product(name: "RunAnywhereONNX", package: "runanywhere-sdks"),
            ],
            path: "Sources/DecisionCLI",
            linkerSettings: [
                .unsafeFlags(
                    [
                        // dlsym-only C ABI symbols are dead-stripped by the static
                        // linker; pin every entry point the decision path calls.
                        "-Xlinker", "-u",
                        "-Xlinker", "_rac_model_registry_import_proto",
                        "-Xlinker", "-u",
                        "-Xlinker", "_rac_model_lifecycle_load_proto",
                        "-Xlinker", "-u",
                        "-Xlinker", "_rac_decision_component_create",
                        "-Xlinker", "-u",
                        "-Xlinker", "_rac_decision_component_load_model",
                        "-Xlinker", "-u",
                        "-Xlinker", "_rac_decision_component_decide_proto",
                        "-Xlinker", "-u",
                        "-Xlinker", "_rac_decision_component_unload",
                        "-Xlinker", "-u",
                        "-Xlinker", "_rac_decision_component_destroy",
                    ],
                    .when(platforms: [.macOS])
                )
            ]
        )
    ]
)