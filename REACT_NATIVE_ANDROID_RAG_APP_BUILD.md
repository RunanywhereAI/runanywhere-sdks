# Android Build Guide

Complete instructions for building native libraries and Android APKs with NDK 26.3.11579264.

## Table of Contents

1. [Quick Start](#quick-start)
2. [Prerequisites](#prerequisites)
3. [Build Workflow](#build-workflow)
4. [Script Reference](#script-reference)
5. [Manual Build Steps](#manual-build-steps)
6. [Development Iteration](#development-iteration)
7. [Verification](#verification)
8. [Troubleshooting](#troubleshooting)
9. [CI/CD Integration](#cicd-integration)

---

## Quick Start

### For Complete Rebuild (CI/Release)

```bash
bash rebuild-android-ndk26.sh
```

This builds everything:
- ✅ Native libraries (ONNX, RAG, LlamaCPP backends)
- ✅ Distributes `.so` files to React Native packages
- ✅ Builds Release APK
- ✅ Ready for testing or distribution

### For Development Iteration

```bash
# First time: build natives + APK
bash rebuild-android-ndk26.sh

# Subsequent iterations: just update UI/JS code
cd examples/react-native/RunAnywhereAI/android
./gradlew assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.runanywhereaI/.MainActivity
```

---

## Prerequisites

### Required Tools

- **NDK 26.3.11579264** — Install via Android Studio SDK Manager
  - Expected location: `~/Library/Android/sdk/ndk/26.3.11579264`
  - macOS/Linux: Adjust NDK path in script if needed
  
- **Android SDK** — API Level 36+ recommended
  - `~/Library/Android/sdk/`
  
- **Gradle** — Included in project (./gradlew)

- **Clang/CMake** — Required by NDK
  - Check: `which clang`

### Environment Variables (Set by Script)

```bash
export ANDROID_NDK_HOME=~/Library/Android/sdk/ndk/26.3.11579264
export ANDROID_NDK=$ANDROID_NDK_HOME
export NDK_ROOT=$ANDROID_NDK_HOME
```

### Device Setup

- **Physical Device** (Recommended):
  - Android 8.0+ (API 26+)
  - USB Debug Enabled
  - Connected via USB

- **Emulator** (Alternative):
  - API Level 26+
  - ARM64 architecture preferred
  - Sufficient disk space (2GB+ for APK)

---

## Build Workflow

### Overview Diagram

```
┌─────────────────────────────────────────────────────────┐
│ rebuild-android-ndk26.sh                                │
├─────────────────────────────────────────────────────────┤
│ Step 1: Clean build-android/                            │
├─────────────────────────────────────────────────────────┤
│ Step 2: Build Native Libraries                          │
│   └─> ./scripts/build-android.sh all arm64-v8a          │
│       Outputs: dist/android/{onnx,rag,llamacpp}/...     │
├─────────────────────────────────────────────────────────┤
│ Step 3: Distribute Libraries                            │
│   └─> SDK packages: sdk/runanywhere-react-native/...    │
│   └─> Example app: examples/react-native/.../...        │
├─────────────────────────────────────────────────────────┤
│ Step 4: Build & Install APK                             │
│   └─> ./gradlew :app:assembleRelease                    │
│   └─> Output: app/build/outputs/apk/release/...         │
└─────────────────────────────────────────────────────────┘
```

### Data Flow

```
sdk/runanywhere-commons/
  ├─ build-android/          (CMake build dir)
  └─ dist/android/           (Native libraries output)
      ├─ onnx/arm64-v8a/     (librac_backend_onnx.so, ...)
      ├─ rag/arm64-v8a/      (librac_backend_rag.so, ...)
      └─ llamacpp/arm64-v8a/ (librac_backend_llamacpp.so, ...)
         ↓ (Step 3 copies)
         
sdk/runanywhere-react-native/packages/
  ├─ onnx/android/src/main/jniLibs/arm64-v8a/
  ├─ rag/android/src/main/jniLibs/arm64-v8a/
  └─ llamacpp/android/src/main/jniLibs/arm64-v8a/
     ↓ (Step 4: Gradle includes)
     
examples/react-native/RunAnywhereAI/
  └─ android/app/build/outputs/apk/release/
     └─ app-release.apk (Final installable)
```

---

## Script Reference

### `rebuild-android-ndk26.sh`

**Location:** `/rebuild-android-ndk26.sh` (repository root)

**Purpose:** One-command full rebuild for CI/CD or clean builds

**What It Does:**

| Step | Action | Time |
|------|--------|------|
| 1 | Clean `build-android/` | < 1s |
| 2 | Build native libraries via CMake | 5-15m |
| 3 | Distribute `.so` files to packages | 1-2s |
| 4 | Build Release APK via Gradle | 3-5m |

**Total Time:** ~10-20 minutes (first run), ~8-15 minutes (cached)

**Output:**

```
✅ Build complete!

APK location:
-rw-r--r-- app/build/outputs/apk/release/app-release.apk (45MB)

Next steps:
1. adb install -r app/build/outputs/apk/release/app-release.apk
2. Test RAG initialization in the app
```

**Exit Codes:**

- `0` = Success
- `1` = NDK not found, build failed, or missing dist output

---

## Manual Build Steps

Use this if the script fails or you need fine-grained control.

### Step 1: Verify NDK

```bash
if [ ! -d ~/Library/Android/sdk/ndk/26.3.11579264 ]; then
    echo "❌ NDK 26 not found. Install via Android Studio SDK Manager."
    exit 1
fi

export ANDROID_NDK_HOME=~/Library/Android/sdk/ndk/26.3.11579264
echo "✓ NDK: $ANDROID_NDK_HOME"
```

### Step 2: Clean Previous Build

```bash
cd sdk/runanywhere-commons
rm -rf build-android
echo "✓ Cleaned build-android/"
```

### Step 3: Build Native Libraries

```bash
./scripts/build-android.sh all arm64-v8a
```

**What this builds:**

- `librac_commons.so` — Core infrastructure
- `librac_backend_onnx.so` — ONNX/embedding backend
- `librac_backend_onnx_jni.so` — JNI wrapper
- `librac_backend_rag.so` — RAG pipeline backend
- `librac_backend_llamacpp.so` — LLM backend
- `librac_backend_llamacpp_jni.so` — JNI wrapper
- `libonnxruntime.so` — ONNX inference engine
- `libsherpa-onnx-*.so` — Speech libraries (STT/TTS/VAD)
- `libomp.so` — OpenMP runtime

**Output Location:**

```
sdk/runanywhere-commons/dist/android/
├─ onnx/arm64-v8a/
│  ├─ libonnxruntime.so (15MB)
│  ├─ librac_backend_onnx.so (2MB)
│  └─ libsherpa-onnx-*.so (8MB total)
├─ rag/arm64-v8a/
│  ├─ librac_backend_rag.so (3MB)
│  ├─ librac_commons.so (8MB)
│  └─ librac_backend_onnx.so (dependency)
└─ llamacpp/arm64-v8a/
   ├─ librac_backend_llamacpp.so (12MB)
   ├─ librac_commons.so (8MB)
   ├─ libomp.so (500KB)
   └─ libc++_shared.so (2MB)
```

### Step 4: Distribute to React Native Packages

```bash
cd sdk/runanywhere-react-native/packages

# Create directories
mkdir -p onnx/android/src/main/jniLibs/arm64-v8a
mkdir -p rag/android/src/main/jniLibs/arm64-v8a
mkdir -p llamacpp/android/src/main/jniLibs/arm64-v8a

# Copy ONNX libraries
cp ../../runanywhere-commons/dist/android/onnx/arm64-v8a/*.so \
   onnx/android/src/main/jniLibs/arm64-v8a/

# Copy RAG libraries
cp ../../runanywhere-commons/dist/android/rag/arm64-v8a/*.so \
   rag/android/src/main/jniLibs/arm64-v8a/

# Copy LlamaCPP libraries
cp ../../runanywhere-commons/dist/android/llamacpp/arm64-v8a/*.so \
   llamacpp/android/src/main/jniLibs/arm64-v8a/

# Also copy to example app's node_modules
export RN_PACKAGES=../../../examples/react-native/RunAnywhereAI/node_modules/@runanywhere

mkdir -p $RN_PACKAGES/onnx/android/src/main/jniLibs/arm64-v8a
mkdir -p $RN_PACKAGES/rag/android/src/main/jniLibs/arm64-v8a
mkdir -p $RN_PACKAGES/llamacpp/android/src/main/jniLibs/arm64-v8a

cp ../../runanywhere-commons/dist/android/onnx/arm64-v8a/*.so \
   $RN_PACKAGES/onnx/android/src/main/jniLibs/arm64-v8a/
cp ../../runanywhere-commons/dist/android/rag/arm64-v8a/*.so \
   $RN_PACKAGES/rag/android/src/main/jniLibs/arm64-v8a/
cp ../../runanywhere-commons/dist/android/llamacpp/arm64-v8a/*.so \
   $RN_PACKAGES/llamacpp/android/src/main/jniLibs/arm64-v8a/
```

### Step 5: Build APK

```bash
cd examples/react-native/RunAnywhereAI/android

# Clean gradle cache for fresh build
rm -rf app/build/.cxx app/.cxx
rm -rf .gradle/*/

# Configure local.properties
cat > local.properties << EOF
sdk.dir=$HOME/Library/Android/sdk
EOF

# Build Release APK
./gradlew :app:assembleRelease

# Or Debug APK (faster for development)
./gradlew :app:assembleDebug
```

### Step 6: Install on Device

```bash
# Find the APK
APK_PATH="app/build/outputs/apk/release/app-release.apk"

# Install
adb install -r "$APK_PATH"

# Launch
adb shell am start -n com.runanywhereaI/.MainActivity

# View logs
adb logcat | grep -E "RAG|ONNX|RunAnywhere"
```

---

## Development Iteration

### Quick Update Cycle (After First Build)

If only JS/Java code changed:

```bash
# 1. Update code in examples/react-native/RunAnywhereAI/
# 2. Build debug APK (skips native recompile)
cd examples/react-native/RunAnywhereAI/android
./gradlew assembleDebug

# 3. Install
adb install -r app/build/outputs/apk/debug/app-debug.apk

# 4. Test
adb shell am start -n com.runanywhereaI/.MainActivity
```

**Time:** ~2-3 minutes (vs 15+ for full rebuild)

### When to Rebuild Natives

Rebuild `.so` files if you modify:

- `sdk/runanywhere-commons/src/backends/**/*.cpp` (Backend logic)
- `sdk/runanywhere-commons/src/infrastructure/**/*.cpp` (Infrastructure)
- Any build configuration files

```bash
# Quick rebuild (just natives, not APK)
cd sdk/runanywhere-commons
./scripts/build-android.sh all arm64-v8a

# Then distribute:
cd ../runanywhere-react-native/packages
# ... (copy commands as above)

# Then rebuild APK:
cd ../../../examples/react-native/RunAnywhereAI/android
./gradlew assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

---

## Verification

### Check Build Success

```bash
# 1. Verify native libraries exist
ls -lh examples/react-native/RunAnywhereAI/node_modules/@runanywhere/onnx/android/src/main/jniLibs/arm64-v8a/
# Expected: libonnxruntime.so, librac_backend_onnx.so, libsherpa-onnx-*.so

# 2. Verify APK
ls -lh examples/react-native/RunAnywhereAI/android/app/build/outputs/apk/release/app-release.apk
# Should be 40-50MB

# 3. Verify APK contents
unzip -l app/build/outputs/apk/release/app-release.apk | grep -E "\.so$" | head -20
```

### Test RAG on Device

```bash
# Install APK
adb install -r app/build/outputs/apk/release/app-release.apk

# Monitor logs while app starts
adb logcat -c
adb shell am start -n com.runanywhereaI/.MainActivity &
sleep 2
adb logcat | grep -E "RAG|ONNX|Embedding|STT\/TTS"

# You should see:
# - "✓ RAG Backend initialized"
# - "✓ ONNX Embedding Provider loaded"
# - "✓ Model downloaded: all-MiniLM-L6-v2"
# - "✓ RAG pipeline ready"
```

### Performance Metrics

```bash
# Check app memory usage
adb shell dumpsys meminfo com.runanywhereaI | grep TOTAL

# Check native library size
adb shell ls -l /data/app/com.runanywhereaI-*/lib/arm64/
```

---

## Troubleshooting

### NDK Not Found

**Error:**
```
❌ ERROR: NDK 26.3.11579264 not found at ~/Library/Android/sdk/ndk/26.3.11579264
```

**Solution:**

1. Install NDK 26 via Android Studio:
   - Android Studio → SDK Manager → SDK Tools → NDK (Side by side)
   - Select version 26.3.11579264

2. Or adjust script for your NDK location:
   ```bash
   # Find your NDK
   ls ~/Library/Android/sdk/ndk/
   
   # Edit rebuild-android-ndk26.sh, change ANDROID_NDK_HOME to match
   ```

### Build Failed: "undefined reference"

**Error:**
```
/path/to/library.a: undefined reference to `rac_backend_onnx_create_instance'
```

**Solution:**

1. Verify all libraries in `dist/android/` exist:
   ```bash
   find sdk/runanywhere-commons/dist/android -name "*.so" | sort
   ```

2. Check `CMakeLists.txt` link order — dependencies should be linked AFTER dependents:
   ```cmake
   target_link_libraries(app
       rac_backend_rag          # depends on rac_commons
       rac_commons              # always link last
   )
   ```

3. Clean and rebuild:
   ```bash
   cd sdk/runanywhere-commons
   rm -rf build-android
   ./scripts/build-android.sh all arm64-v8a
   ```

### APK Install Fails: "INSTALL_FAILED_NO_MATCHING_ABIS"

**Error:**
```
adb: error: cmd: Can't find service manager on device
```

**Solution:**

1. Device may not have arm64-v8a support:
   ```bash
   adb shell getprop ro.product.cpu.abilist
   # Should include: arm64-v8a
   ```

2. Rebuild for other ABI (if needed):
   ```bash
   cd sdk/runanywhere-commons
   ./scripts/build-android.sh all armeabi-v7a  # 32-bit ARM
   ```

3. Or try x86_64 emulator:
   ```bash
   ./scripts/build-android.sh all x86_64
   ```

### Gradle Build Hangs

**Solution:**

1. Increase Gradle heap:
   ```bash
   export GRADLE_OPTS="-Xmx4096m -XX:MaxPermSize=1024m"
   ```

2. Enable parallel builds:
   ```bash
   ./gradlew --parallel :app:assembleRelease
   ```

3. Skip test execution:
   ```bash
   ./gradlew :app:assembleRelease -x test
   ```

### Logcat Shows "dlopen failed: cannot locate symbol"

**Error:**
```
dlopen failed: cannot locate symbol "rac_backend_nnx_create"
```

**Cause:** Mismatch between expected symbol names and built libraries

**Solution:**

1. Verify symbols in library:
   ```bash
   nm -D app/src/main/jniLibs/arm64-v8a/librac_backend_onnx.so | grep rac_backend
   ```

2. Check C++ symbol mangling:
   ```bash
   # Should see symbols like: _Z...rac_backend_onnx_create...
   ```

3. Rebuild with correct CMake configuration:
   ```bash
   cd sdk/runanywhere-commons/build-android
   cmake .. -DCMAKE_ANDROID_ABI=arm64-v8a -DCMAKE_ANDROID_NDK=$ANDROID_NDK_HOME
   ```

---

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Build Android APK

on:
  push:
    branches: [main, feature/rag-improvements]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up NDK 26
        run: |
          sudo ~/Library/Android/sdk/cmdline-tools/latest/bin/sdkmanager "ndk;26.3.11579264"
      
      - name: Run rebuild script
        run: bash rebuild-android-ndk26.sh
      
      - name: Upload APK
        uses: actions/upload-artifact@v3
        with:
          name: app-release.apk
          path: examples/react-native/RunAnywhereAI/android/app/build/outputs/apk/release/app-release.apk
      
      - name: Verify APK
        run: |
          APK="examples/react-native/RunAnywhereAI/android/app/build/outputs/apk/release/app-release.apk"
          unzip -l "$APK" | grep -c "\.so$"  # Should find native libraries
```

### Local Pre-commit Hook

```bash
# .git/hooks/pre-commit
#!/bin/bash

# If C++ files changed, require native rebuild
if git diff --cached --name-only | grep -q "\.cpp$\|\.hpp$"; then
    echo "⚠️  C++ files modified. Run: bash rebuild-android-ndk26.sh"
    exit 1
fi

exit 0
```

---

## Appendix: File Structure

```
runanywhere-sdks/
├── rebuild-android-ndk26.sh        ← MAIN SCRIPT
├── ANDROID_BUILD.md                ← THIS FILE
│
├── sdk/
│   ├── runanywhere-commons/
│   │   ├── scripts/
│   │   │   └── build-android.sh    (Step 2 target)
│   │   ├── build-android/          (CMake output)
│   │   └── dist/android/           (Library distribution source)
│   │
│   └── runanywhere-react-native/packages/
│       ├── onnx/android/src/main/jniLibs/
│       ├── rag/android/src/main/jniLibs/
│       └── llamacpp/android/src/main/jniLibs/
│
└── examples/
    └── react-native/RunAnywhereAI/
        ├── android/                (Step 4 target)
        │   ├── app/build/outputs/apk/release/app-release.apk
        │   └── app/build/outputs/apk/debug/app-debug.apk
        └── node_modules/@runanywhere/ (Step 3 target)
            ├── onnx/android/src/main/jniLibs/
            ├── rag/android/src/main/jniLibs/
            └── llamacpp/android/src/main/jniLibs/
```

---

## Summary

| Need | Command | Time |
|------|---------|------|
| Full CI rebuild | `bash rebuild-android-ndk26.sh` | 15-20m |
| Rebuild natives only | `cd sdk/runanywhere-commons && ./scripts/build-android.sh all arm64-v8a` | 5-15m |
| Rebuild APK only | `cd examples/.../android && ./gradlew assembleDebug` | 2-3m |
| Install on device | `adb install -r app/build/outputs/apk/.../app.apk` | 30-60s |
| View logs | `adb logcat \| grep RAG` | continuous |

**Questions?** Check [Troubleshooting](#troubleshooting) or edit this file as you discover new issues.
