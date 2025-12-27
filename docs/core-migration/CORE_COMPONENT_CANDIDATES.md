# Core Component Candidates

## Unified Cross-SDK Analysis

This document provides a consolidated list of components across all SDKs, categorized by migration priority and feasibility.

---

## Category 1: Move Now (High ROI, Low Risk)

These components are **stable, deterministic, duplicated across 3-4 SDKs**, and have low FFI frequency.

| Component | iOS Location | KMP Location | Flutter Location | RN Location | Rationale | Boundary Data | Effort |
|-----------|--------------|--------------|------------------|-------------|-----------|---------------|--------|
| **SimpleEnergyVAD** | `Features/VAD/Services/SimpleEnergyVADService.swift` | `voice/vad/SimpleEnergyVAD.kt` | `components/vad/` (uses ONNX) | `components/VAD/` (uses C++) | Pure math (RMS, hysteresis), duplicated | Audio chunks → speech boolean | S |
| **RoutingDecisionEngine** | Not implemented | `routing/RoutingDecisionEngine.kt` | `capabilities/routing/` | `Capabilities/Routing/` | Complex scoring algorithm, should be unified | Request params → routing decision | M |
| **ModelLifecycleManager** | `Core/Capabilities/ManagedLifecycle.swift` | `models/lifecycle/ModelLifecycleManager.kt` | `core/model_lifecycle_manager.dart` | Not explicit | State machine (UNLOADED→LOADING→LOADED) | Model ID → state transitions | S |
| **EventPublisher** | `Infrastructure/Events/EventPublisher.swift` | `events/EventBus.kt` | Not explicit | `Public/Events/EventBus.ts` | Event routing, analytics integration | Events → destinations | S |
| **ModuleRegistry** | `Core/Module/ModuleRegistry.swift` | `core/ModuleRegistry.kt` | `core/module_registry.dart` | `Core/ModuleRegistry.ts` | Plugin architecture, provider lookup | Provider registration + lookup | M |
| **ServiceRegistry** | `Core/ServiceRegistry.swift` | (part of ModuleRegistry) | `core/service_registry/` | (part of ModuleRegistry) | Factory pattern for services | Service creation | M |

### Detailed Specifications

#### SimpleEnergyVAD

**Current Behavior** (iOS `SimpleEnergyVADService.swift` lines 298-463):
```swift
// RMS calculation
func calculateAverageEnergy(_ samples: [Float]) -> Float {
    var result: Float = 0
    vDSP_rmsqv(samples, 1, &result, vDSP_Length(samples.count))
    return result
}

// Hysteresis state machine
func updateVoiceActivityState() {
    if currentEnergy > onThreshold && !isSpeaking {
        // Start speaking
        speechOnsetTime = Date()
        consecutiveSpeechFrames += 1
        if consecutiveSpeechFrames >= minSpeechFrames {
            isSpeaking = true
        }
    } else if currentEnergy < offThreshold && isSpeaking {
        // Stop speaking
        consecutiveSilenceFrames += 1
        if consecutiveSilenceFrames >= minSilenceFrames {
            isSpeaking = false
        }
    }
}
```

**Core API**:
```c
typedef struct {
    float speech_threshold;      // Energy threshold for speech detection
    float silence_threshold;     // Energy threshold for silence
    uint32_t min_speech_frames;  // Frames before confirming speech
    uint32_t min_silence_frames; // Frames before confirming silence
    bool tts_active;             // Raise threshold during TTS playback
} ra_vad_config_t;

ra_result_t ra_vad_create(const ra_vad_config_t* config, ra_vad_handle_t* handle);
ra_result_t ra_vad_process(ra_vad_handle_t handle, const float* audio, size_t samples,
                           bool* is_speech, float* energy, float* probability);
ra_result_t ra_vad_calibrate(ra_vad_handle_t handle, const float* audio, size_t samples);
void ra_vad_notify_tts_start(ra_vad_handle_t handle);
void ra_vad_notify_tts_end(ra_vad_handle_t handle);
ra_result_t ra_vad_destroy(ra_vad_handle_t handle);
```

**Batching Strategy**: Process 10-20ms audio chunks (160-320 samples at 16kHz)

---

#### RoutingDecisionEngine

