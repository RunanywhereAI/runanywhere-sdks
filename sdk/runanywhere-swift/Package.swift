// swift-tools-version: 5.9
// Attempted bump to 6.0 was rolled back. Bumping the manifest tools
// version forces Swift 6 language mode on all targets, which turns several
// pre-existing patterns in the SDK (mutable static registration flags,
// closure-captured locals in AVAudioConverter / URLSession callbacks,
// etc.) into hard build errors. Migrating those requires non-trivial
// source changes (sendable globals, actor isolation) that are out of
// scope for this dep-bump pass — see AGENTS.md "no source edits" rule.
// Re-attempt once the Swift 6 strict-concurrency migration lands.
import PackageDescription

// RunAnywhere Swift SDK — LOCAL development Package.swift
//
// This Package.swift lives inside `sdk/runanywhere-swift/` and uses LOCAL
// XCFrameworks from the sibling `Binaries/` directory. It is the counterpart
// to the root-level `Package.swift`, which is the one published to SPM
// consumers and downloads the XCFrameworks from GitHub releases.
//
// Paths in this file are relative to `sdk/runanywhere-swift/`, NOT to the
// repository root. For example `Sources/RunAnywhere` here is the same tree
// that the root-level package refers to as
// `sdk/runanywhere-swift/Sources/RunAnywhere`.
//
// Min platforms: iOS 17.5 / macOS 14.5 (matches the root package).

