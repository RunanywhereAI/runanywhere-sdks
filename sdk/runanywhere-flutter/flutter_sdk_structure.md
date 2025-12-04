# Flutter SDK Structure Plan - Multi-Package Architecture with FFI

**Status**: Draft
**Created**: 2025-12-03
**Last Updated**: 2025-12-03

## 1. Executive Summary

This plan outlines a multi-package Flutter SDK architecture that integrates with `runanywhere-core` via Dart FFI. The SDK will be split into focused packages following Flutter/Dart best practices, enabling developers to include only the components they need while maintaining clean separation of concerns.

### Goals
- **Modular Architecture**: Multiple pub.dev packages for different concerns
- **Native Performance**: Direct FFI bindings to runanywhere-core C API
- **Plugin Extensibility**: Backend modules register via ModuleRegistry at runtime
- **Cross-Platform**: iOS, Android, macOS, Linux support with platform-specific optimizations
- **Developer Experience**: Clean APIs, minimal boilerplate, sensible defaults

### Package Overview
1. `runanywhere` - Main SDK with high-level APIs (current + FFI integration)
2. `runanywhere_core_ffi` - Low-level FFI bindings (auto-generated via ffigen)
3. `runanywhere_onnx` - ONNX Runtime backend adapter
4. `runanywhere_llamacpp` - LlamaCPP backend adapter
5. Future: `runanywhere_coreml`, `runanywhere_tflite` as needed

---

## 2. Package Structure & Dependency Graph

### 2.1 Dependency Hierarchy

```
┌──────────────────────────────────────────────────┐
│         Application (Flutter App)                │
└───────────────┬──────────────────────────────────┘
                │
                ├─► runanywhere (main SDK)
                │   └─► runanywhere_core_ffi
                │
                ├─► runanywhere_onnx (ONNX backend)
                │   └─► runanywhere_core_ffi
                │
                └─► runanywhere_llamacpp (LlamaCPP backend)
                    └─► runanywhere_core_ffi
```

### 2.2 Package Descriptions

#### `runanywhere` (Main SDK)
- **Purpose**: High-level SDK interface, component orchestration
- **Contains**:
  - Existing Dart components (STT, TTS, LLM, VAD, VoiceAgent)
  - ModuleRegistry for provider discovery
  - Service protocols and interfaces
  - Event bus and lifecycle management
  - Cloud routing and analytics
- **Dependencies**: `runanywhere_core_ffi`
- **Pub.dev**: Yes - primary package

#### `runanywhere_core_ffi` (FFI Bindings)
- **Purpose**: Low-level FFI bindings to runanywhere-core C API
- **Contains**:
  - Auto-generated Dart bindings (via ffigen)
  - Platform-specific library loaders
  - Memory management utilities
  - Callback bridges for streaming
  - Native library bundling logic
- **Dependencies**: `dart:ffi`, `ffi`, `ffigen` (dev)
- **Pub.dev**: Yes - foundational package

#### `runanywhere_onnx` (ONNX Backend)
- **Purpose**: ONNX Runtime backend implementation
- **Contains**:
  - ONNXSTTProvider, ONNXTTSProvider, ONNXLLMProvider
  - Thin wrappers around FFI calls
  - ONNX-specific configurations
- **Dependencies**: `runanywhere_core_ffi`, `runanywhere` (for protocols)
- **Pub.dev**: Yes - optional backend

#### `runanywhere_llamacpp` (LlamaCPP Backend)
- **Purpose**: LlamaCPP backend implementation
- **Contains**:
  - LlamaCppLLMProvider
  - GGUF model support
  - Streaming token generation
- **Dependencies**: `runanywhere_core_ffi`, `runanywhere` (for protocols)
- **Pub.dev**: Yes - optional backend

---

## 3. FFI Bindings Module (`runanywhere_core_ffi`)

### 3.1 Directory Structure

```
runanywhere_core_ffi/
├── pubspec.yaml
├── lib/
│   ├── runanywhere_core_ffi.dart          # Main export file
│   ├── src/
│   │   ├── generated/
│   │   │   └── bindings.dart              # Auto-generated via ffigen
│   │   ├── library_loader.dart            # Platform-specific dynamic library loading
│   │   ├── callback_bridge.dart           # Dart <-> C callback handling
│   │   ├── memory_manager.dart            # Memory management utilities
│   │   ├── types.dart                     # Dart representations of C types
│   │   └── platform/
│   │       ├── ios_loader.dart
│   │       ├── android_loader.dart
│   │       ├── macos_loader.dart
│   │       └── linux_loader.dart
│   └── runanywhere_core_ffi_platform_interface.dart
├── ios/                                   # iOS native library bundle
│   ├── RunAnywhere.xcframework
│   └── runanywhere_core_ffi.podspec
├── android/                               # Android native library bundle
│   ├── src/main/jniLibs/
│   │   ├── arm64-v8a/libRunAnywhere.so
│   │   ├── armeabi-v7a/libRunAnywhere.so
│   │   └── x86_64/libRunAnywhere.so
│   └── build.gradle
├── macos/                                 # macOS native library bundle
│   └── RunAnywhere.xcframework
├── linux/                                 # Linux native library bundle
│   └── libRunAnywhere.so
├── ffigen.yaml                            # ffigen configuration
└── README.md
```

### 3.2 Using dart:ffi and ffigen

