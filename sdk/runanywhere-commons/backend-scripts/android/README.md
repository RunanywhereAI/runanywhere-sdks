# Android Build Scripts

Scripts for building RunAnywhere Core as native shared libraries (.so) for Android.

## Quick Start

```bash
# Download dependencies first
./download-onnx.sh
./download-sherpa-onnx.sh  # Optional, for STT/TTS

# Build all backends for arm64 (recommended)
./build.sh all

# Build specific backend
./build.sh llamacpp
./build.sh onnx

# Build for multiple ABIs
./build.sh all arm64-v8a,armeabi-v7a,x86_64
```

## Scripts

| Script | Purpose |
|--------|---------|
| `build.sh` | Build backends with shared JNI bridge |
| `download-onnx.sh` | Download ONNX Runtime for Android |
| `download-sherpa-onnx.sh` | Download Sherpa-ONNX for STT/TTS |
| `generate-maven-package.sh` | Generate versions.json manifest with checksums |

## build.sh

Builds native libraries with a shared JNI bridge that works across all backends.

### Usage

```bash
./build.sh [backends] [abis]

Backends:
  onnx        - ONNX Runtime backend (STT, TTS, VAD, Embeddings)
  llamacpp    - LlamaCPP backend (Text Generation)
  all         - All available backends (default)

ABIs:
  arm64-v8a   - 64-bit ARM (default, most devices)
  armeabi-v7a - 32-bit ARM (older devices)
  x86_64      - 64-bit x86 (emulators)
  x86         - 32-bit x86 (old emulators)
```

### Examples

```bash
# Build all backends for arm64 (default)
./build.sh
./build.sh all

# Build LlamaCPP only (for Text Generation)
./build.sh llamacpp

# Build ONNX only (for STT, TTS, VAD)
./build.sh onnx

# Build for multiple ABIs
./build.sh all arm64-v8a,x86_64

# Build specific backend for specific ABI
./build.sh llamacpp arm64-v8a,armeabi-v7a
```

### Output Structure

```
dist/android/
├── jni/                              # Shared JNI bridge (REQUIRED for all backends)
│   ├── arm64-v8a/
│   │   ├── librunanywhere_jni.so     # JNI wrapper
│   │   └── librunanywhere_bridge.so  # Core bridge
│   ├── include/
│   │   ├── runanywhere_bridge.h
│   │   └── types.h
│   └── [other ABIs]/
│
├── onnx/                             # ONNX backend libraries
│   └── arm64-v8a/
│       ├── librunanywhere_onnx.so    # ONNX backend
│       ├── libonnxruntime.so         # ONNX Runtime
│       └── libsherpa-onnx-jni.so     # Sherpa-ONNX (if included)
│
└── llamacpp/                         # LlamaCPP backend libraries
    └── arm64-v8a/
        ├── librunanywhere_llamacpp.so # LlamaCPP backend
        ├── libomp.so                  # OpenMP (for multi-threading)
        └── libc++_shared.so           # C++ standard library
```

### Size Reference (arm64-v8a)

| Component | Size |
|-----------|------|
| JNI bridge | ~1.5 MB |
| ONNX backend | ~15 MB |
| LlamaCPP backend | ~8 MB |
| Sherpa-ONNX (optional) | ~25 MB |

## Prerequisites

1. **Android NDK** (r25+)
   ```bash
   # Set environment variable
   export ANDROID_NDK_HOME=~/Library/Android/sdk/ndk/26.3.11579264
   # Or
   export NDK_HOME=~/Library/Android/sdk/ndk/26.3.11579264
   ```

2. **CMake** (3.22+)
   ```bash
   brew install cmake
   ```

3. **ONNX Runtime** (for ONNX backend)
   ```bash
   ./download-onnx.sh
   ```

