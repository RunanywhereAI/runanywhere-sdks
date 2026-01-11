# Flutter to Swift SDK Migration Analysis

**Date**: January 2, 2026
**Status**: Phase 0 - Discovery Complete
**Goal**: Migrate Flutter SDK to achieve 100% parity with iOS Swift SDK

---

## Executive Summary

The Flutter SDK needs to be migrated to match the Swift SDK's architecture, where Swift is the **source of truth**. The primary objective is to make Flutter a thin wrapper over the shared `runanywhere-commons` C++ layer, matching Swift's behavior exactly.

### Key Findings

| Metric | Flutter SDK | Swift SDK | Notes |
|--------|-------------|-----------|-------|
| Total Source Files | 254 Dart files | 81 Swift files | Flutter has 3x more files - likely duplicated logic |
| Package Structure | 4 packages (melos) | 4 modules (SPM) | Similar modular structure |
| Native Bridge | `NativeBackend` class | `CppBridge` enum | Different patterns |
| FFI Implementation | dart:ffi direct | Swift C interop via CRACommons | Both work |
| Backend Modularity | Separate packages | Separate targets | Aligned |
| Local/Remote Toggle | binary_config files | Package.swift conditionals | Needs alignment |

---

## 1. Repository Structure Comparison

### Swift SDK (Source of Truth)
```
sdk/runanywhere-swift/
├── Package.swift                    # SPM manifest
├── Sources/
│   ├── CRACommons/                  # C bridge shim module
│   │   └── include/CRACommons.h
│   ├── RunAnywhere/                 # Main SDK (81 files)
│   │   ├── Core/
│   │   │   ├── Module/              # RunAnywhereModule registration
│   │   │   └── Types/               # ComponentTypes, AudioTypes
│   │   ├── Data/Network/            # HTTP services, auth
│   │   ├── Features/
│   │   │   ├── LLM/                 # LLM feature + SystemFoundationModels
│   │   │   ├── STT/                 # Speech-to-text services
│   │   │   └── TTS/                 # Text-to-speech services
│   │   ├── Foundation/
│   │   │   ├── Bridge/              # CppBridge.swift + Extensions/
│   │   │   ├── Errors/              # SDKError, ErrorCode
│   │   │   └── Security/
│   │   ├── Infrastructure/
│   │   │   ├── Device/              # Device info services
│   │   │   ├── Download/            # AlamofireDownloadService
│   │   │   ├── Events/              # EventBus
│   │   │   ├── FileManagement/      # File utilities
│   │   │   └── Logging/             # SDKLogger
│   │   └── Public/
│   │       ├── Configuration/       # SDKEnvironment
│   │       ├── Events/              # EventBus (public)
│   │       ├── Extensions/          # RunAnywhere+STT/TTS/LLM/VAD
│   │       └── Sessions/
│   ├── LlamaCPPRuntime/             # LlamaCPP backend module
│   │   └── LlamaCPP.swift
│   └── ONNXRuntime/                 # ONNX backend module
│       └── ONNX.swift
└── Binaries/                        # XCFrameworks (local mode)
```

### Flutter SDK (Current State)
```
sdk/runanywhere-flutter/
├── melos.yaml                       # Monorepo config
├── packages/
│   ├── runanywhere/                 # Main SDK (254+ files - BLOATED)
│   │   └── lib/
│   │       ├── capabilities/        # NOT in Swift - DELETE candidate
│   │       ├── core/                # Module, types, protocols
│   │       ├── data/                # Network, errors
│   │       ├── features/            # LLM, STT, TTS, VAD
│   │       ├── foundation/          # Config, DI, logging
│   │       ├── infrastructure/      # Analytics, device, events
│   │       ├── native/              # FFI bindings (KEEP)
│   │       └── public/              # Public API
│   ├── runanywhere_native/          # Platform plugin
│   │   ├── ios/                     # iOS platform code
│   │   │   ├── binary_config.rb     # Local/remote toggle
│   │   │   └── Classes/
│   │   └── android/                 # Android platform code
│   │       └── binary_config.gradle # Local/remote toggle
│   ├── runanywhere_llamacpp/        # LlamaCPP backend
│   │   └── lib/
│   └── runanywhere_onnx/            # ONNX backend
│       └── lib/
└── scripts/
    └── setup_native.sh
```

---

## 2. File-Level Parity Table

### Swift → Flutter Mapping (What Flutter MUST have)

