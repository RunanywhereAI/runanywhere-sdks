# RunAnywhere SDK Architecture Alignment

## Overview

This document outlines the architecture of the RunAnywhere Swift SDK (source of truth) and the path to align the Flutter SDK with it, including consuming native binaries from runanywhere-core.

---

## Part 1: Swift SDK Architecture (Source of Truth)

### Module Structure

```
runanywhere-swift/
├── Package.swift                     # SPM manifest with 6 products
├── Sources/
│   ├── RunAnywhere/                  # Core SDK (required)
│   │   ├── Components/               # STT, TTS, VAD, LLM, VLM, WakeWord, Diarization
│   │   ├── Capabilities/             # Voice, Text, Vision capabilities
│   │   ├── Core/                     # ModuleRegistry, EventBus, Analytics
│   │   └── Foundation/               # DI, Storage, Configuration
│   ├── ONNXRuntime/                  # ONNX backend (STT, TTS, VAD)
│   ├── WhisperKitTranscription/      # CoreML STT backend
│   ├── LLMSwift/                     # llama.cpp backend
│   ├── FoundationModelsAdapter/      # Apple Intelligence
│   ├── FluidAudioDiarization/        # Speaker diarization
│   └── CRunAnywhereONNX/             # C bridge headers
```

### XCFramework Consumption

The Swift SDK consumes the native ONNX binary via SPM binary target:

```swift
.binaryTarget(
    name: "RunAnywhereONNXBinary",
    url: "https://github.com/RunanywhereAI/runanywhere-binaries/releases/download/v0.0.1-dev.xxx/RunAnywhereONNX.xcframework.zip",
    checksum: "sha256..."
)
```

**C Bridge Layer**: `CRunAnywhereONNX/` wraps the C API from the XCFramework for Swift consumption.

### Multi-Backend Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    ModuleRegistry (Plugin System)            │
│  ┌──────────────┬──────────────┬──────────────────────────┐ │
│  │STTProviders  │TTSProviders  │LLMProviders   │VADProviders│
│  └──────────────┴──────────────┴──────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│              Framework Adapters (UnifiedFrameworkAdapter)    │
│  ┌───────────┬────────────┬───────────┬─────────────────┐  │
│  │  ONNX     │ WhisperKit │ LLMSwift  │ FoundationModels│  │
│  │ Adapter   │  Adapter   │  Adapter  │    Adapter      │  │
│  └───────────┴────────────┴───────────┴─────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                   Native Binaries / SDKs                     │
│  ┌───────────┬────────────┬───────────┬─────────────────┐  │
│  │XCFramework│ WhisperKit │LLM.swift  │ Apple Foundation│  │
│  │(ONNX Core)│  Package   │ Package   │    Models       │  │
│  └───────────┴────────────┴───────────┴─────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Component Architecture

Each capability (STT, TTS, VAD, LLM) follows this pattern:

```
┌─────────────────────────────────────────┐
│           BaseComponent                  │
│  - Lifecycle management                  │
│  - State (uninitialized → ready → error) │
│  - Event emission                        │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│         STTComponent (example)           │
│  - STTService (from provider registry)   │
│  - Configuration validation              │
│  - transcribe() / streamTranscribe()     │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│     STTService (Protocol)                │
│  - initialize(modelPath:)                │
│  - transcribe(audioData:, options:)      │
│  - streamTranscribe(audioStream:)        │
│  - cleanup()                             │
└─────────────────────────────────────────┘
```

---

## Part 2: Flutter SDK Implementation Status

> **Last Updated**: 2025-11-28
> **Status**: Phase 1 Complete ✅

### Feature Comparison Matrix