4. **Sherpa-ONNX** (optional, for STT/TTS)
   ```bash
   ./download-sherpa-onnx.sh
   ```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ANDROID_NDK_HOME` | Auto-detect | Path to Android NDK |
| `NDK_HOME` | Auto-detect | Alternative NDK path variable |
| `ANDROID_API_LEVEL` | 24 | Minimum Android API level |

## Gradle Integration

### Module build.gradle.kts

```kotlin
android {
    defaultConfig {
        ndk {
            // Specify ABIs you want to support
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }
}
```

### Copy libraries to jniLibs

```bash
# Copy JNI bridge (required)
cp -r dist/android/jni/arm64-v8a/* app/src/main/jniLibs/arm64-v8a/

# Copy backend libraries (choose one or both)
cp -r dist/android/llamacpp/arm64-v8a/* app/src/main/jniLibs/arm64-v8a/
cp -r dist/android/onnx/arm64-v8a/* app/src/main/jniLibs/arm64-v8a/
```

### Load libraries in Kotlin

```kotlin
object RunAnywhereBridge {
    init {
        // Load in dependency order
        System.loadLibrary("c++_shared")      // C++ runtime (if using LlamaCPP)
        System.loadLibrary("omp")             // OpenMP (if using LlamaCPP)
        System.loadLibrary("runanywhere_bridge")
        System.loadLibrary("runanywhere_llamacpp")  // Or: runanywhere_onnx
        System.loadLibrary("runanywhere_jni")
    }

    external fun nativeCreateBackend(name: String): Long
    external fun nativeInitialize(handle: Long, config: String?): Boolean
    // ... other native methods
}
```

## ABI Selection Guide

| ABI | Target Devices | Emulator Support |
|-----|----------------|------------------|
| `arm64-v8a` | Most modern phones (2015+) | Apple Silicon Macs |
| `armeabi-v7a` | Older 32-bit phones | - |
| `x86_64` | - | Intel Macs, x86 emulators |
| `x86` | - | Old Android Studio emulators |

**Recommendation:** Start with `arm64-v8a` only for development. Add other ABIs for release builds.

## Local Development with Kotlin SDK

When developing the Kotlin SDK with local native libraries:

### Step 1: Build Native Libraries

```bash
cd runanywhere-core/

# 1. Download dependencies
./scripts/android/download-onnx.sh
./scripts/android/download-sherpa-onnx.sh

# 2. Build for ARM64 (most common)
ANDROID_NDK_HOME=~/Library/Android/sdk/ndk/27.0.12077973 \
NDK_HOME=~/Library/Android/sdk/ndk/27.0.12077973 \
./scripts/android/build.sh onnx arm64-v8a

# Verify output
ls -la dist/android/onnx/arm64-v8a/
```

### Step 2: Enable Local Mode in Kotlin SDK

```bash
cd sdks/sdk/runanywhere-kotlin/

# Build with local libraries
./gradlew build -Prunanywhere.testLocal=true

# Or add to gradle.properties for persistent local mode:
echo "runanywhere.testLocal=true" >> gradle.properties
```

### Step 3: Verify Configuration

```bash
./gradlew printNativeLibInfo
```

Expected output for local mode:

```text
Build Mode:        LOCAL
Native Version:    0.0.1-dev
runanywhere-core:  .../runanywhere-core
dist dir exists:   true
```

### Directory Structure (Local Mode)

The Kotlin SDK expects libraries at:

```text
runanywhere-core/dist/android/
├── jni/arm64-v8a/          # Shared JNI bridge
│   ├── librunanywhere_jni.so
│   └── librunanywhere_bridge.so
└── onnx/arm64-v8a/         # ONNX backend
    ├── librunanywhere_onnx.so
    ├── libonnxruntime.so
    └── libsherpa-onnx-*.so
```

### Switching Between Modes

```bash
# Local mode (use locally built libraries)
./gradlew build -Prunanywhere.testLocal=true

# Remote mode (download from GitHub releases)
./gradlew build
# or
./gradlew build -Prunanywhere.testLocal=false
```

## Troubleshooting

### "UnsatisfiedLinkError: couldn't find library"

1. Check library is in correct jniLibs folder:
   ```
   app/src/main/jniLibs/arm64-v8a/librunanywhere_jni.so
   ```

2. Verify ABI filter matches device:
   ```kotlin
   abiFilters += listOf("arm64-v8a")  // Must match target device
   ```

3. Load libraries in correct order (dependencies first).

### "NDK not found"

Set the NDK path:
```bash
export ANDROID_NDK_HOME=~/Library/Android/sdk/ndk/26.3.11579264
```

### Build fails with OpenMP errors

LlamaCPP requires OpenMP. The build script copies `libomp.so` automatically. Make sure it's included in your APK.

### Large APK size

1. Use ABI splits to create separate APKs per architecture:
   ```kotlin
   splits {
       abi {
           isEnable = true
           reset()
           include("arm64-v8a", "armeabi-v7a")
       }
   }
   ```

2. Include only the backend you need (LlamaCPP is smaller than ONNX).

## generate-maven-package.sh

Generates a `versions.json` manifest with URLs and SHA256 checksums for Android artifacts. This provides parity with the iOS `generate-spm-package.sh` script.

### Usage

```bash
./generate-maven-package.sh <version> <artifacts-dir>

# Example (in CI workflow after building artifacts)
./generate-maven-package.sh 1.0.0 ./dist/artifacts
```

### Output Files

| File | Purpose |
|------|---------|
| `versions.json` | JSON manifest with URLs and SHA256 checksums |
| `checksums-android.txt` | Simple checksum file for quick reference |

### versions.json Format

```json
{
  "version": "1.0.0",
  "platform": "android",
  "generated": "2024-01-15T10:30:00Z",
  "artifacts": {
    "RunAnywhereJNI": {
      "url": "https://github.com/RunanywhereAI/runanywhere-binaries/releases/download/v1.0.0/RunAnywhereJNI-android.zip",
      "sha256": "abc123...",
      "size": 1548576
    },
    "RunAnywhereONNX": {
      "url": "https://github.com/RunanywhereAI/runanywhere-binaries/releases/download/v1.0.0/RunAnywhereONNX-android.zip",
      "sha256": "def456...",
      "size": 15728640
    }
  }
}
```

### Checksum Validation in Kotlin SDK

```kotlin
// Fetch and validate checksum before downloading
val versionsJson = URL("$baseUrl/versions.json").readText()
val manifest = Json.decodeFromString<VersionsManifest>(versionsJson)
val expectedChecksum = manifest.artifacts["RunAnywhereONNX"]?.sha256

// After download, verify checksum
val actualChecksum = downloadedFile.sha256()
require(actualChecksum == expectedChecksum) { "Checksum mismatch!" }
```