**Current Behavior** (KMP `RoutingDecisionEngine.kt` lines 16-260):
```kotlin
// Scoring factors
val onDeviceScore = calculateOnDeviceScore(request)  // 0-100
val cloudScore = calculateCloudScore(request)         // 0-100

// On-device score components
fun calculateOnDeviceScore(req: RoutingRequest): Float {
    var score = 0f
    score += 30 * req.privacyScore                    // Privacy bonus
    score += latencyBonus(req.latencyRequirement)     // 10-40 points
    score += costBonus(req.costSensitivity)           // 10-30 points
    if (req.preferOnDevice) score += 20               // Config preference
    if (req.estimatedTokens > 1000) score -= 10       // Large request penalty
    return score
}
```

**Core API**:
```c
typedef enum {
    RA_LATENCY_REAL_TIME,    // 40 points on-device
    RA_LATENCY_LOW,          // 30 points
    RA_LATENCY_MEDIUM,       // 20 points
    RA_LATENCY_FLEXIBLE      // 10 points
} ra_latency_requirement_t;

typedef enum {
    RA_COST_HIGH,            // 30 points on-device
    RA_COST_MEDIUM,          // 20 points
    RA_COST_LOW              // 10 points
} ra_cost_sensitivity_t;

typedef enum {
    RA_QUALITY_STANDARD,     // 15 points cloud
    RA_QUALITY_MEDIUM,       // 25 points cloud
    RA_QUALITY_HIGH          // 40 points cloud
} ra_quality_requirement_t;

typedef struct {
    bool force_on_device;
    bool force_cloud;
    bool has_pii;
    float privacy_score;              // 0.0-1.0
    ra_latency_requirement_t latency;
    ra_cost_sensitivity_t cost;
    ra_quality_requirement_t quality;
    uint32_t estimated_tokens;
    bool prefer_on_device;
} ra_routing_request_t;

typedef struct {
    ra_routing_target_t target;       // ON_DEVICE, CLOUD, HYBRID
    float on_device_score;
    float cloud_score;
    float estimated_cost_usd;
    const char* decision_reason;
} ra_routing_decision_t;

ra_result_t ra_routing_decide(const ra_routing_request_t* request,
                              ra_routing_decision_t* decision);
```

---

## Category 2: Hybrid (Core Interface + Wrapper Adapter)

These components have **core business logic** that should be shared, but require **platform-specific adapters** for I/O.

| Component | Core Logic | Platform Adapter | Data Crossing | Batching Strategy |
|-----------|-----------|------------------|---------------|-------------------|
| **DownloadService** | Orchestration, retry logic, checksum, progress calculation | HTTP client (Alamofire/Ktor/http/URLSession) | URL, path, progress callbacks | Progress updates every 1% or 500ms |
| **APIClient** | Auth token management, retry logic, request building | HTTP client | Request/response JSON | Per-request |
| **FileManager** | Path resolution, model discovery | Platform FileSystem | Paths, file metadata | Per-operation |
| **EventBus** | Event types, routing rules | Combine/Flow/Stream/EventEmitter | Event JSON | Per-event |
| **Logger** | Log levels, formatting, redaction | os.Logger/Logcat/console | Log messages | Per-log (buffered) |
| **SecureStorage** | Key names, encryption decisions | Keychain/Keystore/EncryptedPrefs | Key-value pairs | Per-operation |

### Adapter Interface Pattern

```c
// Core defines protocol
typedef struct {
    // HTTP adapter
    ra_result_t (*http_request)(const ra_http_request_t* req, ra_http_response_t* resp);
    ra_result_t (*http_download)(const char* url, const char* dest,
                                  ra_progress_callback_t progress, void* context);

    // FileSystem adapter
    ra_result_t (*file_exists)(const char* path, bool* exists);
    ra_result_t (*file_read)(const char* path, uint8_t** data, size_t* len);
    ra_result_t (*file_write)(const char* path, const uint8_t* data, size_t len);
    ra_result_t (*file_delete)(const char* path);
    ra_result_t (*dir_list)(const char* path, char*** files, size_t* count);

    // SecureStorage adapter
    ra_result_t (*secure_get)(const char* key, char* value, size_t* len);
    ra_result_t (*secure_set)(const char* key, const char* value);
    ra_result_t (*secure_delete)(const char* key);

    // Logger adapter
    void (*log)(ra_log_level_t level, const char* tag, const char* message);

    // Clock adapter
    uint64_t (*now_ms)(void);
} ra_platform_adapter_t;

// Platform provides implementation
ra_result_t ra_set_platform_adapter(const ra_platform_adapter_t* adapter);
```

---

## Category 3: Do Not Move (Platform Side-Effects)

