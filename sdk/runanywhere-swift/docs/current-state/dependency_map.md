# RunAnywhere Swift SDK - Dependency Map

**Generated:** December 7, 2025
**SDK Version:** 0.15.8

---

## Overview

This document maps the dependencies between modules, identifies central hub modules, and documents external framework usage across the RunAnywhere Swift SDK.

---

## Module Dependency Hierarchy

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              PUBLIC LAYER                                    │
│  Public/ (RunAnywhere.swift, Extensions, Events, Models, Errors)            │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
┌──────────────────────┐ ┌──────────────────┐ ┌──────────────────────────────┐
│     Components/      │ │   Capabilities/  │ │      Infrastructure/         │
│  (LLM, STT, TTS,    │ │ (TextGeneration, │ │   (Platform Audio Sessions)   │
│   VAD, VLM, etc.)   │ │ Voice, Registry) │ │                              │
└──────────────────────┘ └──────────────────┘ └──────────────────────────────┘
                    │               │               │
                    └───────────────┼───────────────┘
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              CORE LAYER                                      │
│  Core/ (ModuleRegistry, Protocols, Models, ServiceRegistry)                 │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
┌──────────────────────┐ ┌──────────────────┐ ┌──────────────────────────────┐
│      Data/           │ │   Foundation/    │ │    Backend Adapters          │
│ (Repositories, Net,  │ │ (DI, Logging,   │ │ (LlamaCPP, WhisperKit,       │
│  DataSources)        │ │  Security)       │ │  ONNX, FoundationModels)     │
└──────────────────────┘ └──────────────────┘ └──────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          NATIVE / C BRIDGE                                   │
│  CRunAnywhereCore (ra_types.h, ra_llamacpp_bridge.h, ra_onnx_bridge.h)     │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Module-Level Dependencies

### Public/ Module

**Depends On:**
- Core/ (ModuleRegistry, Protocols, Models)
- Capabilities/ (TextGeneration, Voice, Registry, ModelLoading)
- Components/ (LLMComponent, STTComponent, TTSComponent, etc.)
- Foundation/ (ServiceContainer, SDKLogger, KeychainManager)
- Data/ (Repositories, NetworkService, Storage)

**Depended Upon By:**
- Host Application (main integration point)

