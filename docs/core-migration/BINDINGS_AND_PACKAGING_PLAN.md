# Bindings and Packaging Plan

## Overview

This document outlines the concrete packaging strategy for distributing the shared RunAnywhere Core to all platform SDKs.

---

## iOS Packaging

### XCFramework Structure

```
RunAnywhereCore.xcframework/
├── Info.plist
├── ios-arm64/
│   └── RunAnywhereCore.framework/
│       ├── Headers/
│       │   ├── ra_core.h          # Umbrella header
│       │   ├── ra_types.h         # Type definitions
│       │   ├── ra_llm.h           # LLM API
│       │   ├── ra_stt.h           # STT API
│       │   ├── ra_tts.h           # TTS API
│       │   ├── ra_vad.h           # VAD API
│       │   └── ra_events.h        # Event API
│       ├── Modules/
│       │   └── module.modulemap
│       └── RunAnywhereCore        # Static library (.a)
├── ios-arm64-simulator/
│   └── RunAnywhereCore.framework/
└── ios-arm64-maccatalyst/         # Optional: Mac Catalyst
    └── RunAnywhereCore.framework/
```

### Module Map

```
// module.modulemap
module RunAnywhereCore {
    umbrella header "ra_core.h"
    export *
    module * { export * }

    link "c++"
    link "z"
    link "bz2"
}
```

### Swift Wrapper Strategy

```swift
// RunAnywhereCore.swift - Thin Swift wrapper
import CRunAnywhereCore  // Import C module

public final class RunAnywhereCore {
    private var llmHandle: ra_llm_handle_t?

    public func initialize(config: SDKConfiguration) throws {
        var cConfig = ra_init_config_t()
        cConfig.api_key = config.apiKey?.cString(using: .utf8)
        cConfig.base_url = config.baseURL?.cString(using: .utf8)
        cConfig.environment = ra_environment_t(rawValue: config.environment.rawValue)

        let result = ra_initialize(&cConfig, &platformAdapter)
        guard result == RA_SUCCESS else {
            throw SDKError.initializationFailed(code: result)
        }
    }
}
```

### ObjC Bridging Header

```objc
// RunAnywhereCore-Bridging-Header.h
#import <RunAnywhereCore/ra_core.h>
```

### Build Script

```bash
#!/bin/bash
# build-ios-xcframework.sh

set -e

BUILD_DIR="build/ios"
OUTPUT_DIR="dist"

# Build for device
xcodebuild -project RunAnywhereCore.xcodeproj \
    -scheme RunAnywhereCore \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$BUILD_DIR/device" \
    ONLY_ACTIVE_ARCH=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES

# Build for simulator
xcodebuild -project RunAnywhereCore.xcodeproj \
    -scheme RunAnywhereCore \
    -configuration Release \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$BUILD_DIR/simulator" \
    ONLY_ACTIVE_ARCH=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES

# Create XCFramework
xcodebuild -create-xcframework \
    -framework "$BUILD_DIR/device/Build/Products/Release-iphoneos/RunAnywhereCore.framework" \
    -framework "$BUILD_DIR/simulator/Build/Products/Release-iphonesimulator/RunAnywhereCore.framework" \
    -output "$OUTPUT_DIR/RunAnywhereCore.xcframework"

# Create checksum
shasum -a 256 "$OUTPUT_DIR/RunAnywhereCore.xcframework.zip" > "$OUTPUT_DIR/RunAnywhereCore.xcframework.zip.sha256"
```

### CocoaPods Podspec

```ruby
# RunAnywhereCore.podspec
Pod::Spec.new do |s|
  s.name         = 'RunAnywhereCore'
  s.version      = '1.0.0'
  s.summary      = 'RunAnywhere native core library'
  s.homepage     = 'https://github.com/RunanywhereAI/runanywhere'
  s.license      = { :type => 'MIT', :file => 'LICENSE' }
  s.author       = { 'RunAnywhere' => 'support@runanywhere.ai' }
  s.source       = { :http => "https://github.com/RunanywhereAI/runanywhere/releases/download/v#{s.version}/RunAnywhereCore.xcframework.zip",
                     :sha256 => 'CHECKSUM_HERE' }

  s.ios.deployment_target = '14.0'
  s.osx.deployment_target = '11.0'

  s.vendored_frameworks = 'RunAnywhereCore.xcframework'

  s.pod_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_LDFLAGS' => '-lc++ -lz -lbz2'
  }
end
```

---

## Android Packaging

### AAR Structure

