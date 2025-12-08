# RunAnywhere Swift SDK - File Index

**Generated:** 2025-12-07
**Total Swift Files:** 248
**SDK Version:** 0.15.8

## File Distribution by Module

| Module | File Count | Description |
|--------|------------|-------------|
| RunAnywhere | 225 | Core SDK implementation |
| ONNXRuntime | 8 | ONNX Runtime backend adapter |
| WhisperKitTranscription | 6 | WhisperKit STT adapter |
| LlamaCPPRuntime | 4 | LlamaCPP LLM backend adapter |
| FoundationModelsAdapter | 3 | Apple Foundation Models adapter |
| FluidAudioDiarization | 2 | Speaker diarization adapter |

## Module Structure

### RunAnywhere (Core SDK) - 225 files

#### Capabilities/ (50 files)
- **Analytics/** (4 files) - Generation, STT, TTS, Voice analytics services
- **DeviceCapability/** (14 files) - Device detection, hardware info, thermal monitoring
- **ModelLoading/** (2 files) - Model loading service and loaded model types
- **Registry/** (4 files) - Model discovery, registry service, cache, storage
- **Routing/** (4 files) - Execution target, routing decision, reason, service
- **StructuredOutput/** (1 file) - Structured output handler
- **TextGeneration/** (7 files) - Generation service, streaming, token counting
- **Voice/** (14 files) - VAD, STT, TTS, LLM handlers, voice session management

#### Components/ (8 files)
- LLMComponent.swift - Language model component
- STTComponent.swift - Speech-to-text component
- TTSComponent.swift - Text-to-speech component
- VADComponent.swift - Voice activity detection component
- VLMComponent.swift - Vision-language model component
- VoiceAgentComponent.swift - Voice agent orchestration
- WakeWordComponent.swift - Wake word detection
- SpeakerDiarizationComponent.swift - Speaker diarization component

#### Core/ (40 files)
- **Components/** (1 file) - BaseComponent.swift
- **Initialization/** (2 files) - Component initializers
- **Models/** (16 files) - Configuration, Framework, Model types
- **Protocols/** (16 files) - Core interfaces and protocols
- **ServiceRegistry/** (2 files) - Adapter selection, unified registry
- **Types/** (1 file) - Telemetry event types
- ModelLifecycleManager.swift
- ModuleRegistry.swift

#### Data/ (52 files)
- **DataSources/** (8 files) - Local/Remote data sources
- **Models/** (18 files) - DTOs, Entities, Storage models
- **Network/** (10 files) - API client, auth, network services
- **Protocols/** (6 files) - Repository protocols
- **Repositories/** (4 files) - Repository implementations
- **Services/** (5 files) - Configuration, telemetry, model services
- **Storage/** (5 files) - Database, file system management
- **Sync/** (1 file) - Sync coordinator

#### Foundation/ (35 files)
- **Analytics/** (4 files) - Analytics queue, context, event data
- **Concurrency/** (1 file) - UnfairLock
- **Configuration/** (1 file) - Constants
- **Constants/** (3 files) - Build token, error codes, SDK constants
- **Context/** (1 file) - RunAnywhereScope
- **DependencyInjection/** (3 files) - ServiceContainer, AdapterRegistry
- **DeviceIdentity/** (2 files) - Device manager, persistent identity
- **ErrorTypes/** (3 files) - Error type definitions
- **FileOperations/** (2 files) - Archive utility, model path utils
- **Logging/** (8 files) - Logger, log entry, configuration
- **Security/** (1 file) - KeychainManager

#### Infrastructure/ (2 files)
- **Voice/Platform/** - iOSAudioSession.swift, MacOSAudioSession.swift

#### Public/ (38 files)
- **Configuration/** (3 files) - Privacy mode, routing policy, environment
- **Errors/** (2 files) - RunAnywhereError, SDKError
- **Events/** (2 files) - EventBus, SDKEvent
- **Extensions/** (10 files) - RunAnywhere+ convenience extensions
- **Models/** (21 files) - Public API models
- RunAnywhere.swift - Main SDK entry point
- RunAnywhere+Components.swift
- RunAnywhere+Pipelines.swift

### Backend Adapters

#### ONNXRuntime/ (8 files)
- AudioCaptureManager.swift - Audio capture for ONNX models
- ONNXAdapter.swift - ONNX framework adapter
- ONNXDownloadStrategy.swift - Model download strategy
- ONNXError.swift - Error types
- ONNXRuntime.swift - Module entry point
- ONNXServiceProvider.swift - Service provider implementation
- ONNXSTTService.swift - STT service using ONNX
- ONNXTTSService.swift - TTS service using ONNX

#### WhisperKitTranscription/ (6 files)
- WhisperKitAdapter.swift - WhisperKit framework adapter
- WhisperKitDownloadStrategy.swift - Model download strategy
- WhisperKitService.swift - STT service implementation
- WhisperKitServiceProvider.swift - Service provider
- WhisperKitTranscription.swift - Module entry point
- WhisperKitVoiceService.swift - Voice service wrapper

#### LlamaCPPRuntime/ (4 files)
- LlamaCPPCoreAdapter.swift - C bridge adapter
- LlamaCPPRuntime.swift - Module entry point
- LlamaCPPService.swift - LLM service implementation
- LlamaCPPServiceProvider.swift - Service provider

#### FoundationModelsAdapter/ (3 files)
- FoundationModelsAdapter.swift - Framework adapter
- FoundationModelsService.swift - Service implementation
- FoundationModelsServiceProvider.swift - Service provider

#### FluidAudioDiarization/ (2 files)
- FluidAudioDiarization.swift - Module entry point
- FluidAudioDiarizationProvider.swift - Service provider

## Key Entry Points

| File | Purpose |
|------|---------|
| `Public/RunAnywhere.swift` | Main SDK entry point, initialization, generation APIs |
| `Core/ModuleRegistry.swift` | Plugin registration for STT, LLM, TTS providers |
| `Foundation/DependencyInjection/ServiceContainer.swift` | Dependency injection container |
| `Core/Components/BaseComponent.swift` | Base class for all components |
| `Public/Events/EventBus.swift` | Event-driven communication system |

## Configuration Files

| File | Purpose |
|------|---------|
| `Package.swift` | Swift Package Manager configuration |
| `ARCHITECTURE.md` | Architecture documentation |
| `CHANGELOG.md` | Version history |
| `RELEASING.md` | Release process documentation |

---
*This index is part of the RunAnywhere Swift SDK current-state documentation.*
