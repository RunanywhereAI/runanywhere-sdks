# Android/Kotlin KMP SDK Core Feasibility Analysis

## Overview

The Kotlin Multiplatform SDK at `sdk/runanywhere-kotlin/` provides cross-platform support for JVM, Android, and Native targets. It already separates shared logic (`commonMain`) from platform-specific code.

**SDK Statistics**:
- **Language**: Kotlin 2.1.21
- **Estimated Lines**: ~30,000
- **Portable Logic (commonMain)**: ~85%
- **Platform-Specific**: ~15%

---

## Current SDK Architecture

### Directory Structure

```
src/
├── commonMain/           # Shared Kotlin logic (85%)
│   ├── public/          # RunAnywhere API
│   ├── components/      # STT, LLM, VAD, TTS, VoiceAgent
│   ├── core/            # ModuleRegistry
│   ├── data/            # Network, repositories
│   ├── events/          # EventBus
│   ├── foundation/      # ServiceContainer, logging
│   ├── models/          # Model management
│   ├── routing/         # RoutingDecisionEngine (unique to KMP!)
│   ├── services/        # Analytics, download
│   └── voice/           # VAD handler, SimpleEnergyVAD
├── androidMain/          # Android-specific (8%)
├── jvmMain/              # JVM-specific (5%)
└── nativeMain/           # Native-specific (2%)

modules/
├── runanywhere-core-jni/          # JNI bindings
├── runanywhere-core-native/       # Native C++ bridge
├── runanywhere-core-onnx/         # ONNX Runtime
├── runanywhere-core-llamacpp/     # LlamaCpp
├── runanywhere-llm-llamacpp/      # LLM provider
├── runanywhere-llm-mlc/           # MLC-LLM (Android GPU)
└── runanywhere-whisperkit/        # Whisper STT
```

### Key Entry Points

| Entry Point | Location | Description |
|------------|----------|-------------|
| `RunAnywhere` object | `commonMain/public/RunAnywhere.kt` | Main SDK singleton (expect/actual) |
| `ServiceContainer` | `commonMain/foundation/ServiceContainer.kt` | Central DI (8-step bootstrap) |
| `ModuleRegistry` | `commonMain/core/ModuleRegistry.kt` | Plugin architecture |
| `EventBus` | `commonMain/events/EventBus.kt` | Flow-based event system |

---

## Unique KMP Components Not in iOS

### RoutingDecisionEngine

**Location**: `commonMain/routing/RoutingDecisionEngine.kt`

**Why Unique**: iOS does not have this component yet - it's a KMP advancement.

**Current Behavior** (Lines 16-260):
- Decision factors: forced override, PII detection, privacy score, latency, cost, quality
- On-device score: privacy bonus, latency bonus, cost bonus, config preference
- Cloud score: quality bonus, flexibility bonus, privacy penalty
- Cost estimation: $0.002 per 1K tokens

**Assessment**: This is a **high-value core candidate** that should be backported to iOS and moved to C++ core.

---

## Component Analysis Table

