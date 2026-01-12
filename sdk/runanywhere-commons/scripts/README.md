# RunAnywhere Commons - Build Scripts

Clean, organized build scripts for iOS and Android platforms.

## Directory Structure

```
scripts/
├── build-ios.sh              # iOS entry point: download → build → XCFrameworks
├── build-android.sh          # Android entry point: download → build → .so files
├── load-versions.sh          # Shared version loading from VERSIONS file
├── lint-cpp.sh               # C++ linting utility
├── ios/
│   ├── download-onnx.sh      # Download ONNX Runtime xcframework
│   ├── download-sherpa-onnx.sh # Download Sherpa-ONNX xcframework
│   └── README.md
└── android/
    ├── download-sherpa-onnx.sh # Download Sherpa-ONNX .so files
    ├── generate-maven-package.sh # Generate versions.json for releases
    └── README.md
```

## Quick Start

### iOS Build

```bash
# Build everything for iOS (RACommons + all backends)
./scripts/build-ios.sh

# Build with options
./scripts/build-ios.sh --clean              # Clean build first
./scripts/build-ios.sh --skip-download      # Use cached dependencies
./scripts/build-ios.sh --backend llamacpp   # Build only LlamaCPP
./scripts/build-ios.sh --package            # Create release ZIPs
```

**Output:**
```
dist/
├── RACommons.xcframework           # Core infrastructure
├── RABackendLLAMACPP.xcframework   # LLM text generation
└── RABackendONNX.xcframework       # STT/TTS/VAD (Sherpa-ONNX)
```

### Android Build

```bash
# Build everything for Android
./scripts/build-android.sh

# Build with options
./scripts/build-android.sh all              # All backends (default)
./scripts/build-android.sh llamacpp         # Only LlamaCPP
./scripts/build-android.sh onnx arm64-v8a   # ONNX for arm64 only
./scripts/build-android.sh --check          # Verify 16KB alignment
```

**Output:**
```
dist/android/
├── jni/arm64-v8a/              # JNI bridge
├── onnx/arm64-v8a/             # ONNX backend + runtime
├── llamacpp/arm64-v8a/         # LlamaCPP backend
├── whispercpp/arm64-v8a/       # WhisperCPP backend
└── packages/                    # Release ZIPs
```

## Build Options

### build-ios.sh

| Option | Description |
|--------|-------------|
| `--skip-download` | Skip downloading ONNX/Sherpa-ONNX (use cached) |
| `--skip-backends` | Build RACommons only, skip backends |
| `--backend NAME` | Build specific backend: `llamacpp`, `onnx`, or `all` |
| `--clean` | Clean build directories first |
| `--release` | Release build (default) |
| `--debug` | Debug build |
| `--package` | Create ZIP packages for release |

### build-android.sh

| Argument | Description |
|----------|-------------|
| `[backends]` | `onnx`, `llamacpp`, `whispercpp`, `all` (default: all) |
| `[abis]` | Comma-separated: `arm64-v8a,x86_64` (default: arm64-v8a) |
| `--check` | Verify 16KB alignment of built .so files |
| `--help` | Show usage |

## Integration with Platform SDKs

### Swift SDK

```bash
cd runanywhere-swift
./scripts/build-swift.sh --setup  # Downloads, builds, and sets up local mode
```

### Kotlin SDK

```bash
cd runanywhere-kotlin
./gradlew build -Prunanywhere.testLocal=true
```

## Version Management

All versions are centralized in `VERSIONS` file at the repo root:

```bash
# VERSIONS file defines:
IOS_DEPLOYMENT_TARGET=14.0
ANDROID_MIN_SDK=24
ONNX_VERSION_IOS=1.16.3
SHERPA_ONNX_VERSION_IOS=1.10.32
LLAMACPP_VERSION=b5095
```

Scripts load versions via `source scripts/load-versions.sh`.

## Prerequisites

### iOS

```bash
# Xcode command line tools
xcode-select --install

# CMake 3.22+
brew install cmake
```

### Android

```bash
# Set NDK path
export ANDROID_NDK_HOME=~/Library/Android/sdk/ndk/27.0.12077973

# CMake 3.22+
brew install cmake
```

## How It Works

### Build Flow

1. **Download Dependencies**
   - iOS: ONNX Runtime + Sherpa-ONNX xcframeworks
   - Android: Sherpa-ONNX .so files

2. **CMake Configure**
   - Uses toolchain files for cross-compilation
   - Backend selection via `RAC_BUILD_BACKENDS`, `RAC_BACKEND_LLAMACPP`, etc.

3. **CMake Build**
   - Builds RACommons core library
   - Builds enabled backends (LlamaCPP, ONNX, WhisperCPP)
   - FetchContent downloads llama.cpp/whisper.cpp automatically

4. **Package**
   - iOS: Creates XCFrameworks with `xcodebuild -create-xcframework`
   - Android: Copies .so files to dist directory

### CMake Flags

| Flag | Description |
|------|-------------|
| `RAC_BUILD_BACKENDS` | Enable backend builds (default: ON) |
| `RAC_BACKEND_LLAMACPP` | Build LlamaCPP backend |
| `RAC_BACKEND_ONNX` | Build ONNX backend |
| `RAC_BACKEND_WHISPERCPP` | Build WhisperCPP backend |
| `RAC_BUILD_PLATFORM` | Enable platform-specific builds |
| `RAC_BUILD_JNI` | Build JNI bridge (Android) |
