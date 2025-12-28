# 16KB Page Size Support - Implementation Guide

## Overview

Starting **November 1, 2025**, all Android apps targeting API level 35+ must support 16KB page sizes to be published on Google Play Store.

This document explains the fix implemented for the RunAnywhere Android app.

## Problem

Google Play was rejecting the app with error:
```
Your app does not support 16 KB memory page sizes.
```

**Root Cause**: The native libraries (`.so` files) from `runanywhere-core` were built with 4KB ELF alignment, which doesn't support 16KB page sizes.

## Requirements

For 16KB page size support, you need:

1. **ELF Segment Alignment**: All `.so` files must have LOAD segments aligned to 16KB (`align 2**14`)
2. **ZIP Alignment**: APK/AAB must be 16KB aligned
3. **No Hardcoded Page Sizes**: Code must use `getpagesize()` instead of `4096`

## Solution Implemented

### 1. Updated Native Build Configuration

**File**: `/runanywhere-core/src/bridge/jni/CMakeLists.txt`

Added 16KB alignment linker flags:
```cmake
# Android 16KB page size support (required for Android 15+)
if(ANDROID)
    target_link_options(runanywhere_jni PRIVATE
        -Wl,-z,max-page-size=16384
        -Wl,-z,common-page-size=16384
    )
    message(STATUS "Added 16KB page size alignment flags for runanywhere_jni")
endif()
```

### 2. Updated Build Script

**File**: `/runanywhere-core/scripts/android/build.sh`

Added CMake flags for all native builds:
```bash
-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON \
-DCMAKE_SHARED_LINKER_FLAGS="-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384"
```

### 3. App Build Configuration

**File**: `app/build.gradle.kts`

Confirmed proper packaging configuration:
```kotlin
packaging {
    jniLibs {
        // CRITICAL: useLegacyPackaging = true ensures proper 16KB alignment
        // with AGP 8.5.1+ during packaging
        useLegacyPackaging = true
    }
}
```

**Current Versions**:
- **Android Gradle Plugin**: 8.11.2 ✅ (>= 8.5.1 required)
- **NDK**: 27.1, 27.2, 28.0, 28.2, 29.0 available
- **Gradle**: 8.13

### 4. Manifest Property

**File**: `app/src/main/AndroidManifest.xml`

Added informational property (the real support comes from linker flags):
```xml
<property
    android:name="android.content.PROPERTY_SUPPORTS_16KB_PAGE_SIZE"
    android:value="true" />
```

**Important**: This property alone does NOT provide 16KB support - it's informational only.

## How to Rebuild

### Step 1: Rebuild Native Libraries

```bash
cd /path/to/runanywhere-core
./scripts/android/build.sh all
```

This will rebuild all native libraries with 16KB alignment.

### Step 2: Rebuild Android App

```bash
cd /path/to/sdks/examples/android/RunAnywhereAI
./gradlew clean
./gradlew assembleRelease
# OR for bundle:
./gradlew bundleRelease
```

### Step 3: Verify Alignment

Use the provided verification script:

```bash
cd /path/to/sdks/examples/android/RunAnywhereAI
./scripts/check_16kb_alignment.sh app/build/outputs/apk/release/app-release.apk
```

Expected output:
```
✅ All checks passed! This app supports 16KB page sizes.
```

## Verification Tools

### Manual Verification

**Check ELF Alignment**:
```bash
# Extract APK
unzip app-release.apk -d /tmp/apk_out

# Check a .so file
llvm-objdump -p /tmp/apk_out/lib/arm64-v8a/libonnxruntime.so | grep LOAD

# Should show: align 2**14 (16384 bytes)
```

**Check ZIP Alignment**:
```bash
zipalign -c -P 16 -v 4 app-release.apk
# Should output: Verification successful
```

### Using Android Studio

1. **Build > Analyze APK**
2. Open your APK/AAB
3. Navigate to `lib/` folder
4. Check the **Alignment** column - should show no warnings

## Testing

### Test on 16KB Device

1. **Enable 16KB page size on Pixel device** (Android 15+):
   ```bash
   adb shell
   # In device shell:
   # Go to Developer Options > Boot with 16KB page size
   # Reboot device
   ```

2. **Verify device is 16KB**:
   ```bash
   adb shell getconf PAGE_SIZE
   # Should return: 16384
   ```

3. **Install and test app**:
   ```bash
   adb install app-release.apk
   # Launch app and verify it works
   ```

### Test with Emulator

Use Android 15+ emulator with 16KB page size system image.

## Dependencies Affected

The following native libraries are rebuilt with 16KB alignment:

- `librunanywhere_jni.so` - JNI bridge
- `librunanywhere_bridge.so` - Core bridge
- `librunanywhere_onnx.so` - ONNX backend
- `librunanywhere_llamacpp.so` - LlamaCPP backend
- `libonnxruntime.so` - ONNX Runtime (third-party)
- `libsherpa-onnx-*.so` - Sherpa ONNX (third-party)
- `libc++_shared.so` - NDK C++ library
- `libomp.so` - OpenMP library

**Third-party libraries** (whisper-jni, android-vad) may also need updates if they're not 16KB aligned.

## Troubleshooting

### Issue: "Still getting rejection from Play Store"

**Solution**:
1. Verify you rebuilt native libraries: `ls -la /runanywhere-core/dist/android/unified/arm64-v8a/`
2. Ensure the SDK modules are using the new libraries
3. Run the verification script on the final APK/AAB before uploading
4. Check the upload is the correct build (not an old cached one)

### Issue: "App crashes on 16KB devices"

**Solution**:
1. Check logcat for page alignment errors
2. Verify all native code uses `getpagesize()` instead of hardcoded `4096`
3. Ensure all third-party native dependencies are 16KB compatible

### Issue: "Verification script shows misalignment"

**Solution**:
1. Clean build: `./gradlew clean`
2. Delete `.gradle` cache: `rm -rf ~/.gradle/caches`
3. Rebuild runanywhere-core native libraries
4. Rebuild app from scratch
5. Verify the native libraries in `runanywhere-core/dist/` are the new ones

## Performance Impact

According to Google's data, apps with 16KB alignment show:
- **3.16%** lower app launch times
- **4.56%** reduced power consumption
- **4.48%** faster camera performance
- **8%** improved system boot time

## References

- [Google Play 16KB Requirement](https://developer.android.com/guide/practices/page-sizes)
- [Android 16KB Page Size Guide](https://source.android.com/docs/core/architecture/16kb-page-size/16kb)
- [NDK Page Size Support](https://android-developers.googleblog.com/2025/07/transition-to-16-kb-page-sizes-android-apps-games-android-studio.html)

## Related Files

- `/runanywhere-core/src/bridge/jni/CMakeLists.txt` - JNI linker flags
- `/runanywhere-core/scripts/android/build.sh` - Build script with alignment flags
- `app/build.gradle.kts` - App packaging configuration
- `app/src/main/AndroidManifest.xml` - Manifest property
- `scripts/check_16kb_alignment.sh` - Verification tool

## Deadline

**November 1, 2025** - All apps targeting Android 15 (API 35+) MUST support 16KB page sizes for Google Play submission.

---

**Status**: ✅ Implemented
**Last Updated**: 2025-12-18
**Verified**: Pending rebuild and testing
