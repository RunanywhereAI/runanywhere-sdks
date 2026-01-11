# Flutter SDK to Swift SDK Parity Migration Plan

**Created**: January 2, 2026
**Status**: READY FOR REVIEW
**Reference**: [FLUTTER_TO_SWIFT_MIGRATION_ANALYSIS.md](../../../sdk/FLUTTER_TO_SWIFT_MIGRATION_ANALYSIS.md)

---

## Overview

This plan details the step-by-step migration of the Flutter SDK to achieve 100% parity with the Swift SDK. Swift is the **source of truth**.

**Goals**:
1. Flutter becomes a thin wrapper over `runanywhere-commons` C/C++ layer
2. Delete all duplicated Dart-side business logic
3. Match Swift's public API, naming, and behavior exactly
4. Backend modules remain optional and self-contained

---

## Pre-Implementation Checklist

- [ ] Review and approve this plan
- [ ] Verify Android JNI libraries are available in releases
- [ ] Ensure local commons build works
- [ ] Have Swift SDK available for reference

---

## Phase 1: Aggressive Cleanup (Delete Duplicate Logic)

**Goal**: Remove ~150 Dart files that duplicate commons logic

### Task 1.1: Remove capabilities/ folder
**Files to delete**: `sdk/runanywhere-flutter/packages/runanywhere/lib/capabilities/`

| Path | Reason |
|------|--------|
| `capabilities/analytics/` | Analytics logic belongs in commons |
| `capabilities/download/` | Download logic belongs in commons |
| `capabilities/model_loading/` | Model loading via FFI to commons |
| `capabilities/model_loading/models/` | Model types via FFI |
| `capabilities/registry/` | Registry via FFI to commons |
| `capabilities/streaming/` | Streaming via FFI |
| `capabilities/text_generation/` | Text gen via NativeBackend FFI |
| `capabilities/voice/` | Voice via NativeBackend FFI |
| `capabilities/voice/models/` | Voice types via FFI |
| `capabilities/voice/services/` | Voice services via FFI |

**Commands**:
```bash
cd sdk/runanywhere-flutter/packages/runanywhere/lib
rm -rf capabilities/
```

**Update imports**: Search for `import 'package:runanywhere/capabilities/` and remove.

---

### Task 1.2: Slim down core/ folder
**Files to review and potentially remove**:

| Path | Action |
|------|--------|
| `core/capabilities/` | DELETE - duplicates |
| `core/capabilities_base/` | DELETE - abstractions not needed |
| `core/protocols/analytics/` | DELETE - analytics via FFI |
| `core/protocols/downloading/` | DELETE - download via FFI |
| `core/protocols/frameworks/` | KEEP - but slim down |
| `core/protocols/registry/` | DELETE - registry via FFI |
| `core/protocols/storage/` | KEEP - platform-specific |
| `core/service_registry/` | REVIEW - may need for module registration |

---

### Task 1.3: Remove infrastructure/analytics/
**Files to delete**: `sdk/runanywhere-flutter/packages/runanywhere/lib/infrastructure/analytics/`

All analytics logic should go through FFI to commons telemetry.

---

### Task 1.4: Remove data/sync/
**Files to delete**: `sdk/runanywhere-flutter/packages/runanywhere/lib/data/sync/`

Not present in Swift SDK - remove.

---

### Task 1.5: Run flutter analyze and fix
```bash
cd sdk/runanywhere-flutter
melos bootstrap
dart analyze packages/runanywhere
```

Fix any broken imports, remove dead code.

---

## Phase 2: DartBridge Architecture

**Goal**: Match Swift's CppBridge pattern with 2-phase initialization

### Task 2.1: Create DartBridge coordinator
**File**: `sdk/runanywhere-flutter/packages/runanywhere/lib/native/dart_bridge.dart`

