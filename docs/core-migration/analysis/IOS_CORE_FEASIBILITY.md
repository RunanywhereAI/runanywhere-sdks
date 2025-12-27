# iOS SDK Core Feasibility Analysis

## Overview

The iOS Swift SDK at `sdk/runanywhere-swift/` is the **source of truth** for architecture and conceptual boundaries. This document analyzes each component for core migration feasibility.

**SDK Statistics**:
- **Language**: Swift 6
- **Estimated Lines**: ~25,000
- **Portable Logic**: ~75%
- **Platform-Specific**: ~25%

---

## Current SDK Architecture

### Directory Structure

```
Sources/
├── RunAnywhere/              # Main SDK (platform-agnostic Swift)
│   ├── Public/               # Public API surface
│   ├── Features/             # AI capabilities (STT, TTS, LLM, VAD, VoiceAgent)
│   ├── Core/                 # Capabilities, ModuleRegistry, ServiceRegistry
│   ├── Infrastructure/       # Events, Logging, Analytics, Download, FileManagement
│   ├── Foundation/           # DI, Security, Errors, Constants
│   └── Data/                 # Network layer
├── ONNXRuntime/              # ONNX backend (bridges to C++)
├── LlamaCPPRuntime/          # LlamaCpp backend (bridges to C++)
├── FoundationModelsAdapter/  # Apple AI (iOS 26+)
└── CRunAnywhereCore/         # C bridge headers
```

### Key Entry Points

| Entry Point | Location | Description |
|------------|----------|-------------|
| `RunAnywhere.initialize()` | `Public/RunAnywhere.swift:190` | Two-phase SDK initialization |
| `RunAnywhere+STT.swift` | `Public/Extensions/` | Speech-to-text APIs |
| `RunAnywhere+TextGeneration.swift` | `Public/Extensions/` | LLM generation APIs |
| `ServiceContainer` | `Foundation/DependencyInjection/` | Central DI container |

---

## Component Analysis Table

