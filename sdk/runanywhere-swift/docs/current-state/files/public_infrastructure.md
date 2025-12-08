# RunAnywhere Swift SDK - Public API and Infrastructure Analysis

**Analysis Date:** December 7, 2025
**SDK Version:** 0.15.8
**Total Files Analyzed:** 41 files (39 Public + 2 Infrastructure)

---

## Overview

This document provides a complete file-by-file analysis of all Swift source files in:
- `Sources/RunAnywhere/Public/` (39 files)
- `Sources/RunAnywhere/Infrastructure/` (2 files)

---

## Public/Configuration/

### `Public/Configuration/PrivacyMode.swift`

**Role / Responsibility**
- Privacy configuration for PII detection and filtering
- Defines privacy protection levels
- Codable for remote configuration

**Key Types**
- `PrivacyMode` (enum) – Standard, strict, or custom privacy levels

**Key Public APIs**
- `.standard` – Normal privacy protection
- `.strict` – Enhanced PII detection
- `.custom` – User-defined rules

**Dependencies**
- Foundation only

**Usage & Callers**
- Part of `ConfigurationData`
- Retrieved via `RunAnywhere.getCurrentPrivacyMode()`

**Potential Issues / Smells**
- Custom mode not fully implemented (placeholder)

**Unused / Dead Code**
- None detected

---

### `Public/Configuration/RoutingPolicy.swift`

**Role / Responsibility**
- Determines device vs cloud execution routing
- Core feature for intelligent routing

**Key Types**
- `RoutingPolicy` (enum) – Automatic, preferDevice, deviceOnly, preferCloud, custom routing

**Key Public APIs**
- `.automatic` – SDK decides based on capabilities
- `.preferDevice` – Prefer on-device when possible
- `.deviceOnly` – Never use cloud (strict privacy)
- `.preferCloud` – Prefer cloud execution
- `.custom` – User-defined rules

**Dependencies**
- Foundation only

**Usage & Callers**
- Part of `ConfigurationData.routing`
- Routing decision engine

**Potential Issues / Smells**
- Custom policy not implemented

---

### `Public/Configuration/SDKEnvironment.swift`

**Role / Responsibility**
- SDK environment modes (development, staging, production)
- Default log levels per environment

**Key Types**
- `SDKEnvironment` (enum) – development, staging, production

**Key Public APIs**
- `defaultLogLevel` – Returns appropriate log level for environment

**Dependencies**
- Foundation only

**Usage & Callers**
- SDK initialization
- Logging configuration

---

## Public/Errors/

### `Public/Errors/RunAnywhereError.swift`

**Role / Responsibility**
- Main public error type with comprehensive error cases
- Provides localized descriptions and recovery suggestions
- User-facing error messages

**Key Types**
- `RunAnywhereError` (enum) – All SDK error cases with associated values

**Key Public APIs**
- Initialization errors: `.notInitialized`, `.alreadyInitialized`, `.invalidConfiguration`, `.invalidAPIKey`
- Model errors: `.modelNotFound`, `.modelLoadFailed`, `.modelValidationFailed`, `.modelIncompatible`
- Generation errors: `.generationFailed`, `.generationTimeout`, `.contextTooLong`, `.tokenLimitExceeded`, `.costLimitExceeded`
- Network errors: `.networkUnavailable`, `.requestFailed`, `.downloadFailed`
- Storage/hardware/feature errors with associated values

**Important Internal Logic**
- Conforms to `LocalizedError` for user-friendly messages
- Provides both `errorDescription` and `recoverySuggestion`

**Dependencies**
- Foundation (ByteCountFormatter)

**Usage & Callers**
- Thrown throughout SDK
- Primary error handling interface

**Potential Issues / Smells**
- Some overlap with SDKError (internal type)

---

### `Public/Errors/SDKError.swift`

**Role / Responsibility**
- Internal SDK error type
- More granular than public RunAnywhereError

**Key Types**
- `SDKError` (enum) – Internal error cases

**Key Public APIs**
- `.notInitialized`, `.invalidState`, `.invalidAPIKey`
- `.networkError`, `.serverError`, `.timeout`
- `.componentNotInitialized`, `.validationFailed`, `.storageError`

**Dependencies**
- Foundation only

**Usage & Callers**
- Internal SDK error handling
- Wrapped/converted to RunAnywhereError at boundaries

---

## Public/Events/

### `Public/Events/EventBus.swift`

**Role / Responsibility**
- Central event distribution system using Combine
- Thread-safe singleton for SDK-wide events
- Type-safe event publishers for each category