| Component / Module | Location | Move to Core? | iOS Equivalent | Proposed Core API | Platform Adapters | FFI Frequency | Est. Effort |
|-------------------|----------|---------------|----------------|-------------------|-------------------|---------------|-------------|
| **RunAnywhere** | `commonMain/public/RunAnywhere.kt` | HYBRID | `RunAnywhere.swift` | Entry point wrapper | None | LOW | M |
| **ServiceContainer** | `commonMain/foundation/ServiceContainer.kt` | YES | `ServiceContainer.swift` | `ra_service_*()` | Platform initializers | LOW | M |
| **ModuleRegistry** | `commonMain/core/ModuleRegistry.kt` | YES | `ModuleRegistry.swift` | `ra_module_*()` | None | LOW | M |
| **EventBus** | `commonMain/events/EventBus.kt` | HYBRID | `EventBus.swift` | `ra_event_*()` | Flow (wrapper) | LOW | M |
| **RoutingDecisionEngine** | `commonMain/routing/RoutingDecisionEngine.kt` | YES | **Not in iOS** | `ra_routing_*()` | None | LOW | M |
| **RoutingService** | `commonMain/routing/RoutingService.kt` | YES | **Not in iOS** | Part of routing | None | LOW | S |
| **STTComponent** | `commonMain/components/stt/STTComponent.kt` | YES | `STTCapability.swift` | `ra_stt_component_*()` | AudioInput | LOW | M |
| **LLMComponent** | `commonMain/components/llm/LLMComponent.kt` | YES | `LLMCapability.swift` | `ra_llm_component_*()` | None | LOW | M |
| **VADComponent** | `commonMain/components/vad/VADComponent.kt` | YES | `VADCapability.swift` | `ra_vad_component_*()` | None | LOW | S |
| **VoiceAgentComponent** | `commonMain/components/voiceagent/VoiceAgentComponent.kt` | YES | `VoiceAgentCapability.swift` | `ra_voice_agent_*()` | AudioInput, AudioOutput | LOW | L |
| **SimpleEnergyVAD** | `commonMain/voice/vad/SimpleEnergyVAD.kt` | YES | `SimpleEnergyVADService.swift` | `ra_vad_process()` | None | MED | S |
| **ModelManager** | `commonMain/models/ModelManager.kt` | YES | `ModelInfoService.swift` | `ra_model_*()` | None | LOW | M |
| **ModelRegistry** | `commonMain/models/ModelRegistry.kt` | YES | `RegistryService.swift` | Part of model API | FileSystem | LOW | M |
| **ModelLifecycleManager** | `commonMain/models/lifecycle/ModelLifecycleManager.kt` | YES | `ModelLifecycleManager.swift` | `ra_lifecycle_*()` | None | LOW | S |
| **KtorDownloadService** | `commonMain/services/download/KtorDownloadService.kt` | HYBRID | `AlamofireDownloadService.swift` | `ra_download_*()` | HttpClient | LOW | M |
| **KtorNetworkService** | `commonMain/data/network/KtorNetworkService.kt` | HYBRID | `APIClient.swift` | `ra_http_*()` | HttpClient | LOW | M |
| **AnalyticsService** | `commonMain/services/analytics/AnalyticsService.kt` | YES | Analytics services | `ra_analytics_*()` | HttpClient | LOW | M |
| **TelemetryService** | `commonMain/services/telemetry/TelemetryService.kt` | YES | `TelemetryEventProperties.swift` | Part of analytics | None | LOW | S |
| **SyncCoordinator** | `commonMain/services/sync/SyncCoordinator.kt` | YES | Not in iOS | Part of analytics | HttpClient | LOW | S |
| **MemoryManager** | `commonMain/memory/` | YES | Memory management | `ra_memory_*()` | None | LOW | M |
| Android audio | `androidMain/audio/` | NO | AudioCaptureManager | N/A | N/A | N/A | N/A |
| Android storage | `androidMain/security/` | NO | KeychainManager | N/A | N/A | N/A | N/A |
| JVM audio | `jvmMain/audio/` | NO | N/A (JVM specific) | N/A | N/A | N/A | N/A |
| **WhisperKitProvider** | `modules/runanywhere-whisperkit/` | ALREADY CORE | `ONNXSTTService.swift` | Uses `ra_stt_*` | None | MED | - |
| **LlamaCppAdapter** | `modules/runanywhere-core-llamacpp/` | ALREADY CORE | `LlamaCPPService.swift` | Uses `ra_text_*` | None | MED | - |
| **ONNXAdapter** | `modules/runanywhere-core-onnx/` | ALREADY CORE | `ONNXServiceProvider.swift` | Uses `ra_*` | None | MED | - |
| **MLCProvider** | `modules/runanywhere-llm-mlc/` | NO (Android GPU) | N/A | N/A | N/A | N/A | N/A |

---

## Detailed Component Analysis

