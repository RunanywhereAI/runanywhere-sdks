# Binary Distribution

## Overview

The RunAnywhere Swift SDK uses a **modular XCFramework architecture** with separate binaries for:

| XCFramework | Size | Contents |
|-------------|------|----------|
| `RACommons.xcframework` | ~1-2MB | Core commons library (service registry, model management, events) |
| `RABackendLlamaCPP.xcframework` | ~30MB | LLM backend (llama.cpp + GGML + Metal) |
| `RABackendONNX.xcframework` | ~400KB | STT/TTS/VAD backend wrapper (+ Sherpa-ONNX) |
| `onnxruntime.xcframework` | ~48MB | ONNX Runtime engine (linked separately) |

### Why Two ONNX XCFrameworks?

- **`RABackendONNX.xcframework`**: Contains the RunAnywhere wrapper code + Sherpa-ONNX static library for STT/TTS/VAD capabilities
- **`onnxruntime.xcframework`**: The ONNX Runtime inference engine itself

They are separate because:
- ONNX Runtime is huge (48MB) - shouldn't bloat every backend
- Different licensing (MIT for ONNX Runtime)
- Can be updated independently
- Some apps may already have ONNX Runtime from other dependencies

## Remote Distribution (Default)

By default, the RunAnywhere Swift SDK uses **remote XCFramework distribution** via Swift Package Manager binary targets.

XCFrameworks are automatically downloaded from the [runanywhere-binaries](https://github.com/RunanywhereAI/runanywhere-binaries) repository during package resolution.

### Default Configuration (testLocal = false)

```swift
// In Package.swift
.binaryTarget(
    name: "RACommonsBinary",
    url: "https://github.com/RunanywhereAI/runanywhere-binaries/releases/download/v2.0.0/RACommons.xcframework.zip",
    checksum: "..."
),
.binaryTarget(
    name: "RABackendLlamaCPPBinary",
    url: "https://github.com/RunanywhereAI/runanywhere-binaries/releases/download/v2.0.0/RABackendLlamaCPP.xcframework.zip",
    checksum: "..."
),
// ... etc
```

### Benefits

- **No local builds required**: SDK consumers don't need to build runanywhere-core or runanywhere-commons
- **Consistent versions**: All developers use the same binary version
- **Reduced repository size**: Large binaries are not committed to git
- **Automatic caching**: SPM caches downloaded binaries for faster subsequent builds

## Local Development Mode (testLocal = true)

For local testing or development with custom-built XCFrameworks, you can enable local mode by changing the `testLocal` flag in `Package.swift`.

### How to Enable Local Mode

1. **Edit Package.swift**: Change the flag at the top of the file
   ```swift
   // Set to `true` to use local XCFramework from Binaries/ directory
   let testLocal = true
   ```

2. **Place XCFrameworks**: Put the following in this `Binaries/` directory:
   - `RACommons.xcframework`
   - `RABackendLlamaCPP.xcframework`
   - `RABackendONNX.xcframework`
   - `onnxruntime.xcframework`

3. **Resolve package**: Run `swift package resolve` to update dependencies

### Building XCFrameworks Locally

To build the modular XCFrameworks from source:

```bash
cd sdks/sdk/runanywhere-commons
./scripts/build-ios.sh
```

This will create XCFrameworks in `dist/`:
- `RACommons.xcframework`
- `RABackendLlamaCPP.xcframework`
- `RABackendONNX.xcframework`

Copy them to this `Binaries/` directory.

### When to Use Local Mode

- Testing custom-built XCFrameworks before publishing
- Debugging native C++ code with local symbols
- Developing offline without network access
- Validating XCFramework changes before creating a release

**Important**: Local XCFrameworks should NOT be committed to git. The `.gitignore` excludes `*.xcframework` directories.

## macOS ONNX Runtime Dylib

**Important**: For macOS apps using the ONNX backend (STT/TTS/VAD), you must embed the ONNX Runtime dynamic library.

### Obtaining the Dylib

The `onnxruntime-macos/` directory is **NOT committed to git**. Obtain the ONNX Runtime dylib from:

1. **Download from GitHub releases** (Recommended for production):
   - Get `onnxruntime-macos.zip` from [runanywhere-binaries releases](https://github.com/RunanywhereAI/runanywhere-binaries/releases)
   - Extract to `Binaries/onnxruntime-macos/`
   - The dylib will be at: `Binaries/onnxruntime-macos/libonnxruntime.dylib`

2. **Install via Homebrew** (Development only):
   ```bash
   brew install onnxruntime
   ```

### Integration

1. **Copy to app bundle**: Copy `libonnxruntime.dylib` to `YourApp.app/Contents/Frameworks/`
2. **Set rpath**: Configure your app's rpath to find the dylib at runtime
3. **Code sign**: Ensure the dylib is properly code signed

### Why is this needed?

- **iOS**: ONNX Runtime is statically linked into `onnxruntime.xcframework`
- **macOS**: ONNX Runtime is dynamically linked to reduce binary size and allow independent updates

## Updating to a New Release

1. Find the latest release at: https://github.com/RunanywhereAI/runanywhere-binaries/releases
2. Download the XCFramework ZIPs
3. Generate SHA256 checksums: `shasum -a 256 *.zip`
4. Update `Package.swift` with the new URLs and checksums
5. Test with `swift package resolve` and `swift build`

## Architecture Support

| Platform | Architecture | Type |
|----------|--------------|------|
| iOS Device | arm64 | Static library |
| iOS Simulator | arm64 + x86_64 | Static library |
| macOS | arm64 + x86_64 | Static library (+ ONNX dylib) |