**Key Types**
- `EventBus` (class) – Singleton event bus with typed publishers

**Key Public APIs**
- `shared` – Singleton instance
- `publish(_:)` – Publish any SDK event
- Event publishers: `initializationEvents`, `configurationEvents`, `generationEvents`, `modelEvents`, `voiceEvents`, etc.
- Convenience subscriptions: `on(_:handler:)`, `onInitialization`, `onGeneration`, etc.

**Important Internal Logic**
- Uses `@unchecked Sendable` (Combine is thread-safe)
- PassthroughSubjects for each event category
- Type-safe event routing via switch statement

**Dependencies**
- Foundation, Combine

**Usage & Callers**
- Used throughout SDK to publish events
- Core of event-driven architecture

**Potential Issues / Smells**
- Large switch statement in generic `publish()` - could use protocol witness pattern

---

### `Public/Events/SDKEvent.swift`

**Role / Responsibility**
- Defines all SDK event types and categories
- Type-safe event enums with associated values

**Key Types**
- `SDKEvent` (protocol) – Base protocol with timestamp and type
- `SDKEventType` (enum) – Event categories
- Event enums: `SDKInitializationEvent`, `SDKConfigurationEvent`, `SDKGenerationEvent`, `SDKModelEvent`, `SDKVoiceEvent`, `SDKPerformanceEvent`, `SDKNetworkEvent`, `SDKStorageEvent`, `SDKFrameworkEvent`, `SDKDeviceEvent`, `ComponentInitializationEvent`

**Important Internal Logic**
- All events have timestamps (computed as `Date()`)
- Associated values carry event-specific data
- Detailed component initialization tracking

**Dependencies**
- Foundation

**Usage & Callers**
- Published via `EventBus`
- Telemetry and analytics

**Potential Issues / Smells**
- Very large file (259 lines) - could split by category

---

## Public/Extensions/

### `Public/Extensions/RunAnywhere+Configuration.swift`

**Role / Responsibility**
- Configuration management convenience methods
- Privacy mode and routing policy accessors

**Key Public APIs**
- `getCurrentPrivacyMode() -> PrivacyMode`
- `getCurrentRoutingPolicy() -> RoutingPolicy`
- `updatePrivacyMode(_:)`
- `updateRoutingPolicy(_:)`

**Dependencies**
- Foundation, ConfigurationData

---

### `Public/Extensions/RunAnywhere+Download.swift`

**Role / Responsibility**
- Model download management APIs
- Progress tracking and events

**Key Public APIs**
- `downloadModel(_:) async throws`
- `downloadModelWithProgress(_:) -> AsyncThrowingStream<DownloadProgress>`
- `cancelDownload(_:)`
- `isModelDownloaded(_:) -> Bool`

**Dependencies**
- Foundation, DownloadService

---

### `Public/Extensions/RunAnywhere+Frameworks.swift`

**Role / Responsibility**
- Framework adapter registration and availability

**Key Public APIs**
- `registerFrameworkAdapter(_:priority:)`
- `getFrameworkAvailability() -> [FrameworkAvailability]`
- `availableAdapters(for:) async -> [LLMFramework]`

**Dependencies**
- Foundation, AdapterRegistry

---

### `Public/Extensions/RunAnywhere+Logging.swift`

**Role / Responsibility**
- Logging configuration convenience methods

**Key Public APIs**
- `setLogLevel(_:)`
- `enableRemoteLogging(_:)`
- `getLogLevel() -> LogLevel`

**Dependencies**
- Foundation, SDKLogger

---

### `Public/Extensions/RunAnywhere+ModelAssignments.swift`

**Role / Responsibility**
- Model assignment management for components

**Key Public APIs**
- `getModelAssignments() async -> ModelAssignments`
- `setModelAssignment(_:for:) async`

**Dependencies**
- Foundation, ModelAssignmentService

---

### `Public/Extensions/RunAnywhere+ModelLifecycle.swift`

**Role / Responsibility**
- Model lifecycle management
- Load/unload tracking

**Key Public APIs**
- `getLoadedModels() -> [LoadedModelInfo]`
- `isModelLoaded(_:) -> Bool`
- `unloadModel(_:) async throws`

**Dependencies**
- Foundation, ModelLifecycleManager

---

### `Public/Extensions/RunAnywhere+ModelManagement.swift`

**Role / Responsibility**
- High-level model management APIs

**Key Public APIs**
- `availableModels() async throws -> [ModelInfo]`
- `loadModel(_:) async throws`
- `deleteModel(_:) async throws`

**Dependencies**
- Foundation, ModelLoadingService

---