### 1. RoutingDecisionEngine (Move to Core - HIGH PRIORITY)

**Location**: `commonMain/routing/RoutingDecisionEngine.kt`

**Current Behavior** (Lines 16-260):
```kotlin
// Decision factors (lines 16-108)
1. Forced routing override (testing/debugging)
2. PII detection → always on-device
3. Privacy score threshold → prefer on-device
4. Latency requirements → REAL_TIME forces on-device
5. Cost optimization → high sensitivity uses on-device
6. Quality requirements → HIGH may use cloud if 1.5x better
7. Score-based decision → calculates on-device vs cloud scores

// On-Device Score (lines 113-148)
- Privacy bonus: 30 * privacyScore
- Latency bonus: REAL_TIME: 40, LOW: 30, MEDIUM: 20, FLEXIBLE: 10
- Cost bonus: HIGH: 30, MEDIUM: 20, LOW: 10
- Configuration preference bonus: 20 if preferOnDevice
- Large token penalty: -10 if > 1000 tokens

// Cloud Score (lines 151-195)
- Quality bonus: HIGH: 40, MEDIUM: 25, STANDARD: 15
- Large request bonus: 20 if > 1000 tokens
- Flexibility bonus: 15 if FLEXIBLE latency
- Configuration preference bonus: 20 if !preferOnDevice
- Privacy penalty: -25 * privacyScore
- Cost penalty: -20 if HIGH cost sensitivity
```

**What Moves to Core**:
- Complete scoring algorithm
- Decision factor evaluation
- Cost estimation
- Metrics collection

**Core API**:
```c
typedef struct {
    bool force_on_device;
    bool force_cloud;
    bool has_pii;
    float privacy_score;          // 0.0-1.0
    ra_latency_requirement_t latency;
    ra_cost_sensitivity_t cost_sensitivity;
    ra_quality_requirement_t quality;
    uint32_t estimated_tokens;
    bool prefer_on_device;
} ra_routing_request_t;

typedef struct {
    ra_routing_target_t target;   // ON_DEVICE, CLOUD, HYBRID
    float on_device_score;
    float cloud_score;
    float estimated_cost;
    const char* reason;
} ra_routing_decision_t;

ra_result_t ra_routing_decide(const ra_routing_request_t* request,
    ra_routing_decision_t* decision);
```

**FFI Frequency**: LOW - Called once per generation request

**Effort**: M (2 weeks)

**iOS Backport**: This component should be added to iOS after core implementation.

---

### 2. ServiceContainer (Move to Core)

**Location**: `commonMain/foundation/ServiceContainer.kt`

**Current Behavior** (Lines 230-569):
- 8-step bootstrap process matching iOS exactly
- Lazy initialization of all services
- Development vs. production mode configuration
- Component lifecycle management

**What Moves to Core**:
- Bootstrap sequence logic
- Service lifecycle management
- Configuration validation
- Health check orchestration

**What Stays in Wrapper**:
- expect/actual platform initializers
- Platform-specific file/network creation

**Core API**:
```c
typedef struct {
    const char* api_key;
    const char* base_url;
    ra_environment_t environment;
    ra_platform_adapter_t* platform;
} ra_init_config_t;

// Bootstrap phases
ra_result_t ra_init_phase_1_platform(const ra_init_config_t* config);
ra_result_t ra_init_phase_2_config(void);
ra_result_t ra_init_phase_3_auth(void);
ra_result_t ra_init_phase_4_models(void);
ra_result_t ra_init_phase_5_analytics(void);
ra_result_t ra_init_phase_6_components(void);
ra_result_t ra_init_phase_7_cache(void);
ra_result_t ra_init_phase_8_health(void);

// Full initialization
ra_result_t ra_initialize(const ra_init_config_t* config);
ra_result_t ra_cleanup(void);
```

**FFI Frequency**: LOW - Called once at SDK initialization

**Effort**: M (2-3 weeks)

---

### 3. EventBus (Hybrid)

