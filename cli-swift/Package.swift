// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "runanywhere-ios",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "runanywhere-ios", targets: ["RunAnywhereCLI"])
    ],
    dependencies: [
        // Swift Argument Parser for CLI
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        // Rainbow for colored terminal output
        .package(url: "https://github.com/onevcat/Rainbow.git", from: "4.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "RunAnywhereCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Rainbow", package: "Rainbow"),
            ],
            path: "Sources"
        ),
    ]
)