```
runanywhere-core-{version}.aar
├── AndroidManifest.xml
├── classes.jar                    # JNI wrapper classes
├── jni/
│   ├── arm64-v8a/
│   │   ├── librunanywhere_core.so
│   │   ├── libonnxruntime.so
│   │   └── libllama.so
│   ├── armeabi-v7a/
│   │   └── ... (same .so files)
│   └── x86_64/
│       └── ... (same .so files)
├── R.txt
└── proguard.txt
```

### JNI Surface

```java
// RunAnywhereCore.java
package ai.runanywhere.core;

public class RunAnywhereCore {
    static {
        System.loadLibrary("runanywhere_core");
    }

    // Native methods
    private static native int nativeInitialize(String configJson, PlatformAdapter adapter);
    private static native int nativeShutdown();

    private static native long nativeLlmCreate();
    private static native int nativeLlmInitialize(long handle, String configJson);
    private static native String nativeLlmGenerate(long handle, String prompt, String optionsJson);
    private static native void nativeLlmGenerateStream(long handle, String prompt, String optionsJson,
                                                        StreamCallback callback);
    private static native void nativeLlmCancel(long handle);
    private static native void nativeLlmDestroy(long handle);

    // ... similar for STT, TTS, VAD

    // Callback interface
    public interface StreamCallback {
        void onToken(String token, boolean isComplete, String resultJson);
    }
}
```

### JNI Implementation

```cpp
// runanywhere_jni.cpp
#include <jni.h>
#include "ra_core.h"

extern "C" {

JNIEXPORT jint JNICALL
Java_ai_runanywhere_core_RunAnywhereCore_nativeInitialize(
    JNIEnv* env, jclass clazz, jstring configJson, jobject adapter) {

    const char* config = env->GetStringUTFChars(configJson, nullptr);

    // Create platform adapter from Java object
    ra_platform_adapter_t platformAdapter = createJniAdapter(env, adapter);

    ra_init_config_t initConfig = parseConfig(config);
    ra_result_t result = ra_initialize(&initConfig, &platformAdapter);

    env->ReleaseStringUTFChars(configJson, config);
    return result;
}

JNIEXPORT void JNICALL
Java_ai_runanywhere_core_RunAnywhereCore_nativeLlmGenerateStream(
    JNIEnv* env, jclass clazz, jlong handle, jstring prompt, jstring optionsJson,
    jobject callback) {

    // Store callback reference
    JavaVM* jvm;
    env->GetJavaVM(&jvm);
    jobject globalCallback = env->NewGlobalRef(callback);

    ra_llm_stream_callback_t streamCallback = [](const char* token, bool isComplete,
                                                   const ra_llm_result_t* result, void* context) {
        // Attach to JVM thread
        JNIEnv* cbEnv;
        jvm->AttachCurrentThread(&cbEnv, nullptr);

        jobject cb = (jobject)context;
        jclass cbClass = cbEnv->GetObjectClass(cb);
        jmethodID onToken = cbEnv->GetMethodID(cbClass, "onToken", "(Ljava/lang/String;ZLjava/lang/String;)V");

        jstring jToken = cbEnv->NewStringUTF(token);
        jstring jResult = cbEnv->NewStringUTF(resultToJson(result).c_str());

        cbEnv->CallVoidMethod(cb, onToken, jToken, isComplete, jResult);

        if (isComplete) {
            cbEnv->DeleteGlobalRef(cb);
        }
    };

    const char* promptStr = env->GetStringUTFChars(prompt, nullptr);
    ra_llm_options_t options = parseOptions(optionsJson);

    ra_llm_generate_stream((ra_llm_handle_t)handle, promptStr, &options,
                           streamCallback, globalCallback);

    env->ReleaseStringUTFChars(prompt, promptStr);
}

} // extern "C"
```

### Symbol Stripping

```bash
# strip-symbols.sh
# Keep only public symbols

for abi in arm64-v8a armeabi-v7a x86_64; do
    # Strip debug symbols
    $NDK/toolchains/llvm/prebuilt/*/bin/llvm-strip \
        --strip-debug \
        jniLibs/$abi/librunanywhere_core.so

    # Create version script to hide internal symbols
    cat > version.script << 'EOF'
{
    global:
        Java_ai_runanywhere_*;
        ra_*;
    local:
        *;
};
EOF

done
```

### ProGuard/R8 Configuration

```proguard
# proguard-rules.pro
-keep class ai.runanywhere.core.** { *; }
-keepclassmembers class ai.runanywhere.core.** {
    native <methods>;
}
-dontwarn ai.runanywhere.core.**
```

### Gradle Build

