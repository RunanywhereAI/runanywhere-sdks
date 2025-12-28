# Swift vs C++ Boundaries - Final Architecture

> **Document Purpose:** This document defines the clear boundaries between what lives in the C++ `runanywhere-commons` layer vs. what stays in Swift `runanywhere-swift`.

## Architecture Overview

```
┌────────────────────────────────────────────────────────────────────────┐
│                           Swift SDK Layer                               │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │                    RunAnywhere (Core SDK)                        │  │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │  │
│  │  │ ServiceRegistry │  │ ManagedLifecycle│  │ EventPublisher  │  │  │
│  │  │ (Swift-only)    │  │ (Swift wrapper) │  │ (Swift event    │  │  │
│  │  │                 │  │                 │  │  routing)       │  │  │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘  │  │
│  │  ┌─────────────────────────────────────────────────────────────┐│  │
│  │  │                   Analytics Services                        ││  │
│  │  │  GenerationAnalyticsService, STTAnalyticsService, etc.     ││  │
│  │  │  (Swift event creation + routing)                          ││  │
│  │  └─────────────────────────────────────────────────────────────┘│  │
│  └─────────────────────────────────────────────────────────────────┘  │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────────────┐  │
│  │ LlamaCPPRuntime│  │  ONNXRuntime   │  │ FoundationModelsAdapter│  │
│  │ (Swift wrapper)│  │ (Swift wrapper)│  │     (Swift native)     │  │
│  └───────┬────────┘  └───────┬────────┘  └────────────────────────┘  │
│          │                   │                                        │
└──────────┼───────────────────┼────────────────────────────────────────┘
           │                   │
           │ FFI (C Bridge)    │
           ▼                   ▼
┌────────────────────────────────────────────────────────────────────────┐
│                          C++ Commons Layer                              │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │                      RACommons.xcframework                       │  │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │  │
│  │  │  Core Types     │  │   Lifecycle     │  │    Logging      │  │  │
│  │  │  rac_types.h    │  │  rac_lifecycle.h│  │  rac_logging.h  │  │  │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘  │  │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │  │
│  │  │  Error Codes    │  │  Model Types    │  │  Events API     │  │  │
│  │  │  rac_error.h    │  │ rac_model_types │  │  rac_events.h   │  │  │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘  │  │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │  │
│  │  │   LLM Types     │  │   STT Types     │  │   TTS Types     │  │  │
│  │  │ rac_llm_types.h │  │ rac_stt_types.h │  │ rac_tts_types.h │  │  │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘  │  │
│  │  ┌─────────────────┐  ┌─────────────────┐                       │  │
│  │  │   VAD Types     │  │  Energy VAD     │                       │  │
│  │  │ rac_vad_types.h │  │ rac_vad_energy.h│                       │  │
│  │  └─────────────────┘  └─────────────────┘                       │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │              RABackendLlamaCPP.xcframework                       │  │
│  │  Full LLM implementation with llama.cpp                          │  │
│  │  rac_llm_llamacpp.h + libllama + libggml                        │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │                RABackendONNX.xcframework                         │  │
│  │  STT/TTS/VAD implementations with ONNX/Sherpa                   │  │
│  │  rac_stt_onnx.h + rac_tts_onnx.h + rac_vad_onnx.h               │  │
│  └─────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────┘
```

## What Lives in C++ (`runanywhere-commons`)

### ✅ Core Types & Definitions
- All fundamental types (`rac_types.h`)
- Error codes and error handling (`rac_error.h`)
- Result types, string views, audio buffers
- Boolean type, handles, callbacks

### ✅ Capability Types
- LLM types: `rac_llm_options_t`, `rac_llm_result_t`, `rac_llm_config_t`
- STT types: `rac_stt_options_t`, `rac_stt_result_t`, `rac_stt_config_t`
- TTS types: `rac_tts_options_t`, `rac_tts_result_t`, `rac_tts_config_t`
- VAD types: `rac_vad_config_t`, `rac_vad_result_t`

### ✅ Backend Implementations
- **LlamaCPP Backend**: Full LLM inference (`rac_llm_llamacpp.h`)
  - Model loading/unloading
  - Text generation (batch and streaming)
  - Token counting, context management
- **ONNX Backend**: STT/TTS/VAD implementations
  - Speech-to-text (`rac_stt_onnx.h`)
  - Text-to-speech (`rac_tts_onnx.h`)
  - Voice activity detection (`rac_vad_onnx.h`)

### ✅ Lifecycle State Machine
- `rac_lifecycle.h`: State tracking, metrics collection
- States: idle, loading, loaded, failed
- Used by backends for their internal lifecycle

