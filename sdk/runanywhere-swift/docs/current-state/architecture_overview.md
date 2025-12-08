# RunAnywhere Swift SDK - Architecture Overview

**Generated:** 2025-12-07
**SDK Version:** 0.15.8
**Minimum iOS:** 16.0 | **macOS:** 13.0

## Executive Summary

The RunAnywhere Swift SDK is a modular, plugin-based AI SDK that provides:
- **On-device AI inference** for LLM, STT, TTS, and VLM
- **Intelligent routing** between on-device and cloud execution
- **Event-driven architecture** for reactive UI integration
- **Clean component-based design** with dependency injection

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Host Application                                  │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    Public API Layer (RunAnywhere.swift)                  │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐        │
│  │ initialize()│ │ generate()  │ │ transcribe()│ │ loadModel() │        │
│  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘        │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         EventBus (Combine-based)                         │
│  SDKInitializationEvent | SDKGenerationEvent | SDKVoiceEvent | ...      │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
┌──────────────────────┐ ┌──────────────────┐ ┌──────────────────────────┐
│   ServiceContainer   │ │  ModuleRegistry  │ │    AdapterRegistry       │
│  (Dependency Inject) │ │ (Plugin Manager) │ │   (Framework Adapters)   │
└──────────────────────┘ └──────────────────┘ └──────────────────────────┘
                    │               │               │
                    └───────────────┼───────────────┘
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         Components Layer                                 │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐           │
│  │   LLM   │ │   STT   │ │   TTS   │ │   VAD   │ │   VLM   │           │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘           │
│       │           │           │           │           │                 │
│       └───────────┴─────┬─────┴───────────┴───────────┘                 │
│                         ▼                                               │
│              ┌─────────────────────┐                                    │
│              │    BaseComponent    │                                    │
│              │ (Lifecycle Manager) │                                    │
│              └─────────────────────┘                                    │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      Backend Adapters (Plugins)                          │
│  ┌───────────────┐ ┌──────────────────┐ ┌────────────────────────────┐  │
│  │ LlamaCPP      │ │ WhisperKit       │ │ ONNXRuntime                │  │
│  │ Runtime       │ │ Transcription    │ │ (STT/TTS)                  │  │
│  └───────────────┘ └──────────────────┘ └────────────────────────────┘  │
│  ┌───────────────┐ ┌──────────────────┐                                 │
│  │ Foundation    │ │ FluidAudio       │                                 │
│  │ Models        │ │ Diarization      │                                 │
│  └───────────────┘ └──────────────────┘                                 │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    Native Frameworks / C Bridge                          │
│  ┌───────────────┐ ┌──────────────────┐ ┌────────────────────────────┐  │
│  │ CRunAnywhere  │ │ WhisperKit       │ │ onnxruntime                │  │
│  │ Core (C API)  │ │ (Swift Package)  │ │ (Binary XCFramework)       │  │
│  └───────────────┘ └──────────────────┘ └────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

## Core Design Patterns

### 1. Plugin Architecture (ModuleRegistry)

The SDK uses a plugin-based architecture where AI providers are registered at runtime:

```swift
// Host app registers providers during initialization
ModuleRegistry.shared.registerLLM(LlamaCPPServiceProvider())
ModuleRegistry.shared.registerSTT(WhisperKitServiceProvider())
ModuleRegistry.shared.registerTTS(ONNXTTSServiceProvider())
```

**Key Benefits:**
- Optional dependencies (only include backends you need)
- Easy extensibility (add custom providers)
- Priority-based provider selection

**Implementation:** [ModuleRegistry.swift](Sources/RunAnywhere/Core/ModuleRegistry.swift)

### 2. Component-Based Architecture (BaseComponent)

All AI capabilities inherit from `BaseComponent<TService>`:

```
BaseComponent<TService>
    ├── LLMComponent (LLMService)
    ├── STTComponent (STTService)
    ├── TTSComponent (TTSService)
    ├── VADComponent (VADService)
    ├── VLMComponent (VLMService)
    └── VoiceAgentComponent (orchestrates STT→LLM→TTS)
```

