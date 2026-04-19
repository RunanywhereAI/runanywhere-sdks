// swift-tools-version: 5.9
// Minimal Swift CLI demo — links the new RunAnywhereCore from
// frontends/swift and exercises a full VoiceSession lifecycle.
// Builds standalone: `swift run` inside examples/swift-demo/.

import PackageDescription

let package = Package(
    name: "RunAnywhereDemo",
    platforms: [
        .macOS(.v13),
    ],
    dependencies: [
        .package(path: "../../frontends/swift"),
    ],
    targets: [
        .executableTarget(
            name: "RunAnywhereDemo",
            dependencies: [
                .product(name: "RunAnywhereCore", package: "swift"),
            ]
        ),
    ]
)