#### ffigen.yaml Configuration
```yaml
name: RunAnywhereCoreBindings
description: Auto-generated FFI bindings for runanywhere-core
output: 'lib/src/generated/bindings.dart'
headers:
  entry-points:
    - 'native/include/runanywhere_bridge.h'
    - 'native/include/ra_types.h'
comments:
  style: any
  length: full
preamble: |
  // AUTO-GENERATED - DO NOT EDIT
  // Generated from runanywhere-core C API
exclude-all-by-default: false
functions:
  include:
    - 'ra_.*'   # Include all ra_ prefixed functions
structs:
  include:
    - 'ra_.*'
enums:
  include:
    - 'ra_.*'
```

#### Generated Bindings Usage
```dart
// lib/src/generated/bindings.dart (auto-generated)
class RunAnywhereCoreBindings {
  final DynamicLibrary _lib;

  RunAnywhereCoreBindings(this._lib);

  // Example: ra_create_backend
  late final _ra_create_backend = _lib.lookupFunction<
    Pointer<Void> Function(Pointer<Utf8>),
    Pointer<Void> Function(Pointer<Utf8>)
  >('ra_create_backend');

  Pointer<Void> ra_create_backend(Pointer<Utf8> backend_name) {
    return _ra_create_backend(backend_name);
  }

  // ... (hundreds of auto-generated bindings)
}
```

### 3.3 Platform-Specific Library Loading

#### library_loader.dart
```dart
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

class RunAnywhereCoreLoader {
  static DynamicLibrary? _library;

  static DynamicLibrary get library {
    if (_library != null) return _library!;

    if (Platform.isIOS || Platform.isMacOS) {
      _library = DynamicLibrary.process(); // XCFramework linked at build time
    } else if (Platform.isAndroid) {
      _library = DynamicLibrary.open('libRunAnywhere.so');
    } else if (Platform.isLinux) {
      _library = DynamicLibrary.open('libRunAnywhere.so');
    } else {
      throw UnsupportedError('Platform not supported');
    }

    return _library!;
  }

  static void dispose() {
    _library = null;
  }
}
```

#### iOS Specific (ios_loader.dart)
```dart
// iOS uses XCFramework linked via Podspec
// No dynamic loading needed - symbols available in process
class IOSLibraryLoader {
  static DynamicLibrary load() {
    return DynamicLibrary.process();
  }
}
```

#### Android Specific (android_loader.dart)
```dart
class AndroidLibraryLoader {
  static DynamicLibrary load() {
    // Load from bundled .so in android/src/main/jniLibs/
    return DynamicLibrary.open('libRunAnywhere.so');
  }
}
```

### 3.4 Callback Handling for Streaming

#### callback_bridge.dart
```dart
import 'dart:ffi';
import 'package:ffi/ffi.dart';

/// Bridge for text streaming callbacks (LLM)
typedef NativeTextStreamCallback = Bool Function(
  Pointer<Utf8> token,
  Pointer<Void> userData
);

typedef DartTextStreamCallback = void Function(String token);

class CallbackBridge {
  static final Map<int, DartTextStreamCallback> _textCallbacks = {};
  static int _nextId = 0;

  /// Create native callback wrapper
  static Pointer<NativeFunction<NativeTextStreamCallback>> wrapTextCallback(
    DartTextStreamCallback dartCallback
  ) {
    final id = _nextId++;
    _textCallbacks[id] = dartCallback;

    return Pointer.fromFunction<NativeTextStreamCallback>(
      _nativeTextCallback,
      false // default return value
    );
  }

  /// Native callback that forwards to Dart
  static bool _nativeTextCallback(Pointer<Utf8> token, Pointer<Void> userData) {
    try {
      final id = userData.address;
      final callback = _textCallbacks[id];
      if (callback != null) {
        callback(token.toDartString());
        return true; // continue streaming
      }
      return false;
    } catch (e) {
      return false; // stop on error
    }
  }

  /// Clean up callback
  static void disposeTextCallback(int id) {
    _textCallbacks.remove(id);
  }
}

/// Similar bridges for TTS audio streaming
typedef NativeTTSStreamCallback = Bool Function(
  Pointer<Float> samples,
  Int32 numSamples,
  Pointer<Void> userData
);

typedef DartTTSStreamCallback = void Function(List<double> samples);
```

### 3.5 Memory Management Patterns

#### memory_manager.dart
```dart
import 'dart:ffi';
import 'package:ffi/ffi.dart';

class MemoryManager {
  final RunAnywhereCoreBindings _bindings;

  MemoryManager(this._bindings);

  /// Allocate and convert Dart string to C string
  Pointer<Utf8> allocateString(String str) {
    return str.toNativeUtf8();
  }

  /// Free C string (allocated by us)
  void freeString(Pointer<Utf8> ptr) {
    malloc.free(ptr);
  }

  /// Free C string allocated by bridge (uses ra_free_string)
  void freeBridgeString(Pointer<Utf8> ptr) {
    _bindings.ra_free_string(ptr.cast());
  }

  /// Free audio samples allocated by bridge
  void freeAudio(Pointer<Float> ptr) {
    _bindings.ra_free_audio(ptr);
  }

  /// Free embedding vector
  void freeEmbedding(Pointer<Float> ptr) {
    _bindings.ra_free_embedding(ptr);
  }

  /// Convert C float array to Dart List
  List<double> floatArrayToList(Pointer<Float> ptr, int length) {
    return ptr.asTypedList(length).map((e) => e.toDouble()).toList();
  }

  /// Convert Dart List to C float array
  Pointer<Float> listToFloatArray(List<double> list) {
    final ptr = malloc.allocate<Float>(sizeOf<Float>() * list.length);
    for (var i = 0; i < list.length; i++) {
      ptr[i] = list[i];
    }
    return ptr;
  }
}
```