### `Public/Extensions/RunAnywhere+Storage.swift`

**Role / Responsibility**
- Storage management APIs with event reporting
- Cache cleanup, temp file management

**Key Public APIs**
- `getStorageInfo() async -> StorageInfo`
- `clearCache() async throws`
- `cleanTempFiles() async throws`
- `deleteStoredModel(_:) async throws`

**Dependencies**
- Foundation, StorageAnalyzer, FileManager

---

### `Public/Extensions/RunAnywhere+StructuredOutput.swift`

**Role / Responsibility**
- Structured output generation using Generatable protocol

**Key Public APIs**
- `generate<T: Generatable>(_:from:) async throws -> T`
- `generateWithRetry<T: Generatable>(_:from:maxAttempts:) async throws -> T`

**Dependencies**
- Foundation, Generatable protocol

---

### `Public/Extensions/RunAnywhere+Voice.swift`

**Role / Responsibility**
- Voice capabilities (transcription, conversation)

**Key Public APIs**
- `transcribe(audio:modelId:options:) async throws -> STTResult`
- `createVoiceConversation(sttModelId:llmModelId:ttsVoice:) -> AsyncThrowingStream<VoiceConversationEvent>`
- `processVoiceTurn(audio:sttModelId:llmModelId:ttsVoice:) async throws -> Data`

**Dependencies**
- Foundation, STT/LLM/TTS components

**Potential Issues / Smells**
- `createVoiceConversation` only initializes, doesn't implement loop (incomplete)

---

## Public/Models/

### `Public/Models/ComponentInitializationParameters.swift`

**Role / Responsibility**
- Base protocol and parameter types for component initialization

**Key Types**
- `ComponentInitParameters` (protocol)
- `EmbeddingInitParameters` (struct)
- `UnifiedComponentConfig` (struct)
- `VoiceAgentConfiguration` (struct)

**Unused / Dead Code**
- `EmbeddingInitParameters` potentially unused

---

### `Public/Models/ComponentTypes.swift`

**Role / Responsibility**
- Component type enumeration

**Key Types**
- `SDKComponent` (enum) – llm, stt, tts, vad, vlm, voiceAgent, wakeWord, speakerDiarization, embedding

---

### `Public/Models/Conversation.swift`

**Role / Responsibility**
- Message and context models for conversational AI

**Key Types**
- `Message` (struct)
- `MessageRole` (enum) – System, user, assistant
- `Context` (struct)

---

### `Public/Models/CostBreakdown.swift`

**Role / Responsibility**
- Cost tracking for on-device vs cloud execution

**Key Types**
- `CostBreakdown` (struct)

---

### `Public/Models/FrameworkAvailability.swift`

**Role / Responsibility**
- Framework availability information

**Key Types**
- `FrameworkAvailability` (struct)

---

### `Public/Models/FrameworkOptions/CoreMLOptions.swift`

**Role / Responsibility**
- Core ML-specific configuration

**Key Types**
- `CoreMLOptions` (struct)
- `ComputeUnits` (enum)

---

### `Public/Models/FrameworkOptions/GGUFOptions.swift`

**Role / Responsibility**
- GGUF/llama.cpp configuration

**Key Types**
- `GGUFOptions` (struct)

---

### `Public/Models/FrameworkOptions/MLXOptions.swift`

**Role / Responsibility**
- Apple MLX configuration

**Key Types**
- `MLXOptions` (struct)

---

### `Public/Models/FrameworkOptions/TFLiteOptions.swift`

**Role / Responsibility**
- TensorFlow Lite configuration

**Key Types**
- `TFLiteOptions` (struct)

---

### `Public/Models/GenerationOptions.swift`

**Role / Responsibility**
- Generation configuration options

**Key Types**
- `RunAnywhereGenerationOptions` (struct)

---

### `Public/Models/GenerationResult.swift`

**Role / Responsibility**
- Generation result with metrics

**Key Types**
- `GenerationResult` (struct)
- `PerformanceMetrics` (struct)

---

### `Public/Models/PerformanceMetrics.swift`

**Role / Responsibility**
- Performance measurement data

**Key Types**
- `PerformanceMetrics` (struct)

---

### `Public/Models/SDKInitParams.swift`

**Role / Responsibility**
- SDK initialization parameters

**Key Types**
- `SDKInitParams` (struct)
- `SupabaseConfig` (struct)

---

### `Public/Models/SharedComponentTypes.swift`

**Role / Responsibility**
- Common types across components

**Key Types**
- `AudioMetadata` (struct)
- `AudioFormat` (enum)
- `ImageFormat` (enum)

---

