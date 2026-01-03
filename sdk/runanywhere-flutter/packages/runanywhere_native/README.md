# RunAnywhere Native

Native binaries package for the RunAnywhere Flutter SDK.

This package bundles the native libraries (`.so` files for Android, `XCFramework` for iOS) required for on-device AI capabilities including:

- **Speech-to-Text (STT)** - Whisper, Zipformer models via Sherpa-ONNX
- **Text-to-Speech (TTS)** - VITS/Piper models via Sherpa-ONNX
- **Language Models (LLM)** - GGUF models via llama.cpp, ONNX models
- **Voice Activity Detection (VAD)** - Silero VAD
- **Embeddings** - Text embeddings

## Usage

This package is a dependency of the main `runanywhere` package and should not be used directly. It is automatically included when you add `runanywhere` to your project.

```yaml
dependencies:
  runanywhere:
    path: ../runanywhere  # or from pub.dev
```

## Binary Configuration

### Remote Mode (Default - Production)

Binaries are automatically downloaded from GitHub releases during build:
- **Android**: Downloaded in `preBuild` task from `runanywhere-binaries` releases
- **iOS**: Downloaded in CocoaPods `prepare_command`

### Local Mode (Development)

For local development with custom-built binaries:

1. **Android**:
   ```bash
   # Build locally
   cd runanywhere-core/scripts/android && ./build.sh

   # Copy to package
   cp -R build/android/* packages/runanywhere_native/android/src/main/jniLibs/
   ```

   Edit `android/binary_config.gradle`:
   ```gradle
   testLocal = true
   ```

2. **iOS**:
   ```bash
   # Build locally
   cd runanywhere-core/scripts/ios && ./build.sh --all

   # Copy to package
   cp -R dist/RunAnywhereCore.xcframework packages/runanywhere_native/ios/Frameworks/
   ```

   Edit `ios/binary_config.rb`:
   ```ruby
   TEST_LOCAL = true
   ```

## Version Configuration

Binary versions are configured in:
- `android/binary_config.gradle` - Android binaries
- `ios/binary_config.rb` - iOS binaries
- `lib/runanywhere_native.dart` - Dart constants

Current version: `v0.0.1-dev.27bdcd0`

## Directory Structure

```
runanywhere_native/
├── lib/
│   └── runanywhere_native.dart     # Version constants
├── android/
│   ├── binary_config.gradle        # Android binary configuration
│   ├── build.gradle                # Android build with download task
│   └── src/main/
│       ├── AndroidManifest.xml
│       ├── jniLibs/                # Native .so files (downloaded/copied)
│       └── kotlin/.../Plugin.kt
├── ios/
│   ├── binary_config.rb            # iOS binary configuration
│   ├── runanywhere_native.podspec  # CocoaPods spec with download logic
│   ├── Classes/                    # Plugin files
│   └── Frameworks/                 # XCFramework (downloaded/copied)
└── README.md
```

## Native Libraries

### Android (jniLibs)

```
arm64-v8a/
  librunanywhere_bridge.so      # Main C API bridge
  libonnxruntime.so             # ONNX Runtime
  libsherpa-onnx-c-api.so       # Sherpa-ONNX C API
  librunanywhere_onnx.so        # ONNX backend
  librunanywhere_llamacpp.so    # LlamaCpp backend
  ...
armeabi-v7a/
  ...
x86_64/
  ...
```

### iOS (XCFramework)

```
RunAnywhereCore.xcframework/
  ios-arm64/
    RunAnywhereCore.framework/
  ios-arm64_x86_64-simulator/
    RunAnywhereCore.framework/
```

## Checksums

Binary integrity is verified using SHA-256 checksums:
- Android: Configured in `binary_config.gradle`
- iOS: Configured in `binary_config.rb`

If checksums don't match, the build will fail with an error message.

## License

MIT License - see LICENSE file for details.