```dart
/// Central coordinator for all C++ bridges (matches Swift CppBridge)
class DartBridge {
  static DartBridge? _instance;
  static DartBridge get shared => _instance ??= DartBridge._();

  SDKEnvironment _environment = SDKEnvironment.development;
  bool _isInitialized = false;
  bool _servicesInitialized = false;

  SDKEnvironment get environment => _environment;
  bool get isInitialized => _isInitialized;
  bool get servicesInitialized => _servicesInitialized;

  DartBridge._();

  /// Phase 1: Core init (sync) - must be called first
  void initialize(SDKEnvironment environment) {
    if (_isInitialized) return;
    _environment = environment;

    // Register platform callbacks with commons
    DartBridgePlatform.register();   // File ops, logging
    DartBridgeEvents.register();      // Analytics callback
    DartBridgeTelemetry.initialize(); // HTTP callback
    DartBridgeDevice.register();      // Device registration

    _isInitialized = true;
  }

  /// Phase 2: Services init (async) - after HTTP configured
  Future<void> initializeServices() async {
    if (_servicesInitialized) return;

    await DartBridgeModelAssignment.register();
    await DartBridgePlatformServices.register();

    _servicesInitialized = true;
  }

  /// Shutdown all bridges
  Future<void> shutdown() async {
    if (!_isInitialized) return;
    // Cleanup in reverse order
    _servicesInitialized = false;
    _isInitialized = false;
  }
}
```

---

### Task 2.2: Create DartBridge extensions

**File**: `lib/native/dart_bridge_platform.dart`
```dart
/// Platform adapter bridge (file ops, logging, keychain, clock)
class DartBridgePlatform {
  static void register() {
    // Register file operations callback
    // Register logging callback
    // Register keychain callback
    // Register clock callback
  }
}
```

**File**: `lib/native/dart_bridge_device.dart`
```dart
/// Device registration bridge
class DartBridgeDevice {
  static void register() {
    // Register device info callback
    // Register device capabilities callback
  }
}
```

**File**: `lib/native/dart_bridge_http.dart`
```dart
/// HTTP transport bridge
class DartBridgeHTTP {
  static void register() {
    // Register HTTP request callback
    // Register HTTP response callback
  }
}
```

**File**: `lib/native/dart_bridge_auth.dart`
```dart
/// Authentication flow bridge
class DartBridgeAuth {
  static void register() {
    // Register auth callback
    // Register token refresh callback
  }
}
```

---

### Task 2.3: Update NativeBackend to use DartBridge

The existing `NativeBackend` class is good for backend-specific operations. Ensure it integrates with `DartBridge` for lifecycle.

---

## Phase 3: Module Registration Pattern

**Goal**: Match Swift's RunAnywhereModule protocol

### Task 3.1: Define RunAnywhereModule abstract class

**File**: `lib/core/module/runanywhere_module.dart`

```dart
/// Base class for SDK modules (matches Swift RunAnywhereModule protocol)
abstract class RunAnywhereModule {
  /// Unique identifier for the module
  String get identifier;

  /// Module version
  String get version;

  /// Loading priority (higher = loaded first)
  int get priority;

  /// Register the module with the SDK
  Future<void> register();

  /// Unregister the module
  Future<void> unregister();
}
```

---

### Task 3.2: Create ModuleRegistry

**File**: `lib/core/module/module_registry.dart`

```dart
/// Registry for SDK modules
class ModuleRegistry {
  static final ModuleRegistry shared = ModuleRegistry._();
  ModuleRegistry._();

  final List<RunAnywhereModule> _modules = [];

  void registerModule(RunAnywhereModule module) {
    _modules.add(module);
    // Sort by priority (descending)
    _modules.sort((a, b) => b.priority.compareTo(a.priority));
  }

  Future<void> initializeAll() async {
    for (final module in _modules) {
      await module.register();
    }
  }

  Future<void> shutdownAll() async {
    for (final module in _modules.reversed) {
      await module.unregister();
    }
  }
}
```

---

### Task 3.3: Update LlamaCPP backend package

**File**: `packages/runanywhere_llamacpp/lib/llamacpp_module.dart`

```dart
class LlamaCPPModule extends RunAnywhereModule {
  @override String get identifier => 'llamacpp';
  @override String get version => '0.1.0';
  @override int get priority => 100;

  @override
  Future<void> register() async {
    // Register LlamaCPP backend with NativeBackend
  }

  @override
  Future<void> unregister() async {
    // Cleanup
  }
}
```

---

### Task 3.4: Update ONNX backend package

**File**: `packages/runanywhere_onnx/lib/onnx_module.dart`

```dart
class ONNXModule extends RunAnywhereModule {
  @override String get identifier => 'onnx';
  @override String get version => '0.1.0';
  @override int get priority => 100;

  @override
  Future<void> register() async {
    // Register ONNX backend with NativeBackend
  }

  @override
  Future<void> unregister() async {
    // Cleanup
  }
}
```

---

## Phase 4: Public API Alignment