**Location**: `commonMain/events/EventBus.kt`

**Current Behavior** (Lines 15-425):
- Uses Kotlin `MutableSharedFlow` / `SharedFlow`
- Event types: SDKInitializationEvent, SDKGenerationEvent, SDKModelEvent, etc.
- Thread-safe via `tryEmit()`
- Convenience extensions: `on<T>()`, `onInitialization()`, etc.

**What Moves to Core**:
- Event type definitions
- Event routing logic
- Event filtering

**What Stays in Wrapper**:
- Flow-based subscription mechanism
- Kotlin extension functions

**Core API**:
```c
// Same as iOS analysis - cross-platform event system
ra_result_t ra_event_publish(const ra_event_t* event);
ra_result_t ra_event_subscribe(ra_event_type_t type, ra_event_callback_t cb, void* ctx);
ra_result_t ra_event_unsubscribe(ra_subscription_id_t id);
```

**FFI Frequency**: LOW - Events are infrequent

**Effort**: M (2 weeks)

---

### 4. SimpleEnergyVAD (Move to Core)

**Location**: `commonMain/voice/vad/SimpleEnergyVAD.kt`

**Current Behavior**:
- RMS energy calculation
- Hysteresis state machine
- Threshold calibration
- Matches iOS `SimpleEnergyVADService.swift`

**What Moves to Core**:
- Same as iOS analysis - identical algorithm

**Core API**:
```c
// Same as iOS - cross-platform VAD
ra_result_t ra_vad_create(ra_vad_config_t* config, ra_vad_handle_t* out);
ra_result_t ra_vad_process(ra_vad_handle_t h, const float* audio, size_t samples,
    bool* is_speech, float* probability);
```

**FFI Frequency**: MED (batched audio chunks)

**Effort**: S (1 week)

---

### 5. KtorNetworkService (Hybrid)

**Location**: `commonMain/data/network/KtorNetworkService.kt`

**Current Behavior**:
- Uses Ktor KMP for HTTP
- Request/response serialization
- Retry policies
- Authentication header injection

**What Moves to Core**:
- Request building logic
- Auth header management
- Retry logic
- Response parsing

**What Stays in Wrapper**:
- Ktor HTTP engine
- Platform-specific connection handling

**Platform Adapter**:
```c
typedef struct {
    ra_result_t (*request)(const ra_http_request_t* req, ra_http_response_t* resp);
    ra_result_t (*request_async)(const ra_http_request_t* req,
        ra_http_callback_t callback, void* context);
} ra_http_adapter_t;
```

**FFI Frequency**: LOW - Per-request

**Effort**: M (2 weeks)

---

### 6. ModelLifecycleManager (Move to Core)

**Location**: `commonMain/models/lifecycle/ModelLifecycleManager.kt`

**Current Behavior**:
- Lifecycle states: UNLOADED → LOADING → LOADED → IN_USE → UNLOADING
- Lifecycle events: modelWillLoad, modelDidLoad, modelLoadFailed, etc.
- Memory tracking during transitions
- Framework and modality tracking

**What Moves to Core**:
- State machine
- Event publishing
- Memory tracking integration
- Transition validation

**Core API**:
```c
typedef enum {
    RA_MODEL_STATE_UNLOADED,
    RA_MODEL_STATE_LOADING,
    RA_MODEL_STATE_LOADED,
    RA_MODEL_STATE_IN_USE,
    RA_MODEL_STATE_UNLOADING,
    RA_MODEL_STATE_FAILED
} ra_model_state_t;

ra_result_t ra_model_lifecycle_transition(const char* model_id,
    ra_model_state_t from, ra_model_state_t to);
ra_model_state_t ra_model_lifecycle_get_state(const char* model_id);
```

**FFI Frequency**: LOW - Per-model load/unload

**Effort**: S (1 week)

---

### 7. MemoryManager (Move to Core)

**Location**: `commonMain/memory/`

