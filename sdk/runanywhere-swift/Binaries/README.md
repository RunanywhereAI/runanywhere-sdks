# Binary Distribution

## Remote Distribution (Current)

As of v0.0.1-dev.1f175bc, the RunAnywhere Swift SDK uses **remote XCFramework distribution** via Swift Package Manager binary targets.

The XCFramework is automatically downloaded from the [runanywhere-binaries](https://github.com/RunanywhereAI/runanywhere-binaries) repository during package resolution.

### Current Configuration

```swift
.binaryTarget(
    name: "RunAnywhereCoreBinary",
    url: "https://github.com/RunanywhereAI/runanywhere-binaries/releases/download/v0.0.1-dev.1f175bc/RunAnywhereCore.xcframework.zip",
    checksum: "4207fba7c79dc0586d610e86a08ec731dc7b8a7ae1ca43bddec2a88d59356a94"
)
```

### Benefits

- **No local builds required**: SDK consumers don't need to build runanywhere-core
- **Consistent versions**: All developers use the same binary version
- **Reduced repository size**: Large binaries (59.9MB) are not committed to git
- **Automatic caching**: SPM caches downloaded binaries for faster subsequent builds

## Local Development (Legacy)

Local XCFrameworks in this directory are **deprecated** and no longer used by the SDK. They remain for backward compatibility with older build scripts only.

### To update to a new release:

1. Find the latest release at: https://github.com/RunanywhereAI/runanywhere-binaries/releases
2. Download the `RunAnywhereCore.xcframework.zip` artifact
3. Generate the SHA256 checksum: `shasum -a 256 RunAnywhereCore.xcframework.zip`
4. Update `Package.swift` with the new URL and checksum
5. Test with `swift package resolve` and `swift build`

### Verifying the binary

```bash
# Download the binary
curl -L -o RunAnywhereCore.xcframework.zip \
  "https://github.com/RunanywhereAI/runanywhere-binaries/releases/download/v0.0.1-dev.1f175bc/RunAnywhereCore.xcframework.zip"

# Verify checksum
shasum -a 256 RunAnywhereCore.xcframework.zip
# Should output: 4207fba7c79dc0586d610e86a08ec731dc7b8a7ae1ca43bddec2a88d59356a94
```

## Architecture

The `RunAnywhereCore.xcframework` is a unified binary that includes:
- **ONNX Runtime backend**: STT, TTS, VAD capabilities
- **LlamaCPP backend**: LLM text generation with GGUF models
- **Multi-platform support**: iOS (arm64), iOS Simulator (arm64 + x86_64)

The XCFramework is consumed by Swift through the `CRunAnywhereCore` C bridge module, which exposes the native C++ API to Swift code.