| Feature | iOS Status | Flutter Status | Gap |
|---------|------------|----------------|-----|
| **STT Core** | ✅ 100% | ✅ 90% | Small - streaming pending |
| **TTS Core** | ✅ 100% | ✅ 95% | ✅ **IMPLEMENTED** |
| **VAD Core** | ✅ 100% | ✅ 95% | ✅ **IMPLEMENTED** |
| **LLM Integration** | ✅ 100% | ⚠️ 60% | Medium |
| **Voice Agent** | ✅ 100% | ✅ 90% | ✅ **IMPLEMENTED** |
| **Speaker Diarization** | ✅ 100% | ❌ 0% | Large |
| **Wake Word** | ✅ 100% | ❌ 0% | Large |
| **VLM** | ✅ 100% | ❌ 0% | Large |
| **Streaming** | ✅ 100% | ⚠️ 30% | Medium |
| **Model Management** | ✅ 100% | ⚠️ 60% | Medium |
| **Configuration** | ✅ 100% | ✅ 90% | Small |
| **Provider Registry** | ✅ 100% | ✅ 95% | ✅ **IMPLEMENTED** |

### ✅ Completed Implementations (Phase 1)

1. **TTS Service**: Full implementation with SystemTTSService using flutter_tts
2. **VAD Service**: Complete SimpleEnergyVAD ported from iOS with energy-based detection
3. **Provider-Component Binding**: ModuleRegistry now connects to all components
4. **VoiceAgentComponent**: Full pipeline orchestration (VAD → STT → LLM → TTS)

### iOS Components → Flutter Checklist

#### STTComponent
- [x] Basic STTConfiguration
- [x] STTComponent scaffold
- [x] STTOptions with full properties (language, diarization, timestamps)
- [x] Provider binding in createService()
- [ ] Streaming/live transcription
- [ ] Word-level timestamps
- [ ] Speaker diarization integration

#### TTSComponent ✅ COMPLETE

- [x] Basic TTSOutput model
- [x] TTSService protocol/implementation
- [x] TTSOptions (voice, rate, pitch, volume, SSML)
- [x] Audio output handling
- [x] Voice enumeration
- [x] System TTS integration (flutter_tts)
- [x] Provider binding in createService()
- [ ] Streaming synthesis (future)

#### VADComponent ✅ COMPLETE

- [x] Basic VADConfiguration
- [x] VADService protocol/implementation
- [x] SimpleEnergyVAD (complete port from iOS)
- [x] Audio buffer processing
- [x] Energy threshold detection
- [x] Auto-calibration support
- [x] Speech activity callbacks
- [x] TTS feedback prevention
- [x] Pause/resume support
- [x] Provider binding in createService()

#### VoiceAgentComponent ✅ COMPLETE

- [x] Basic structure
- [x] Service initialization
- [x] Pipeline orchestration (VAD → STT → LLM → TTS)
- [x] Event publishing via EventBus
- [x] Stream processing
- [x] Individual component access methods
- [x] State management

---

## Part 3: RunAnywhere Core → Flutter Integration

### Current iOS Integration Path

```
runanywhere-core/               Swift SDK
     │                              │
     │ build-ios-backend.sh         │ Package.swift
     ↓                              ↓
RunAnywhereONNX.xcframework → binaryTarget (remote URL)
     │                              │
     │ Headers/                     │ CRunAnywhereONNX/
     ↓                              ↓
runanywhere_bridge.h      →   Swift FFI via C interop
```

### Required Flutter Integration Path

```
runanywhere-core/               Flutter SDK
     │                              │
     │ build-android-onnx.sh (NEW)  │ pubspec.yaml
     │ build-ios-backend.sh         │
     ↓                              ↓
┌─────────────────────────────────────────────────────────┐
│ Platform Binaries                                        │
│ ├── iOS: RunAnywhereONNX.xcframework                    │
│ ├── Android: librunanywhere.so (per ABI)                │
│ ├── macOS: libRunAnywhere.dylib                         │
│ └── Linux: libRunAnywhere.so                            │
└─────────────────────────────────────────────────────────┘
                              │
                              ↓
┌─────────────────────────────────────────────────────────┐
│ Dart FFI Bindings (runanywhere_native.dart)             │
│                                                          │
│ typedef CreateBackendNative =                            │
│     Pointer<Void> Function(Pointer<Utf8>);              │
│                                                          │
│ final createBackend = dylib.lookupFunction<             │
│     CreateBackendNative,                                 │
│     Pointer<Void> Function(Pointer<Utf8>)               │
│ >('ra_create_backend');                                 │
└─────────────────────────────────────────────────────────┘
```

### C API Surface for Flutter FFI

