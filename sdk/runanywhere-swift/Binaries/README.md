# Binary Distribution

## Remote Distribution (Default)

By default, the RunAnywhere Swift SDK uses **remote XCFramework distribution** via Swift Package Manager binary targets.

The XCFramework is automatically downloaded from the [runanywhere-binaries](https://github.com/RunanywhereAI/runanywhere-binaries) repository during package resolution.

### Default Configuration (testLocal = false)

```swift
.binaryTarget(
    name: "RunAnywhereCoreBinary",
    url: "https://github.com/RunanywhereAI/runanywhere-binaries/releases/download/v0.0.1-dev.e6b7a2f/RunAnywhereCore.xcframework.zip",
    checksum: "0c2da2bacb4931cdbe77eb0686ed20351ffe4ea1a66384f4522a61e1e4efa7aa"
)
```

### Benefits

- **No local builds required**: SDK consumers don't need to build runanywhere-core
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

2. **Place XCFramework**: Put `RunAnywhereCore.xcframework` in this `Binaries/` directory
   - Download from [runanywhere-binaries releases](https://github.com/RunanywhereAI/runanywhere-binaries/releases)
   - Or build locally from runanywhere-core

3. **Resolve package**: Run `swift package resolve` to update dependencies

### When to Use Local Mode

- Testing custom-built XCFrameworks before publishing
- Debugging native C++ code with local symbols
- Developing offline without network access
- Validating XCFramework changes before creating a release

**Important**: Local XCFrameworks should NOT be committed to git. The `.gitignore` excludes `*.xcframework` files.

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
  "https://github.com/RunanywhereAI/runanywhere-binaries/releases/download/v0.0.1-dev.e6b7a2f/RunAnywhereCore.xcframework.zip"

# Verify checksum
shasum -a 256 RunAnywhereCore.xcframework.zip
# Should output: 0c2da2bacb4931cdbe77eb0686ed20351ffe4ea1a66384f4522a61e1e4efa7aa
```

## Architecture

The `RunAnywhereCore.xcframework` is a unified binary that includes:

- **ONNX Runtime backend**: STT, TTS, VAD capabilities via Sherpa-ONNX
- **LlamaCPP backend**: LLM text generation with GGUF models and Metal GPU acceleration
- **Multi-platform support**: iOS (arm64), iOS Simulator (arm64 + x86_64), macOS (arm64 + x86_64)

The XCFramework is consumed by Swift through the `CRunAnywhereCore` C bridge module, which exposes the native C++ API to Swift code.

## macOS ONNX Runtime Dylib

**Important**: For macOS apps using the ONNX backend (STT/TTS/VAD), you must embed the ONNX Runtime dynamic library.

### Location

**Important**: The `onnxruntime-macos/` directory is **NOT committed to git**. You must obtain the ONNX Runtime dylib from one of these sources:

1. **Download from GitHub releases** (Recommended for production):
   - Get `onnxruntime-macos.zip` from [runanywhere-binaries releases](https://github.com/RunanywhereAI/runanywhere-binaries/releases)
   - Extract to `Binaries/onnxruntime-macos/`
   - The dylib will be at: `Binaries/onnxruntime-macos/libonnxruntime.dylib`

2. **Install via Homebrew** (Development only):

   ```bash
   brew install onnxruntime
   ```

   The system-wide installation is only recommended for development, not production deployment.

### Integration

1. **Copy to app bundle**: Copy `libonnxruntime.dylib` to `YourApp.app/Contents/Frameworks/`
2. **Set rpath**: Configure your app's rpath to find the dylib at runtime
3. **Code sign**: Ensure the dylib is properly code signed

### Why is this needed?

- iOS: ONNX Runtime is statically linked into the XCFramework
- macOS: ONNX Runtime is dynamically linked to reduce binary size and allow updates
