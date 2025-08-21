// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FluidAudioDiarization",
    platforms: [
        .iOS(.v16),      // FluidAudio actually supports iOS 16+
        .macOS(.v13)     // FluidAudio actually supports macOS 13+
    ],
    products: [
        .library(
            name: "FluidAudioDiarization",
            targets: ["FluidAudioDiarization"]
        ),
    ],
    dependencies: [
        // FluidAudio dependency from local path
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.2.0"),
        // Reference to main SDK for protocols
        .package(name: "runanywhere-swift", path: "../../")  // Points to main SDK
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