**Lifecycle States:**
1. `notInitialized` - Component created
2. `initializing` - Service being created/configured
3. `ready` - Ready for processing
4. `failed` - Initialization failed

**Implementation:** [BaseComponent.swift](Sources/RunAnywhere/Core/Components/BaseComponent.swift)

### 3. Event-Driven Architecture (EventBus)

Thread-safe Combine-based event distribution:

```swift
// Event Types
SDKInitializationEvent  // SDK lifecycle
SDKGenerationEvent      // Text generation
SDKVoiceEvent           // Voice pipeline
SDKModelEvent           // Model loading
ComponentInitializationEvent  // Component lifecycle
```

**Implementation:** [EventBus.swift](Sources/RunAnywhere/Public/Events/EventBus.swift)

### 4. Dependency Injection (ServiceContainer)

Centralized lazy-initialized service container:

```swift
ServiceContainer.shared
    ├── modelRegistry          // Model discovery
    ├── adapterRegistry        // Framework adapters
    ├── modelLoadingService    // Model loading
    ├── generationService      // Text generation
    ├── streamingService       // Streaming generation
    ├── voiceCapabilityService // Voice pipeline
    ├── downloadService        // Model downloads
    ├── routingService         // Cloud/local routing
    └── telemetryService       // Analytics
```

**Implementation:** [ServiceContainer.swift](Sources/RunAnywhere/Foundation/DependencyInjection/ServiceContainer.swift)

## Module Descriptions

### Public Layer
| Module | Purpose |
|--------|---------|
| `Public/RunAnywhere.swift` | Main SDK entry point with all public APIs |
| `Public/Extensions/` | Convenience extensions (Configuration, Download, Voice, etc.) |
| `Public/Events/` | EventBus and SDK event definitions |
| `Public/Models/` | Public-facing model types |
| `Public/Errors/` | Error type definitions |

### Core Layer
| Module | Purpose |
|--------|---------|
| `Core/ModuleRegistry.swift` | Plugin registration system |
| `Core/Components/BaseComponent.swift` | Base class for all components |
| `Core/Protocols/` | Core interfaces (Component, FrameworkAdapter, etc.) |
| `Core/Models/` | Configuration and model types |
| `Core/ServiceRegistry/` | Unified adapter selection |

### Capabilities Layer
| Module | Purpose |
|--------|---------|
| `Capabilities/TextGeneration/` | LLM generation service, streaming |
| `Capabilities/Voice/` | Voice pipeline handlers (VAD, STT, TTS, LLM) |
| `Capabilities/ModelLoading/` | Model loading service |
| `Capabilities/Registry/` | Model registry and discovery |
| `Capabilities/Routing/` | Cloud vs local routing decisions |
| `Capabilities/Analytics/` | Per-capability analytics services |
| `Capabilities/DeviceCapability/` | Hardware detection (GPU, Neural Engine) |

### Data Layer
| Module | Purpose |
|--------|---------|
| `Data/Network/` | API client, authentication |
| `Data/Repositories/` | Data access abstractions |
| `Data/Storage/` | Database and file system |
| `Data/Services/` | Business logic services |
| `Data/Sync/` | Data synchronization |

### Foundation Layer
| Module | Purpose |
|--------|---------|
| `Foundation/DependencyInjection/` | ServiceContainer, AdapterRegistry |
| `Foundation/Logging/` | SDKLogger, log batching |
| `Foundation/Security/` | KeychainManager |
| `Foundation/Analytics/` | Analytics queue management |
| `Foundation/ErrorTypes/` | SDK error definitions |

### Backend Adapters
| Module | Backend | Capabilities |
|--------|---------|--------------|
| `LlamaCPPRuntime/` | llama.cpp via C bridge | LLM text generation |
| `WhisperKitTranscription/` | WhisperKit | Speech-to-text |
| `ONNXRuntime/` | ONNX Runtime | STT, TTS |
| `FoundationModelsAdapter/` | Apple Foundation Models | On-device LLM (Apple Silicon) |
| `FluidAudioDiarization/` | FluidAudio | Speaker diarization |

## Data Flow

