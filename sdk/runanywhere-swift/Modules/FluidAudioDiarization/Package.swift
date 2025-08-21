// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FluidAudioDiarization",
    platforms: [
        .iOS(.v17),      // FluidAudio requires iOS 17+
        .macOS(.v14)     // FluidAudio requires macOS 14+
    ],
    products: [
        .library(
            name: "FluidAudioDiarization",
            targets: ["FluidAudioDiarization"]
        ),
    ],
    dependencies: [
        // FluidAudio dependency
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.3.0"),
        // Reference to main SDK for protocols
        .package(path: "../../"),
    ],
    targets: [
        .target(
            name: "FluidAudioDiarization",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "RunAnywhereSDK", package: "runanywhere-swift")
            ]
        ),
    ]
)
