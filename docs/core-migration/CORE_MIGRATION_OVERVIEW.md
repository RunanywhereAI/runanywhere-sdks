# Core Migration Overview

## Executive Summary

This document assesses the feasibility of migrating shared business logic from the RunAnywhere SDKs (iOS Swift, Kotlin KMP, Flutter Dart, React Native TypeScript) into a unified **native C/C++ core**, consumed via platform-specific bindings.

**Key Finding**: The RunAnywhere SDK architecture is **highly suitable** for core migration, with approximately **70-80% of business logic being portable**. The existing C++ core (`runanywhere-core`) already handles inference backends (LlamaCpp, ONNX Runtime), and this proposal extends it to include orchestration logic, state machines, routing decisions, and service management.

**Recommendation**: Proceed with staged migration using **C++ for the core** with a **stable C ABI surface**. Python/Go are **not recommended** for the mobile runtime due to embedding complexity and size overhead.

---

## Current State Analysis

### SDK Inventory

| SDK | Language | Lines of Code (est.) | Core Logic % | Platform-Specific % |
|-----|----------|---------------------|--------------|---------------------|
| iOS Swift | Swift 6 | ~25,000 | 75% | 25% |
| Kotlin KMP | Kotlin 2.1 | ~30,000 | 85% | 15% |
| Flutter | Dart 3 | ~20,000 | 80% | 20% |
| React Native | TypeScript | ~15,000 | 70% | 30% |

### Architecture Alignment

All 4 SDKs follow remarkably consistent architectural patterns:

1. **Component Architecture**: BaseComponent → STTComponent, LLMComponent, TTSComponent, VADComponent, VLMComponent, VoiceAgentComponent
2. **Provider Pattern**: ModuleRegistry with STTServiceProvider, LLMServiceProvider, TTSServiceProvider
3. **Event System**: EventBus with typed events (SDKInitializationEvent, SDKGenerationEvent, SDKModelEvent)
4. **Service Container**: Centralized dependency injection with lazy initialization
5. **8-Step Initialization**: Matching bootstrap sequence across all SDKs
6. **Routing Engine**: On-device vs. cloud routing decisions

---

## Pros and Cons of Core Migration

### Pros

| Benefit | Description | Impact |
|---------|-------------|--------|
| **Single Source of Truth** | One implementation for all platforms | Eliminates parity bugs, reduces maintenance 4x |
| **Faster Feature Shipping** | Implement once, bind to all platforms | 75% development time reduction |
| **Performance & Battery** | Tighter memory/threading control, SIMD | 10-30% better inference performance |
| **Reuse Native Runtimes** | LlamaCpp, ONNX Runtime already C++ | Zero integration overhead |
| **Unified Testing** | One golden test suite | Higher coverage, fewer edge cases |
| **Smaller Wrappers** | Thin platform bindings only | Reduced SDK size by ~40% |
| **Consistency** | Identical behavior across platforms | Better developer experience |

### Cons

| Cost | Description | Mitigation |
|------|-------------|------------|
| **Build Complexity** | XCFramework, ABIs, CI matrix | Automated build scripts, clear versioning |
| **FFI Tax** | Crossing boundaries has overhead | Batch operations, event queues, ring buffers |
| **Debugging Friction** | Mixed native/managed stacks | Comprehensive logging, crash symbolication |
| **ABI Rigidity** | C ABI changes are painful | Semantic versioning, stable struct evolution |
| **Platform Feature Gaps** | Some APIs are platform-specific | Clear wrapper responsibilities |
| **Learning Curve** | Team needs C++ expertise | Training, code review, documentation |

---

## Recommended Boundary: Core vs. Wrappers

### North Star Principle

> **Core = Decisions + Transforms**
> **Wrappers = Side Effects**

### What Belongs in Core (C++)