These components **must stay in platform wrappers** because they use platform-specific APIs that cannot be abstracted without significant overhead.

| Component | iOS Implementation | Android/KMP Implementation | Reason |
|-----------|-------------------|---------------------------|--------|
| **AudioCaptureManager** | AVAudioEngine, AVAudioSession | AudioRecord, AudioManager | Real-time audio requires platform APIs |
| **AudioPlaybackManager** | AVAudioEngine | AudioTrack, MediaPlayer | Real-time playback requires platform APIs |
| **SystemTTSService** | AVSpeechSynthesizer | android.speech.tts.TextToSpeech | Platform-native TTS engines |
| **KeychainManager** | Keychain Services | Keystore, EncryptedSharedPreferences | Security APIs are platform-specific |
| **DeviceIdentity** | UUID + Keychain | Settings.Secure.ANDROID_ID | Device ID persistence is platform-specific |
| **PermissionHandler** | AVAudioApplication | ContextCompat.checkSelfPermission | Permission APIs are platform-specific |
| **SentryManager** | Sentry iOS SDK | Sentry Android SDK | Crash reporting SDKs |
| **StorageAnalyzer** | FileManager.attributesOfFileSystem | StatFs | Disk space queries |
| **NetworkReachability** | Network.framework | ConnectivityManager | Network state |
| **BatteryState** | UIDevice.batteryState | BatteryManager | Power state |
| **ThermalState** | ProcessInfo.thermalState | PowerManager | Thermal throttling |

### Audio I/O Boundary

Audio components stay in wrappers, but core defines the expected format:

```c
// Core expects audio in standard format
typedef struct {
    float* samples;           // PCM float32
    size_t sample_count;
    uint32_t sample_rate;     // Expected: 16000 for STT, varies for TTS
    uint8_t channels;         // Expected: 1 (mono)
} ra_audio_buffer_t;

// Wrapper captures platform audio, converts, passes to core
// iOS: AVAudioEngine → convert → ra_audio_buffer_t
// Android: AudioRecord → convert → ra_audio_buffer_t
```

---

## Component Migration Priority Matrix

| Priority | Component | ROI | Risk | Dependencies | Effort |
|----------|-----------|-----|------|--------------|--------|
| 1 | SimpleEnergyVAD | HIGH | LOW | None | S |
| 2 | RoutingDecisionEngine | HIGH | LOW | None | M |
| 3 | ModelLifecycleManager | HIGH | LOW | EventPublisher | S |
| 4 | EventPublisher | HIGH | LOW | None | S |
| 5 | ModuleRegistry | HIGH | MEDIUM | ServiceRegistry | M |
| 6 | ServiceRegistry | MEDIUM | MEDIUM | None | M |
| 7 | ComponentStateManager | MEDIUM | MEDIUM | EventPublisher | M |
| 8 | MemoryPressureHandler | MEDIUM | LOW | ModelLifecycleManager | M |
| 9 | AnalyticsQueueManager | MEDIUM | LOW | EventPublisher | M |
| 10 | DownloadOrchestrator | MEDIUM | MEDIUM | Platform HTTP adapter | M |

---

## Cross-SDK Consistency Check

| Feature | iOS | KMP | Flutter | RN | Action |
|---------|-----|-----|---------|----|----|
| VAD Algorithm | SimpleEnergy | SimpleEnergy | ONNX Silero | ONNX Silero | Unify to core (support both) |
| Routing Engine | Not impl | ✅ Full impl | Partial | Partial | Port KMP impl to core |
| Event System | Combine | Flow | Streams | EventEmitter | Core defines events, wrappers subscribe |
| State Machine | ManagedLifecycle | ModelLifecycleManager | model_lifecycle_manager | Not explicit | Unify pattern |
| Module Registry | ✅ | ✅ | ✅ | ✅ | Move to core |
| Memory Management | Basic | ✅ Full | ✅ Full | Partial | Unify to core |

---

## Summary Statistics

| Category | Count | Estimated Effort |
|----------|-------|-----------------|
| Move Now (YES) | 6 components | 8-10 weeks |
| Hybrid (Core + Adapter) | 6 components | 10-12 weeks |
| Do Not Move (NO) | 12+ components | N/A |

**Total Core Migration**: ~20-24 weeks for full migration
**Recommended Phase 1**: 4-6 weeks (VAD, Routing, Lifecycle, Events, Registry)

---

*Document generated: December 2025*