### 3.6 Type Mappings

#### types.dart
```dart
import 'dart:ffi';

/// Mirror of ra_result_code from C API
enum RAResultCode {
  success(0),
  errorInvalidHandle(1),
  errorNotInitialized(2),
  errorInvalidConfig(3),
  errorModelNotLoaded(4),
  errorInvalidInput(5),
  errorUnsupportedCapability(6),
  errorMemoryAllocation(7),
  errorInternal(8);

  final int value;
  const RAResultCode(this.value);

  static RAResultCode fromInt(int value) {
    return values.firstWhere((e) => e.value == value);
  }
}

/// Mirror of ra_capability_type
enum RACapabilityType {
  textGeneration(0),
  embeddings(1),
  stt(2),
  tts(3),
  vad(4),
  diarization(5);

  final int value;
  const RACapabilityType(this.value);
}

/// Mirror of ra_device_type
enum RADeviceType {
  cpu(0),
  gpu(1),
  npu(2),
  auto(3);

  final int value;
  const RADeviceType(this.value);
}

/// Dart handle wrapper for type safety
class RABackendHandle {
  final Pointer<Void> pointer;
  RABackendHandle(this.pointer);

  bool get isNull => pointer.address == 0;
}

class RAStreamHandle {
  final Pointer<Void> pointer;
  RAStreamHandle(this.pointer);

  bool get isNull => pointer.address == 0;
}
```

---

## 4. Backend Modules

### 4.1 ONNX Backend (`runanywhere_onnx`)

#### Directory Structure
```
runanywhere_onnx/
├── pubspec.yaml
├── lib/
│   ├── runanywhere_onnx.dart              # Main export
│   ├── src/
│   │   ├── onnx_stt_provider.dart
│   │   ├── onnx_tts_provider.dart
│   │   ├── onnx_llm_provider.dart
│   │   ├── onnx_vad_provider.dart
│   │   └── onnx_adapter.dart              # Base adapter logic
└── README.md
```

#### Example: onnx_llm_provider.dart
```dart
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_core_ffi/runanywhere_core_ffi.dart';

class ONNXLLMProvider implements LLMServiceProvider {
  @override
  String get name => 'ONNX Runtime';

  @override
  bool canHandle({String? modelId}) {
    // Handle .onnx model files
    return modelId?.endsWith('.onnx') ?? false;
  }

  @override
  Future<LLMService> createLLMService(dynamic configuration) async {
    return ONNXLLMService(configuration as LLMConfiguration);
  }
}

class ONNXLLMService implements LLMService {
  final LLMConfiguration config;
  final RunAnywhereCoreBindings _bindings;
  final MemoryManager _memory;
  RABackendHandle? _backend;

  ONNXLLMService(this.config)
    : _bindings = RunAnywhereCoreBindings(RunAnywhereCoreLoader.library),
      _memory = MemoryManager(RunAnywhereCoreBindings(RunAnywhereCoreLoader.library));

  @override
  Future<void> initialize({String? modelPath}) async {
    // Create ONNX backend
    final namePtr = _memory.allocateString('onnx');
    final backendPtr = _bindings.ra_create_backend(namePtr);
    _memory.freeString(namePtr);

    if (backendPtr.address == 0) {
      throw Exception('Failed to create ONNX backend');
    }

    _backend = RABackendHandle(backendPtr);

    // Initialize backend
    final result = _bindings.ra_initialize(_backend!.pointer, nullptr);
    if (result != RAResultCode.success.value) {
      throw Exception('Failed to initialize backend: $result');
    }

    // Load model
    if (modelPath != null) {
      final pathPtr = _memory.allocateString(modelPath);
      final loadResult = _bindings.ra_text_load_model(
        _backend!.pointer,
        pathPtr,
        nullptr
      );
      _memory.freeString(pathPtr);

      if (loadResult != RAResultCode.success.value) {
        throw Exception('Failed to load model: $loadResult');
      }
    }
  }

  @override
  Future<LLMGenerationResult> generate({
    required String prompt,
    required LLMGenerationOptions options,
  }) async {
    if (_backend == null) {
      throw Exception('Service not initialized');
    }

    final promptPtr = _memory.allocateString(prompt);
    final resultJsonPtr = malloc.allocate<Pointer<Utf8>>(sizeOf<Pointer<Utf8>>());

    final result = _bindings.ra_text_generate(
      _backend!.pointer,
      promptPtr,
      nullptr, // system_prompt
      options.maxTokens,
      options.temperature,
      resultJsonPtr
    );

    _memory.freeString(promptPtr);

    if (result != RAResultCode.success.value) {
      throw Exception('Generation failed: $result');
    }

    final json = resultJsonPtr.value.toDartString();
    _memory.freeBridgeString(resultJsonPtr.value);
    malloc.free(resultJsonPtr);

    final decoded = jsonDecode(json);
    return LLMGenerationResult(
      text: decoded['text'],
      promptTokens: decoded['prompt_tokens'],
      completionTokens: decoded['completion_tokens'],
    );
  }

  @override
  Stream<String> generateStream({
    required String prompt,
    required LLMGenerationOptions options,
  }) {
    final controller = StreamController<String>();

    // Wrap Dart callback for C
    final callback = CallbackBridge.wrapTextCallback((token) {
      controller.add(token);
    });

    final promptPtr = _memory.allocateString(prompt);

    _bindings.ra_text_generate_stream(
      _backend!.pointer,
      promptPtr,
      nullptr,
      options.maxTokens,
      options.temperature,
      callback,
      nullptr
    ).then((result) {
      _memory.freeString(promptPtr);
      if (result == RAResultCode.success.value) {
        controller.close();
      } else {
        controller.addError(Exception('Stream failed: $result'));
      }
    });

    return controller.stream;
  }

  @override
  bool get isReady => _backend != null &&
    _bindings.ra_text_is_model_loaded(_backend!.pointer);

  @override
  Future<void> cleanup() async {
    if (_backend != null) {
      _bindings.ra_destroy(_backend!.pointer);
      _backend = null;
    }
  }
}
```