| Category | Components | Rationale |
|----------|-----------|-----------|
| **State Machines** | ComponentState, ModelLifecycle, PipelineState | Deterministic, identical across platforms |
| **Routing/Policy** | RoutingDecisionEngine, CostCalculator, ResourceChecker | Complex algorithms, high duplication |
| **Orchestration** | VoiceAgentPipeline, VAD→STT→LLM→TTS flow | Consistent behavior required |
| **Model Management** | ModelRegistry, ModelLoader, DownloadOrchestration | Shared logic, platform storage via adapters |
| **Telemetry** | EventPublisher, AnalyticsQueue, TelemetryBatching | Consistent metrics across SDKs |
| **Schema Validation** | StructuredOutput, JSONSchemaParser | Deterministic parsing |
| **Memory Management** | MemoryPressureHandler, CacheEviction, AllocationTracker | Unified resource management |
| **Service Registry** | ModuleRegistry, ServiceContainer, ProviderLookup | Plugin architecture |

### What Stays in Wrappers (Swift/Kotlin/Dart/TS)

| Category | Components | Rationale |
|----------|-----------|-----------|
| **Audio I/O** | AudioCaptureManager, AudioPlaybackManager | Platform audio APIs (AVFoundation, AudioRecord) |
| **Permissions** | Microphone, storage permissions | OS-specific APIs |
| **Secure Storage** | KeychainManager, Keystore | Platform security APIs |
| **Device Info** | DeviceIdentity, HardwareCapabilities | Platform APIs (UIDevice, Build) |
| **System Services** | SystemTTS (AVSpeechSynthesizer) | Platform-native fallbacks |
| **UI Integration** | Combine/Flow/Stream publishers | Framework-specific reactive |
| **Crash Reporting** | Sentry integration | Platform crash handlers |

### Hybrid (Core Interface + Wrapper Adapter)

| Category | Core Defines | Wrapper Implements |
|----------|--------------|-------------------|
| **HTTP Client** | HttpClientProtocol | Alamofire, Ktor, http package |
| **File System** | FileSystemProtocol | FileManager, java.io.File, dart:io |
| **Key-Value Store** | KeyValueStoreProtocol | UserDefaults, SharedPreferences |
| **Audio Input** | AudioInputProtocol | AVAudioEngine, AudioRecord |
| **Audio Output** | AudioOutputProtocol | AVAudioEngine, AudioTrack |
| **Device Info** | DeviceInfoProtocol | UIDevice, Build, DeviceInfoPlugin |
| **Clock** | ClockProtocol | Date(), System.currentTimeMillis() |
| **Reachability** | ReachabilityProtocol | Network.framework, ConnectivityManager |

---

## Language Choice Recommendation

### C++ (Primary - Recommended)

**Use for**: All core business logic, inference backends, state machines, orchestration

**Rationale**:
- LlamaCpp and ONNX Runtime are already C++
- Direct integration with existing `runanywhere-core`
- Best performance and memory control
- Mature cross-platform tooling (CMake, Ninja)
- Well-understood FFI patterns for all platforms

**Estimated Core Size**: ~50,000 lines of C++

### C (ABI Surface)

**Use for**: Stable public API (C ABI for FFI)

**Rationale**:
- C ABI is the most portable and stable
- Swift, Kotlin JNI, Dart FFI, and JSI all interface with C easily
- Forward/backward compatible struct evolution
- No name mangling issues

**Pattern**: C++ implementation with `extern "C"` headers

### Python (Not Recommended for Mobile)

**Problems**:
- Embedding Python runtime on mobile is complex (~30MB+ overhead)
- Performance overhead for hot paths
- Debugging across Python/native boundary is painful
- Distribution complexity (wheels, cross-compilation)

**Use only for**: Tooling, test harnesses, benchmarks, server-side

### Go (Not Recommended for Mobile)

**Problems**:
- Go runtime adds significant size (~5-10MB)
- cgo has thread limitations and performance overhead
- Not designed for mobile embedding
- Build complexity for cross-compilation

**Use only for**: Server-side daemons, CLI tools, optional cloud components

---