| Swift File | Flutter Equivalent | Status | Action |
|------------|-------------------|--------|--------|
| **Core/Module/** | | | |
| `RunAnywhereModule.swift` | `core/module/runanywhere_module.dart` | ⚠️ Partial | Align registration pattern |
| `ComponentTypes.swift` | `core/types/` | ✅ Exists | Verify parity |
| `AudioTypes.swift` | `core/types/audio_types.dart` | ⚠️ Check | Verify all types present |
| **Foundation/Bridge/** | | | |
| `CppBridge.swift` | `native/native_backend.dart` | ✅ Exists | Pattern differs (class vs enum) |
| `CppBridge+PlatformAdapter.swift` | - | ❌ Missing | Add FFI platform callbacks |
| `CppBridge+Environment.swift` | - | ❌ Missing | Add environment config FFI |
| `CppBridge+Telemetry.swift` | - | ❌ Missing | Add telemetry FFI |
| `CppBridge+Device.swift` | - | ❌ Missing | Add device registration FFI |
| `CppBridge+HTTP.swift` | - | ❌ Missing | Add HTTP transport FFI |
| `CppBridge+Auth.swift` | - | ❌ Missing | Add auth flow FFI |
| `CppBridge+Services.swift` | - | ❌ Missing | Add service registry FFI |
| `CppBridge+LLM.swift` | `native/native_backend.dart` | ⚠️ Partial | Already has LLM FFI |
| `CppBridge+STT.swift` | `native/native_backend.dart` | ⚠️ Partial | Already has STT FFI |
| `CppBridge+TTS.swift` | `native/native_backend.dart` | ⚠️ Partial | Already has TTS FFI |
| `CppBridge+VAD.swift` | `native/native_backend.dart` | ⚠️ Partial | Already has VAD FFI |
| **Foundation/Errors/** | | | |
| `SDKError.swift` | `foundation/error_types/` | ⚠️ Check | Verify error codes match |
| `ErrorCode.swift` | `native/ffi_types.dart` | ✅ Exists | RaResultCode enum |
| **Public/** | | | |
| `RunAnywhere.swift` | `public/runanywhere.dart` | ⚠️ Check | Verify init/shutdown |
| `SDKEnvironment.swift` | `foundation/configuration/` | ⚠️ Check | Verify environments |
| `EventBus.swift` | `infrastructure/events/` | ⚠️ Check | Verify event system |
| **Features/LLM/** | | | |
| `SystemFoundationModelsModule.swift` | - | N/A iOS-only | Apple Foundation Models |
| **Features/STT/** | | | |
| `AudioCaptureManager.swift` | `features/stt/services/` | ⚠️ Check | Platform-specific |
| **Infrastructure/** | | | |
| `SDKLogger.swift` | `foundation/logging/` | ⚠️ Check | Verify logging |
| `AlamofireDownloadService.swift` | `capabilities/download/` | ⚠️ Check | Verify download |
| `DeviceInfoService.swift` | `infrastructure/device/` | ⚠️ Check | Verify device info |
| **Backend Modules** | | | |
| `LlamaCPP.swift` | `runanywhere_llamacpp/` | ✅ Exists | Verify registration |
| `ONNX.swift` | `runanywhere_onnx/` | ✅ Exists | Verify registration |

### Flutter Extras (DELETE Candidates)

| Flutter Path | In Swift? | Action |
|--------------|-----------|--------|
| `capabilities/` folder | ❌ No | **DELETE** - Logic should be in commons |
| `capabilities/analytics/` | ❌ No | **DELETE** - Move to commons FFI |
| `capabilities/model_loading/` | ❌ No | **DELETE** - Move to commons FFI |
| `capabilities/registry/` | ❌ No | **DELETE** - Move to commons FFI |
| `capabilities/streaming/` | ❌ No | **DELETE** - Move to commons FFI |
| `capabilities/text_generation/` | ❌ No | **DELETE** - Native backend handles |
| `capabilities/voice/` | ❌ No | **DELETE** - Native backend handles |
| `core/capabilities/` | ❌ No | **REVIEW** - May duplicate |
| `core/capabilities_base/` | ❌ No | **REVIEW** - May duplicate |
| `core/protocols/` | ⚠️ Partial | **SLIM DOWN** - Too many protocols |
| `data/sync/` | ❌ No | **DELETE** - Not in Swift |
| `infrastructure/analytics/` | ❌ No | **DELETE** - Move to commons FFI |
| `infrastructure/file_management/` | ⚠️ Minimal | **SLIM DOWN** |

---

## 3. Critical Gaps Analysis

### 3.1 CppBridge Architecture Gap (CRITICAL)

**Swift Pattern** (Source of Truth):
```swift
// CppBridge.swift - Central coordinator enum
public enum CppBridge {
    private static var _environment: SDKEnvironment = .development
    private static var _isInitialized = false
    private static var _servicesInitialized = false

    // Phase 1: Core init (sync)
    public static func initialize(environment: SDKEnvironment) {
        PlatformAdapter.register()  // File ops, logging, keychain
        Events.register()           // Analytics callback
        Telemetry.initialize()      // HTTP callback
        Device.register()           // Device registration
    }

    // Phase 2: Services init (async)
    public static func initializeServices() async {
        ModelAssignment.register()  // Model assignment callbacks
        Platform.register()         // LLM/TTS service callbacks
    }
}
```

**Flutter Pattern** (Current):
```dart
// native_backend.dart - Simple wrapper class
class NativeBackend {
    final DynamicLibrary _lib;
    RaBackendHandle? _handle;

    factory NativeBackend() {
        final lib = PlatformLoader.load();
        return NativeBackend._(lib);
    }

    void create(String backendName, {Map<String, dynamic>? config}) {
        _handle = _createBackend(namePtr);
        _initialize(_handle!, configPtr);
    }
}
```

**Gap**: Flutter is missing the 2-phase initialization, platform callbacks, and bridge extensions.

**Fix Required**:
1. Create `DartBridge` class (equivalent to CppBridge)
2. Implement 2-phase initialization matching Swift
3. Add extension files for each subsystem (Platform, Device, HTTP, Auth, etc.)
4. Register platform callbacks for file ops, logging, HTTP transport

### 3.2 Module Registration Gap

**Swift Pattern**:
```swift
public protocol RunAnywhereModule: AnyObject, Sendable {
    static var identifier: String { get }
    static var version: String { get }
    static var priority: Int { get }

    func register() async throws
    func unregister() async throws
}

// Backend registers itself
RunAnywhere.registerModule(LlamaCPPModule.self)
```

**Flutter Pattern** (incomplete):
```dart
// No clear module registration protocol
```

**Fix Required**:
1. Define `RunAnywhereModule` abstract class matching Swift
2. Implement module registry in main SDK
3. Each backend package registers via module pattern

### 3.3 Business Logic Duplication (CRITICAL)

Flutter has extensive Dart-side business logic that should live in commons:

**DELETE These (logic exists in commons)**:
- `capabilities/analytics/` - Analytics logic in Dart
- `capabilities/model_loading/` - Model loading logic in Dart
- `capabilities/text_generation/` - Text generation orchestration
- `capabilities/voice/` - Voice pipeline orchestration
- `infrastructure/analytics/` - Analytics services

**KEEP These (platform-specific)**:
- `native/` - FFI bindings (essential)
- Audio session management (platform-specific)
- Permissions handling (platform-specific)
- File system paths (platform-specific)

---

## 4. Native Library Consumption

### 4.1 Current Artifact Structure

**commons-v0.1.0 Release**:
- `RACommons.xcframework` - Core commons (iOS/macOS)
- `RABackendLlamaCPP.xcframework` - LLM backend (iOS/macOS)
- `RABackendONNX.xcframework` - STT/TTS/VAD backend (iOS/macOS)
- **Missing**: Android JNI libraries (.so files)

**core-v0.1.1-dev Release**:
- iOS XCFrameworks for backends
- Android pre-built native libraries (.so)
- Split per-backend for modularity

### 4.2 Flutter Integration Requirements

**iOS Integration** (Podspec):
```ruby
# runanywhere_native.podspec
Pod::Spec.new do |s|
  s.name = 'runanywhere_native'

  # Binary config for local vs remote
  if ENV['RA_LOCAL_BUILD'] == 'true'
    s.vendored_frameworks = [
      '../../../runanywhere-commons/build/RACommons.xcframework'
    ]
  else
    # Remote: Use pre-built from releases
    s.vendored_frameworks = 'Frameworks/RACommons.xcframework'
  end
end
```

**Android Integration** (Gradle):
```groovy
// build.gradle
android {
    sourceSets {
        main {
            if (project.hasProperty('raLocalBuild')) {
                jniLibs.srcDirs = ['../../../runanywhere-commons/build/android']
            } else {
                jniLibs.srcDirs = ['libs']
            }
        }
    }
}
```

### 4.3 Missing Artifacts for Flutter

1. **Android JNI libraries** for commons - Need to be built/released
2. **Architecture coverage**: arm64-v8a, armeabi-v7a, x86_64
3. **Backend-specific Android SOs**: llamacpp.so, onnx.so

---

## 5. Public API Parity

### 5.1 Swift Public API (What Flutter MUST match)

```swift
// Main entry point
public final class RunAnywhere {
    public static let shared: RunAnywhere
    public var isInitialized: Bool
    public var environment: SDKEnvironment

    public func initialize(
        apiKey: String,
        environment: SDKEnvironment = .production
    ) async throws

    public func shutdown() async

    // Extensions provide feature access
}

// Extension: Text Generation
extension RunAnywhere {
    public func generateText(prompt: String, options: GenerateOptions) async throws -> String
    public func generateTextStream(prompt: String, options: GenerateOptions) -> AsyncStream<String>
}

// Extension: STT
extension RunAnywhere {
    public func transcribe(audio: Data, options: TranscribeOptions) async throws -> TranscriptionResult
    public func transcribeStream(audio: AsyncStream<Data>) -> AsyncStream<TranscriptionUpdate>
}

// Extension: TTS
extension RunAnywhere {
    public func synthesize(text: String, options: SynthesizeOptions) async throws -> Data
    public func synthesizeStream(text: String) -> AsyncStream<Data>
}

// Extension: VAD
extension RunAnywhere {
    public func detectVoiceActivity(audio: Data) async throws -> VADResult
}
```

### 5.2 Flutter Public API (Target)

```dart
// Main entry point
class RunAnywhere {
    static final RunAnywhere shared = RunAnywhere._();
    bool get isInitialized;
    SDKEnvironment get environment;

    Future<void> initialize({
        required String apiKey,
        SDKEnvironment environment = SDKEnvironment.production,
    });

    Future<void> shutdown();
}

// Extension methods (via extension on RunAnywhere)
extension RunAnywhereTextGeneration on RunAnywhere {
    Future<String> generateText(String prompt, {GenerateOptions? options});
    Stream<String> generateTextStream(String prompt, {GenerateOptions? options});
}

extension RunAnywhereSTT on RunAnywhere {
    Future<TranscriptionResult> transcribe(Uint8List audio, {TranscribeOptions? options});
    Stream<TranscriptionUpdate> transcribeStream(Stream<Uint8List> audio);
}

extension RunAnywhereTTS on RunAnywhere {
    Future<Uint8List> synthesize(String text, {SynthesizeOptions? options});
    Stream<Uint8List> synthesizeStream(String text);
}

extension RunAnywhereVAD on RunAnywhere {
    Future<VADResult> detectVoiceActivity(Uint8List audio);
}
```

---

## 6. Error Handling Parity

### Swift Error Types (Source of Truth)
```swift
public enum SDKError: Error {
    case notInitialized
    case invalidApiKey
    case modelLoadFailed(String)
    case inferenceFailed(String)
    case networkError(Error)
    case cancelled
    case timeout
    // ... matches ErrorCode enum
}
```

### Flutter Error Types (Target)
```dart
sealed class SDKError implements Exception {
    final String message;
    final int? code;
}

class NotInitializedError extends SDKError { }
class InvalidApiKeyError extends SDKError { }
class ModelLoadError extends SDKError { }
class InferenceError extends SDKError { }
class NetworkError extends SDKError { }
class CancelledError extends SDKError { }
class TimeoutError extends SDKError { }
```

---

## 7. Implementation Phases

### Phase 1: Cleanup (Estimated: 2-3 days work)

**DELETE duplicate Dart logic**:
- [ ] Remove `capabilities/analytics/` (55+ files)
- [ ] Remove `capabilities/model_loading/`
- [ ] Remove `capabilities/streaming/`
- [ ] Remove `capabilities/text_generation/`
- [ ] Remove `capabilities/voice/`
- [ ] Remove `infrastructure/analytics/`
- [ ] Remove `data/sync/`

**Expected Result**: ~150 files → ~80 files

### Phase 2: Bridge Architecture (Estimated: 3-4 days work)

**Create DartBridge pattern matching CppBridge**:
- [ ] Create `dart_bridge.dart` - Main coordinator
- [ ] Create `dart_bridge_platform.dart` - Platform callbacks
- [ ] Create `dart_bridge_device.dart` - Device registration
- [ ] Create `dart_bridge_http.dart` - HTTP transport
- [ ] Create `dart_bridge_auth.dart` - Auth flow
- [ ] Implement 2-phase initialization
- [ ] Register callbacks with commons via FFI

### Phase 3: Module Registration (Estimated: 1-2 days work)

**Align module pattern with Swift**:
- [ ] Define `RunAnywhereModule` abstract class
- [ ] Create module registry
- [ ] Update `runanywhere_llamacpp` to use module pattern
- [ ] Update `runanywhere_onnx` to use module pattern
- [ ] Verify priority-based loading

### Phase 4: Public API Alignment (Estimated: 2-3 days work)

**Align public API surface with Swift**:
- [ ] Update `RunAnywhere` class to match Swift
- [ ] Create extension classes for STT, TTS, LLM, VAD
- [ ] Align method signatures
- [ ] Align error types
- [ ] Align configuration objects

### Phase 5: Build System (Estimated: 2-3 days work)

**Implement local/remote artifact toggle**:
- [ ] Finalize iOS Podspec for local/remote
- [ ] Finalize Android Gradle for local/remote
- [ ] Create artifact fetch scripts
- [ ] Validate architectures
- [ ] Document build modes

### Phase 6: Verification (Estimated: 1-2 days work)

**End-to-end testing**:
- [ ] Build example app iOS
- [ ] Build example app Android
- [ ] Test STT pipeline
- [ ] Test TTS pipeline
- [ ] Test LLM pipeline
- [ ] Test VAD
- [ ] Verify error handling matches Swift

---

## 8. Acceptance Criteria

### Done means:
1. Flutter SDK file count reduced from 254 to ~80-100 (matching Swift complexity)
2. All business logic calls into commons via FFI (no Dart-side orchestration)
3. Public API exactly matches Swift naming and behavior
4. Module registration pattern matches Swift
5. 2-phase initialization implemented
6. Local and remote build modes work on both iOS and Android
7. Example app builds and runs end-to-end on both platforms
8. Error types and codes match Swift exactly

### Verification Commands:
```bash
# Build example app iOS
cd examples/flutter/RunAnywhereAI
flutter build ios --simulator

# Build example app Android
flutter build apk

# Run tests
flutter test

# Verify file count reduction
find sdk/runanywhere-flutter/packages -name "*.dart" | wc -l
# Target: < 100 files
```

---

## 9. Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Missing Android JNI libs | High | Build and release with commons |
| FFI callback issues | Medium | Test thoroughly on both platforms |
| Module loading order | Medium | Match Swift priority system exactly |
| Breaking existing users | Low | No backwards compat required per spec |

---

## 10. Open Questions

1. **Q**: Are Android JNI libraries for commons being built in CI?
   **A**: Need to verify - critical blocker for Android

2. **Q**: What is the exact C ABI surface that Flutter FFI should call?
   **A**: See `runanywhere_bridge.h` in commons - already defined

3. **Q**: How should platform callbacks be registered from Dart?
   **A**: Need to implement callback registration via FFI

---

## Appendix A: Commons C ABI Functions

Flutter's `native_backend.dart` already binds to these functions:
- `ra_get_available_backends`, `ra_create_backend`, `ra_initialize`, `ra_destroy`
- `ra_stt_load_model`, `ra_stt_transcribe`, `ra_stt_*` (streaming)
- `ra_tts_load_model`, `ra_tts_synthesize`, `ra_tts_*`
- `ra_text_load_model`, `ra_text_generate`, `ra_text_*`
- `ra_vad_load_model`, `ra_vad_process`, `ra_vad_*`
- `ra_embed_load_model`, `ra_embed_text`, `ra_embed_*`

**Missing FFI bindings** (need to add):
- Platform adapter callbacks (`rac_platform_adapter.h`)
- Device registration callbacks
- HTTP transport callbacks
- Auth flow callbacks
- Service registry callbacks
- Event/telemetry callbacks

---

## Appendix B: Release Artifacts Reference

**commons-v0.1.0**: https://github.com/RunanywhereAI/runanywhere-sdks/releases/tag/commons-v0.1.0
- RACommons.xcframework
- RABackendLlamaCPP.xcframework
- RABackendONNX.xcframework

**core-v0.1.1-dev**: https://github.com/RunanywhereAI/runanywhere-binaries/releases/tag/core-v0.1.1-dev.03aacf9
- iOS XCFrameworks
- Android native libs (.so)
- Per-backend split
