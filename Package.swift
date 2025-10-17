// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RunAnywhere",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        // Core SDK
        .library(
            name: "RunAnywhere",
            targets: ["RunAnywhere"]
        ),
        // Optional adapter modules
        .library(
            name: "LLMSwift",
            targets: ["LLMSwift"]
        ),
        .library(
            name: "WhisperKitTranscription",
            targets: ["WhisperKitTranscription"]
        ),
        .library(
            name: "FluidAudioDiarization",
            targets: ["FluidAudioDiarization"]
        )
    ],
    dependencies: [
        // Core SDK dependencies
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.9.0"),
        .package(url: "https://github.com/JohnSundell/Files.git", from: "4.3.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.6.1"),
        .package(url: "https://github.com/devicekit/DeviceKit.git", from: "5.6.0"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.57.1"),
        .package(url: "https://github.com/kean/Pulse", from: "4.0.0"),

        // Adapter module dependencies
        .package(url: "https://github.com/eastriverlee/LLM.swift", from: "2.0.1"),
        .package(url: "https://github.com/argmaxinc/WhisperKit", exact: "0.13.1"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.5.0"),
    ],
    targets: [
        // Core SDK target
        .target(
            name: "RunAnywhere",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "Files", package: "Files"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "DeviceKit", package: "DeviceKit"),
                .product(name: "Pulse", package: "Pulse"),
            ],
            path: "sdk/runanywhere-swift/Sources/RunAnywhere",
            exclude: [
                "Data/README.md",
                "Data/Storage/Database/README.md"
            ],
            swiftSettings: [
                .define("SWIFT_PACKAGE")
            ]
        ),

        // LLMSwift adapter target (requires iOS 16+)
        .target(
            name: "LLMSwift",
            dependencies: [
                "RunAnywhere",
                .product(name: "LLM", package: "LLM.swift")
            ],
            path: "sdk/runanywhere-swift/Modules/LLMSwift/Sources/LLMSwift"
        ),

        // WhisperKit adapter target (requires iOS 16+)
        .target(
            name: "WhisperKitTranscription",
            dependencies: [
                "RunAnywhere",
                "WhisperKit"
            ],
            path: "sdk/runanywhere-swift/Modules/WhisperKitTranscription/Sources/WhisperKitTranscription"
        ),

        // FluidAudio adapter target (requires iOS 17+)
        .target(
            name: "FluidAudioDiarization",
            dependencies: [
                "RunAnywhere",
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            path: "sdk/runanywhere-swift/Modules/FluidAudioDiarization/Sources/FluidAudioDiarization"
        )
    ]
)