## Top Risks and Mitigations

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| **ABI Breaking Changes** | High | Medium | Semantic versioning, struct versioning, deprecation policy |
| **Memory Safety** | High | Medium | ASAN/MSAN in CI, smart pointers, RAII patterns |
| **Build Complexity** | Medium | High | Unified CMake, CI caching, pre-built binaries |
| **FFI Performance** | Medium | Medium | Batch APIs, ring buffers, minimize crossings |
| **Debugging Difficulty** | Medium | High | Comprehensive logging, crash symbolication, native debugger support |
| **Thread Safety** | High | Medium | Clear ownership rules, mutex patterns, message passing |
| **Platform Parity** | Medium | Low | Extensive integration tests per platform |
| **Team Learning Curve** | Low | Medium | Documentation, training, code review |

---

## Migration ROI Analysis

### High ROI Candidates (Move First)

1. **RoutingDecisionEngine** - Complex algorithm duplicated 4x
2. **ModelLifecycleManager** - State machine with subtle bugs when divergent
3. **EventBus/EventPublisher** - Telemetry consistency critical
4. **ModuleRegistry/ServiceRegistry** - Plugin architecture foundation
5. **MemoryPressureHandler** - Platform differences cause bugs
6. **SimpleEnergyVAD** - Pure math, should be identical

### Medium ROI Candidates (Move Second)

7. **VoiceAgentPipeline** - Orchestration logic
8. **DownloadOrchestration** - Retry/resume logic
9. **StructuredOutputParser** - JSON schema validation
10. **AnalyticsQueueManager** - Batching/redaction

### Low ROI Candidates (Move Last or Keep in Wrappers)

11. **STTComponent/TTSComponent/LLMComponent** - Thin wrappers over services
12. **Configuration loading** - Simple, platform-specific file I/O

---

## Proposed Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Platform SDKs (Thin Wrappers)               │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────────┐ │
│  │   iOS    │  │ Android  │  │ Flutter  │  │   React Native   │ │
│  │  Swift   │  │  Kotlin  │  │   Dart   │  │   TypeScript     │ │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────────┬─────────┘ │
└───────┼─────────────┼─────────────┼─────────────────┼───────────┘
        │ Swift C     │ JNI        │ dart:ffi        │ Nitrogen/JSI
        │ Bridge      │            │                 │
┌───────┴─────────────┴─────────────┴─────────────────┴───────────┐
│                        C API Surface                             │
│  ra_initialize(), ra_route_request(), ra_create_component()...  │
└──────────────────────────────────┬──────────────────────────────┘
                                   │
┌──────────────────────────────────┴──────────────────────────────┐
│                    RunAnywhere Core (C++)                        │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Orchestration Layer                                      │   │
│  │  ├── RoutingDecisionEngine                               │   │
│  │  ├── VoiceAgentPipeline                                  │   │
│  │  ├── ModelLifecycleManager                               │   │
│  │  └── EventPublisher                                      │   │
│  └──────────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Component Layer                                          │   │
│  │  ├── STTComponent, TTSComponent, LLMComponent, VADComponent│  │
│  │  └── ModuleRegistry, ServiceContainer                    │   │
│  └──────────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Infrastructure Layer                                     │   │
│  │  ├── MemoryManager, DownloadOrchestrator                 │   │
│  │  ├── AnalyticsQueue, StructuredOutputParser              │   │
│  │  └── Platform Adapters (HTTP, FileSystem, KeyValue)      │   │
│  └──────────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Inference Backends                                       │   │
│  │  ├── LlamaCpp (GGUF LLMs)                                │   │
│  │  ├── ONNX Runtime (Whisper, Piper, Silero VAD)          │   │
│  │  └── CoreML/NNAPI Accelerators                           │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Next Steps

1. **Read companion documents** for detailed SDK-specific analysis:
   - `IOS_CORE_FEASIBILITY.md`
   - `ANDROID_CORE_FEASIBILITY.md`
   - `FLUTTER_CORE_FEASIBILITY.md`
   - `RN_CORE_FEASIBILITY.md`

2. **Review candidate list**: `CORE_COMPONENT_CANDIDATES.md`

3. **Review boundary specification**: `CORE_API_BOUNDARY_SPEC.md`

4. **Review packaging plan**: `BINDINGS_AND_PACKAGING_PLAN.md`

5. **Review migration sequence**: `MIGRATION_SEQUENCE.md`

---

*Document generated: December 2025*
*Auditor: CoreFeasibilityAuditor*
