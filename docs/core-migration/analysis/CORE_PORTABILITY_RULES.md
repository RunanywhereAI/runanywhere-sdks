# Core Portability Rules

## Decision Framework

This document defines the explicit rules for determining whether a component should move to the shared C++ core or remain in platform wrappers.

---

## The Four Tests

Every candidate module/component must pass through these four tests:

### Test 1: Portability Test

**Question**: Is this logic deterministic, OS-agnostic, and identical across platforms?

| Pass Criteria | Examples from Repo |
|--------------|-------------------|
| ✅ Pure algorithms | `RoutingDecisionEngine` scoring (KMP `routing/RoutingDecisionEngine.kt`) |
| ✅ State machines | `ComponentState` enum transitions (iOS `Core/Capabilities/CapabilityProtocols.swift`) |
| ✅ Data transforms | Audio resampling math (iOS `ONNXRuntime/ONNXSTTService.swift` lines 252-305) |
| ✅ Business rules | PII detection, privacy thresholds (KMP `routing/RoutingDecisionEngine.kt` lines 36-42) |
| ❌ Platform APIs | AVAudioSession, AudioRecord, Keychain |
| ❌ UI frameworks | Combine, Flow, Streams |
| ❌ Permissions | Microphone access, storage permissions |

**Rule**: If the component depends on platform-specific APIs (AVFoundation, AudioManager, KeychainServices, etc.), it **must stay in wrappers**.

### Test 2: Churn vs. Stability Test

**Question**: Is this logic stable and foundational, or actively changing?

| Pass Criteria | Examples from Repo |
|--------------|-------------------|
| ✅ Stable interfaces | `STTService` protocol (iOS `Features/STT/Protocol/STTService.swift`) |
| ✅ Foundational logic | `ServiceContainer` (iOS `Foundation/DependencyInjection/ServiceContainer.swift`) |
| ✅ Mature algorithms | VAD energy-based detection (iOS `Features/VAD/Services/SimpleEnergyVADService.swift`) |
| ❌ Experimental features | New model types still in flux |
| ❌ Rapidly evolving APIs | Beta cloud APIs |
| ❌ A/B test variants | Feature flags, experiments |

**Rule**: If the component is **actively churning** with frequent changes, keep it in wrappers until stable. Moving unstable code to core increases ABI breakage risk.

### Test 3: Boundary Cost (FFI Tax) Test

**Question**: How frequently does this component cross the FFI boundary?

| Pass Criteria | Examples from Repo |
|--------------|-------------------|
| ✅ Batch operations | `transcribe(audioData)` - single call with result |
| ✅ Event-based | Model lifecycle events - infrequent, async |
| ✅ Configuration | SDK initialization - once per session |
| ❌ Per-token callbacks | Streaming generation tokens (current approach) |
| ❌ Per-frame audio | Real-time audio chunks at 60fps |
| ❌ Fine-grained state | Every keystroke, every UI update |

**Streaming Solution**: For per-token/per-frame scenarios, use:
- **Ring buffers**: Core writes, wrapper reads on demand
- **Batch callbacks**: Accumulate tokens, deliver in batches (10-100ms)
- **Pull model**: Wrapper polls for ready data

**Rule**: If crossing FFI boundary per-token or per-frame, **redesign the boundary** or keep in wrappers.

### Test 4: Performance/Consistency ROI Test

**Question**: Is this component performance-critical, correctness-critical, or duplicated across 3+ SDKs?

| Pass Criteria | Examples from Repo |
|--------------|-------------------|
| ✅ Performance-critical | Inference (already in C++) |
| ✅ Correctness-critical | Routing decisions (cost, privacy, latency) |
| ✅ Duplicated 4x | `ModuleRegistry` (iOS, KMP, Flutter, RN all have it) |
| ✅ Bug-prone divergence | State machine edge cases |
| ❌ Simple getters | `getVersion()`, `isInitialized()` |
| ❌ Platform-optimized | Platform-native TTS (uses OS APIs) |

**Rule**: If the component is **duplicated in 3+ SDKs** with identical logic, or if **divergence causes bugs**, it's a strong core candidate.