The C API (`runanywhere_bridge.h`) exposes 156 functions. Priority for Flutter:

#### High Priority (48 functions)

**Backend Lifecycle (5)**
```c
ra_backend_handle ra_create_backend(const char* name);
ra_result_code ra_initialize(ra_backend_handle, const char* config_json);
void ra_destroy(ra_backend_handle);
bool ra_supports_capability(ra_backend_handle, ra_capability_type);
```

**STT (8)**
```c
ra_result_code ra_stt_load_model(ra_backend_handle, const char* path, const char* type, const char* config);
ra_result_code ra_stt_transcribe(ra_backend_handle, const float* samples, size_t num, int sample_rate, const char* lang, char** result);
ra_stream_handle ra_stt_create_stream(ra_backend_handle, const char* config);
ra_result_code ra_stt_feed_audio(ra_backend_handle, ra_stream_handle, const float* samples, size_t num, int rate);
ra_result_code ra_stt_decode(ra_backend_handle, ra_stream_handle, char** result);
```

**TTS (5)**
```c
ra_result_code ra_tts_load_model(ra_backend_handle, const char* path, const char* type, const char* config);
ra_result_code ra_tts_synthesize(ra_backend_handle, const char* text, const char* voice_id, float speed, float pitch, float** audio, size_t* num, int* rate);
```

**VAD (5)**
```c
ra_result_code ra_vad_load_model(ra_backend_handle, const char* path, const char* config);
ra_result_code ra_vad_process(ra_backend_handle, const float* samples, size_t num, int rate, bool* is_speech, float* probability);
```

**Utilities (3)**
```c
void ra_free_string(char* str);
const char* ra_get_last_error(void);
const char* ra_get_version(void);
```

### Build Scripts Needed

**Android (`scripts/build-android-onnx.sh`)**:
```bash
for ABI in armeabi-v7a arm64-v8a x86 x86_64; do
    cmake -B "build/android/${ABI}" \
        -DCMAKE_SYSTEM_NAME=Android \
        -DCMAKE_ANDROID_NDK="${ANDROID_NDK}" \
        -DCMAKE_ANDROID_ABI="${ABI}" \
        -DRA_BUILD_ONNX=ON
done
```

Output: `android/src/main/jniLibs/{abi}/librunanywhere.so`

---

## Part 4: Implementation Roadmap

### Phase 1: Critical Service Implementations (Week 1-2)

1. **Implement TTS Service**
   - Use flutter_tts or platform channels for system TTS
   - Match iOS TTSService protocol

2. **Implement VAD Service**
   - Port SimpleEnergyVAD algorithm from iOS
   - Energy-based speech detection

3. **Bind Components to Providers**
   - Connect createService() to ModuleRegistry
   - Dynamic provider selection

### Phase 2: Native Binary Integration (Week 3-4)

1. **Build Android .so libraries**
   - Add Android NDK support to CMakeLists.txt
   - Create build-android-onnx.sh script

2. **Create Dart FFI Bindings**
   - `lib/native/runanywhere_ffi.dart`
   - Type mappings for all 48 priority functions

3. **Platform Plugin Structure**
   ```
   runanywhere_flutter/
   ├── lib/native/
   │   ├── runanywhere_ffi.dart       # FFI bindings
   │   ├── runanywhere_bindings.dart  # Generated with ffigen
   │   └── platform_loader.dart       # Dynamic library loading
   ├── ios/                           # XCFramework
   └── android/src/main/jniLibs/      # .so files
   ```

### Phase 3: Feature Parity (Week 5-6)

1. **Streaming Support**
   - Live transcription
   - Streaming synthesis

2. **Advanced Components**
   - Speaker diarization
   - Wake word detection
   - VLM support

### Phase 4: Voice Agent Orchestration (Week 7)

1. **Complete VoiceAgentComponent**
   - VAD → STT → LLM → TTS pipeline
   - Event publishing
   - State management

---

## Part 5: Flutter SDK Target Structure

