# RunAnywhere Swift SDK - Architecture

## Table of Contents

- [Overview](#overview)
- [Modular Architecture](#modular-architecture)
- [Project Structure](#project-structure)
- [Core Components](#core-components)
- [Data and Control Flow](#data-and-control-flow)
- [Concurrency Model](#concurrency-model)
- [Dependencies and Boundaries](#dependencies-and-boundaries)
- [Extensibility](#extensibility)
- [Testing](#testing)
- [Design Decisions](#design-decisions)
- [Type Reference](#type-reference)

---

## Overview

The RunAnywhere Swift SDK is a production-grade, on-device AI SDK designed to provide modular, low-latency AI capabilities for Apple platforms (iOS, macOS, tvOS, watchOS). The SDK follows a capability-based architecture with a modular backend design using `runanywhere-commons` (C++) for shared functionality.

### Design Principles

- **Modular Backends** - Separate XCFrameworks for each backend (LlamaCPP, ONNX) means you only include what you need
- **C++ Commons Layer** - Shared C++ library (`runanywhere-commons`) handles backend registration, events, and common APIs
- **Swift Orchestration** - Swift SDK remains the orchestrator for service creation and capability routing
- **Low Latency** - All inference runs on-device with Metal acceleration support
- **Lazy Initialization** - Network services and device registration happen lazily on first API call
- **Event-Driven Design** - Dual event system where C++ publishes events and Swift bridges them to app consumers

---

## Modular Architecture

### Layer Overview

```
+------------------------------------------------------------------+
|                       Your Application                            |
+------------------------------------------------------------------+
|                     RunAnywhere Swift SDK                         |
|  +---------------+  +----------------+  +---------------------+   |
|  |ServiceRegistry|  |ModuleDiscovery |  |   EventPublisher    |   |
|  +---------------+  +----------------+  +---------------------+   |
+------------------------------------------------------------------+
|                C Bridge Modules (CRACommons, etc.)                |
+------------------------------------------------------------------+
|                   runanywhere-commons (C++)                       |
|  +---------------+  +----------------+  +---------------------+   |
|  |ModuleRegistry |  |ServiceRegistry |  |   EventPublisher    |   |
|  +---------------+  +----------------+  +---------------------+   |
+------------------------------------------------------------------+
|   LlamaCPP   |      ONNX      |   WhisperCPP  | Other Backends   |
|   Backend    |     Backend    |    Backend    |                  |
+------------------------------------------------------------------+
```

### XCFramework Composition

| Framework                        | Size Target | Provides                                |
|----------------------------------|-------------|-----------------------------------------|
| `RACommons.xcframework`          | ~2MB        | Core C++ commons, registries, events    |
| `RABackendLlamaCPP.xcframework`  | ~15-25MB    | LLM capability (GGUF models)            |
| `RABackendONNX.xcframework`      | ~50-70MB    | STT, TTS, VAD (ONNX models)             |
| `RABackendWhisperCPP.xcframework`| ~8MB        | STT (Whisper models)                    |

### Binary Size Savings

| App Configuration    | Old Monolithic | New Modular | Savings |
|----------------------|----------------|-------------|---------|
| LLM only             | ~95MB          | ~17MB       | 82%     |
| STT only (ONNX)      | ~95MB          | ~52MB       | 45%     |
| LLM + STT + TTS      | ~95MB          | ~87MB       | 8%      |
| Full (all backends)  | ~95MB          | ~95MB       | 0%      |

---

## Project Structure

### Top-Level Layout

```
runanywhere-swift/
├── Package.swift                 # Swift Package Manager manifest
├── Sources/
│   ├── RunAnywhere/              # Core SDK module
│   ├── ONNXRuntime/              # ONNX backend for STT/TTS/VAD
│   ├── LlamaCPPRuntime/          # LlamaCPP backend for LLM
│   ├── CRACommons/               # C bridge to runanywhere-commons
│   ├── CRABackendLlamaCPP/       # C bridge to LlamaCPP backend
│   └── CRABackendONNX/           # C bridge to ONNX backend
├── Binaries/                     # Binary dependencies (xcframeworks)
├── Tests/                        # Test suites
└── scripts/                      # Build and setup scripts
```

### Core SDK Structure (Sources/RunAnywhere/)

```
RunAnywhere/
├── Public/                       # Public API surface
│   ├── RunAnywhere.swift         # Main entry point (static enum)
│   ├── Configuration/            # SDKEnvironment
│   ├── Events/                   # EventBus for public event subscriptions
│   └── Extensions/               # Public API extensions (LLM, STT, TTS, etc.)
│
├── Core/                         # Core SDK infrastructure
│   ├── Module/                   # RunAnywhereModule protocol, ModuleDiscovery
│   ├── Types/                    # Shared type definitions
│   └── ServiceRegistry.swift     # Central service factory registry
│
├── Features/                     # AI capability implementations
│   ├── LLM/                      # LLMCapability, LLMService protocol
│   ├── STT/                      # STTCapability, STTService protocol
│   ├── TTS/                      # TTSCapability, TTSService protocol
│   └── VoiceAgent/               # Composite voice pipeline
│
├── Infrastructure/               # Cross-cutting concerns
│   ├── Device/                   # Device registration and fingerprinting
│   ├── Download/                 # Model download with Alamofire
│   ├── Events/                   # EventPublisher, SDKEvent protocol
│   ├── FileManagement/           # Storage and file operations
│   └── Logging/                  # SDKLogger, Pulse integration
│
├── Data/                         # Data layer
│   └── Network/                  # APIClient, AuthenticationService
│
└── Foundation/                   # Core utilities
    ├── Constants/                # SDK version, build tokens
    ├── Errors/                   # Error codes and categories
    ├── Bridge/                   # C++ bridge utilities
    └── Security/                 # KeychainManager
```

---

## Core Components

### Public API Layer (RunAnywhere)

The `RunAnywhere` enum serves as the single entry point for all SDK operations.

**Location:** `Public/RunAnywhere.swift`

**Responsibilities:**
- SDK initialization with API key, base URL, and environment
- Lazy device registration on first API call
- Text generation (`generate()`, `generateStream()`, `chat()`)
- Voice operations (`transcribe()`, `loadSTTModel()`, `loadTTSModel()`)
- Model management (`loadModel()`, `unloadModel()`, `availableModels()`)
- Event access via `RunAnywhere.events`

**Pattern:** All public methods delegate to capabilities via `ServiceContainer.shared`.

```swift
public static func generate(
    _ prompt: String,
    options: LLMGenerationOptions?
) async throws -> LLMGenerationResult {
    guard isInitialized else { throw SDKError.general(.notInitialized, "SDK not initialized") }
    try await ensureDeviceRegistered()
    return try await serviceContainer.llmCapability.generate(prompt, options: options)
}
```

### Module System

The module system enables pluggable backend modules that provide AI capabilities.

**Key Protocols:**
- `RunAnywhereModule` - Defines module identity, capabilities, and registration
- `CapabilityType` - Enum of capability types (`.llm`, `.stt`, `.tts`, `.vad`, `.speakerDiarization`)

**Key Types:**
- `ModuleRegistry` - Singleton that tracks registered modules
- `ModuleDiscovery` - Thread-safe auto-discovery mechanism
- `ServiceRegistry` - Central registry for service factories

**Registration Flow:**
1. App imports a module (e.g., `import LlamaCPPRuntime`)
2. App calls `RunAnywhere.register(LlamaCPP.self)`
3. Module registers its service factory with `ServiceRegistry.shared`
4. Capabilities use `ServiceRegistry` to create services on demand

**Example Module (LlamaCPP):**

```swift
public enum LlamaCPP: RunAnywhereModule {
    public static let moduleId = "llamacpp"
    public static let moduleName = "LlamaCPP"
    public static let capabilities: Set<CapabilityType> = [.llm]

    @MainActor
    public static func register(priority: Int) {
        ServiceRegistry.shared.registerLLM(
            name: moduleName,
            priority: priority,
            canHandle: { modelId in canHandleModel(modelId) },
            factory: { config in try await createService(config: config) }
        )
    }
}
```

### Capability Layer

Capabilities are actor-based abstractions that own model lifecycle and provide thread-safe operations.

**Key Protocols:**
- `Capability` - Base protocol for all capabilities
- `ModelLoadableCapability` - For capabilities that load models (LLM, STT, TTS)
- `ServiceBasedCapability` - For capabilities without model loading (VAD)
- `CompositeCapability` - For capabilities that compose others (VoiceAgent)

**Implemented Capabilities:**

| Capability                     | Actor | Purpose                       |
|--------------------------------|-------|-------------------------------|
| `LLMCapability`                | Yes   | Text generation with streaming|
| `STTCapability`                | Yes   | Speech-to-text transcription  |
| `TTSCapability`                | Yes   | Text-to-speech synthesis      |
| `VADCapability`                | Yes   | Voice activity detection      |
| `SpeakerDiarizationCapability` | Yes   | Speaker identification        |
| `VoiceAgentCapability`         | Yes   | Composite voice pipeline      |

**Lifecycle Management:**

Each capability uses `ManagedLifecycle<ServiceType>` which:
- Delegates to `ModelLifecycleManager` for actual loading/unloading
- Publishes lifecycle events via `EventPublisher`
- Tracks analytics automatically
- Handles concurrent load requests safely

```swift
public actor LLMCapability: ModelLoadableCapability {
    private let managedLifecycle: ManagedLifecycle<LLMService>

    public func loadModel(_ modelId: String) async throws {
        try await managedLifecycle.load(modelId)
    }

    public func generate(
        _ prompt: String,
        options: LLMGenerationOptions
    ) async throws -> LLMGenerationResult {
        let service = try await managedLifecycle.requireService()
        return try await service.generate(prompt: prompt, options: options)
    }
}
```

### Service Registry

The `ServiceRegistry` is the central factory registry for creating AI services based on model/voice IDs.

**Key Type:** `ServiceRegistry` (MainActor singleton)

**Service Types:**
- `LLMServiceFactory` - Creates LLM services
- `STTServiceFactory` - Creates STT services
- `TTSServiceFactory` - Creates TTS services
- `VADServiceFactory` - Creates VAD services
- `SpeakerDiarizationServiceFactory` - Creates diarization services

**Resolution Strategy:**
1. Modules register with priority and `canHandle` closure
2. Registry sorts registrations by priority (higher first)
3. On service creation, first matching factory is used

```swift
public func createLLM(
    for modelId: String?,
    config: LLMConfiguration
) async throws -> LLMService {
    guard let registration = llmRegistrations.first(where: { $0.canHandle(modelId) }) else {
        throw CapabilityError.providerNotFound("LLM service for model: \(modelId ?? "default")")
    }
    return try await registration.factory(config)
}
```

### Service Container (Dependency Injection)

The `ServiceContainer` provides centralized access to all SDK services and capabilities.

**Key Type:** `ServiceContainer` singleton

**Lazily Initialized Services:**
- Capabilities: `llmCapability`, `sttCapability`, `ttsCapability`, `vadCapability`, `voiceAgentCapability`
- Infrastructure: `downloadService`, `fileManager`, `storageAnalyzer`, `modelRegistry`
- Network: `networkService`, `apiClient`, `authenticationService`
- Data: `configurationService`, `modelInfoService`
- Analytics: `analyticsQueueManager`, `devAnalyticsService`

```swift
public class ServiceContainer {
    public static let shared = ServiceContainer()

    private(set) lazy var llmCapability: LLMCapability = { LLMCapability() }()
    private(set) lazy var downloadService: AlamofireDownloadService = { AlamofireDownloadService() }()
}
```

### Model Management

Model management handles discovery, registration, download, and persistence.

**Key Types:**
- `ModelInfo` - Immutable model metadata (ID, format, download URL, local path, etc.)
- `RegistryService` - In-memory model registry with integrated local model discovery
- `ModelInfoService` - In-memory model metadata storage
- `AlamofireDownloadService` - Model downloading with progress, extraction, and resume support

**Model Flow:**
1. Models are registered via `RegistryService.registerModel(_:)`
2. Downloads are handled by `AlamofireDownloadService.downloadModel(_:)`
3. After download, `localPath` is set and model is cached in memory
4. On app restart, `RegistryService` discovers cached models and updates registry

**Artifact Types:**

Models can be single files (`.gguf`, `.onnx`) or archives that need extraction (`.tar.bz2`, `.zip`).

### Event System

The event system provides unified event routing to both public subscribers and internal analytics.

**Key Types:**
- `SDKEvent` protocol - Base protocol for all events
- `EventPublisher` - Routes events based on `destination` property
- `EventBus` - Public Combine-based event stream
- `EventCategory` - Event categorization (`.llm`, `.stt`, `.model`, `.sdk`, etc.)
- `EventDestination` - Routing control (`.all`, `.publicOnly`, `.analyticsOnly`)

**Event Flow:**

```
Component -> EventPublisher.track(event)
                    |
       +------------+------------+
       v                         v
EventBus (public)      AnalyticsQueueManager (telemetry)
```

**Built-in Event Types:**
- `LLMEvent` - Generation started/completed/failed, model load/unload
- `STTEvent` - Transcription events
- `TTSEvent` - Synthesis events
- `ModelEvent` - Download progress, extraction, deletion
- `SDKLifecycleEvent` - Init started/completed, config loaded

### Logging and Observability

Structured logging with environment-aware configuration.

**Key Types:**
- `SDKLogger` - Lightweight logger with category support
- `Logging` - Singleton managing log service and destinations
- `LogLevel` - `.debug`, `.info`, `.warning`, `.error`, `.fault`
- `PulseDestination` - Integration with Pulse for network logging

**Usage:**

```swift
private let logger = SDKLogger(category: "LLMCapability")
logger.info("Generating with model: \(modelId)")
logger.error("Generation failed: \(error)")
```

---

## Data and Control Flow

### Text Generation Request

**App calls:** `try await RunAnywhere.generate("Hello!", options: nil)`

**Flow:**

1. **Public API** (`RunAnywhere.generate`)
   - Validates SDK is initialized
   - Calls `ensureDeviceRegistered()` (lazy, O(1) after first call)
   - Delegates to `serviceContainer.llmCapability.generate()`

2. **LLMCapability** (actor)
   - Calls `managedLifecycle.requireService()` to get loaded `LLMService`
   - Starts analytics tracking via `GenerationAnalyticsService`
   - Calls `service.generate(prompt:options:)`
   - Records completion metrics
   - Returns `LLMGenerationResult`

3. **LLMService** (e.g., `LlamaCPPService`)
   - Calls C bridge: `ra_text_generate(backend, prompt, ...)`
   - Returns generated text

4. **Events Published:**
   - `LLMEvent.generationStarted` (public + analytics)
   - `LLMEvent.generationCompleted` (public + analytics)

**Error Handling:**
- Errors propagate as `CapabilityError` or `LLMError`
- `LLMEvent.generationFailed` is published
- Analytics track error via `trackOperationError()`

### Model Loading

**App calls:** `try await RunAnywhere.loadModel("my-model-id")`

**Flow:**

1. **Public API** (`RunAnywhere.loadModel`)
   - Ensures device is registered
   - Delegates to `llmCapability.loadModel(modelId)`

2. **LLMCapability -> ManagedLifecycle**
   - Publishes `LLMEvent.modelLoadStarted`
   - Delegates to `ModelLifecycleManager.load(modelId)`

3. **ModelLifecycleManager**
   - Checks if already loaded (returns early if same model)
   - Unloads current model if different
   - Calls `ServiceRegistry.createLLM(for: modelId, config: config)`

4. **ServiceRegistry -> LlamaCPP Module**
   - Finds registration where `canHandle(modelId)` returns true
   - Calls factory to create `LlamaCPPService`
   - Service calls `ra_text_load_model()` via C bridge

5. **Events Published:**
   - `LLMEvent.modelLoadStarted`
   - `LLMEvent.modelLoadCompleted` (with duration)
   - On failure: `LLMEvent.modelLoadFailed`

### Voice Agent Turn

**App calls:** `try await voiceAgentCapability.processVoiceTurn(audioData)`

**Flow:**

1. **VoiceAgentCapability** (composite actor)
   - Verifies all components are initialized

2. **Step 1: Transcription**
   - `stt.transcribe(audioData)` -> STT service -> returns text

3. **Step 2: LLM Response**
   - `llm.generate(transcription)` -> LLM service -> returns response

4. **Step 3: Speech Synthesis**
   - `tts.synthesize(response)` -> TTS service -> returns audio data

5. **Returns:** `VoiceAgentResult` with transcription, response, and synthesized audio

---

## Concurrency Model

### Actor Isolation

All capabilities are implemented as Swift actors, providing:
- Thread-safe state access
- Automatic isolation of mutable state
- Prevention of data races

**Key Actors:**
- `LLMCapability`, `STTCapability`, `TTSCapability`, `VADCapability`
- `SpeakerDiarizationCapability`, `VoiceAgentCapability`
- `ManagedLifecycle<ServiceType>`, `ModelLifecycleManager<ServiceType>`

### MainActor Requirements

The following are marked `@MainActor`:
- `ServiceRegistry` (service registration must happen on main thread)
- `ModuleRegistry` (module registration)
- Module `register(priority:)` methods

### Async/Await Usage

- All public API methods use `async/await`
- Service protocol methods are `async throws`
- Event publishing supports both sync and async variants

### Background Operations

- Model downloads run on background threads (Alamofire handles this)
- Device registration can be triggered in background via `Task.detached`
- Analytics queue manager processes events asynchronously

### Concurrency Primitives

| Primitive            | Usage                                             |
|----------------------|---------------------------------------------------|
| Swift Actors         | Capabilities, lifecycle managers                  |
| `DispatchQueue`      | `RegistryService.accessQueue` for model registry  |
| `NSLock`             | `ModuleDiscovery._discoveredModules` access       |
| `AsyncStream`        | Download progress, streaming generation           |
| `Task`               | Background operations, detached work              |
| Combine              | `EventBus` uses `PassthroughSubject`              |

---

## Dependencies and Boundaries

### External Dependencies

| Dependency       | Purpose                        | Used In                           |
|------------------|--------------------------------|-----------------------------------|
| **swift-crypto** | Cryptographic operations       | Core SDK                          |
| **Alamofire**    | Network requests, downloads    | `AlamofireDownloadService`, `APIClient` |
| **Files**        | File system abstraction        | `SimplifiedFileManager`           |
| **ZIPFoundation**| Archive extraction             | `ArchiveUtility`                  |
| **DeviceKit**    | Device information             | `Device`, telemetry               |
| **SWCompression**| Tar/bz2 extraction             | Archive handling                  |
| **Sentry**       | Crash reporting                | `SentryManager`                   |

### Binary Dependencies

- **RACommons** (xcframework) - Core C++ commons
- **RABackendLlamaCPP** (xcframework) - LLM backend
- **RABackendONNX** (xcframework) - STT/TTS/VAD backend
- **onnxruntime** (dylib, macOS only) - ONNX Runtime

### Module Boundaries

```
+-------------------------------------------------------------+
|                    Public API Surface                        |
| (RunAnywhere enum, EventBus, ModelInfo, LLMGenerationResult) |
+-------------------------------------------------------------+
                              |
+-------------------------------------------------------------+
|                         Core SDK                             |
|  ServiceRegistry <- ServiceContainer <- Capabilities         |
|  (internal protocols, actors, infrastructure)                |
+-------------------------------------------------------------+
                              |
+-------------------------------------------------------------+
|                    External Modules                          |
|    ONNXRuntime | LlamaCPPRuntime | FoundationModels          |
|  (implement RunAnywhereModule, register with ServiceRegistry)|
+-------------------------------------------------------------+
                              |
+-------------------------------------------------------------+
|                    C Bridge Layer                            |
|     CRACommons (rac_*.h headers)                             |
|     Binary XCFrameworks                                      |
+-------------------------------------------------------------+
```

### Dependency Encapsulation

- **Alamofire** - Wrapped in `AlamofireDownloadService`, not exposed in public API
- **Files** - Used internally by `SimplifiedFileManager`
- **External service protocols** (`LLMService`, `STTService`, etc.) - Not directly exposed; capabilities mediate all access

---

## Extensibility

### Creating a New Backend Module

1. Create a new Swift Package target depending on `RunAnywhere`
2. Implement the `RunAnywhereModule` protocol:

```swift
public enum MyModule: RunAnywhereModule {
    public static let moduleId = "my-module"
    public static let moduleName = "My Module"
    public static let capabilities: Set<CapabilityType> = [.llm]

    @MainActor
    public static func register(priority: Int) {
        ServiceRegistry.shared.registerLLM(
            name: moduleName,
            priority: priority,
            canHandle: { modelId in /* ... */ },
            factory: { config in try await MyLLMService() }
        )
    }
}
```

3. Implement the required service protocol (`LLMService`, `STTService`, etc.)

### Service Protocols

Each capability type has a corresponding service protocol:

| Capability   | Service Protocol            | Required Methods                                    |
|--------------|-----------------------------|-----------------------------------------------------|
| LLM          | `LLMService`                | `initialize()`, `generate()`, `streamGenerate()`, `cleanup()` |
| STT          | `STTService`                | `transcribe()`, `streamTranscribe()`, `cleanup()`   |
| TTS          | `TTSService`                | `synthesize()`, `cleanup()`                         |
| VAD          | `VADService`                | `detectSpeech()`, `cleanup()`                       |
| Diarization  | `SpeakerDiarizationService` | `identifySpeaker()`, `processAudio()`               |

### Custom Download Strategies

Register custom download strategies for special model sources:

```swift
ServiceContainer.shared.downloadService.registerStrategy(MyCustomStrategy())
```

### Event Subscriptions

Apps can subscribe to SDK events:

```swift
let cancellable = RunAnywhere.events.events
    .filter { $0.category == .llm }
    .sink { event in print(event.type) }
```

### Logging Customization

Add custom log destinations:

```swift
Logging.shared.addDestination(MyLogDestination())
Logging.shared.setMinLogLevel(.debug)
```

---

## Testing

### Test Structure

The SDK includes testability features:

- **Dependency Injection** - `ServiceContainer` allows mocking services
- **Protocol-Based Design** - Service protocols enable test doubles
- **Reset Methods** - `ServiceContainer.reset()`, `ModuleRegistry.reset()` for test isolation
- **Environment Support** - `.development` environment disables keychain, enables mock network

### Internal Testing Hooks

- Development environment disables certain features for testing
- `testLocal` flag in `Package.swift` - Use local xcframework for development
- Mock network service created in development mode

---

## Design Decisions

### Static Enum vs Instance-Based SDK

**Choice:** `RunAnywhere` is a static enum, not an instantiable class.

**Trade-offs:**
- Simple, discoverable API (`RunAnywhere.generate()`)
- Singleton-like access without explicit initialization
- Harder to support multiple SDK instances (rare requirement)
- Global state complicates testing

### Lazy Initialization

**Choice:** Network services, device registration, and configuration are initialized lazily on first API call.

**Rationale:** Fast app startup; SDK init is synchronous and quick (~0ms network).

**Trade-off:** First API call has higher latency due to bootstrap.

### Actor-Based Capabilities

**Choice:** Capabilities are Swift actors, not classes with locks.

**Rationale:** Modern Swift concurrency, compile-time safety, no manual lock management.

**Trade-off:** MainActor requirements for registration could be surprising.

### C Bridge Architecture

**Choice:** ML backends implemented in C++ and exposed via unified C API.

**Rationale:**
- Reuse across platforms (iOS, Android, Flutter)
- Performance-critical code in native C++
- Single xcframework simplifies distribution

**Trade-off:** Debugging C bridge issues requires native tooling.

### Priority-Based Service Resolution

**Choice:** Services are resolved by priority, first matching `canHandle()` wins.

**Rationale:** Allows multiple modules with overlapping capabilities, clear preference order.

**Trade-off:** Model ID patterns must be carefully designed to avoid conflicts.

---

## Type Reference

### Public Types

| Type                    | Description                                               |
|-------------------------|-----------------------------------------------------------|
| `RunAnywhere`           | Static enum providing all public SDK methods              |
| `LLMGenerationResult`   | Result of text generation with metrics                    |
| `LLMGenerationOptions`  | Options for text generation (temperature, max tokens, etc.)|
| `LLMStreamingResult`    | Stream + result task for streaming generation             |
| `ModelInfo`             | Immutable model metadata                                  |
| `EventBus`              | Combine-based event subscription                          |
| `SDKEnvironment`        | Environment enum (`.development`, `.staging`, `.production`)|
| `SDKError`              | SDK error type with codes and categories                  |
| `CapabilityType`        | Enum of capability types                                  |

### Internal Types

| Type                    | Description                                   |
|-------------------------|-----------------------------------------------|
| `ServiceContainer`      | Dependency injection container                |
| `ServiceRegistry`       | Factory registry for AI services              |
| `ModuleRegistry`        | Registry of loaded modules                    |
| `LLMCapability`         | Actor managing LLM lifecycle and generation   |
| `STTCapability`         | Actor managing STT lifecycle and transcription|
| `TTSCapability`         | Actor managing TTS lifecycle and synthesis    |
| `VADCapability`         | Actor managing VAD operations                 |
| `VoiceAgentCapability`  | Composite actor for voice pipelines           |
| `ManagedLifecycle<T>`   | Lifecycle manager with event tracking         |
| `ModelLifecycleManager<T>`| Core lifecycle state machine                |
| `AlamofireDownloadService`| Model download with progress                |
| `SDKLogger`             | Structured logging utility                    |
| `EventPublisher`        | Event routing to bus and analytics            |

### Protocols

| Protocol                    | Description                              |
|-----------------------------|------------------------------------------|
| `RunAnywhereModule`         | Module registration contract             |
| `LLMService`                | LLM backend implementation contract      |
| `STTService`                | STT backend implementation contract      |
| `TTSService`                | TTS backend implementation contract      |
| `VADService`                | VAD backend implementation contract      |
| `SpeakerDiarizationService` | Diarization backend contract             |
| `Capability`                | Base capability protocol                 |
| `ModelLoadableCapability`   | Capability with model lifecycle          |
| `SDKEvent`                  | Base protocol for all events             |

### Modules

| Module     | Library Name            | Capabilities          |
|------------|-------------------------|-----------------------|
| Core       | `RunAnywhere`           | Infrastructure, public API |
| ONNX       | `RunAnywhereONNX`       | STT, TTS, VAD         |
| LlamaCPP   | `RunAnywhereLlamaCPP`   | LLM                   |