#### Registration
```dart
// In app initialization
import 'package:runanywhere_onnx/runanywhere_onnx.dart';

void initializeONNX() {
  ModuleRegistry.shared.registerLLM(ONNXLLMProvider(), priority: 100);
  ModuleRegistry.shared.registerSTT(ONNXSTTProvider(), priority: 100);
  ModuleRegistry.shared.registerTTS(ONNXTTSProvider(), priority: 90);
}
```

### 4.2 LlamaCPP Backend (`runanywhere_llamacpp`)

#### Directory Structure
```
runanywhere_llamacpp/
├── pubspec.yaml
├── lib/
│   ├── runanywhere_llamacpp.dart
│   └── src/
│       └── llamacpp_llm_provider.dart
└── README.md
```

#### llamacpp_llm_provider.dart
```dart
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_core_ffi/runanywhere_core_ffi.dart';

class LlamaCppLLMProvider implements LLMServiceProvider {
  @override
  String get name => 'llama.cpp';

  @override
  bool canHandle({String? modelId}) {
    // Handle .gguf model files
    return modelId?.endsWith('.gguf') ?? false;
  }

  @override
  Future<LLMService> createLLMService(dynamic configuration) async {
    return LlamaCppLLMService(configuration as LLMConfiguration);
  }
}

class LlamaCppLLMService implements LLMService {
  final LLMConfiguration config;
  final RunAnywhereCoreBindings _bindings;
  RABackendHandle? _backend;

  LlamaCppLLMService(this.config)
    : _bindings = RunAnywhereCoreBindings(RunAnywhereCoreLoader.library);

  @override
  Future<void> initialize({String? modelPath}) async {
    // Create llamacpp backend
    final namePtr = 'llamacpp'.toNativeUtf8();
    final backendPtr = _bindings.ra_create_backend(namePtr);
    malloc.free(namePtr);

    _backend = RABackendHandle(backendPtr);

    // Initialize and load model
    _bindings.ra_initialize(_backend!.pointer, nullptr);

    if (modelPath != null) {
      final pathPtr = modelPath.toNativeUtf8();
      _bindings.ra_text_load_model(_backend!.pointer, pathPtr, nullptr);
      malloc.free(pathPtr);
    }
  }

  // ... Similar implementation to ONNX
}
```

---

## 5. Main SDK Changes (`runanywhere`)

### 5.1 Integration Points

The existing `runanywhere` package needs minimal changes:

1. **Add dependency** on `runanywhere_core_ffi`
2. **Update service protocols** to support FFI-backed providers
3. **Deprecate platform channels** in favor of FFI (gradual migration)

#### pubspec.yaml
```yaml
dependencies:
  runanywhere_core_ffi: ^0.1.0
```

#### ModuleRegistry (Already Exists)
No changes needed - current ModuleRegistry already supports provider registration.

### 5.2 Service Protocol Updates

The service protocols (`STTService`, `LLMService`, etc.) already exist in `module_registry.dart` and match the iOS Swift implementation. No changes required.

### 5.3 Platform Channel Deprecation Path

#### Phase 1: Coexistence
```dart
// Allow both platform channels and FFI providers
class STTComponent {
  Future<void> initialize() async {
    // Try FFI provider first
    final ffiProvider = ModuleRegistry.shared.sttProvider(modelId: config.modelId);
    if (ffiProvider != null) {
      _service = await ffiProvider.createSTTService(config);
      return;
    }

    // Fallback to platform channel (legacy)
    _service = await _createPlatformChannelService();
  }
}
```

#### Phase 2: FFI Only (Future)
Remove platform channel code entirely once FFI is stable.

---

## 6. Example App Integration

### 6.1 pubspec.yaml
```yaml
name: runanywhere_example
dependencies:
  flutter:
    sdk: flutter

  # Main SDK
  runanywhere: ^0.15.8

  # Backend modules (optional - pick what you need)
  runanywhere_onnx: ^0.1.0
  runanywhere_llamacpp: ^0.1.0
```

