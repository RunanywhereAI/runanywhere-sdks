# Flutter SDK Core Feasibility Analysis

## Overview

The Flutter SDK at `sdk/runanywhere-flutter/` **already uses Dart FFI** to bridge to a shared native C/C++ core. This makes it the most mature platform for core migration.

**SDK Statistics**:
- **Language**: Dart 3
- **Estimated Lines**: ~20,000
- **FFI Bridge**: Already implemented (1,100+ lines in `native_backend.dart`)
- **Portable Logic**: ~80%
- **Platform-Specific**: ~20%

---

## Current SDK Architecture

### Key Insight: Flutter Already Has FFI

Unlike iOS (Swift) and KMP (Kotlin), the Flutter SDK **already bridges to native code via dart:ffi**. This means:

1. The C API (`ra_*` functions) is already defined
2. FFI patterns are already established
3. Binary distribution is already working (XCFramework, .so)

### Directory Structure

```
lib/
├── runanywhere.dart              # Main public export
├── public/                        # Public API (RunAnywhere class)
├── core/                          # Core abstractions
│   ├── module_registry.dart      # Plugin registry
│   ├── model_lifecycle_manager.dart
│   └── service_registry/
├── components/                    # AI components (Dart orchestration)
│   ├── stt/, tts/, llm/, vad/
│   └── voice_agent/
├── backends/                      # FFI bridges (already implemented!)
│   ├── native/
│   │   ├── native_backend.dart   # 1087 lines - C API wrapper
│   │   ├── ffi_types.dart        # C type definitions
│   │   └── platform_loader.dart  # Library loading
│   ├── onnx/                     # ONNX backend via FFI
│   └── llamacpp/                 # LlamaCpp backend via FFI
├── capabilities/                  # Cross-cutting capabilities
│   ├── memory/, routing/, download/
├── foundation/                    # Infrastructure
│   ├── dependency_injection/
│   └── logging/
└── data/                         # Network, repositories

ios/                               # iOS plugin (minimal - loads XCFramework)
android/                           # Android plugin (loads .so files)
```

### Existing FFI Implementation

**NativeBackend** (`lib/backends/native/native_backend.dart`):
```dart
// Already defines 100+ C function bindings
final _raCreateBackend = _lib.lookupFunction<...>('ra_create_backend');
final _raInitialize = _lib.lookupFunction<...>('ra_initialize');
final _raSttLoadModel = _lib.lookupFunction<...>('ra_stt_load_model');
final _raSttTranscribe = _lib.lookupFunction<...>('ra_stt_transcribe');
// ... 100+ more bindings
```

---

## Component Analysis Table

| Component / Module | Location | Move to Core? | Current Status | Proposed Core API | FFI Frequency | Est. Effort |
|-------------------|----------|---------------|----------------|-------------------|---------------|-------------|
| **RunAnywhere class** | `lib/public/runanywhere.dart` | HYBRID | Dart wrapper | Entry point stays | LOW | S |
| **ModuleRegistry** | `lib/core/module_registry.dart` | YES | Dart | `ra_module_*()` | LOW | M |
| **ServiceRegistry** | `lib/core/service_registry/` | YES | Dart | `ra_service_*()` | LOW | M |
| **ModelLifecycleManager** | `lib/core/model_lifecycle_manager.dart` | YES | Dart | `ra_lifecycle_*()` | LOW | S |
| **STTComponent** | `lib/components/stt/` | YES | Dart orchestration | `ra_stt_component_*()` | LOW | M |
| **LLMComponent** | `lib/components/llm/` | YES | Dart orchestration | `ra_llm_component_*()` | LOW | M |
| **TTSComponent** | `lib/components/tts/` | YES | Dart orchestration | `ra_tts_component_*()` | LOW | M |
| **VADComponent** | `lib/components/vad/` | YES | Dart orchestration | `ra_vad_component_*()` | LOW | S |
| **VoiceAgentComponent** | `lib/components/voice_agent/` | YES | Dart orchestration | `ra_voice_agent_*()` | LOW | L |
| **NativeBackend** | `lib/backends/native/native_backend.dart` | FFI BRIDGE | **Already FFI** | Keep as bridge | MED | - |
| **OnnxSTTService** | `lib/backends/onnx/services/` | **ALREADY CORE** | Calls C API | Uses `ra_stt_*` | MED | - |
| **OnnxTTSService** | `lib/backends/onnx/services/` | **ALREADY CORE** | Calls C API | Uses `ra_tts_*` | MED | - |
| **LlamaCppLLMService** | `lib/backends/llamacpp/services/` | **ALREADY CORE** | Calls C API | Uses `ra_text_*` | MED | - |
| **MemoryService** | `lib/capabilities/memory/` | YES | Dart | `ra_memory_*()` | LOW | M |
| **DownloadService** | `lib/capabilities/download/` | HYBRID | Dart | `ra_download_*()` | LOW | M |
| **RoutingService** | `lib/capabilities/routing/` | YES | Dart | `ra_routing_*()` | LOW | M |
| **AnalyticsService** | `lib/capabilities/analytics/` | YES | Dart | `ra_analytics_*()` | LOW | M |
| **EventBus** | Not found explicitly | TO ADD | N/A | `ra_event_*()` | LOW | M |
| **PlatformLoader** | `lib/backends/native/platform_loader.dart` | NO | Platform lib loading | N/A | N/A | - |
| iOS plugin | `ios/Classes/` | NO | XCFramework loading | N/A | N/A | - |
| Android plugin | `android/src/main/kotlin/` | NO | .so loading | N/A | N/A | - |