```
runanywhere_flutter/
├── lib/
│   ├── runanywhere.dart                    # Main entry point
│   ├── components/
│   │   ├── stt/
│   │   │   ├── stt_component.dart
│   │   │   ├── stt_service.dart            # Protocol
│   │   │   ├── stt_configuration.dart
│   │   │   └── onnx_stt_service.dart       # ONNX implementation
│   │   ├── tts/
│   │   │   ├── tts_component.dart
│   │   │   ├── tts_service.dart            # Protocol
│   │   │   ├── tts_configuration.dart
│   │   │   ├── system_tts_service.dart     # Platform TTS
│   │   │   └── onnx_tts_service.dart       # ONNX implementation
│   │   ├── vad/
│   │   │   ├── vad_component.dart
│   │   │   ├── vad_service.dart            # Protocol
│   │   │   ├── simple_energy_vad.dart      # Energy-based VAD
│   │   │   └── onnx_vad_service.dart       # ONNX implementation
│   │   ├── llm/
│   │   │   └── llm_component.dart
│   │   └── voice_agent/
│   │       └── voice_agent_component.dart  # Full pipeline
│   ├── core/
│   │   ├── module_registry.dart
│   │   ├── event_bus.dart
│   │   └── service_container.dart
│   ├── native/
│   │   ├── runanywhere_ffi.dart            # FFI bindings
│   │   ├── platform_loader.dart            # Library loading
│   │   └── native_backend.dart             # Native backend wrapper
│   └── models/
│       ├── model_registry.dart
│       └── model_loader.dart
├── ios/
│   └── runanywhere_flutter.podspec         # Links XCFramework
├── android/
│   ├── build.gradle
│   └── src/main/jniLibs/
│       ├── arm64-v8a/librunanywhere.so
│       ├── armeabi-v7a/librunanywhere.so
│       ├── x86/librunanywhere.so
│       └── x86_64/librunanywhere.so
└── pubspec.yaml
```

---

## Summary

| Aspect | Swift SDK | Flutter SDK | Status |
|--------|-----------|-------------|--------|
| **Native Binary** | XCFramework via SPM | Need FFI bindings | 🔲 Phase 2 |
| **STT** | Full implementation | ✅ Provider binding complete | ✅ Done (streaming pending) |
| **TTS** | Full implementation | ✅ SystemTTSService + provider | ✅ **COMPLETE** |
| **VAD** | Full implementation | ✅ SimpleEnergyVAD ported | ✅ **COMPLETE** |
| **Voice Agent** | Full pipeline | ✅ Full orchestration | ✅ **COMPLETE** |
| **Provider System** | Full ModuleRegistry | ✅ All providers connected | ✅ **COMPLETE** |

---

## Implementation Log

### 2025-11-28: Phase 1 Complete

**Files Created/Modified:**

#### TTS Implementation

- `lib/core/models/audio_format.dart` - AudioFormat enum + AudioMetadata
- `lib/components/tts/tts_options.dart` - TTSOptions matching iOS
- `lib/components/tts/tts_output.dart` - TTSOutput + SynthesisMetadata + PhonemeTimestamp
- `lib/components/tts/tts_service.dart` - Abstract TTSService protocol
- `lib/components/tts/system_tts_service.dart` - flutter_tts implementation
- `lib/components/tts/tts_component.dart` - Complete rewrite with provider binding

#### VAD Implementation

- `lib/components/vad/vad_service.dart` - Abstract VADService protocol
- `lib/components/vad/vad_configuration.dart` - Full configuration matching iOS
- `lib/components/vad/vad_output.dart` - VADInput + VADOutput
- `lib/components/vad/simple_energy_vad.dart` - **Complete iOS algorithm port** (530+ lines)
- `lib/components/vad/vad_service_provider.dart` - DefaultVADProvider
- `lib/components/vad/vad_component.dart` - Full component with provider binding

#### Provider Registry

- `lib/core/module_registry.dart` - Added TTS/VAD providers, priority-based selection

#### Voice Agent

- `lib/components/voice_agent/voice_agent_component.dart` - Full pipeline orchestration
- `lib/public/events/sdk_event.dart` - Extended voice events

**Key Algorithms Ported:**

1. **SimpleEnergyVAD** - RMS energy calculation, hysteresis (1 frame start, 8 frames end), auto-calibration using 90th percentile, TTS feedback prevention