### 6.2 main.dart
```dart
import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_onnx/runanywhere_onnx.dart';
import 'package:runanywhere_llamacpp/runanywhere_llamacpp.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register backend providers
  _registerBackends();

  // Initialize SDK
  await RunAnywhere.initialize(
    apiKey: 'your-api-key',
    baseURL: 'https://api.runanywhere.ai',
    environment: SDKEnvironment.development,
  );

  runApp(MyApp());
}

void _registerBackends() {
  // Register ONNX for STT, TTS
  ModuleRegistry.shared.registerSTT(ONNXSTTProvider(), priority: 100);
  ModuleRegistry.shared.registerTTS(ONNXTTSProvider(), priority: 90);

  // Register LlamaCpp for LLM (GGUF models)
  ModuleRegistry.shared.registerLLM(LlamaCppLLMProvider(), priority: 100);
}
```

### 6.3 Usage Example
```dart
class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  Future<void> _loadModel() async {
    // LlamaCpp provider will be selected automatically for .gguf
    await RunAnywhere.loadModel('llama-3.2-1b.gguf');
  }

  void _generateText() async {
    final result = await RunAnywhere.generate(
      'Explain quantum computing',
      maxTokens: 512,
    );

    print(result.text);
  }

  void _streamText() {
    RunAnywhere.generateStream('Tell me a story').listen((token) {
      setState(() {
        _text += token;
      });
    });
  }
}
```

---

## 7. Build & Distribution

### 7.1 Native Library Bundling

#### iOS (XCFramework)
```
runanywhere_core_ffi/
└── ios/
    ├── RunAnywhere.xcframework/
    │   ├── ios-arm64/
    │   │   └── RunAnywhere.framework
    │   └── ios-arm64_x86_64-simulator/
    │       └── RunAnywhere.framework
    └── runanywhere_core_ffi.podspec
```

**runanywhere_core_ffi.podspec**:
```ruby
Pod::Spec.new do |s|
  s.name             = 'runanywhere_core_ffi'
  s.version          = '0.1.0'
  s.summary          = 'FFI bindings for RunAnywhere Core'
  s.homepage         = 'https://runanywhere.ai'
  s.license          = { :type => 'MIT' }
  s.author           = { 'RunAnywhere' => 'support@runanywhere.ai' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '14.0'

  s.vendored_frameworks = 'RunAnywhere.xcframework'

  # Ensure framework is linked
  s.xcconfig = {
    'OTHER_LDFLAGS' => '-framework RunAnywhere'
  }
end
```

#### Android (JNI .so files)
```
runanywhere_core_ffi/
└── android/
    ├── build.gradle
    └── src/main/jniLibs/
        ├── arm64-v8a/libRunAnywhere.so
        ├── armeabi-v7a/libRunAnywhere.so
        └── x86_64/libRunAnywhere.so
```

**build.gradle**:
```gradle
android {
    compileSdkVersion 34

    sourceSets {
        main {
            jniLibs.srcDirs = ['src/main/jniLibs']
        }
    }
}
```

### 7.2 pub.dev Publishing Strategy

#### Package Versioning
- All packages use semantic versioning (semver)
- Core FFI follows runanywhere-core version
- Backend modules independent versioning

```bash
# Initial releases
runanywhere: 0.15.8 (current)
runanywhere_core_ffi: 0.1.0
runanywhere_onnx: 0.1.0
runanywhere_llamacpp: 0.1.0
```

#### Publishing Order
1. `runanywhere_core_ffi` first (foundational)
2. Backend modules (`runanywhere_onnx`, `runanywhere_llamacpp`)
3. `runanywhere` last (depends on all)

#### Publish Commands
```bash
# Publish runanywhere_core_ffi
cd runanywhere_core_ffi/
dart pub publish

# Publish backends
cd ../runanywhere_onnx/
dart pub publish

cd ../runanywhere_llamacpp/
dart pub publish

# Publish main SDK
cd ../runanywhere/
dart pub publish
```

### 7.3 Local Development Workflow

#### path_provider in pubspec.yaml
```yaml
# For local development
dependencies:
  runanywhere_core_ffi:
    path: ../runanywhere_core_ffi
  runanywhere_onnx:
    path: ../runanywhere_onnx
```

#### Symlinks for Native Libraries
```bash
# Link native libs during development
ln -s ../../../../runanywhere-core/dist/RunAnywhere.xcframework \
      runanywhere_core_ffi/ios/RunAnywhere.xcframework

ln -s ../../../../runanywhere-core/dist/android/jni/ \
      runanywhere_core_ffi/android/src/main/jniLibs
```

#### Rebuild Script
```bash
#!/bin/bash
# rebuild_native.sh

set -e

# Build runanywhere-core
cd ../../../../runanywhere-core/
./scripts/build-ios.sh
./scripts/build-android.sh

# Copy to Flutter packages
cd ../sdks/sdk/runanywhere-flutter/
cp -r ../../../../runanywhere-core/dist/RunAnywhere.xcframework \
      runanywhere_core_ffi/ios/

mkdir -p runanywhere_core_ffi/android/src/main/jniLibs/
cp -r ../../../../runanywhere-core/dist/android/jni/* \
      runanywhere_core_ffi/android/src/main/jniLibs/

echo "Native libraries updated!"
```

---

## 8. Implementation Phases

### Phase 1: FFI Bindings Generation (Week 1-2)
**Goal**: Create `runanywhere_core_ffi` package with auto-generated bindings

**Tasks**:
1. ✅ Set up `runanywhere_core_ffi` package structure
2. ✅ Configure `ffigen.yaml` for runanywhere_bridge.h
3. ✅ Generate Dart bindings
4. ✅ Implement platform-specific library loaders
5. ✅ Create callback bridge infrastructure
6. ✅ Write memory management utilities
7. ✅ Add unit tests for FFI layer
8. ✅ Bundle iOS XCFramework
9. ✅ Bundle Android .so files