**Key Files & Their Dependencies:**
| File | Internal Dependencies |
|------|----------------------|
| RunAnywhere.swift | ServiceContainer, EventBus, DatabaseManager, KeychainManager, ModelLoadingService |
| RunAnywhere+Components.swift | Components/*, ModuleRegistry |
| RunAnywhere+Voice.swift | STTComponent, LLMComponent, TTSComponent |
| EventBus.swift | Foundation (Combine) |
| SDKEvent.swift | Foundation only |

---

### Core/ Module

**Depends On:**
- Foundation/ (SDKLogger, ErrorTypes)

**Depended Upon By:**
- Public/
- Components/
- Capabilities/
- Backend Adapters

**Key Files & Their Dependencies:**
| File | Internal Dependencies |
|------|----------------------|
| ModuleRegistry.swift | Foundation (SDKLogger) |
| BaseComponent.swift | Protocols, SDKError, EventBus |
| ModelLifecycleManager.swift | Core/Models, SDKLogger |
| UnifiedServiceRegistry.swift | AdapterRegistry, Protocols |

**Central Hub Status:** YES - Core types (ModelInfo, Protocols) are imported everywhere

---

### Components/ Module

**Depends On:**
- Core/ (BaseComponent, Protocols, ModuleRegistry)
- Capabilities/ (Analytics services)
- Foundation/ (SDKLogger, EventBus)
- Data/ (Services)

**Depended Upon By:**
- Public/
- Capabilities/Voice (VoiceAgentComponent uses all components)

**Component Dependencies:**
```
VoiceAgentComponent
    ├── VADComponent → Core/Protocols, Capabilities/Voice/SimpleEnergyVAD
    ├── STTComponent → Core/Protocols, ModuleRegistry (external providers)
    ├── LLMComponent → Core/Protocols, ModuleRegistry (external providers)
    └── TTSComponent → Core/Protocols, ModuleRegistry (external providers), AVFoundation

SpeakerDiarizationComponent → Core/Protocols, Capabilities/Voice/DefaultSpeakerDiarization
WakeWordComponent → Core/Protocols (placeholder - no real dependencies)
VLMComponent → Core/Protocols (placeholder - no real dependencies)
```

---

### Capabilities/ Module

**Depends On:**
- Core/ (Models, Protocols)
- Foundation/ (SDKLogger, ErrorTypes, AnalyticsQueueManager)
- Data/ (Services, Repositories)
- Components/ (for Voice pipeline handlers)

**Depended Upon By:**
- Public/
- Components/

**Submodule Dependencies:**
| Submodule | Dependencies |
|-----------|--------------|
| TextGeneration/ | Core/Models, Foundation/SDKLogger, Data/Services |
| Voice/ | Core/Protocols, Foundation/*, Components/*, AVFoundation |
| Registry/ | Core/Models, Foundation/SDKLogger, Data/Storage |
| Routing/ | Core/Models, Capabilities/DeviceCapability |
| DeviceCapability/ | Foundation, UIKit (iOS), Metal |
| ModelLoading/ | Core/Models, Data/Services, Foundation/FileOperations |
| Analytics/ | Foundation/Analytics, Data/Telemetry |
| StructuredOutput/ | Core/Models, Foundation |

---

### Data/ Module

**Depends On:**
- Core/ (Models only - no circular dependencies)
- Foundation/ (SDKLogger, ErrorTypes, KeychainManager)

**Depended Upon By:**
- Capabilities/
- Public/
- Foundation/ (partial - AnalyticsQueueManager)

**Submodule Dependencies:**
| Submodule | Dependencies |
|-----------|--------------|
| Network/ | Foundation, Alamofire, Pulse |
| Repositories/ | DataSources, Protocols, GRDB |
| DataSources/ | Models, Network, Foundation |
| Storage/ | Foundation, GRDB |
| Services/ | Repositories, Foundation |
| Sync/ | Services, Foundation |

---

### Foundation/ Module

**Depends On:**
- External frameworks only (Foundation, Combine, Security, os.log)

**Depended Upon By:**
- ALL other modules (lowest internal dependency layer)

**Central Hub Status:** YES - ServiceContainer, SDKLogger are used everywhere

**Submodule Dependencies:**
| Submodule | External Dependencies |
|-----------|----------------------|
| DependencyInjection/ | Foundation only |
| Logging/ | Foundation, os.log, Combine |
| Security/ | Security framework (Keychain) |
| Analytics/ | Foundation, Combine |
| FileOperations/ | Foundation, zlib (ArchiveUtility) |
| ErrorTypes/ | Foundation only |
| DeviceIdentity/ | Foundation, UIKit (device info) |

---

### Backend Adapters

**Common Pattern:** All adapters depend on Core/ and Foundation/, and provide services via ModuleRegistry.

| Adapter | Dependencies | Capabilities Provided |
|---------|--------------|----------------------|
| LlamaCPPRuntime/ | CRunAnywhereCore, Core/Protocols, Foundation | LLM (textToText) |
| WhisperKitTranscription/ | WhisperKit framework, Core/Protocols, Foundation | STT (voiceToText) |
| ONNXRuntime/ | CRunAnywhereCore, Core/Protocols, Foundation, AVFoundation | STT, TTS |
| FoundationModelsAdapter/ | FoundationModels (iOS 26+), Core/Protocols | LLM (textToText) |
| FluidAudioDiarization/ | FluidAudio framework, Core/Protocols | SpeakerDiarization |

---

## External Framework Dependencies

### System Frameworks
| Framework | Usage Location | Purpose |
|-----------|----------------|---------|
| Foundation | Everywhere | Core types, async/await, Codable |
| Combine | EventBus, Services | Reactive event distribution |
| AVFoundation | ONNXRuntime, Components/TTS, Infrastructure | Audio capture, playback, AVSpeechSynthesizer |
| Security | Foundation/Security | Keychain access |
| Metal | Capabilities/DeviceCapability | GPU detection |
| CoreML | Core/Models | Model format detection |
| UIKit | Various | Device info, battery state (iOS only) |
| os.log | Foundation/Logging | System logging |

### Third-Party Dependencies
| Dependency | Module | Purpose |
|------------|--------|---------|
| Alamofire | Data/Network | HTTP downloads |
| GRDB | Data/Storage | SQLite database |
| Pulse | Data/Network | Network request logging/debugging |
| WhisperKit | WhisperKitTranscription | Whisper speech recognition |
| FluidAudio | FluidAudioDiarization | Speaker diarization |
| zlib | Foundation/FileOperations | Archive extraction |

### C Bridge Dependencies
| Header | Usage |
|--------|-------|
| CRunAnywhereCore | ONNXRuntime, LlamaCPPRuntime - bridges to native llama.cpp and onnxruntime |

---

## Cyclic Dependency Analysis

### Potential Cycles Identified

1. **Foundation ↔ Data (Partial)**
   - AnalyticsQueueManager (Foundation) → TelemetryRepository (Data)
   - This is managed via protocol abstraction but creates implicit coupling

2. **Components ↔ Capabilities/Voice**
   - VoiceAgentComponent depends on Voice handlers
   - Voice handlers depend on component services
   - Resolved through protocol abstraction

### No True Cyclic Dependencies
The architecture successfully avoids true circular dependencies through:
- Protocol-based abstraction
- Dependency injection via ServiceContainer
- ModuleRegistry for provider registration

---

## Central Hub Modules

Modules that are dependencies for many other modules:

| Module | Dependents | Hub Score |
|--------|------------|-----------|
| Foundation/DependencyInjection | ALL | Critical |
| Foundation/Logging | ALL | Critical |
| Core/Protocols | ALL except Foundation | High |
| Core/Models | ALL except Foundation | High |
| Core/ModuleRegistry | Components, Adapters | High |
| Public/Events/EventBus | Components, Capabilities | Medium |

---

## Leaf Modules

Modules with minimal dependents (easier to refactor):

| Module | Dependents |
|--------|------------|
| Capabilities/StructuredOutput | Public only |
| Capabilities/Analytics/* | Components (telemetry calls) |
| Infrastructure/Voice/Platform | Components/TTS (audio session) |
| FluidAudioDiarization | SpeakerDiarizationComponent |
| FoundationModelsAdapter | ModuleRegistry (optional provider) |

---

## Dependency Recommendations

### High Coupling Areas
1. **ServiceContainer** - Single point of failure, consider splitting by domain
2. **ModuleRegistry** - All provider registration goes through here
3. **Core/Protocols** - Many protocols in one location, could be co-located with implementations

### Suggested Improvements
1. Consider splitting ServiceContainer into domain-specific containers
2. Co-locate protocols with their primary implementations
3. Move Analytics services closer to the components they track
4. Reduce Foundation/Data coupling by moving telemetry protocol to Core

---

*This document is part of the RunAnywhere Swift SDK current-state documentation.*
