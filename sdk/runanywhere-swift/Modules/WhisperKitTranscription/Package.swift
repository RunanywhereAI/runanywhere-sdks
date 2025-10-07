// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhisperKitTranscription",
    platforms: [
        .iOS(.v16),      // WhisperKit requires iOS 16+
        .macOS(.v13),    // Updated to match WhisperKit requirement
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(
            name: "WhisperKitTranscription",
            targets: ["WhisperKitTranscription"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", exact: "0.13.1"),
        .package(name: "runanywhere-swift", path: "../../"),  // RunAnywhereSDK
    ],
    targets: [
        .target(
            name: "WhisperKitTranscription",
            dependencies: [
                "WhisperKit",
                .product(name: "RunAnywhere", package: "runanywhere-swift"),
            ]
        ),
        .testTarget(
            name: "WhisperKitTranscriptionTests",
            dependencies: ["WhisperKitTranscription"]
        ),
    ]
)