**Deliverable**: `runanywhere_core_ffi` v0.1.0 published to pub.dev

### Phase 2: Core Integration (Week 3-4)
**Goal**: Integrate FFI bindings into existing `runanywhere` SDK

**Tasks**:
1. ✅ Add `runanywhere_core_ffi` dependency to `runanywhere`
2. ✅ Update ModuleRegistry to prioritize FFI providers
3. ✅ Test coexistence with existing platform channel code
4. ✅ Verify all service protocols work with FFI
5. ✅ Update example app to use FFI (optional flag)
6. ✅ Add integration tests

**Deliverable**: `runanywhere` v0.16.0 with FFI support

### Phase 3: Backend Modules (Week 5-6)
**Goal**: Create standalone backend packages

**Tasks**:
1. ✅ Create `runanywhere_onnx` package
   - ONNXSTTProvider (Whisper models)
   - ONNXTTSProvider (Piper models)
   - ONNXLLMProvider (ONNX LLM models)
   - ONNXVADProvider (Silero VAD)
2. ✅ Create `runanywhere_llamacpp` package
   - LlamaCppLLMProvider (GGUF models)
3. ✅ Write integration tests for each backend
4. ✅ Add example projects
5. ✅ Publish to pub.dev

**Deliverable**:
- `runanywhere_onnx` v0.1.0
- `runanywhere_llamacpp` v0.1.0

### Phase 4: Example App & Documentation (Week 7-8)
**Goal**: Comprehensive example app and developer docs

**Tasks**:
1. ✅ Update Flutter example app
   - Multi-backend support
   - Model switching UI
   - Performance metrics
2. ✅ Write developer documentation
   - Getting started guide
   - Backend selection guide
   - Performance optimization tips
   - Migration guide (platform channels → FFI)
3. ✅ Create video tutorials
4. ✅ Benchmarking suite
5. ✅ Platform channel deprecation plan

**Deliverable**: Complete Flutter SDK with FFI backends

---

## 9. File Structure - Complete Trees

### 9.1 runanywhere_core_ffi/
```
runanywhere_core_ffi/
├── README.md
├── LICENSE
├── pubspec.yaml
├── ffigen.yaml
├── lib/
│   ├── runanywhere_core_ffi.dart
│   ├── src/
│   │   ├── generated/
│   │   │   └── bindings.dart              # Auto-generated
│   │   ├── library_loader.dart
│   │   ├── callback_bridge.dart
│   │   ├── memory_manager.dart
│   │   ├── types.dart
│   │   └── platform/
│   │       ├── ios_loader.dart
│   │       ├── android_loader.dart
│   │       ├── macos_loader.dart
│   │       └── linux_loader.dart
│   └── runanywhere_core_ffi_platform_interface.dart
├── ios/
│   ├── RunAnywhere.xcframework/
│   │   ├── ios-arm64/
│   │   │   └── RunAnywhere.framework/
│   │   │       ├── RunAnywhere
│   │   │       ├── Headers/
│   │   │       │   ├── runanywhere_bridge.h
│   │   │       │   └── ra_types.h
│   │   │       └── Info.plist
│   │   └── ios-arm64_x86_64-simulator/
│   │       └── RunAnywhere.framework/
│   │           ├── RunAnywhere
│   │           ├── Headers/
│   │           └── Info.plist
│   └── runanywhere_core_ffi.podspec
├── android/
│   ├── build.gradle
│   └── src/main/jniLibs/
│       ├── arm64-v8a/
│       │   └── libRunAnywhere.so
│       ├── armeabi-v7a/
│       │   └── libRunAnywhere.so
│       └── x86_64/
│           └── libRunAnywhere.so
├── macos/
│   └── RunAnywhere.xcframework/
├── linux/
│   └── libRunAnywhere.so
├── test/
│   ├── bindings_test.dart
│   ├── library_loader_test.dart
│   ├── callback_test.dart
│   └── memory_test.dart
└── example/
    ├── pubspec.yaml
    └── lib/
        └── main.dart
```

### 9.2 runanywhere_onnx/
```
runanywhere_onnx/
├── README.md
├── LICENSE
├── pubspec.yaml
├── lib/
│   ├── runanywhere_onnx.dart
│   └── src/
│       ├── onnx_adapter.dart
│       ├── onnx_stt_provider.dart
│       ├── onnx_stt_service.dart
│       ├── onnx_tts_provider.dart
│       ├── onnx_tts_service.dart
│       ├── onnx_llm_provider.dart
│       ├── onnx_llm_service.dart
│       ├── onnx_vad_provider.dart
│       └── onnx_vad_service.dart
├── test/
│   ├── onnx_stt_test.dart
│   ├── onnx_llm_test.dart
│   └── integration_test.dart
└── example/
    ├── pubspec.yaml
    └── lib/
        └── main.dart
```

### 9.3 runanywhere_llamacpp/
```
runanywhere_llamacpp/
├── README.md
├── LICENSE
├── pubspec.yaml
├── lib/
│   ├── runanywhere_llamacpp.dart
│   └── src/
│       ├── llamacpp_llm_provider.dart
│       ├── llamacpp_llm_service.dart
│       └── llamacpp_adapter.dart
├── test/
│   ├── llamacpp_llm_test.dart
│   └── integration_test.dart
└── example/
    └── lib/
        └── main.dart
```