---

## The North Star Principle

> **Core = Decisions + Transforms**
> **Wrappers = Side Effects**

### Decisions (Core)

Logic that **decides** what to do based on inputs:

| Decision Type | Example | Location |
|--------------|---------|----------|
| Routing | On-device vs. cloud | `RoutingDecisionEngine` |
| Provider selection | Which STT service for model | `ModuleRegistry` |
| Memory eviction | Which models to unload | `MemoryPressureHandler` |
| State transitions | Component lifecycle | `ManagedLifecycle` |
| Cost estimation | Token pricing | `CostCalculator` |
| Privacy classification | PII detection | `RoutingService` |

### Transforms (Core)

Logic that **transforms** data deterministically:

| Transform Type | Example | Location |
|---------------|---------|----------|
| Audio resampling | 48kHz → 16kHz | `ONNXSTTService` |
| Token counting | Text → token estimate | `estimateTokenCount()` |
| JSON parsing | Structured output | `StructuredOutputParser` |
| Event batching | Raw events → telemetry payload | `AnalyticsQueueManager` |
| Checksum verification | SHA256 validation | `ModelIntegrityVerifier` |

### Side Effects (Wrappers)

Logic that **interacts with the outside world**:

| Side Effect | Example | Platform |
|-------------|---------|----------|
| Audio capture | Microphone recording | AVAudioEngine, AudioRecord |
| Audio playback | Speaker output | AVAudioEngine, AudioTrack |
| Network I/O | HTTP requests | Alamofire, Ktor, http package |
| File I/O | Read/write files | FileManager, java.io.File |
| Secure storage | Keychain/Keystore | KeychainManager, EncryptedSharedPreferences |
| Permissions | Request mic access | AVAudioApplication, PermissionHandler |
| UI updates | Progress display | SwiftUI, Compose, Flutter, React Native |

---

## Repo-Specific Mapping

### iOS SDK (Source of Truth)

| Component | Location | Move to Core? | Reason |
|-----------|----------|---------------|--------|
| `RunAnywhere.swift` | `Public/` | HYBRID | Entry point stays, init logic moves |
| `STTCapability` | `Features/STT/` | YES | Lifecycle management |
| `TTSCapability` | `Features/TTS/` | YES | Lifecycle management |
| `LLMCapability` | `Features/LLM/` | YES | Lifecycle management + streaming metrics |
| `VADCapability` | `Features/VAD/` | YES | State machine |
| `VoiceAgentCapability` | `Features/VoiceAgent/` | YES | Pipeline orchestration |
| `SimpleEnergyVADService` | `Features/VAD/Services/` | YES | Pure math (replace Accelerate) |
| `ModuleRegistry` | `Core/Module/` | YES | Plugin architecture |
| `ServiceRegistry` | `Core/` | YES | Factory pattern |
| `ManagedLifecycle` | `Core/Capabilities/` | YES | Generic lifecycle manager |
| `EventPublisher` | `Infrastructure/Events/` | YES | Event routing |
| `EventBus` | `Public/Events/` | HYBRID | Core publishes, wrapper subscribes |
| `ModelInfoService` | `Infrastructure/ModelManagement/` | YES | In-memory storage |
| `DownloadService` | `Infrastructure/Download/` | HYBRID | Logic core, I/O wrapper |
| `AudioCaptureManager` | `Features/STT/Services/` | NO | AVFoundation-specific |
| `AudioPlaybackManager` | `Features/TTS/Services/` | NO | AVFoundation-specific |
| `SystemTTSService` | `Features/TTS/System/` | NO | AVSpeechSynthesizer |
| `KeychainManager` | `Foundation/Security/` | NO | Keychain-specific |
| `DeviceIdentity` | `Infrastructure/Device/` | NO | UUID + Keychain |
| `SDKLogger` | `Infrastructure/Logging/` | HYBRID | Interface core, os.Logger wrapper |

### Kotlin KMP SDK

