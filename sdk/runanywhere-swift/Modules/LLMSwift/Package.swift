// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LLMSwift",
    platforms: [
        .iOS(.v16),      // LLM.swift requires iOS 16+
        .macOS(.v13),    // LLM.swift requires macOS 13+
        .tvOS(.v16),     // LLM.swift requires tvOS 16+
        .watchOS(.v9)    // LLM.swift requires watchOS 9+
    ],
    products: [
        .library(
            name: "LLMSwift",
            targets: ["LLMSwift"]
        ),
    ],
    dependencies: [
        // LLM.swift dependency - using latest from GitHub main branch
        .package(url: "https://github.com/eastriverlee/LLM.swift", branch: "main"),
        // Reference to main SDK for protocols
        .package(path: "../../"),
    ],
    targets: [
        .target(
            name: "LLMSwift",
            dependencies: [
                .product(name: "LLM", package: "LLM.swift"),
                .product(name: "RunAnywhereSDK", package: "runanywhere-swift")
            ]
        ),
        .testTarget(
            name: "LLMSwiftTests",
            dependencies: ["LLMSwift"]
        ),
    ]
)