### 9.4 runanywhere/ (Main SDK - Updated)
```
runanywhere/
├── pubspec.yaml                          # Add runanywhere_core_ffi dependency
├── lib/
│   ├── runanywhere.dart
│   ├── core/
│   │   └── module_registry.dart          # No changes needed
│   ├── components/
│   │   ├── stt/
│   │   │   ├── stt_component.dart        # Add FFI provider support
│   │   │   └── stt_service.dart
│   │   ├── llm/
│   │   │   └── llm_component.dart        # Add FFI provider support
│   │   ├── tts/
│   │   │   └── tts_component.dart
│   │   ├── vad/
│   │   │   └── vad_component.dart
│   │   └── voice_agent/
│   │       └── voice_agent_component.dart
│   └── (existing structure)
└── example/
    ├── pubspec.yaml                      # Add backend dependencies
    └── lib/
        └── main.dart                     # Register backends
```

---

## 10. Testing Strategy

### 10.1 Unit Tests (runanywhere_core_ffi)
```dart
// test/library_loader_test.dart
void main() {
  test('loads native library on iOS', () {
    final lib = RunAnywhereCoreLoader.library;
    expect(lib, isNotNull);
  });

  test('creates ONNX backend', () {
    final bindings = RunAnywhereCoreBindings(RunAnywhereCoreLoader.library);
    final namePtr = 'onnx'.toNativeUtf8();
    final handle = bindings.ra_create_backend(namePtr);
    malloc.free(namePtr);

    expect(handle.address, isNot(0));
    bindings.ra_destroy(handle);
  });
}
```

### 10.2 Integration Tests (Backend Modules)
```dart
// runanywhere_onnx/test/integration_test.dart
void main() {
  testWidgets('ONNX LLM end-to-end', (tester) async {
    ModuleRegistry.shared.registerLLM(ONNXLLMProvider());

    await RunAnywhere.initialize(/* ... */);
    await RunAnywhere.loadModel('phi-2.onnx');

    final result = await RunAnywhere.generate('Hello');
    expect(result.text, isNotEmpty);
  });
}
```

### 10.3 Performance Benchmarks
```dart
// benchmark/inference_benchmark.dart
void main() async {
  final onnx = ONNXLLMService(/* ... */);
  final llamacpp = LlamaCppLLMService(/* ... */);

  // Benchmark ONNX
  final onnxStart = DateTime.now();
  await onnx.generate(prompt: 'Test', options: /* ... */);
  final onnxDuration = DateTime.now().difference(onnxStart);

  // Benchmark LlamaCpp
  final llamaStart = DateTime.now();
  await llamacpp.generate(prompt: 'Test', options: /* ... */);
  final llamaDuration = DateTime.now().difference(llamaStart);

  print('ONNX: ${onnxDuration.inMilliseconds}ms');
  print('LlamaCpp: ${llamaDuration.inMilliseconds}ms');
}
```

---

## 11. Migration Path from Platform Channels

### 11.1 Coexistence Period
```dart
// Allow both methods to coexist
class LLMComponent extends BaseComponent<LLMService> {
  @override
  Future<LLMService> createService() async {
    // Try FFI provider first (if available)
    final ffiProvider = ModuleRegistry.shared.llmProvider(
      modelId: configuration.modelId
    );

    if (ffiProvider != null) {
      logger.info('Using FFI provider: ${ffiProvider.name}');
      return await ffiProvider.createLLMService(configuration);
    }

    // Fallback to platform channel
    logger.warn('FFI not available, using platform channel');
    return await _createPlatformChannelService();
  }
}
```

### 11.2 Deprecation Warnings
```dart
@Deprecated('Platform channels will be removed in v1.0.0. Use FFI backends instead.')
Future<LLMService> _createPlatformChannelService() async {
  // Old implementation
}
```

### 11.3 Timeline
- **v0.16.0**: FFI support added (coexistence)
- **v0.18.0**: FFI becomes default
- **v0.20.0**: Platform channels deprecated
- **v1.0.0**: Platform channels removed

---

## 12. Performance Considerations

### 12.1 FFI Call Overhead
- **Minimize**: Batch operations when possible
- **Reuse**: Cache handles and pointers
- **Async**: Use isolates for long-running operations

```dart
// Good: Batch processing
final results = await onnx.generateBatch(prompts);

// Bad: Multiple FFI calls
for (var prompt in prompts) {
  await onnx.generate(prompt); // Each call crosses FFI boundary
}
```

### 12.2 Memory Management
- **Always free**: C-allocated memory via `ra_free_*` functions
- **Pooling**: Reuse audio buffers for streaming
- **Cleanup**: Call `cleanup()` on all services

### 12.3 Platform-Specific Optimizations

#### iOS: Metal Acceleration
```dart
final config = LLMConfiguration(
  modelId: 'model.onnx',
  deviceType: DeviceType.gpu, // Uses Metal on iOS
);
```

#### Android: NNAPI
```dart
final config = LLMConfiguration(
  modelId: 'model.onnx',
  deviceType: DeviceType.npu, // Uses NNAPI on Android
);
```

---

## 13. Documentation Requirements

### 13.1 Package READMEs
Each package needs:
- Quick start guide
- API reference
- Example code
- Performance tips
- Troubleshooting

### 13.2 Developer Guide
- Architecture overview
- Backend selection matrix
- Model compatibility guide
- Migration from platform channels
- Performance optimization