| Component | Location | Move to Core? | iOS Equivalent |
|-----------|----------|---------------|----------------|
| `RunAnywhere.kt` | `public/` | HYBRID | `RunAnywhere.swift` |
| `ServiceContainer.kt` | `foundation/` | YES | `ServiceContainer.swift` |
| `ModuleRegistry.kt` | `core/` | YES | `ModuleRegistry.swift` |
| `EventBus.kt` | `events/` | HYBRID | `EventBus.swift` |
| `RoutingDecisionEngine.kt` | `routing/` | YES | Not in iOS (KMP has it) |
| `STTComponent.kt` | `components/stt/` | YES | `STTCapability.swift` |
| `SimpleEnergyVAD.kt` | `voice/vad/` | YES | `SimpleEnergyVADService.swift` |
| `ModelManager.kt` | `models/` | YES | `ModelInfoService.swift` |
| `KtorDownloadService.kt` | `services/download/` | HYBRID | `AlamofireDownloadService.swift` |
| Android audio classes | `androidMain/audio/` | NO | Platform-specific |
| `AndroidSecureStorage.kt` | `androidMain/security/` | NO | Platform-specific |

### Flutter SDK

| Component | Location | Move to Core? | iOS Equivalent |
|-----------|----------|---------------|----------------|
| `RunAnywhere` class | `lib/public/` | HYBRID | `RunAnywhere.swift` |
| `ModuleRegistry` | `lib/core/` | YES | `ModuleRegistry.swift` |
| `STTComponent` | `lib/components/stt/` | YES | `STTCapability.swift` |
| `LLMComponent` | `lib/components/llm/` | YES | `LLMCapability.swift` |
| `NativeBackend` | `lib/backends/native/` | FFI BRIDGE | C API bridge |
| `OnnxSTTService` | `lib/backends/onnx/` | FFI BRIDGE | `ONNXSTTService.swift` |
| `MemoryService` | `lib/capabilities/memory/` | YES | Memory management |
| Platform plugins | `ios/`, `android/` | NO | Platform glue |

### React Native SDK

| Component | Location | Move to Core? | iOS Equivalent |
|-----------|----------|---------------|----------------|
| `RunAnywhere` object | `src/Public/` | HYBRID | `RunAnywhere.swift` |
| `ModuleRegistry.ts` | `src/Core/` | YES | `ModuleRegistry.swift` |
| `LLMComponent.ts` | `src/components/LLM/` | YES | `LLMCapability.swift` |
| `STTComponent.ts` | `src/components/STT/` | YES | `STTCapability.swift` |
| `HybridRunAnywhere.cpp` | `cpp/` | CORE BRIDGE | C++ JSI bridge |
| `HybridRunAnywhereFileSystem` | `ios/`, `android/` | NO | Platform file I/O |
| `EventBus.ts` | `src/Public/Events/` | HYBRID | `EventBus.swift` |
| `ServiceContainer.ts` | `src/Foundation/` | YES | `ServiceContainer.swift` |

---

## Examples: Applying the Tests

### Example 1: RoutingDecisionEngine

**Portability Test**: ✅ Pure scoring algorithm, no platform APIs
**Churn Test**: ✅ Stable algorithm, infrequent changes
**Boundary Test**: ✅ Called once per request, returns decision
**ROI Test**: ✅ Duplicated in KMP, should be in all SDKs

**Verdict**: **MOVE TO CORE** - High ROI, low risk

### Example 2: AudioCaptureManager

**Portability Test**: ❌ Uses AVAudioEngine, AVAudioSession (iOS-only)
**Churn Test**: ✅ Stable
**Boundary Test**: ❌ Per-frame audio callbacks
**ROI Test**: ❌ Must use platform APIs for real-time audio

**Verdict**: **KEEP IN WRAPPER** - Platform-specific side effect

### Example 3: SimpleEnergyVAD

**Portability Test**: ⚠️ Uses vDSP_rmsqv (Accelerate), but algorithm is portable
**Churn Test**: ✅ Stable algorithm
**Boundary Test**: ✅ Batch audio processing
**ROI Test**: ✅ Duplicated in iOS and KMP

**Verdict**: **MOVE TO CORE** - Replace vDSP with standard C++ math

### Example 4: Streaming Token Generation