| Component / Module | Location | Move to Core? | Why | Proposed Core API | Platform Adapters | FFI Frequency | Est. Effort |
|-------------------|----------|---------------|-----|-------------------|-------------------|---------------|-------------|
| **STTCapability** | `Features/STT/STTCapability.swift` | YES | Actor-based lifecycle, state machine | `ra_stt_component_*()` | AudioInput | LOW | M |
| **TTSCapability** | `Features/TTS/TTSCapability.swift` | YES | Actor-based lifecycle, state machine | `ra_tts_component_*()` | AudioOutput | LOW | M |
| **LLMCapability** | `Features/LLM/LLMCapability.swift` | YES | Lifecycle + streaming metrics | `ra_llm_component_*()` | None | LOW | M |
| **VADCapability** | `Features/VAD/VADCapability.swift` | YES | State machine | `ra_vad_component_*()` | None | LOW | S |
| **VoiceAgentCapability** | `Features/VoiceAgent/VoiceAgentCapability.swift` | YES | Pipeline orchestration | `ra_voice_agent_*()` | AudioInput, AudioOutput | LOW | L |
| **SimpleEnergyVADService** | `Features/VAD/Services/SimpleEnergyVADService.swift` | YES | Pure math (RMS, hysteresis) | `ra_vad_process()` | None | MED (batch) | S |
| **StreamingMetricsCollector** | `Features/LLM/LLMCapability.swift:274` | YES | TTFT, tokens/sec tracking | Part of `ra_llm_*` | None | LOW | S |
| **ModuleRegistry** | `Core/Module/ModuleRegistry.swift` | YES | Plugin architecture | `ra_register_module()` | None | LOW | M |
| **ServiceRegistry** | `Core/ServiceRegistry.swift` | YES | Factory pattern | `ra_register_service()` | None | LOW | M |
| **ManagedLifecycle** | `Core/Capabilities/ManagedLifecycle.swift` | YES | Generic lifecycle manager | Part of component APIs | None | LOW | S |
| **EventPublisher** | `Infrastructure/Events/EventPublisher.swift` | YES | Event routing | `ra_publish_event()` | None | LOW | S |
| **EventBus** | `Public/Events/EventBus.swift` | HYBRID | Core publishes, Swift subscribes | `ra_subscribe_events()` | Combine (wrapper) | LOW | M |
| **TelemetryEventProperties** | `Infrastructure/Events/TelemetryEventProperties.swift` | YES | Telemetry data structures | Part of event API | None | LOW | S |
| **ModelInfoService** | `Infrastructure/ModelManagement/Services/ModelInfoService.swift` | YES | In-memory model storage | `ra_model_registry_*()` | None | LOW | S |
| **ModelAssignmentService** | `Infrastructure/ModelManagement/Services/ModelAssignmentService.swift` | HYBRID | API fetching | `ra_fetch_assignments()` | HttpClient | LOW | M |
| **DownloadService** | `Infrastructure/Download/Services/AlamofireDownloadService.swift` | HYBRID | Logic core, I/O wrapper | `ra_download_*()` | HttpClient, FileSystem | LOW | M |
| **ArchiveUtility** | `Infrastructure/Download/Utilities/ArchiveUtility.swift` | YES | ZIP/tar extraction | `ra_extract_archive()` | FileSystem | LOW | S |
| **SimplifiedFileManager** | `Infrastructure/FileManagement/Services/SimplifiedFileManager.swift` | HYBRID | Path resolution core | `ra_file_*()` | FileSystem | LOW | M |
| **StorageAnalyzer** | `Infrastructure/FileManagement/Services/DefaultStorageAnalyzer.swift` | NO | Platform disk queries | N/A | N/A | N/A | N/A |
| **APIClient** | `Data/Network/Services/APIClient.swift` | HYBRID | Core handles auth/retry | `ra_http_request()` | HttpClient | LOW | M |
| **AuthenticationService** | `Data/Network/Services/AuthenticationService.swift` | HYBRID | Token logic core | `ra_authenticate()` | HttpClient, SecureStorage | LOW | M |
| **SDKLogger** | `Infrastructure/Logging/SDKLogger.swift` | HYBRID | Interface core | `ra_log()` | Logger (os.Logger) | LOW | S |
| **SentryManager** | `Infrastructure/Logging/SentryManager.swift` | NO | Crash reporting | N/A | N/A | N/A | N/A |
| **AudioCaptureManager** | `Features/STT/Services/AudioCaptureManager.swift` | NO | AVFoundation | N/A | N/A | N/A | N/A |
| **AudioPlaybackManager** | `Features/TTS/Services/AudioPlaybackManager.swift` | NO | AVFoundation | N/A | N/A | N/A | N/A |
| **SystemTTSService** | `Features/TTS/System/SystemTTSService.swift` | NO | AVSpeechSynthesizer | N/A | N/A | N/A | N/A |
| **KeychainManager** | `Foundation/Security/KeychainManager.swift` | NO | Keychain APIs | N/A | N/A | N/A | N/A |
| **DeviceIdentity** | `Infrastructure/Device/Services/DeviceIdentity.swift` | NO | UUID + Keychain | N/A | N/A | N/A | N/A |
| **ONNXSTTService** | `ONNXRuntime/ONNXSTTService.swift` | ALREADY CORE | Calls C API | Already uses `ra_stt_*` | None | MED | - |
| **ONNXTTSService** | `ONNXRuntime/ONNXTTSService.swift` | ALREADY CORE | Calls C API | Already uses `ra_tts_*` | None | MED | - |
| **LlamaCPPService** | `LlamaCPPRuntime/LlamaCPPService.swift` | ALREADY CORE | Calls C API | Already uses `ra_text_*` | None | MED | - |

---

## Detailed Component Analysis

### 1. STTCapability (Move to Core)

**Location**: `Features/STT/STTCapability.swift`

**Current Behavior**:
- Actor-based for thread safety
- Manages `ManagedLifecycle<STTService>`
- Provides `transcribe()` and `streamTranscribe()` APIs
- Tracks analytics (latency, confidence)

**What Moves to Core**:
- State machine (idle → loading → loaded → failed)
- Service lookup via ModuleRegistry
- Analytics tracking logic
- Streaming session management

**What Stays in Wrapper**:
- Swift async/await interface
- Combine publishers for events
- Swift types (STTInput, STTOutput)

**Core API**:
```c
// Lifecycle
ra_result_t ra_stt_component_create(ra_stt_component_handle_t* out);
ra_result_t ra_stt_component_initialize(ra_stt_component_handle_t h, const char* model_id);
ra_result_t ra_stt_component_cleanup(ra_stt_component_handle_t h);
ra_component_state_t ra_stt_component_get_state(ra_stt_component_handle_t h);

// Operations
ra_result_t ra_stt_component_transcribe(ra_stt_component_handle_t h,
    const float* audio, size_t samples, ra_stt_output_t* out);
ra_result_t ra_stt_component_stream_start(ra_stt_component_handle_t h, ra_stream_handle_t* out);
ra_result_t ra_stt_component_stream_feed(ra_stream_handle_t s, const float* audio, size_t samples);
ra_result_t ra_stt_component_stream_get_result(ra_stream_handle_t s, char* text, size_t* len);
```

**FFI Frequency**: LOW - Called per utterance, not per frame

**Effort**: M (2-3 weeks)

---

### 2. SimpleEnergyVADService (Move to Core)

**Location**: `Features/VAD/Services/SimpleEnergyVADService.swift`