```kotlin
// build.gradle.kts
android {
    namespace = "ai.runanywhere.core"
    compileSdk = 34

    defaultConfig {
        minSdk = 24

        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }

        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++17"
                arguments += "-DANDROID_STL=c++_shared"
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}
```

---

## Flutter Packaging

### Native Library Distribution

```
runanywhere_flutter/
├── ios/
│   ├── Frameworks/
│   │   └── RunAnywhereCore.xcframework/
│   ├── Classes/
│   │   └── RunAnywherePlugin.swift
│   └── runanywhere.podspec
├── android/
│   ├── src/main/
│   │   ├── jniLibs/
│   │   │   ├── arm64-v8a/librunanywhere_core.so
│   │   │   └── ...
│   │   └── kotlin/
│   │       └── RunAnywherePlugin.kt
│   └── build.gradle
└── lib/
    └── native/
        ├── native_backend.dart      # FFI bindings
        ├── ffi_types.dart
        └── platform_loader.dart
```

### dart:ffi Bindings

```dart
// native_backend.dart
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// Type definitions matching C headers
typedef RaResultT = Int32;
typedef RaLlmHandleT = Pointer<Void>;

// Native function signatures
typedef RaInitializeNative = Int32 Function(Pointer<RaInitConfig>, Pointer<RaPlatformAdapter>);
typedef RaInitializeDart = int Function(Pointer<RaInitConfig>, Pointer<RaPlatformAdapter>);

typedef RaLlmGenerateNative = Int32 Function(RaLlmHandleT, Pointer<Utf8>, Pointer<RaLlmOptions>, Pointer<RaLlmResult>);
typedef RaLlmGenerateDart = int Function(RaLlmHandleT, Pointer<Utf8>, Pointer<RaLlmOptions>, Pointer<RaLlmResult>);

class NativeBackend {
  late final DynamicLibrary _lib;

  // Function bindings
  late final RaInitializeDart _raInitialize;
  late final RaLlmGenerateDart _raLlmGenerate;

  NativeBackend() {
    _lib = _loadLibrary();
    _bindFunctions();
  }

  DynamicLibrary _loadLibrary() {
    if (Platform.isIOS) {
      return DynamicLibrary.executable();
    } else if (Platform.isAndroid) {
      return DynamicLibrary.open('librunanywhere_core.so');
    } else if (Platform.isMacOS) {
      return DynamicLibrary.open('libRunAnywhereCore.dylib');
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('libRunAnywhereCore.so');
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('RunAnywhereCore.dll');
    }
    throw UnsupportedError('Unsupported platform');
  }

  void _bindFunctions() {
    _raInitialize = _lib.lookupFunction<RaInitializeNative, RaInitializeDart>('ra_initialize');
    _raLlmGenerate = _lib.lookupFunction<RaLlmGenerateNative, RaLlmGenerateDart>('ra_llm_generate');
    // ... more bindings
  }

  int initialize(Map<String, dynamic> config) {
    final configPtr = _createConfigStruct(config);
    final adapterPtr = _createAdapterStruct();
    final result = _raInitialize(configPtr, adapterPtr);
    calloc.free(configPtr);
    calloc.free(adapterPtr);
    return result;
  }
}
```

### Platform Plugin Structure

```dart
// runanywhere_flutter_platform_interface.dart
abstract class RunAnywhereFlutterPlatform extends PlatformInterface {
  Future<void> initialize(Map<String, dynamic> config);
  Future<String> generate(String prompt, Map<String, dynamic> options);
  Stream<String> generateStream(String prompt, Map<String, dynamic> options);
  // ... more methods
}

// runanywhere_flutter_method_channel.dart
class MethodChannelRunAnywhereFlutter extends RunAnywhereFlutterPlatform {
  final _nativeBackend = NativeBackend();

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    final result = _nativeBackend.initialize(config);
    if (result != 0) {
      throw RunAnywhereException(result);
    }
  }
}
```

---

## React Native Packaging

### Nitrogen/JSI Approach

```typescript
// RunAnywhere.nitro.ts
import { HybridObject } from 'react-native-nitro-modules'

export interface RunAnywhere extends HybridObject<{ ios: 'c++'; android: 'c++' }> {
  initialize(configJson: string): Promise<void>

  // LLM
  llmCreate(): Promise<number>
  llmInitialize(handle: number, configJson: string): Promise<void>
  llmGenerate(handle: number, prompt: string, optionsJson: string): Promise<string>
  llmGenerateStream(handle: number, prompt: string, optionsJson: string,
                     callback: (token: string, isComplete: boolean, resultJson: string) => void): Promise<void>
  llmCancel(handle: number): Promise<void>
  llmDestroy(handle: number): Promise<void>

  // STT, TTS, VAD similar...
}
```