**Current Behavior**:
- Memory pressure detection
- Cache eviction policies (LRU)
- Allocation tracking
- Model unloading on pressure

**What Moves to Core**:
- Eviction policy logic
- Allocation tracking
- Pressure thresholds
- Unload decision making

**What Stays in Wrapper**:
- Platform memory queries (via adapter)

**Core API**:
```c
typedef struct {
    size_t total_bytes;
    size_t available_bytes;
    size_t used_by_models;
    float pressure_level;  // 0.0-1.0
} ra_memory_state_t;

ra_result_t ra_memory_get_state(ra_memory_state_t* state);
ra_result_t ra_memory_register_allocation(const char* model_id, size_t bytes);
ra_result_t ra_memory_unregister_allocation(const char* model_id);
ra_result_t ra_memory_get_eviction_candidates(char** model_ids, size_t* count);
```

**FFI Frequency**: LOW - Per allocation/check

**Effort**: M (2 weeks)

---

## Platform-Specific Analysis

### androidMain

| Component | Description | Keep in Wrapper? |
|-----------|-------------|------------------|
| Audio capture | AudioRecord, AudioManager | YES - Platform API |
| Secure storage | EncryptedSharedPreferences, Keystore | YES - Platform API |
| File system | Context.filesDir, getExternalFilesDir | YES - Platform API |
| Device info | Build.MODEL, Build.VERSION | YES - Platform API |
| Network | OkHttp engine for Ktor | YES - Platform-optimized |

### jvmMain

| Component | Description | Keep in Wrapper? |
|-----------|-------------|------------------|
| Audio capture | javax.sound.sampled | YES - Platform API |
| Secure storage | Encrypted files, OS keychain | YES - Platform API |
| File system | java.io.File, java.nio.Path | YES - Platform API |
| Network | Apache/OkHttp engine for Ktor | YES - Platform-optimized |

### nativeMain

| Component | Description | Keep in Wrapper? |
|-----------|-------------|------------------|
| Native interop | cinterop bindings | YES - Generates C bindings |
| Memory | Native memory management | CORE - Already native |

---

## Summary

### Move to Core (YES)

| Component | Effort | Priority | Notes |
|-----------|--------|----------|-------|
| RoutingDecisionEngine | M | 1 | **Unique to KMP - backport to iOS** |
| SimpleEnergyVAD | S | 2 | Same as iOS |
| ModelLifecycleManager | S | 3 | Same as iOS |
| ServiceContainer | M | 4 | Same as iOS |
| ModuleRegistry | M | 5 | Same as iOS |
| EventBus (core) | M | 6 | Same as iOS |
| MemoryManager | M | 7 | Same as iOS |
| STTComponent | M | 8 | Same as iOS |
| LLMComponent | M | 9 | Same as iOS |
| VoiceAgentComponent | L | 10 | Same as iOS |

### Hybrid (Core Logic + Wrapper Adapter)

| Component | Core Logic | Wrapper Adapter |
|-----------|-----------|-----------------|
| KtorNetworkService | Auth, retry, parsing | Ktor HTTP engine |
| KtorDownloadService | Orchestration, checksum | Ktor HTTP |
| EventBus | Event types, routing | Flow publishers |
| ModelRegistry | Registry logic | FileSystem scanner |

### Keep in Wrapper (NO)

| Component | Reason |
|-----------|--------|
| Android audio | AudioRecord, AudioManager |
| Android storage | EncryptedSharedPreferences |
| JVM audio | javax.sound |
| Platform device info | Build.*, ProcessInfo |
| MLCProvider | Android GPU-specific |

---

## Effort Estimates

**Total KMP Migration Effort**: ~10-14 weeks (less than iOS due to existing modular structure)
**Recommended Phase 1**: ~4-5 weeks (RoutingEngine, VAD, Events, Lifecycle)

**Key Advantage**: KMP's commonMain/platformMain separation means most business logic is already isolated.

---

*Document generated: December 2025*
*Compared against: iOS Swift SDK (source of truth)*