**Current Behavior** (Lines 298-463):
- Calculates RMS energy using `vDSP_rmsqv` (Accelerate)
- Hysteresis logic for state transitions (prevents rapid on/off)
- Calibration system measures ambient noise
- TTS feedback prevention (raises threshold during TTS)

**What Moves to Core**:
- RMS calculation (replace vDSP with standard C++ math)
- Hysteresis state machine
- Calibration algorithm
- TTS feedback prevention logic

**What Stays in Wrapper**:
- Audio buffer management (AVAudioEngine integration)

**Core API**:
```c
ra_result_t ra_vad_create(ra_vad_config_t* config, ra_vad_handle_t* out);
ra_result_t ra_vad_process(ra_vad_handle_t h, const float* audio, size_t samples,
    bool* is_speech, float* probability);
ra_result_t ra_vad_calibrate(ra_vad_handle_t h, const float* audio, size_t samples);
void ra_vad_notify_tts_start(ra_vad_handle_t h);
void ra_vad_notify_tts_end(ra_vad_handle_t h);
ra_result_t ra_vad_destroy(ra_vad_handle_t h);
```

**Algorithm (C++)**:
```cpp
float calculateRMS(const float* audio, size_t samples) {
    float sum = 0.0f;
    for (size_t i = 0; i < samples; i++) {
        sum += audio[i] * audio[i];
    }
    return sqrtf(sum / samples);
}
```

**FFI Frequency**: MED - Called per audio chunk (10-20ms), but batched

**Effort**: S (1 week)

---

### 3. ModuleRegistry (Move to Core)

**Location**: `Core/Module/ModuleRegistry.swift`

**Current Behavior** (Lines 69-328):
- `@MainActor` singleton for thread safety
- `register<M: RunAnywhereModule>()` registers modules with priority
- `modules(for capability)` finds modules by capability type
- `storageStrategy(for framework)` and `downloadStrategy(for model)`
- Auto-discovery via static initialization

**What Moves to Core**:
- Registry data structure
- Priority-based lookup
- Module discovery mechanism
- Strategy resolution

**Core API**:
```c
// Registration
ra_result_t ra_module_registry_register(const ra_module_info_t* module);
ra_result_t ra_module_registry_register_provider(ra_capability_type_t cap,
    const ra_provider_info_t* provider);

// Lookup
ra_result_t ra_module_registry_get_modules(ra_capability_type_t cap,
    ra_module_info_t** out, size_t* count);
ra_result_t ra_module_registry_get_provider(ra_capability_type_t cap,
    const char* model_id, ra_provider_info_t* out);
ra_result_t ra_module_registry_get_storage_strategy(ra_framework_t framework,
    ra_storage_strategy_t* out);
```

**FFI Frequency**: LOW - Called at initialization and model load time

**Effort**: M (2 weeks)

---

### 4. EventPublisher (Move to Core)

**Location**: `Infrastructure/Events/EventPublisher.swift`

**Current Behavior** (Lines 45-56):
- Routes events based on `event.destination`
- If not `.analyticsOnly`: sends to EventBus (public subscriptions)
- If not `.publicOnly`: sends to Analytics backend (telemetry)

**What Moves to Core**:
- Event routing logic
- Destination filtering
- Event type definitions
- Analytics integration

**What Stays in Wrapper**:
- EventBus subscription mechanism (Combine-based)
- Swift event types

**Core API**:
```c
typedef enum {
    RA_EVENT_DEST_PUBLIC = 1,
    RA_EVENT_DEST_ANALYTICS = 2,
    RA_EVENT_DEST_BOTH = 3
} ra_event_destination_t;

typedef struct {
    const char* type;
    const char* payload_json;
    ra_event_destination_t destination;
    uint64_t timestamp;
} ra_event_t;

// Publishing
ra_result_t ra_event_publish(const ra_event_t* event);

// Subscription (callback-based for core consumers)
typedef void (*ra_event_callback_t)(const ra_event_t* event, void* context);
ra_result_t ra_event_subscribe(ra_event_callback_t callback, void* context);
```

**FFI Frequency**: LOW - Events are infrequent (model load, generation complete)

**Effort**: S (1 week)

---

### 5. DownloadService (Hybrid)

**Location**: `Infrastructure/Download/Services/AlamofireDownloadService.swift`

**Current Behavior** (Lines 162-283):
1. Determine download destination (temp for archives, direct for files)
2. Perform download via Alamofire
3. Extract archive if needed
4. Update model metadata
5. Track completion analytics

**What Moves to Core**:
- Download orchestration logic
- Retry/resume strategy
- Progress calculation
- Archive extraction decision
- Checksum verification

**What Stays in Wrapper**:
- Alamofire HTTP implementation
- FileManager file I/O
- Platform temp directory