let package = Package(
    name: "RunAnywhere",
    platforms: [
        // iOS 17.5 / macOS 14.5 — latest minor of the LTS line, matches the
        // Xcode 15.4 baseline.
        .iOS("17.5"),
        .macOS("14.5"),
    ],
    products: [
        // Core SDK — always needed. The `RunAnywhere` library vends only the
        // core target. Consumers that need backend runtimes must import
        // `RunAnywhereLlamaCPP` / `RunAnywhereONNX` separately so the linker
        // can drop unused backend code. This matches the root Package.swift
        // (see root Package.swift:80-83) which is the published SPM product
        // surface — keeping the local and root manifests in sync ensures the
        // local example apps exercise the same selective-linking shape that
        // external consumers see.
        .library(
            name: "RunAnywhere",
            targets: ["RunAnywhere"]
        ),

        // Individual backend products (used by the example apps that only
        // want to link a subset of the runtimes).
        .library(name: "RunAnywhereLlamaCPP", targets: ["LlamaCPPRuntime"]),
        .library(name: "RunAnywhereONNX", targets: ["ONNXRuntime"]),
    ],
    dependencies: [
        // SPM deps use `.upToNextMinor` (not open-ended `from:`) so a
        // silent upstream major bump can't land in `Package.resolved` without
        // a Package.swift edit. Version floors are mirrored in
        // Sources/RunAnywhere/Generated/Versions.swift (RAVersions) — keep
        // both in sync via scripts/release/sync-versions.sh.
        .package(url: "https://github.com/apple/swift-crypto.git", .upToNextMinor(from: "3.15.1")),
        .package(url: "https://github.com/JohnSundell/Files.git", .upToNextMinor(from: "4.3.0")),
        .package(url: "https://github.com/devicekit/DeviceKit.git", .upToNextMinor(from: "5.8.0")),
        .package(url: "https://github.com/getsentry/sentry-cocoa", .upToNextMinor(from: "8.58.2")),
        // swift-protobuf is consumed by the pb.swift files generated from
        // idl/*.proto in Sources/RunAnywhere/Generated/.
        // Floor must stay >= 1.28.0: generated code uses
        // SwiftProtobuf._NameMap(bytecode:).
        .package(url: "https://github.com/apple/swift-protobuf.git", .upToNextMinor(from: "1.38.0")),
    ],
    targets: [
        // C Bridge Module — Core Commons
        .target(
            name: "CRACommons",
            dependencies: ["RACommonsBinary"],
            path: "Sources/RunAnywhere/CRACommons",
            publicHeadersPath: "include"
        ),

        // C Bridge Module — LlamaCPP Backend Headers
        //
        // Depends on CRACommons so the backend registration header can pull
        // `rac_types.h` / `rac_error.h` / `rac_llm.h` from the single source
        // of truth instead of carrying drifting local copies.
        .target(
            name: "LlamaCPPBackend",
            dependencies: [
                "CRACommons",
                "RABackendLlamaCPPBinary",
            ],
            path: "Sources/LlamaCPPRuntime/include",
            publicHeadersPath: "."
        ),

        // C Bridge Module — ONNX Backend Headers
        //
        // Depends on CRACommons so the registration header pulls `rac_types.h`
        // / `rac_result_t` from the single source of truth. The xcframework
        // dependencies (RABackendONNX + RABackendSherpa) carry the actual
        // symbol bodies.
        .target(
            name: "ONNXBackend",
            dependencies: [
                "CRACommons",
                "RABackendONNXBinary",
                "RABackendSherpaBinary",
            ],
            path: "Sources/ONNXRuntime/include",
            publicHeadersPath: "."
        ),

        // Core SDK target
        .target(
            name: "RunAnywhere",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Files", package: "Files"),
                .product(name: "DeviceKit", package: "DeviceKit"),
                .product(name: "Sentry", package: "sentry-cocoa"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                "CRACommons",
                "RACommonsBinary",
            ],
            path: "Sources/RunAnywhere",
            exclude: [
                // CRACommons is declared as its own sibling target above;
                // exclude from this target's source list to avoid a double
                // compile.
                "CRACommons",
                // The two proto schemas below are emitted by codegen but have
                // zero consumers in the Swift SDK. Excluding them avoids
                // compiling ~2154 lines of dead generated code. Keep
                // `pipeline.pb.swift` and `solutions.pb.swift` — those are
                // consumed via the Solutions facade.
                "Generated/router.pb.swift",
                "Generated/diffusion_options.pb.swift",
            ],
            swiftSettings: [
                .define("SWIFT_PACKAGE"),
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedLibrary("z"),
                .linkedLibrary("bz2"),
                .linkedFramework("CFNetwork"),
                .linkedFramework("Security"),
                .linkedFramework("SystemConfiguration"),
            ]
        ),

        // LlamaCPP Runtime Backend
        .target(
            name: "LlamaCPPRuntime",
            dependencies: [
                "RunAnywhere",
                "LlamaCPPBackend",
                "RABackendLlamaCPPBinary",
            ],
            path: "Sources/LlamaCPPRuntime",
            exclude: [
                "include",
                // Stray docs file picked up by SwiftPM as an unhandled
                // resource. Silence the "unhandled file(s)" warning.
                "README.md",
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
            ]
        ),

        // ONNX Runtime Backend (STT/TTS/VAD)
        .target(
            name: "ONNXRuntime",
            dependencies: [
                "RunAnywhere",
                "ONNXBackend",
                "RABackendONNXBinary",
                "RABackendSherpaBinary",
            ],
            path: "Sources/ONNXRuntime",
            exclude: [
                "include",
                // Stray docs file picked up by SwiftPM as an unhandled
                // resource. Silence the "unhandled file(s)" warning.
                "README.md",
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedFramework("CoreML"),
                .linkedLibrary("archive"),
                .linkedLibrary("bz2"),
            ]
        ),

        // Unit tests: HandleStreamAdapter lifecycle, proto helpers
        // (LoRA / model-import / lifecycle / structured-output / tool-calling),
        // error mapping.
        //
        // `SwiftProtobuf` is listed alongside `RunAnywhere` because the
        // HandleStreamAdapter coverage in Tests/RunAnywhereTests/Adapters/
        // calls `Message.serializedData()` directly to drive synthetic
        // proto-byte payloads through the C trampoline.
        .testTarget(
            name: "RunAnywhereTests",
            dependencies: [
                "RunAnywhere",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "Tests/RunAnywhereTests"
        ),

        // Binary targets (local XCFrameworks under Binaries/)
        .binaryTarget(
            name: "RACommonsBinary",
            path: "Binaries/RACommons.xcframework"
        ),
        .binaryTarget(
            name: "RABackendLlamaCPPBinary",
            path: "Binaries/RABackendLLAMACPP.xcframework"
        ),
        .binaryTarget(
            name: "RABackendONNXBinary",
            path: "Binaries/RABackendONNX.xcframework"
        ),
        .binaryTarget(
            name: "RABackendSherpaBinary",
            path: "Binaries/RABackendSherpa.xcframework"
        ),
    ]
)