---

## Detailed Component Analysis

### 1. NativeBackend - The Existing FFI Bridge

**Location**: `lib/backends/native/native_backend.dart` (1,087 lines)

**Current Implementation**:
```dart
class NativeBackend {
  late final DynamicLibrary _lib;
  late final Pointer<Void> _backendHandle;
  late final Pointer<Void> _onnxBackendHandle;

  // Function bindings (lines 118-270)
  late final RaCreateBackendNative _raCreateBackend;
  late final RaInitializeNative _raInitialize;
  late final RaSttLoadModelNative _raSttLoadModel;
  late final RaSttTranscribeNative _raSttTranscribe;
  // ... 100+ more

  // Backend lifecycle
  Future<bool> createBackend(String name) async {...}
  Future<bool> initialize(String configJson) async {...}

  // STT operations
  Future<bool> loadSttModel(String path, String modelType, String? config) async {...}
  Future<String> transcribe(String audioBase64, int sampleRate, String? language) async {...}

  // LLM operations
  Future<bool> loadTextModel(String path, String? config) async {...}
  Future<String> generate(String prompt, String? options) async {...}
  void generateStream(String prompt, String? options, Function callback) {...}
}
```

**Assessment**: This is **already the target architecture**. The Flutter SDK is ahead of iOS/KMP in terms of core integration.

---

### 2. FFI Types Definition

**Location**: `lib/backends/native/ffi_types.dart` (200+ lines)

**Current Types**:
```dart
// Result codes (lines 16-59)
class RaResultCode {
  static const int success = 0;
  static const int errorInvalidParam = -1;
  static const int errorNotInitialized = -2;
  // ... more error codes
}

// Device types (lines 61-98)
class RaDeviceType {
  static const int cpu = 0;
  static const int gpu = 1;
  static const int neuralEngine = 2;
  // ... more device types
}

// Opaque handles (lines 147-155)
typedef RaBackendHandle = Pointer<Void>;
typedef RaStreamHandle = Pointer<Void>;
```

**Assessment**: These type definitions should be **generated from the C headers** to ensure consistency.

---

### 3. Platform Library Loading

**Location**: `lib/backends/native/platform_loader.dart` (317 lines)

**Current Implementation**:
```dart
class PlatformLoader {
  static DynamicLibrary? _library;

  static DynamicLibrary load() {
    if (Platform.isIOS) {
      // iOS: Use DynamicLibrary.executable() - static XCFramework
      return DynamicLibrary.executable();
    } else if (Platform.isAndroid) {
      // Android: Load dependencies in order, then main library
      _tryLoadDependency('c++_shared');
      _tryLoadDependency('onnxruntime');
      // ... more dependencies
      return DynamicLibrary.open('librunanywhere_bridge.so');
    } else if (Platform.isMacOS) {
      // macOS: Try multiple paths
      return _loadMacOS();
    }
    // ... Linux, Windows
  }
}
```

**Assessment**: This stays in Flutter wrapper - it's platform-specific library loading logic.

---

### 4. Components (Dart Orchestration Layer)

**Location**: `lib/components/stt/stt_component.dart`, etc.

**Current Architecture**:
```dart
class STTComponent extends BaseComponent<STTServiceWrapper> {
  @override
  Future<void> initialize(STTConfiguration config) async {
    // Get provider from ModuleRegistry
    final provider = ModuleRegistry.shared.sttProvider(config.modelId);
    // Create service
    _service = await provider.createSTTService(config);
    // Track state
    _state = ComponentState.ready;
  }

  Future<STTOutput> transcribe(STTInput input) async {
    // Delegate to service (which uses FFI)
    return await _service.transcribe(input);
  }
}
```

**What Should Move to Core**:
- Component state machine
- Provider lookup logic
- Analytics tracking
- Error handling

**What Stays in Dart**:
- Dart async/await interface
- Stream handling
- Dart types

**Assessment**: Component orchestration logic should move to C++ core, with Dart providing a thin wrapper.

---

### 5. ModuleRegistry

**Location**: `lib/core/module_registry.dart`