**Goal**: Match Swift public API exactly

### Task 4.1: Update RunAnywhere main class

**File**: `lib/public/runanywhere.dart`

```dart
/// Main SDK entry point (matches Swift RunAnywhere)
class RunAnywhere {
  static final RunAnywhere shared = RunAnywhere._();
  RunAnywhere._();

  bool get isInitialized => DartBridge.shared.isInitialized;
  SDKEnvironment get environment => DartBridge.shared.environment;

  /// Initialize the SDK
  Future<void> initialize({
    required String apiKey,
    SDKEnvironment environment = SDKEnvironment.production,
  }) async {
    // Phase 1: Core init
    DartBridge.shared.initialize(environment);

    // Validate API key
    // Configure HTTP client

    // Phase 2: Services init
    await DartBridge.shared.initializeServices();

    // Initialize registered modules
    await ModuleRegistry.shared.initializeAll();
  }

  /// Shutdown the SDK
  Future<void> shutdown() async {
    await ModuleRegistry.shared.shutdownAll();
    await DartBridge.shared.shutdown();
  }
}
```

---

### Task 4.2: Create extension classes

**File**: `lib/public/extensions/runanywhere_text_generation.dart`
```dart
extension RunAnywhereTextGeneration on RunAnywhere {
  Future<String> generateText(String prompt, {GenerateOptions? options}) async {
    // Delegate to NativeBackend
  }

  Stream<String> generateTextStream(String prompt, {GenerateOptions? options}) {
    // Stream from NativeBackend
  }
}
```

**File**: `lib/public/extensions/runanywhere_stt.dart`
```dart
extension RunAnywhereSTT on RunAnywhere {
  Future<TranscriptionResult> transcribe(Uint8List audio, {TranscribeOptions? options}) async {
    // Delegate to NativeBackend
  }

  Stream<TranscriptionUpdate> transcribeStream(Stream<Uint8List> audio) {
    // Stream from NativeBackend
  }
}
```

**File**: `lib/public/extensions/runanywhere_tts.dart`
```dart
extension RunAnywhereTTS on RunAnywhere {
  Future<Uint8List> synthesize(String text, {SynthesizeOptions? options}) async {
    // Delegate to NativeBackend
  }

  Stream<Uint8List> synthesizeStream(String text) {
    // Stream from NativeBackend
  }
}
```

**File**: `lib/public/extensions/runanywhere_vad.dart`
```dart
extension RunAnywhereVAD on RunAnywhere {
  Future<VADResult> detectVoiceActivity(Uint8List audio) async {
    // Delegate to NativeBackend
  }
}
```

---

### Task 4.3: Align error types

**File**: `lib/public/errors/sdk_error.dart`

```dart
/// SDK error types (matches Swift SDKError)
sealed class SDKError implements Exception {
  String get message;
  int? get code;
}

class NotInitializedError extends SDKError {
  @override final String message = 'SDK not initialized';
  @override final int? code = null;
}

class InvalidApiKeyError extends SDKError {
  @override final String message;
  @override final int? code = -1;
  InvalidApiKeyError(this.message);
}

class ModelLoadError extends SDKError {
  @override final String message;
  @override final int code = -2;
  ModelLoadError(this.message);
}

class InferenceError extends SDKError {
  @override final String message;
  @override final int code = -3;
  InferenceError(this.message);
}

// ... match all Swift error types
```

---

## Phase 5: Build System (Local/Remote Artifacts)

**Goal**: Implement testLocal toggle matching Swift

### Task 5.1: Update iOS Podspec

**File**: `packages/runanywhere_native/ios/runanywhere_native.podspec`

```ruby
Pod::Spec.new do |s|
  s.name             = 'runanywhere_native'
  s.version          = '0.1.0'
  s.summary          = 'RunAnywhere Native Bridge'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.9'

  s.source_files = 'Classes/**/*'

  # Load binary config
  binary_config = File.exist?('binary_config.rb') ? eval(File.read('binary_config.rb')) : {}
  use_local = binary_config[:use_local] || ENV['RA_LOCAL_BUILD'] == 'true'

  if use_local
    # Local: Link to locally built frameworks
    local_path = binary_config[:local_path] || '../../../runanywhere-commons/build'
    s.vendored_frameworks = [
      "#{local_path}/RACommons.xcframework"
    ]
  else
    # Remote: Use pre-downloaded frameworks
    s.vendored_frameworks = 'Frameworks/*.xcframework'
  end

  s.dependency 'Flutter'
end
```