### `Public/Models/StreamingResult.swift`

**Role / Responsibility**
- Streaming generation result wrapper

**Key Types**
- `StreamingResult` (struct)

---

### `Public/Models/Voice/` (multiple files)

**Key Types**
- `VoiceAudioChunk` (struct)
- `VoiceError` (enum)
- `VoiceProcessingMode` (enum)
- `STTConfiguration`, `STTOptions`, `STTResult`, `STTSegment`, `STTTranscriptionResult`
- `TTSConfiguration`, `TTSOptions`
- `VADConfiguration`, `VADOptions`, `VADState`
- `VLMConfiguration`, `VLMOptions`
- `SpeakerDiarizationConfiguration`
- `WakeWordConfiguration`

---

## Public/RunAnywhere.swift (Main Entry Point)

**Role / Responsibility**
- Main SDK entry point
- All public APIs accessible as static methods
- Event-driven and async/await patterns

**Key Public APIs**
- `initialize(apiKey:baseURL:environment:) throws` – Initialize SDK
- `generate(_:options:) async throws -> GenerationResult` – Text generation
- `generateStream(_:options:) async throws -> StreamingResult` – Streaming generation
- `chat(_:) async throws -> String` – Simple chat
- `transcribe(_:) async throws -> String` – Audio transcription
- `loadModel(_:) async throws` – Load LLM model
- `loadSTTModel(_:) async throws` – Load STT model
- `loadTTSModel(_:) async throws` – Load TTS model
- `availableModels() async throws -> [ModelInfo]` – Get available models
- `events: EventBus` – Access event bus
- `estimateTokenCount(_:) -> Int` – Token estimation

**Important Internal Logic**
- Lazy device registration on first API call
- Supabase integration for dev analytics
- Retry logic with exponential backoff
- Thread-safe registration state using actor

**Dependencies**
- Foundation, Combine, UIKit (iOS)
- Internal services: ServiceContainer, EventBus, DatabaseManager, KeychainManager

---

## Public/RunAnywhere+Components.swift

**Role / Responsibility**
- Component creation and initialization

**Key Public APIs**
- `createLLMComponent(configuration:) -> LLMComponent`
- `createSTTComponent(configuration:) -> STTComponent`
- `createTTSComponent(configuration:) -> TTSComponent`
- `createVADComponent(configuration:) -> VADComponent`
- `initializeComponent(_:) async throws`

---

## Public/RunAnywhere+Pipelines.swift

**Role / Responsibility**
- High-level pipeline creation

**Key Public APIs**
- `createVoiceAgentPipeline(config:) async throws -> VoiceAgentComponent`

---

## Infrastructure/

### `Infrastructure/Voice/Platform/iOSAudioSession.swift`

**Role / Responsibility**
- iOS-specific audio session management
- AVAudioSession configuration
- Category and mode handling

**Key Types**
- `IOSAudioSession` (class)

**Key Public APIs**
- `configure(for:)` – Configure for voice processing mode
- `activate()` / `deactivate()` – Session lifecycle

**Important Internal Logic**
- Uses AVAudioSession for iOS
- Handles recording, playback, conversation modes
- Route change notifications

**Dependencies**
- AVFoundation

---

### `Infrastructure/Voice/Platform/MacOSAudioSession.swift`

**Role / Responsibility**
- macOS-specific audio session (stub)
- AVAudioEngine configuration

**Key Types**
- `MacOSAudioSession` (class)

**Key Public APIs**
- `configure(for:)` – Configure for voice processing mode
- `activate()` / `deactivate()` – Session lifecycle

**Important Internal Logic**
- macOS doesn't have AVAudioSession
- Uses AVAudioEngine instead

**Dependencies**
- AVFoundation

---

## Summary

### Files by Category
- **Configuration:** 3 files
- **Errors:** 2 files
- **Events:** 2 files
- **Extensions:** 10 files
- **Models:** 21 files
- **Main Entry Points:** 3 files
- **Infrastructure:** 2 files

### Key Patterns Observed
1. **Event-driven architecture** using Combine
2. **Clean separation** of public API from internal implementation
3. **Component-based design** with consistent initialization patterns
4. **Strong typing** throughout with enums and structs
5. **Async/await** patterns for all I/O operations

### Potential Issues Identified
1. `createVoiceConversation` incomplete implementation
2. Custom privacy/routing modes not implemented
3. Some overlap between `SDKError` and `RunAnywhereError`
4. Large event types file could be split
5. `EmbeddingInitParameters` potentially unused

---
*This document is part of the RunAnywhere Swift SDK current-state documentation.*