### Text Generation Flow
```
1. RunAnywhere.generate(prompt)
       │
       ▼
2. GenerationService.generate()
       │
       ▼
3. RoutingService.decide() → On-device or Cloud?
       │
       ▼
4. ModelLoadingService.loadModel() → Find/Load model
       │
       ▼
5. AdapterRegistry.findBestAdapter() → Select LLM provider
       │
       ▼
6. LLMService.generate() → Actual inference
       │
       ▼
7. EventBus.publish(SDKGenerationEvent.completed)
       │
       ▼
8. Return GenerationResult with metrics
```

### Voice Pipeline Flow
```
1. Audio Input → VoiceAgentComponent
       │
       ▼
2. VADHandler → Detect speech segments
       │
       ▼
3. STTHandler → Transcribe audio (WhisperKit/ONNX)
       │
       ▼
4. LLMHandler → Generate response (LlamaCPP)
       │
       ▼
5. TTSHandler → Synthesize speech (ONNX)
       │
       ▼
6. Audio Output
```

## Key Interfaces

### LLMService Protocol
```swift
public protocol LLMService: AnyObject {
    func initialize(modelPath: String?) async throws
    func generate(prompt: String, options: GenerationOptions) async throws -> String
    func streamGenerate(prompt:, options:, onToken:) async throws
    var isReady: Bool { get }
    var currentModel: String? { get }
    func cleanup() async
}
```

### STTService Protocol
```swift
public protocol STTService {
    func initialize(modelPath: String?) async throws
    func transcribe(audioData: Data, options: STTOptions) async throws -> STTTranscriptionResult
    func transcribeStream(audioStream:, options:) -> AsyncThrowingStream<STTSegment, Error>
    var isReady: Bool { get }
    var currentModel: String? { get }
    func cleanup() async
}
```

### UnifiedFrameworkAdapter Protocol
```swift
public protocol UnifiedFrameworkAdapter {
    var framework: LLMFramework { get }
    var supportedModalities: [FrameworkModality] { get }
    var supportedFormats: [ModelFormat] { get }

    func canHandle(model: ModelInfo) -> Bool
    func loadModel(_ model: ModelInfo) async throws -> any LLMService
    func getProvidedModels() -> [ModelInfo]
    func getDownloadStrategy() -> DownloadStrategy?
    func onRegistration()
}
```

## Threading Model

- **@MainActor:** All components (`BaseComponent`, `ModuleRegistry`, UI-related)
- **DispatchQueue:** AdapterRegistry uses concurrent queue with barrier writes
- **Actors:** Device registration state uses Swift actors
- **Combine:** EventBus uses thread-safe PassthroughSubject

## External Dependencies

| Dependency | Purpose | Module |
|------------|---------|--------|
| Combine | Event distribution | Foundation |
| Pulse | Network logging | Data |
| Alamofire | HTTP downloads | Data |
| GRDB | SQLite database | Data/Storage |
| WhisperKit | Speech recognition | WhisperKitTranscription |
| FluidAudio | Speaker diarization | FluidAudioDiarization |
| CRunAnywhereCore | C bridge to llama.cpp | LlamaCPPRuntime |

## Configuration

### SDK Initialization
```swift
try RunAnywhere.initialize(
    apiKey: "your-api-key",
    baseURL: "https://api.runanywhere.ai",
    environment: .production  // or .development, .staging
)
```

### Generation Options
```swift
RunAnywhereGenerationOptions(
    maxTokens: 100,
    temperature: 0.7,
    streamingEnabled: true,
    preferredFramework: .llamaCpp
)
```

## Known Architectural Considerations

1. **Tight MainActor Coupling:** Many core components are @MainActor isolated, which can cause issues in background processing scenarios.

2. **Dual Registry Pattern:** Both `ModuleRegistry` (service providers) and `AdapterRegistry` (framework adapters) exist with some overlap in functionality.

3. **Lazy Service Initialization:** Services are lazily initialized which provides flexibility but can cause unexpected initialization delays at first use.

4. **Backend Sync Disabled:** The `SyncCoordinator` has auto-sync disabled (`enableAutoSync: false`) indicating backend integration may be incomplete.

---
*This document is part of the RunAnywhere Swift SDK current-state documentation.*
