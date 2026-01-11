# RunAnywhere Core Build Scripts

Scripts are organized by platform for clarity.

## Directory Structure

```
scripts/
├── ios/                      # iOS build scripts
│   ├── build.sh              # Build xcframework (single or all backends)
│   ├── download-onnx.sh      # Download ONNX Runtime for iOS
│   ├── download-sherpa-onnx.sh  # Download Sherpa-ONNX for STT/TTS
│   ├── build-sherpa-onnx.sh  # Build Sherpa-ONNX from source (optional)
│   └── generate-spm-package.sh  # Generate Swift Package Manager package
│
├── macos/                    # macOS build scripts
│   ├── build.sh              # Build universal static library (arm64 + x86_64)
│   ├── download-onnx.sh      # Download ONNX Runtime for macOS (dylib)
│   ├── download-sherpa-onnx.sh  # Download Sherpa-ONNX for STT/TTS
│   └── README.md             # macOS-specific documentation
│
├── android/                  # Android build scripts
│   ├── build.sh              # Build native .so libraries (single or all backends)
│   ├── download-onnx.sh      # Download ONNX Runtime for Android
│   └── download-sherpa-onnx.sh  # Download Sherpa-ONNX for STT/TTS
│
├── build-xcframework.sh      # Create combined iOS + macOS XCFramework
│
└── README.md                 # This file
```

## Quick Start

### iOS

```bash
# Download dependencies
./scripts/ios/download-onnx.sh
./scripts/ios/download-sherpa-onnx.sh  # For STT/TTS support

# Build xcframework with all backends (recommended)
./scripts/ios/build.sh --all

# Build specific backend only
./scripts/ios/build.sh --onnx          # ONNX only
./scripts/ios/build.sh --llamacpp      # LlamaCPP only
```

**Output:**
- `dist/RunAnywhereCore.xcframework/` - Unified (all backends)

### macOS

```bash
# Download dependencies
./scripts/macos/download-onnx.sh
./scripts/macos/download-sherpa-onnx.sh  # For STT/TTS/VAD support

# Build universal library (arm64 + x86_64)
./scripts/macos/build.sh --all

# Build specific backend only
./scripts/macos/build.sh --onnx          # ONNX only
./scripts/macos/build.sh --llamacpp      # LlamaCPP only

# Create combined iOS + macOS XCFramework
./scripts/build-xcframework.sh
```

**Output:**

- `dist/libRunAnywhereCore.a` - Universal static library (includes Sherpa-ONNX)
- `dist/Headers-macOS/` - Headers for macOS
- `dist/onnxruntime-macos/` - ONNX Runtime dylib (must be embedded in app)

**Note:** macOS ONNX Runtime is a dynamic library. Your app must embed `libonnxruntime.dylib`.

### Android

```bash
# Download dependencies
./scripts/android/download-onnx.sh
./scripts/android/download-sherpa-onnx.sh  # For STT/TTS support

# Build .so with all backends (recommended)
./scripts/android/build.sh all

# Build specific backend only
./scripts/android/build.sh onnx
./scripts/android/build.sh llamacpp

# Specify ABIs (default: arm64-v8a)
./scripts/android/build.sh all arm64-v8a,armeabi-v7a,x86_64
```

**Output:**
- `dist/android/jni/` - Shared JNI bridge (required by all backends)
- `dist/android/onnx/` - ONNX backend libraries
- `dist/android/llamacpp/` - LlamaCPP backend libraries

## Backend Options

| Backend | iOS | Android | Capabilities |
|---------|-----|---------|--------------|
| `onnx` | Yes | Yes | STT, TTS, VAD, Embeddings, Text Gen |
| `llamacpp` | Yes | Yes | Text Generation (LLM) |
| `coreml` | Planned | N/A | Apple Neural Engine |
| `tflite` | Planned | Planned | TensorFlow Lite models |

## Prerequisites

### iOS

- Xcode with command line tools
- CMake (`brew install cmake`)
- ONNX Runtime: `./scripts/ios/download-onnx.sh`
- Sherpa-ONNX (optional, for STT/TTS): `./scripts/ios/download-sherpa-onnx.sh`

### macOS

- Xcode with command line tools
- CMake (`brew install cmake`)
- ONNX Runtime: `./scripts/macos/download-onnx.sh`
- Sherpa-ONNX (for STT/TTS/VAD): `./scripts/macos/download-sherpa-onnx.sh`

### Android

- Android NDK (set `ANDROID_NDK_HOME` or `NDK_HOME`)
- CMake (`brew install cmake`)
- ONNX Runtime: `./scripts/android/download-onnx.sh`
- Sherpa-ONNX (optional, for STT/TTS): `./scripts/android/download-sherpa-onnx.sh`

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `IOS_DEPLOYMENT_TARGET` | 14.0 | Minimum iOS version |
| `MACOS_DEPLOYMENT_TARGET` | 14.0 | Minimum macOS version |
| `ANDROID_API_LEVEL` | 24 | Minimum Android API level |
| `ANDROID_NDK_HOME` | Auto-detect | Path to Android NDK |

## CI/CD and Publishing

### GitHub Workflows

The following workflows are available in `.github/workflows/`:

| Workflow | Trigger | Description |
|----------|---------|-------------|
| `release-binaries.yml` | Tags, main branch, manual | **Main release workflow** - builds iOS+macOS+Android and publishes to public binaries repo |
| `build-apple.yml` | Tags, manual | Standalone Apple (iOS + macOS) build |
| `build-android.yml` | Tags, manual | Standalone Android build |

### Publishing Architecture

```text
runanywhere-core (PRIVATE)          runanywhere-binaries (PUBLIC)
        |                                      ^
        |    GitHub Actions                    |
        +------ build & publish -------------->+
                                               |
                               Swift SDK downloads from here
                               via Package.swift binary target
```

### Release Process

**Stable Release (e.g., v1.0.0):**

```bash
git tag v1.0.0
git push origin v1.0.0
```

**Prerelease (automatic on main):**

- Every merge to `main` creates a prerelease version
- Format: `1.0.1-dev.<commit-sha>`

### Published Artifacts

| Artifact | Description | Platforms |
|----------|-------------|-----------|
| `RunAnywhereCore.xcframework.zip` | Combined XCFramework | iOS device, iOS simulator, macOS |
| `onnxruntime-macos.zip` | ONNX Runtime dylib (macOS only) | macOS arm64 + x86_64 |
| `RunAnywhereONNX-android.zip` | Android ONNX native libs | arm64-v8a |
| `RunAnywhereLlamaCPP-android.zip` | Android LlamaCPP native libs | arm64-v8a |

### Consuming Artifacts

**Swift SDK (SPM):**

```swift
// In Package.swift
.binaryTarget(
    name: "RunAnywhereCoreBinary",
    url: "https://github.com/RunanywhereAI/runanywhere-binaries/releases/download/v1.0.0/RunAnywhereCore.xcframework.zip",
    checksum: "<sha256>"
)
```

**macOS Apps:**

1. Link with `RunAnywhereCore.xcframework`
2. Download and embed `onnxruntime-macos.zip` → `libonnxruntime.dylib`
3. Set rpath or embed in `YourApp.app/Contents/Frameworks/`

**Android (Kotlin SDK):**

The Kotlin SDK automatically downloads native libraries from GitHub releases during Gradle sync.