### ✅ Model Management Types
- `rac_model_types.h`: ModelCategory, ModelFormat, InferenceFramework
- `rac_model_registry.h`: Model metadata storage
- `rac_model_paths.h`: Path utilities

### ✅ Energy-based VAD
- `rac_vad_energy.h`: Full implementation
- RMS calculation, threshold calibration
- Hysteresis logic for speech detection

### ✅ Logging Infrastructure
- `rac_logging.h`: Unified logging API
- Log levels, callbacks, formatting

---

## What Stays in Swift (`runanywhere-swift`)

### ❌ Cannot Migrate: ServiceRegistry
**Reason:** Uses Swift-specific constructs that have no C equivalent.

```swift
// Swift closures cannot be represented in C
public typealias LLMServiceFactory = @Sendable (LLMConfiguration) async throws -> LLMService
public typealias CanHandlePredicate = @Sendable (String?) -> Bool
```

The ServiceRegistry:
- Stores providers with async factory closures
- Creates Swift protocol-conforming service instances
- Uses Swift's actor isolation (`@MainActor`)

**Current state:** Already thin - just registration and lookup.

### ❌ Cannot Migrate: EventPublisher & Event Types
**Reason:** Creates Swift-specific event types that conform to Swift protocols.

```swift
// Swift events with Codable/Sendable conformance
public enum LLMEvent: SDKEvent {
    case generationStarted(generationId: String, ...)
    case generationCompleted(generationId: String, ...)
}
```

Events:
- Conform to `SDKEvent` Swift protocol
- Use Swift enums with associated values
- Route to Swift's `EventBus` for consumers

**Current state:** Swift must handle event creation and routing.

### ❌ Cannot Migrate: Analytics Services
**Reason:** They only create Swift events and route to EventPublisher.

```swift
// Analytics just creates events
EventPublisher.shared.track(LLMEvent.generationStarted(...))
```

All analytics services:
- Use Swift actors for state isolation
- Create Swift event types
- Calculate Swift-level metrics

**Current state:** Already minimal wrappers.

### ❌ Cannot Migrate: ManagedLifecycle Actor
**Reason:** Uses Swift actor concurrency model.

```swift
public actor ManagedLifecycle<ServiceType> {
    // Swift actor isolation
    // Swift generics
}
```

However:
- Uses C++ lifecycle API internally (for backends)
- Creates Swift events for EventPublisher

**Current state:** Appropriately structured as Swift wrapper over C++ lifecycle.

### ❌ Cannot Migrate: Platform Adapters
**Reason:** Platform-specific implementations.

- **Networking:** Uses `URLSession`/`Alamofire` for HTTP
- **Audio:** Uses `AVAudioSession`, `AudioUnit`
- **Keychain:** Uses `Security.framework`
- **Archive Extraction:** Uses platform compression APIs

---

## Boundary Summary Table

| Component | Location | Reason |
|-----------|----------|--------|
| Core types (`rac_types.h`) | C++ | Shared across all SDKs |
| Error codes (`rac_error.h`) | C++ | Shared error definitions |
| LLM/STT/TTS/VAD types | C++ | Shared capability types |
| Backend implementations | C++ | Shared inference logic |
| Lifecycle state machine | C++ | Used by backends |
| Energy VAD | C++ | Full business logic |
| Model types/registry | C++ | Shared model management |
| ServiceRegistry | Swift | Uses Swift closures/protocols |
| EventPublisher | Swift | Creates Swift event types |
| Analytics services | Swift | Event creation/routing |
| ManagedLifecycle | Swift | Swift actor concurrency |
| Platform adapters | Swift | Platform-specific APIs |

---

## Design Principles

1. **C++ contains all reusable business logic** - Inference, state machines, algorithms
2. **Swift contains orchestration and events** - Service discovery, event routing
3. **Swift wrappers are thin** - Just FFI calls + type conversion + event creation
4. **No duplicate logic** - If it's in C++, Swift just calls it
5. **Swift cannot have business logic** - Otherwise it would need replication in Kotlin/React Native/Flutter

---

## Verification Checklist

- [x] All inference logic is in C++
- [x] All types are defined in C++ headers
- [x] Swift wrappers only do FFI + events
- [x] No state machines in Swift (except Swift-specific like actors)
- [x] Event creation stays in Swift (Swift types)
- [x] Platform adapters stay in Swift (platform APIs)

---

*Last Updated: December 2024*
*Status: Migration Complete - Architecture Verified*