**Current Implementation**:
```dart
class ModuleRegistry {
  static final shared = ModuleRegistry._();

  final _sttProviders = <STTServiceProvider>[];
  final _llmProviders = <LLMServiceProvider>[];
  final _ttsProviders = <TTSServiceProvider>[];

  void registerSTT(STTServiceProvider provider) {
    _sttProviders.add(provider);
  }

  STTServiceProvider? sttProvider(String? modelId) {
    return _sttProviders.firstWhereOrNull((p) => p.canHandle(modelId));
  }
}
```

**What Should Move to Core**:
- Registry data structure
- Provider lookup algorithm
- Priority-based selection

**Core API**:
```c
ra_result_t ra_module_register_stt_provider(const ra_stt_provider_t* provider);
ra_result_t ra_module_get_stt_provider(const char* model_id, ra_stt_provider_t* out);
```

**Assessment**: YES - should move to core for consistency across SDKs.

---

### 6. Memory/Routing/Analytics Services

**Location**: `lib/capabilities/memory/`, `lib/capabilities/routing/`, etc.

**Current Architecture**:
- Pure Dart implementations
- No FFI currently
- Matches iOS/KMP patterns

**Assessment**: These should move to core:
- MemoryService → `ra_memory_*()` (unified memory pressure handling)
- RoutingService → `ra_routing_*()` (consistent routing decisions)
- AnalyticsService → `ra_analytics_*()` (unified telemetry)

---

## Migration Strategy for Flutter

Since Flutter **already has FFI infrastructure**, migration is different:

### Current State
```
┌─────────────────────┐
│   Flutter Dart      │
│   Components        │
│   (orchestration)   │
└─────────┬───────────┘
          │ dart:ffi
┌─────────┴───────────┐
│   C API Bridge      │
│   (ra_* functions)  │
└─────────┬───────────┘
          │
┌─────────┴───────────┐
│   Native Backends   │
│   (LlamaCpp, ONNX)  │
└─────────────────────┘
```

### Target State
```
┌─────────────────────┐
│   Flutter Dart      │
│   (thin wrapper)    │
└─────────┬───────────┘
          │ dart:ffi
┌─────────┴───────────┐
│   C API Bridge      │
│   (ra_* functions)  │
└─────────┬───────────┘
          │
┌─────────┴───────────────────┐
│   RunAnywhere Core (C++)    │
│   ├── Component Layer       │
│   ├── Orchestration Layer   │
│   ├── Services Layer        │
│   └── Native Backends       │
└─────────────────────────────┘
```

### Migration Steps for Flutter

1. **Phase 1**: Extend C API with component/orchestration functions
   - Add `ra_stt_component_*()`, `ra_llm_component_*()`, etc.
   - Keep existing `ra_stt_*()`, `ra_llm_*()` as low-level API

2. **Phase 2**: Update NativeBackend to use new APIs
   - Add bindings for component-level functions
   - Deprecate direct backend calls from Dart

3. **Phase 3**: Simplify Dart components
   - Remove orchestration logic from Dart
   - Components become thin wrappers calling core

4. **Phase 4**: Move remaining services
   - ModuleRegistry → core
   - MemoryService → core
   - RoutingService → core

---

## Summary

### Already in Core

| Component | Status |
|-----------|--------|
| ONNX STT/TTS/VAD inference | ✅ Via `ra_stt_*`, `ra_tts_*`, `ra_vad_*` |
| LlamaCpp LLM inference | ✅ Via `ra_text_*` |
| Archive extraction | ✅ Via `ra_extract_archive` |

### Move to Core (YES)

| Component | Effort | Priority |
|-----------|--------|----------|
| ModuleRegistry | M | 1 |
| Component state machines | M | 2 |
| MemoryService | M | 3 |
| RoutingService | M | 4 |
| AnalyticsService | M | 5 |
| ModelLifecycleManager | S | 6 |

### Keep in Dart (NO)

| Component | Reason |
|-----------|--------|
| PlatformLoader | Platform-specific library loading |
| iOS/Android plugins | Platform glue code |
| Dart async interfaces | Language-specific ergonomics |
| Stream handling | Dart-specific patterns |

---

## Effort Estimates

**Total Flutter Migration Effort**: ~6-8 weeks (faster due to existing FFI)

**Key Advantage**: Flutter already has the FFI bridge (`NativeBackend`). Migration is mostly:
1. Adding new C API functions
2. Updating Dart bindings
3. Simplifying Dart components

---

## Recommendations

1. **Use Flutter as the reference** for FFI patterns when migrating iOS and KMP
2. **Generate FFI types** from C headers to ensure consistency
3. **Keep NativeBackend** but extend it with component-level APIs
4. **Simplify Dart layer** - let core handle orchestration

---

*Document generated: December 2025*
*Note: Flutter SDK is most mature for core integration*