**Portability Test**: ✅ Pure token delivery
**Churn Test**: ✅ Stable API
**Boundary Test**: ❌ Per-token callback is chatty
**ROI Test**: ✅ All SDKs need streaming

**Verdict**: **REDESIGN BOUNDARY** - Use token batching or pull model
- Core accumulates tokens in buffer
- Wrapper polls every 50-100ms
- Single callback with batch of tokens

### Example 5: EventBus

**Portability Test**: ⚠️ Event types are portable, pub/sub needs platform support
**Churn Test**: ✅ Stable
**Boundary Test**: ✅ Events are infrequent
**ROI Test**: ✅ All SDKs have EventBus

**Verdict**: **HYBRID**
- Core: Event types, routing logic, analytics integration
- Wrapper: Combine/Flow/Stream subscription mechanism

---

## Decision Flowchart

```
                    ┌─────────────────────────┐
                    │   Candidate Component   │
                    └───────────┬─────────────┘
                                │
                    ┌───────────▼─────────────┐
                    │  Uses platform APIs?    │
                    │  (AVFoundation, etc.)   │
                    └───────────┬─────────────┘
                                │
              ┌────────────────YES──────────────────┐
              │                                     │
    ┌─────────▼─────────┐                          │
    │  KEEP IN WRAPPER  │                          │
    │  (Side Effect)    │                          │
    └───────────────────┘                          │
                                                   │
              ┌────────────────NO───────────────────┘
              │
    ┌─────────▼─────────────────┐
    │  Actively churning?       │
    │  (Experimental, unstable) │
    └───────────┬───────────────┘
                │
      ┌────────YES──────────┐
      │                     │
    ┌─▼─────────────────┐   │
    │ KEEP IN WRAPPER   │   │
    │ (Wait for stable) │   │
    └───────────────────┘   │
                            │
      ┌────────NO───────────┘
      │
    ┌─▼─────────────────────────┐
    │  Chatty FFI boundary?     │
    │  (Per-token, per-frame)   │
    └───────────┬───────────────┘
                │
      ┌────────YES──────────┐
      │                     │
    ┌─▼──────────────────┐  │
    │ REDESIGN BOUNDARY  │  │
    │ (Batch, pull model)│  │
    └─┬──────────────────┘  │
      │                     │
      └─────────────────────┼───────┐
                            │       │
      ┌────────NO───────────┘       │
      │                             │
    ┌─▼────────────────────────┐    │
    │  Duplicated 3+ SDKs?     │    │
    │  Performance/correctness │    │
    │  critical?               │    │
    └───────────┬──────────────┘    │
                │                   │
      ┌────────YES──────────┐       │
      │                     │       │
    ┌─▼─────────────────────▼───┐   │
    │      MOVE TO CORE         │   │
    │   (Decision or Transform) │   │
    └───────────────────────────┘   │
                                    │
      ┌────────NO───────────────────┘
      │
    ┌─▼─────────────────┐
    │ KEEP IN WRAPPER   │
    │ (Low ROI)         │
    └───────────────────┘
```

---

## Adapter Interface Pattern

For hybrid components, define interfaces in core with wrapper implementations:

```cpp
// Core: Defines interface
class IHttpClient {
public:
    virtual ~IHttpClient() = default;
    virtual HttpResponse request(const HttpRequest& req) = 0;
    virtual void requestAsync(const HttpRequest& req, HttpCallback callback) = 0;
};

// Core: Uses interface
class DownloadOrchestrator {
    IHttpClient* httpClient_;
public:
    void downloadModel(const ModelInfo& model, DownloadCallback callback) {
        // Core logic: retries, progress calculation, verification
        httpClient_->requestAsync(buildRequest(model), [this, callback](HttpResponse resp) {
            // Handle response, calculate checksum, etc.
        });
    }
};
```

```swift
// Wrapper (iOS): Implements interface
class AlamofireHttpClient: HttpClientAdapter {
    func request(_ req: HttpRequest) -> HttpResponse {
        // Use Alamofire for actual I/O
    }
}
```

---

*Document generated: December 2025*
*Auditor: CoreFeasibilityAuditor*
