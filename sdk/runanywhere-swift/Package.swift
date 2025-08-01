// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RunAnywhereSDK",
    platforms: [
        .iOS(.v13),
        .macOS(.v12),
        .tvOS(.v13),
        .watchOS(.v6)
    ],
    products: [
        .library(
            name: "RunAnywhereSDK",
            targets: ["RunAnywhereSDK"]
        ),
        .library(
            name: "RunAnywhereSDKDynamic",
            type: .dynamic,
            targets: ["RunAnywhereSDK"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.9.0"),
        .package(url: "https://github.com/JohnSundell/Files.git", from: "4.3.0"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.57.1")
    ],
    targets: [
        .target(
            name: "RunAnywhereSDK",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "Files", package: "Files")
            ],
            path: "Sources/RunAnywhere",
            swiftSettings: [
                .define("SWIFT_PACKAGE")
            ],
            // SwiftLint plugin temporarily disabled for build
            // plugins: [
            //     .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
            // ]
        ),
        .testTarget(
            name: "RunAnywhereSDKTests",
            dependencies: ["RunAnywhereSDK"],
            path: "Tests/RunAnywhereTests"
        )
    ]
)