### C++ HybridObject

```cpp
// HybridRunAnywhere.hpp
#include <NitroModules/HybridObject.hpp>
#include "ra_core.h"

class HybridRunAnywhere : public HybridRunAnywhereSpec {
public:
    HybridRunAnywhere() : HybridObject(TAG) {}

    std::shared_ptr<Promise<void>> initialize(const std::string& configJson) override {
        return Promise<void>::async([this, configJson]() {
            ra_init_config_t config = parseConfig(configJson);
            ra_platform_adapter_t adapter = createJsiAdapter();
            ra_result_t result = ra_initialize(&config, &adapter);
            if (result != RA_SUCCESS) {
                throw std::runtime_error(ra_error_message(result));
            }
        });
    }

    std::shared_ptr<Promise<std::string>> llmGenerate(
        double handle, const std::string& prompt, const std::string& optionsJson) override {

        return Promise<std::string>::async([=]() {
            ra_llm_handle_t h = (ra_llm_handle_t)(intptr_t)handle;
            ra_llm_options_t options = parseOptions(optionsJson);
            ra_llm_result_t result;

            ra_result_t status = ra_llm_generate(h, prompt.c_str(), &options, &result);
            if (status != RA_SUCCESS) {
                throw std::runtime_error(ra_error_message(status));
            }

            std::string text = result.text;
            ra_llm_result_free(&result);
            return text;
        });
    }

    void llmGenerateStream(double handle, const std::string& prompt,
                           const std::string& optionsJson,
                           std::function<void(std::string, bool, std::string)> callback) override {

        ra_llm_handle_t h = (ra_llm_handle_t)(intptr_t)handle;
        ra_llm_options_t options = parseOptions(optionsJson);

        // Store callback for use in C callback
        auto sharedCallback = std::make_shared<decltype(callback)>(std::move(callback));

        ra_llm_stream_callback_t cCallback = [](const char* token, bool isComplete,
                                                  const ra_llm_result_t* result, void* context) {
            auto& cb = *static_cast<decltype(sharedCallback)*>(context);
            (*cb)(token, isComplete, resultToJson(result));
        };

        ra_llm_generate_stream(h, prompt.c_str(), &options, cCallback, sharedCallback.get());
    }

private:
    static constexpr auto TAG = "RunAnywhere";
};
```

### Native Module Loading

```cpp
// cpp-adapter.cpp (Android)
#include <jni.h>
#include "HybridRunAnywhere.hpp"

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
    // Load dependencies in order
    dlopen("libc++_shared.so", RTLD_NOW);
    dlopen("libonnxruntime.so", RTLD_NOW);
    dlopen("librunanywhere_core.so", RTLD_NOW);

    return JNI_VERSION_1_6;
}
```

---

## CI Build Matrix

### GitHub Actions Workflow

```yaml
# .github/workflows/build-core.yml
name: Build Core Libraries

on:
  push:
    branches: [main]
    tags: ['v*']
  pull_request:
    branches: [main]

jobs:
  build-ios:
    runs-on: macos-14  # Apple Silicon
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Build XCFramework
        run: ./scripts/build-ios-xcframework.sh

      - name: Create Checksum
        run: |
          cd dist
          shasum -a 256 RunAnywhereCore.xcframework.zip > RunAnywhereCore.xcframework.zip.sha256

      - uses: actions/upload-artifact@v4
        with:
          name: ios-xcframework
          path: dist/RunAnywhereCore.xcframework*

  build-android:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        abi: [arm64-v8a, armeabi-v7a, x86_64]
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Set up NDK
        uses: nttld/setup-ndk@v1
        with:
          ndk-version: r25c

      - name: Build for ${{ matrix.abi }}
        run: ./scripts/build-android.sh ${{ matrix.abi }}

      - uses: actions/upload-artifact@v4
        with:
          name: android-${{ matrix.abi }}
          path: dist/jniLibs/${{ matrix.abi }}/*.so

  package-android:
    needs: build-android
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
        with:
          pattern: android-*
          path: jniLibs

      - name: Create AAR
        run: ./scripts/package-android-aar.sh

      - uses: actions/upload-artifact@v4
        with:
          name: android-aar
          path: dist/runanywhere-core-*.aar

  release:
    if: startsWith(github.ref, 'refs/tags/')
    needs: [build-ios, package-android]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4

      - name: Create Release
        uses: softprops/action-gh-release@v1
        with:
          files: |
            ios-xcframework/RunAnywhereCore.xcframework.zip
            ios-xcframework/RunAnywhereCore.xcframework.zip.sha256
            android-aar/runanywhere-core-*.aar
```