### 13.3 API Documentation
All public APIs must have:
```dart
/// Synthesize speech from text using TTS.
///
/// This method uses the registered TTS provider (ONNX, etc.) to convert
/// [text] into audio samples.
///
/// Example:
/// ```dart
/// final audio = await tts.synthesize(
///   text: 'Hello, world!',
///   options: TTSOptions(voice: 'en-US-male'),
/// );
/// ```
///
/// Returns a [Uint8List] containing audio samples in the specified format.
///
/// Throws [TTSException] if synthesis fails.
Future<Uint8List> synthesize({
  required String text,
  required TTSOptions options,
});
```

---

## 14. Success Criteria

### 14.1 Technical
- ✅ All FFI bindings auto-generated via ffigen
- ✅ Zero memory leaks in FFI layer
- ✅ <5ms overhead per FFI call
- ✅ 100% test coverage for FFI layer
- ✅ Works on iOS, Android, macOS, Linux

### 14.2 Developer Experience
- ✅ Single-line backend registration
- ✅ Automatic provider selection
- ✅ Clear error messages
- ✅ Minimal boilerplate

### 14.3 Performance
- ✅ ONNX: <100ms first token latency
- ✅ LlamaCpp: <200ms first token latency
- ✅ STT: Real-time transcription (1x audio speed)
- ✅ TTS: Real-time synthesis (1x audio speed)

---

## 15. Risk Mitigation

### 15.1 FFI Complexity
**Risk**: FFI debugging is difficult
**Mitigation**: Extensive logging, error handling, unit tests

### 15.2 Platform-Specific Issues
**Risk**: Different behavior on iOS vs Android
**Mitigation**: Platform-specific integration tests, CI/CD for all platforms

### 15.3 Breaking Changes
**Risk**: C API changes break Dart bindings
**Mitigation**: Versioned FFI package, semantic versioning

### 15.4 Native Library Size
**Risk**: Large XCFramework/AAR sizes
**Mitigation**: Optional backends, tree-shaking, compression

---

## 16. Future Enhancements

### 16.1 Additional Backends
- `runanywhere_coreml` - Apple CoreML backend
- `runanywhere_tflite` - TensorFlow Lite backend
- `runanywhere_webgpu` - Web/Desktop GPU backend

### 16.2 Advanced Features
- Model quantization API
- Hardware acceleration selection
- Batch inference optimization
- Multi-model pipelines

### 16.3 Tooling
- Model conversion tools
- Benchmarking CLI
- Model registry integration

---

## Appendix A: Reference iOS Implementation

### iOS STTServiceProvider (Source of Truth)
```swift
// From sdks/sdk/runanywhere-swift/Sources/RunAnywhereCoreSwift/Providers/STTServiceProvider.swift
public protocol STTServiceProvider {
    var name: String { get }

    func canHandle(modelId: String?) -> Bool

    func createSTTService(
        configuration: STTConfiguration
    ) async throws -> STTService
}
```

### iOS Service Protocol
```swift
public protocol STTService {
    func initialize(modelPath: String?) async throws

    func transcribe(
        audioData: [Int16],
        options: STTOptions
    ) async throws -> STTTranscriptionResult

    var isReady: Bool { get }
    var currentModel: String? { get }
    var supportsStreaming: Bool { get }

    func cleanup() async
}
```

**Flutter must match this exactly** in business logic, adapting only syntax.

---

## Appendix B: C API Quick Reference

### Backend Lifecycle
```c
ra_backend_handle ra_create_backend(const char* backend_name);
ra_result_code ra_initialize(ra_backend_handle handle, const char* config_json);
void ra_destroy(ra_backend_handle handle);
```

### LLM
```c
ra_result_code ra_text_load_model(ra_backend_handle, const char* model_path, const char* config);
ra_result_code ra_text_generate(ra_backend_handle, const char* prompt, ...);
ra_result_code ra_text_generate_stream(ra_backend_handle, ..., ra_text_stream_callback, void*);
```

### STT
```c
ra_result_code ra_stt_load_model(ra_backend_handle, const char* path, const char* type, ...);
ra_result_code ra_stt_transcribe(ra_backend_handle, const float* samples, size_t num, ...);
ra_stream_handle ra_stt_create_stream(ra_backend_handle, const char* config);
```

### TTS
```c
ra_result_code ra_tts_load_model(ra_backend_handle, const char* path, const char* type, ...);
ra_result_code ra_tts_synthesize(ra_backend_handle, const char* text, ..., float** audio, ...);
ra_result_code ra_tts_synthesize_stream(ra_backend_handle, ..., ra_tts_stream_callback, ...);
```

### Memory
```c
void ra_free_string(char* str);
void ra_free_audio(float* audio);
void ra_free_embedding(float* embedding);
```

---

## Summary

This plan provides a **complete, production-ready architecture** for the Flutter SDK with FFI-based native integration. Key highlights:

1. **4 packages**: Clean separation of concerns
2. **Auto-generated bindings**: Via ffigen for maintainability
3. **Plugin architecture**: ModuleRegistry for extensibility
4. **iOS as source of truth**: Business logic mirrors Swift implementation
5. **Phase 1-4 implementation**: 8-week timeline
6. **Backward compatibility**: Coexistence with platform channels

The architecture follows Flutter best practices, Dart FFI patterns, and aligns with the iOS Swift SDK design.
