# Build and Installation Guide for RunAnywhere SDKs

This guide provides step-by-step instructions for building and installing the RunAnywhere SDK packages, particularly focusing on the RAG (Retrieval-Augmented Generation) module for React Native on Android.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Building Native Libraries (C++)](#building-native-libraries-c)
- [Compiling TypeScript Packages](#compiling-typescript-packages)
- [Installing Dependencies](#installing-dependencies)
- [Building and Installing Android APK](#building-and-installing-android-apk)
- [Troubleshooting](#troubleshooting)

## Prerequisites

Ensure you have the following installed:

- **Node.js**: v20.20.0 (npm v10+)
- **Java**: JDK 21.0.1
- **Android SDK**: API Level 36+
- **CMake**: 3.22+
- **Gradle**: 8.13 (wrapper)
- **React Native CLI**: `npm install -g react-native-cli`
- **Android NDK**: r25c or later (verified with 26.3.11579264)
- **TypeScript**: v5.x (`npm install -g typescript`)

## Building Native Libraries (C++)

### 1. Fix C++ Type Conversion Issues (if needed)

If you encounter JSON type conversion errors in the RAG backend, ensure explicit type conversions:

**File**: `sdk/runanywhere-commons/src/backends/rag/onnx_generator.cpp`

**Lines 146-147** (Vocabulary parsing):
```cpp
// Correct:
vocab_[item.key()] = item.value().get<int64_t>();
reverse_vocab_[item.value().get<int64_t>()] = item.key();

// Incorrect:
// vocab_[item.key()] = item.value();  // ❌ Missing .get<int64_t>()
```

**Lines 262-265** (Config parsing):
```cpp
// Correct:
max_context_length = config["max_context_length"].get<int>();
tokenizer_path = config["tokenizer_path"].get<std::string>();

// Incorrect:
// max_context_length = config["max_context_length"];  // ❌ Missing .get<int>()
```

### 2. Build Native Libraries for Android

```bash
cd examples/react-native/RunAnywhereAI/android
./gradlew :app:buildCMakeRelWithDebInfo[arm64-v8a]
```

This builds all native libraries:
- `libonnxruntime.so` - ONNX Runtime
- `libllama.so` - LlamaCPP
- `libwhisper.so` - WhisperCPP
- `librunanywherecore.so` - Core SDK
- `librac_backend_rag.so` - RAG backend
- And other supporting libraries

Expected output: ~14 `.so` files totaling ~121MB in:
```
app/build/intermediates/cxx/RelWithDebInfo/.../obj/arm64-v8a/
```

## Compiling TypeScript Packages

### 1. Compile RAG Package

The RAG package TypeScript source must be compiled before use:

```bash
cd sdk/runanywhere-react-native/packages/rag
npx tsc
```

This creates the `lib/` folder with:
- `index.js` - Main entry point
- `RAG.js` - RAG class implementation
- `index.d.ts` - Type definitions
- `RAG.d.ts` - RAG class types
- `specs/` - Generated Nitro module specs

**Verify compilation**:
```bash
ls -la lib/
# Should show: index.js, RAG.js, index.d.ts, RAG.d.ts, specs/
```

### 2. Compile Other Packages (if needed)

```bash
# Core package
cd sdk/runanywhere-react-native/packages/core
npx tsc

# ONNX package
cd sdk/runanywhere-react-native/packages/onnx
npx tsc

# LlamaCPP package
cd sdk/runanywhere-react-native/packages/llamacpp
npx tsc
```

## Installing Dependencies

### 1. Clean Previous Installations

```bash
cd examples/react-native/RunAnywhereAI
rm -rf node_modules
```

### 2. Install with npm (Recommended)

Use **npm** instead of pnpm or yarn to avoid workspace conflicts:

```bash
npm install
```

**Important**: If you see `postinstall-postinstall` errors, remove it from `package.json`:

```json
{
  "devDependencies": {
    // Remove this line:
    // "postinstall-postinstall": "^2.1.0"
  }
}
```

### 3. Reinstall Specific Package (if needed)

If you updated a package and need to refresh the symlink:

```bash
# Remove specific package
rm -rf node_modules/@runanywhere/rag

# Reinstall it
npm install @runanywhere/rag@file:../../../sdk/runanywhere-react-native/packages/rag
```

### 4. Clear Metro Bundler Cache

Always clear the Metro cache after package changes:

```bash
cd examples/react-native/RunAnywhereAI
rm -rf node_modules/.cache
npx react-native start --reset-cache
```

Keep Metro running in a separate terminal.

## Building and Installing Android APK

### 1. Clean Build (recommended for first build)

```bash
cd examples/react-native/RunAnywhereAI/android
./gradlew clean
./gradlew assembleDebug
```

Expected build time: 5-7 minutes for first build, 2-3 minutes for incremental builds.

### 2. Install APK on Emulator/Device

```bash
# Install APK
adb install -r app/build/outputs/apk/debug/app-debug.apk

# Launch app
adb shell am start -n com.runanywhereaI/.MainActivity
```

### 3. Monitor Logs

```bash
# Watch all logs
adb logcat

# Filter for RAG-related logs
adb logcat | grep -E "(RAG|ReactNativeJS)"

# Check specific error
adb logcat -d | grep "Cannot find module"
```

### 4. Verify Native Libraries Loaded

Check logcat for these success messages:

```
I RunAnywhereRAGPackage: Successfully loaded native library: runanywhererg
I RunAnywhereRAGPackage: Successfully loaded native library: librac_backend_rag
I Nitro.HybridObjectRegistry: Successfully registered HybridObject "RunAnywhereRAG"!
```

## Troubleshooting

### Issue 1: "Cannot find module" Error

**Symptoms**:
```
Error: Cannot find module
[RAGScreen] RAG module initialization failed
```

**Solution**:
1. Ensure TypeScript is compiled:
   ```bash
   cd sdk/runanywhere-react-native/packages/rag
   npx tsc
   ls lib/  # Should show index.js, RAG.js, etc.
   ```

2. Reinstall the package:
   ```bash
   cd examples/react-native/RunAnywhereAI
   rm -rf node_modules/@runanywhere/rag
   npm install @runanywhere/rag@file:../../../sdk/runanywhere-react-native/packages/rag
   ```

3. Clear Metro cache and restart:
   ```bash
   pkill -f "react-native start"
   rm -rf node_modules/.cache
   npx react-native start --reset-cache
   ```

4. Rebuild and reinstall APK:
   ```bash
   cd android
   ./gradlew clean assembleDebug
   adb install -r app/build/outputs/apk/debug/app-debug.apk
   ```

### Issue 2: CMake Build Errors

**Symptoms**:
```
error: cannot convert 'nlohmann::json_abi_v3_11_3::json' to 'int64_t'
```

**Solution**:
Add explicit `.get<Type>()` calls when extracting values from nlohmann::json objects. See [Building Native Libraries](#building-native-libraries-c) section.

### Issue 3: Gradle Daemon Issues

**Symptoms**:
```
CONFIGURING [stuck]
1 busy Daemon could not be reused
```

**Solution**:
```bash
cd android
./gradlew --stop
./gradlew assembleDebug
```

### Issue 4: Metro Bundler Configuration Warnings

**Symptoms**:
```
Warning: "dependency.platforms.ios.podspecPath" is not allowed
Warning: "dependency.hooks" is not allowed
```

**Impact**: These warnings are informational and don't affect Android builds. They indicate deprecated React Native config keys in package dependencies.

### Issue 5: Package Manager Conflicts

**Symptoms**:
```
Error: Cannot find workspace
pnpm/yarn workspace errors
```

**Solution**:
Use **npm** instead of pnpm or yarn for the example app:

```bash
cd examples/react-native/RunAnywhereAI
rm -rf node_modules package-lock.json yarn.lock pnpm-lock.yaml
npm install
```

### Issue 6: Missing Model in Catalog

**Symptoms**:
"All MiniLM L6 v2 (Embedding)" model disappears from catalog

**Solution**:
This is typically caused by the RAG module failing to initialize. Follow the steps in Issue 1 to fix module resolution.

### Issue 7: Watchman Cache Issues

**Symptoms**:
Metro bundler not detecting file changes or stale modules

**Solution**:
```bash
watchman watch-del-all
rm -rf /tmp/metro-* /tmp/haste-*
cd examples/react-native/RunAnywhereAI
npx react-native start --reset-cache
```

## Complete Build Workflow

Here's the complete workflow from scratch:

```bash
# 1. Build native libraries
cd examples/react-native/RunAnywhereAI/android
./gradlew :app:buildCMakeRelWithDebInfo[arm64-v8a]

# 2. Compile TypeScript packages
cd ../../sdk/runanywhere-react-native/packages/rag
npx tsc

cd ../core
npx tsc

cd ../onnx
npx tsc

cd ../llamacpp
npx tsc

# 3. Install dependencies
cd ../../../examples/react-native/RunAnywhereAI
rm -rf node_modules
npm install

# 4. Start Metro bundler
npx react-native start --reset-cache &

# 5. Build Android APK
cd android
./gradlew clean assembleDebug

# 6. Install and run
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.runanywhereaI/.MainActivity

# 7. Monitor logs
adb logcat | grep -E "(RAG|ReactNativeJS)"
```

## Package Structure

Understanding the package structure helps with troubleshooting:

```
sdk/runanywhere-react-native/packages/rag/
├── package.json           # "main": "lib/index.js"
├── src/                   # TypeScript source
│   ├── index.ts
│   ├── RAG.ts
│   └── specs/
├── lib/                   # Compiled JavaScript (generated by tsc)
│   ├── index.js          # Main entry point
│   ├── RAG.js
│   ├── index.d.ts
│   └── RAG.d.ts
├── android/              # Android native code
├── ios/                  # iOS native code
└── cpp/                  # C++ Nitro specs

examples/react-native/RunAnywhereAI/
├── node_modules/
│   └── @runanywhere/
│       └── rag/          # Symlink to ../../../sdk/.../packages/rag
├── android/
│   └── app/build/intermediates/cxx/.../
│       └── obj/arm64-v8a/  # Native .so libraries
└── package.json          # file: dependencies for local packages
```

## Key Points

1. **Always compile TypeScript before installing** - The `lib/` folder must exist
2. **Use npm for example apps** - Avoid pnpm/yarn workspace conflicts
3. **Clear Metro cache after package changes** - Use `--reset-cache`
4. **Reinstall packages when updating** - Refresh symlinks with `rm -rf node_modules/@runanywhere/[package]`
5. **Monitor native library loading** - Check logcat for "Successfully loaded native library"
6. **Clean builds for major changes** - Use `./gradlew clean` before `assembleDebug`

## iOS Build Notes

For iOS builds (to be documented after successful Android build):

1. Compile TypeScript packages (same as Android)
2. Run `pod install` in iOS directory
3. Build with Xcode or `npx react-native run-ios`

## Additional Resources

- React Native Documentation: https://reactnative.dev/
- Nitro Modules: https://github.com/margelo/nitro
- Android NDK: https://developer.android.com/ndk
- TypeScript Compiler: https://www.typescriptlang.org/docs/handbook/compiler-options.html

## Version Compatibility

- React Native: 0.83.1
- React: 19.2.0
- Nitro Modules: ^0.33.7
- Gradle: 8.13 (wrapper)
- Android API: 36 (compile/target)
- Build Tools: 36.0.0
- Node.js: v20.20.0
- Java: 21.0.1
- CMake: 3.22.1
- TypeScript: 5.x
- Android NDK: 26.3.11579264 (verified for all backends)

---

**Last Updated**: February 11, 2026  
**Tested Platform**: Android arm64-v8a, Medium Phone API 36.1 emulator