### Caching Strategy

```yaml
# Cache ONNX Runtime and LlamaCpp builds
- uses: actions/cache@v4
  with:
    path: |
      ~/.cache/onnxruntime
      ~/.cache/llamacpp
    key: deps-${{ runner.os }}-${{ hashFiles('**/deps.lock') }}

# Cache CMake build
- uses: actions/cache@v4
  with:
    path: build
    key: build-${{ runner.os }}-${{ matrix.abi }}-${{ hashFiles('CMakeLists.txt', 'src/**') }}
```

### Artifact Naming Convention

```
runanywhere-core-{version}-{platform}-{arch}.{ext}

Examples:
- runanywhere-core-1.0.0-ios.xcframework.zip
- runanywhere-core-1.0.0-android-arm64-v8a.so
- runanywhere-core-1.0.0-android.aar
- runanywhere-core-1.0.0-macos-arm64.dylib
- runanywhere-core-1.0.0-linux-x86_64.so
- runanywhere-core-1.0.0-windows-x86_64.dll
```

---

## Testing Strategy

### Core Unit Tests (C++)

```cpp
// tests/test_vad.cpp
#include <gtest/gtest.h>
#include "ra_core.h"

class VADTest : public ::testing::Test {
protected:
    ra_vad_handle_t handle;

    void SetUp() override {
        ra_vad_config_t config = {
            .speech_threshold = 0.5f,
            .silence_threshold = 0.3f,
            .min_speech_frames = 3,
            .min_silence_frames = 5
        };
        ASSERT_EQ(RA_SUCCESS, ra_vad_create(&config, &handle));
    }

    void TearDown() override {
        ra_vad_destroy(handle);
    }
};

TEST_F(VADTest, DetectsSpeech) {
    float speech_audio[1600];  // 100ms at 16kHz
    generateSpeechSignal(speech_audio, 1600);

    ra_vad_result_t result;
    ASSERT_EQ(RA_SUCCESS, ra_vad_process(handle, speech_audio, 1600, &result));
    EXPECT_TRUE(result.is_speech);
    EXPECT_GT(result.probability, 0.5f);
}

TEST_F(VADTest, DetectsSilence) {
    float silence_audio[1600];
    generateSilence(silence_audio, 1600);

    ra_vad_result_t result;
    ASSERT_EQ(RA_SUCCESS, ra_vad_process(handle, silence_audio, 1600, &result));
    EXPECT_FALSE(result.is_speech);
    EXPECT_LT(result.probability, 0.5f);
}
```

### Smoke Tests Per Binding

```swift
// iOS Smoke Test
func testCoreInitialization() async throws {
    let config = SDKConfiguration(apiKey: "test", environment: .development)
    let core = RunAnywhereCore()
    try await core.initialize(config: config)
    XCTAssertTrue(core.isInitialized)
}
```

```kotlin
// Android Smoke Test
@Test
fun testCoreInitialization() = runBlocking {
    val config = SDKConfiguration(apiKey = "test", environment = Environment.Development)
    val core = RunAnywhereCore()
    core.initialize(config)
    assertTrue(core.isInitialized)
}
```

```dart
// Flutter Smoke Test
void main() {
  test('Core initialization', () async {
    final core = NativeBackend();
    final result = core.initialize({'apiKey': 'test', 'environment': 0});
    expect(result, equals(0));
  });
}
```

```typescript
// React Native Smoke Test
test('Core initialization', async () => {
  const native = requireNativeModule();
  await expect(native.initialize(JSON.stringify({apiKey: 'test'}))).resolves.not.toThrow();
});
```

---

## Summary

| Platform | Binary Format | Distribution | Binding Mechanism |
|----------|--------------|--------------|-------------------|
| iOS | XCFramework | CocoaPods, SPM, Manual | Swift ↔ C |
| Android | AAR + .so | Maven, Manual | JNI (Java ↔ C) |
| Flutter | Plugin + .so/XCFramework | pub.dev | dart:ffi |
| React Native | npm + native binaries | npm | Nitrogen/JSI |

**Key Points**:
1. **Single C++ codebase** compiled for all platforms
2. **Platform-specific wrappers** are thin (~500-1000 lines)
3. **Automated CI** builds and publishes artifacts
4. **Checksums** verify binary integrity
5. **Semantic versioning** for ABI stability

---

*Document generated: December 2025*