**Core API**:
```c
typedef struct {
    const char* model_id;
    const char* url;
    const char* destination;
    const char* checksum_sha256;  // Optional
} ra_download_request_t;

typedef void (*ra_download_progress_t)(const char* model_id,
    size_t downloaded, size_t total, void* context);
typedef void (*ra_download_complete_t)(const char* model_id,
    ra_result_t result, const char* path, void* context);

ra_result_t ra_download_start(const ra_download_request_t* request,
    ra_download_progress_t progress, ra_download_complete_t complete, void* context);
ra_result_t ra_download_cancel(const char* model_id);
ra_result_t ra_download_pause(const char* model_id);
ra_result_t ra_download_resume(const char* model_id);
```

**Platform Adapter**:
```c
typedef struct {
    ra_result_t (*http_download)(const char* url, const char* dest,
        ra_download_progress_t progress, void* context);
    ra_result_t (*file_exists)(const char* path, bool* exists);
    ra_result_t (*file_size)(const char* path, size_t* size);
    ra_result_t (*file_delete)(const char* path);
    ra_result_t (*extract_archive)(const char* archive, const char* dest);
} ra_platform_adapter_t;

ra_result_t ra_set_platform_adapter(const ra_platform_adapter_t* adapter);
```

**FFI Frequency**: LOW - Called per model download

**Effort**: M (2-3 weeks)

---

### 6. AudioCaptureManager (Keep in Wrapper)

**Location**: `Features/STT/Services/AudioCaptureManager.swift`

**Current Behavior** (Lines 47-215):
- Requests microphone permission via `AVAudioApplication` (iOS 17+)
- Sets up `AVAudioEngine` with input tap
- Configures audio session (category, mode, options)
- Resamples audio to 16kHz mono Int16

**Why Not in Core**:
- Tightly coupled to AVFoundation
- Permission handling is OS-specific
- Audio session management is iOS-specific
- Cannot be abstracted without significant overhead

**Wrapper Responsibility**:
- Capture audio using AVAudioEngine
- Convert to 16kHz mono format
- Pass to core VAD/STT components

**Core Interface**:
```c
// Core expects audio in standard format
typedef struct {
    const float* samples;
    size_t count;
    uint32_t sample_rate;  // Expected: 16000
    uint8_t channels;      // Expected: 1
} ra_audio_buffer_t;
```

---

### 7. KeychainManager (Keep in Wrapper)

**Location**: `Foundation/Security/KeychainManager.swift`

**Current Behavior**:
- Stores API keys securely
- Persists device UUID
- Uses Keychain Services framework

**Why Not in Core**:
- Security APIs are platform-specific
- Android uses Keystore/EncryptedSharedPreferences
- No portable alternative with equivalent security

**Core Interface**:
```c
// Core defines what needs storage, wrapper provides how
typedef struct {
    ra_result_t (*get)(const char* key, char* value, size_t* len);
    ra_result_t (*set)(const char* key, const char* value);
    ra_result_t (*remove)(const char* key);
} ra_secure_storage_adapter_t;
```

---

## Summary

### Move to Core (YES)

| Component | Effort | Priority |
|-----------|--------|----------|
| SimpleEnergyVADService | S | 1 |
| EventPublisher | S | 2 |
| ManagedLifecycle | S | 3 |
| ModuleRegistry | M | 4 |
| ServiceRegistry | M | 5 |
| STTCapability | M | 6 |
| TTSCapability | M | 7 |
| LLMCapability | M | 8 |
| VADCapability | S | 9 |
| VoiceAgentCapability | L | 10 |

### Hybrid (Core Logic + Wrapper Adapter)

| Component | Core Logic | Wrapper Adapter |
|-----------|-----------|-----------------|
| DownloadService | Orchestration, retry, checksum | Alamofire HTTP |
| APIClient | Auth, retry logic | Alamofire HTTP |
| SimplifiedFileManager | Path resolution | FileManager I/O |
| EventBus | Event types, routing | Combine publishers |
| SDKLogger | Log levels, formatting | os.Logger output |

### Keep in Wrapper (NO)

| Component | Reason |
|-----------|--------|
| AudioCaptureManager | AVFoundation |
| AudioPlaybackManager | AVFoundation |
| SystemTTSService | AVSpeechSynthesizer |
| KeychainManager | Keychain Services |
| DeviceIdentity | UUID + Keychain |
| SentryManager | Crash reporting |
| StorageAnalyzer | Platform disk APIs |

---

## Effort Estimates

| Effort | Duration | Description |
|--------|----------|-------------|
| S | 1 week | Single developer, straightforward |
| M | 2-3 weeks | Single developer, moderate complexity |
| L | 4-6 weeks | May need multiple developers |

**Total iOS Migration Effort**: ~12-16 weeks for full migration
**Recommended Phase 1**: ~4-6 weeks (VAD, Events, Registry)

---

*Document generated: December 2025*
*Source of Truth: iOS Swift SDK*