---

### Task 5.2: Update Android Gradle

**File**: `packages/runanywhere_native/android/build.gradle`

```groovy
android {
    // ...

    sourceSets {
        main {
            def useLocal = project.hasProperty('raLocalBuild') ||
                           System.getenv('RA_LOCAL_BUILD') == 'true'

            if (useLocal) {
                def localPath = project.hasProperty('raLocalPath') ?
                    project.property('raLocalPath') :
                    '../../../runanywhere-commons/build/android'
                jniLibs.srcDirs = [localPath]
            } else {
                jniLibs.srcDirs = ['libs']
            }
        }
    }
}
```

---

### Task 5.3: Create artifact fetch script

**File**: `sdk/runanywhere-flutter/scripts/fetch_artifacts.sh`

```bash
#!/bin/bash
set -e

VERSION="${1:-commons-v0.1.0}"
PLATFORM="${2:-all}"

RELEASE_URL="https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/${VERSION}"

# iOS
if [[ "$PLATFORM" == "all" || "$PLATFORM" == "ios" ]]; then
    echo "Fetching iOS artifacts..."
    mkdir -p packages/runanywhere_native/ios/Frameworks
    curl -L "${RELEASE_URL}/RACommons.xcframework.zip" -o /tmp/RACommons.zip
    unzip -o /tmp/RACommons.zip -d packages/runanywhere_native/ios/Frameworks/
fi

# Android
if [[ "$PLATFORM" == "all" || "$PLATFORM" == "android" ]]; then
    echo "Fetching Android artifacts..."
    mkdir -p packages/runanywhere_native/android/libs
    curl -L "${RELEASE_URL}/RACommons-android.zip" -o /tmp/RACommons-android.zip
    unzip -o /tmp/RACommons-android.zip -d packages/runanywhere_native/android/libs/
fi

echo "Artifacts fetched successfully!"
```

---

### Task 5.4: Update binary_config files

**File**: `packages/runanywhere_native/ios/binary_config.rb`
```ruby
{
  use_local: ENV['RA_LOCAL_BUILD'] == 'true',
  local_path: ENV['RA_LOCAL_PATH'] || '../../../runanywhere-commons/build'
}
```

**File**: `packages/runanywhere_native/android/binary_config.gradle`
```groovy
ext {
    raUseLocal = System.getenv('RA_LOCAL_BUILD') == 'true' ||
                 project.hasProperty('raLocalBuild')
    raLocalPath = System.getenv('RA_LOCAL_PATH') ?:
                  '../../../runanywhere-commons/build/android'
}
```

---

## Phase 6: Verification

### Task 6.1: Build example app iOS

```bash
cd examples/flutter/RunAnywhereAI
flutter clean
flutter pub get
cd ios && pod install && cd ..
flutter build ios --simulator
```

### Task 6.2: Build example app Android

```bash
cd examples/flutter/RunAnywhereAI
flutter clean
flutter pub get
flutter build apk
```

### Task 6.3: Run integration tests

```bash
cd sdk/runanywhere-flutter
melos run test
```

### Task 6.4: Verify file count reduction

```bash
find sdk/runanywhere-flutter/packages -name "*.dart" | wc -l
# Target: < 100 files (down from 254)
```

---

## Rollback Plan

If issues arise:
1. Git revert to pre-migration commit
2. Restore deleted files from git history
3. Debug specific issue before re-attempting

---

## Post-Migration Checklist

- [ ] All tests pass
- [ ] Example app builds on iOS
- [ ] Example app builds on Android
- [ ] STT works end-to-end
- [ ] TTS works end-to-end
- [ ] LLM works end-to-end
- [ ] VAD works
- [ ] Error messages match Swift
- [ ] Logging matches Swift subsystem patterns
- [ ] File count reduced to ~80-100

---

## Handoff Notes

After each phase, update this section with:
- What was completed
- Any deviations from plan
- Issues encountered and resolutions
- Next steps

### Phase 1 Notes
_To be filled after Phase 1 completion_

### Phase 2 Notes
_To be filled after Phase 2 completion_

### Phase 3 Notes
_To be filled after Phase 3 completion_

### Phase 4 Notes
_To be filled after Phase 4 completion_

### Phase 5 Notes
_To be filled after Phase 5 completion_

### Phase 6 Notes
_To be filled after Phase 6 completion_
