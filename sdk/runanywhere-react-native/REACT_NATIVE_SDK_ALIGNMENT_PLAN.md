# React Native SDK Alignment Plan
**iOS SDK as Source of Truth**

**Date:** 2025-01-21  
**Purpose:** Comprehensive plan to align React Native SDK structure exactly with iOS SDK

---

## Executive Summary

The React Native SDK must follow the **exact same structure** as the iOS Swift SDK. This document maps every module, file, and pattern from iOS to React Native.

**Key Principle:** iOS SDK is the source of truth. React Native SDK should be a TypeScript translation maintaining exact architectural patterns.

---

## Current State Analysis

### iOS SDK Structure (Source of Truth)
```
Sources/RunAnywhere/
├── Core/                    ✅ Complete
│   ├── Components/          ✅ BaseComponent.swift
│   ├── Protocols/           ✅ All protocols defined
│   ├── Models/              ✅ Configuration, Model, Framework models
│   ├── Initialization/      ✅ ComponentInitializer
│   ├── ServiceRegistry/     ✅ AdapterRegistry
│   ├── ModuleRegistry.swift ✅ Plugin system
│   └── Types/               ✅ TelemetryEventType
│
├── Components/              ✅ Complete (8 components)
│   ├── STT/                 ✅
│   ├── TTS/                 ✅
│   ├── LLM/                 ✅
│   ├── VAD/                 ✅
│   ├── VoiceAgent/          ✅
│   ├── WakeWord/            ✅
│   ├── SpeakerDiarization/  ✅
│   └── VLM/                 ✅
│
├── Capabilities/            ✅ Complete
│   ├── TextGeneration/      ✅
│   ├── Voice/               ✅
│   ├── Memory/              ✅
│   ├── ModelLoading/        ✅
│   ├── Registry/            ✅
│   ├── Routing/             ✅
│   ├── DeviceCapability/    ✅
│   ├── StructuredOutput/   ✅
│   └── Analytics/          ✅
│
├── Data/                    ✅ Complete
│   ├── Network/             ✅
│   ├── Storage/             ✅
│   ├── Repositories/        ✅
│   ├── DataSources/         ✅
│   ├── Services/            ✅
│   ├── Sync/                ✅
│   └── Models/              ✅
│
├── Foundation/              ✅ Complete
│   ├── DependencyInjection/ ✅ ServiceContainer
│   ├── Logging/             ✅
│   ├── Analytics/           ✅
│   ├── Security/            ✅ KeychainManager
│   ├── DeviceIdentity/      ✅
│   ├── Configuration/       ✅
│   ├── ErrorTypes/          ✅
│   ├── Context/             ✅
│   └── FileOperations/      ✅
│
├── Public/                  ✅ Complete
│   ├── RunAnywhere.swift    ✅ Main entry
│   ├── Extensions/          ✅
│   ├── Events/              ✅ EventBus
│   ├── Models/              ✅
│   ├── Configuration/       ✅
│   ├── Errors/              ✅
│   ├── StructuredOutput/    ✅
│   └── Utilities/           ✅
│
└── Infrastructure/          ✅ Complete
    └── Voice/Platform/      ✅ iOSAudioSession
```

### React Native SDK Current Structure
```
src/
├── components/              ⚠️ Partial (4/8 components)
│   ├── BaseComponent.ts     ✅
│   ├── STT/                 ✅
│   ├── TTS/                 ✅
│   ├── LLM/                 ✅
│   ├── VAD/                 ✅
│   ├── VoiceAgent/          ❌ Missing
│   ├── WakeWord/            ❌ Missing
│   ├── SpeakerDiarization/  ❌ Missing
│   └── VLM/                 ❌ Missing
│
├── services/                ⚠️ Partial (4 services)
│   ├── AuthenticationService.ts ✅
│   ├── ConfigurationService.ts  ✅
│   ├── DownloadService.ts       ✅
│   └── ModelRegistry.ts         ✅
│
├── errors/                  ✅
├── events/                  ✅
├── types/                   ⚠️ Needs expansion
├── helpers/                 ⚠️ Should be in Public/Utilities
├── native/                  ✅
└── RunAnywhere.ts           ⚠️ Should be in Public/
```

**Missing:**
- ❌ Core/ folder structure
- ❌ Capabilities/ folder
- ❌ Data/ folder structure
- ❌ Foundation/ folder structure
- ❌ Public/ folder structure
- ❌ Infrastructure/ folder
- ❌ 4 Components (VoiceAgent, WakeWord, SpeakerDiarization, VLM)
- ❌ All Capabilities modules
- ❌ Complete Data layer
- ❌ Complete Foundation services

---

## Alignment Plan

### Phase 1: Restructure Folders (Match iOS Exactly)

#### 1.1 Create Core Folder Structure
```
src/
├── Core/
│   ├── Components/
│   │   └── BaseComponent.ts (move from components/)
│   ├── Protocols/
│   │   ├── Component/
│   │   │   └── Component.ts
│   │   ├── Analytics/
│   │   │   └── AnalyticsProtocol.ts
│   │   ├── Configuration/
│   │   │   └── ComponentConfiguration.ts
│   │   ├── Downloading/
│   │   │   ├── DownloadProtocol.ts
│   │   │   └── ModelDownloadProtocol.ts
│   │   ├── Frameworks/
│   │   │   └── FrameworkAdapter.ts
│   │   ├── Hardware/
│   │   │   └── HardwareDetector.ts
│   │   ├── Lifecycle/
│   │   │   ├── LifecycleManaged.ts
│   │   │   └── ModelBasedComponent.ts
│   │   ├── Memory/
│   │   │   └── MemoryManager.ts
│   │   ├── Registry/
│   │   │   └── ModelRegistry.ts
│   │   ├── Storage/
│   │   │   ├── FileStorage.ts
│   │   │   ├── ModelStorage.ts
│   │   │   └── StorageAnalyzer.ts
│   │   └── Voice/
│   │       └── VoiceService.ts
│   ├── Models/
│   │   ├── Common/
│   │   │   ├── ComponentState.ts
│   │   │   ├── SDKComponent.ts
│   │   │   └── TelemetryEventType.ts
│   │   ├── Configuration/
│   │   │   ├── ComponentConfiguration.ts
│   │   │   ├── ComponentInitParameters.ts
│   │   │   ├── ModelConfiguration.ts
│   │   │   ├── STTConfiguration.ts
│   │   │   ├── TTSConfiguration.ts
│   │   │   └── LLMConfiguration.ts
│   │   ├── Framework/
│   │   │   ├── FrameworkType.ts
│   │   │   ├── ModelFramework.ts
│   │   │   └── AdapterRegistration.ts
│   │   └── Model/
│   │       ├── ModelInfo.ts
│   │       ├── ModelMetadata.ts
│   │       ├── ModelStatus.ts
│   │       └── ModelLifecycle.ts
│   ├── Initialization/
│   │   ├── ComponentInitializer.ts
│   │   └── UnifiedComponentInitializer.ts
│   ├── ServiceRegistry/
│   │   ├── AdapterSelectionStrategy.ts
│   │   └── UnifiedServiceRegistry.ts
│   ├── ModuleRegistry.ts
│   └── Types/
│       └── TelemetryEventType.ts
```

#### 1.2 Create Components Folder (Move & Expand)
```
src/
├── Components/
│   ├── STT/
│   │   └── STTComponent.ts (move from components/)
│   ├── TTS/
│   │   └── TTSComponent.ts (move from components/)
│   ├── LLM/
│   │   └── LLMComponent.ts (move from components/)
│   ├── VAD/
│   │   └── VADComponent.ts (move from components/)
│   ├── VoiceAgent/
│   │   └── VoiceAgentComponent.ts (NEW)
│   ├── WakeWord/
│   │   └── WakeWordComponent.ts (NEW)
│   ├── SpeakerDiarization/
│   │   └── SpeakerDiarizationComponent.ts (NEW)
│   └── VLM/
│       └── VLMComponent.ts (NEW)
```

#### 1.3 Create Capabilities Folder
```
src/
├── Capabilities/
│   ├── TextGeneration/
│   │   ├── Models/
│   │   │   ├── GenerationOptions.ts
│   │   │   └── GenerationResult.ts
│   │   └── Services/
│   │       ├── GenerationService.ts
│   │       ├── StreamingService.ts
│   │       └── StructuredOutputService.ts
│   ├── Voice/
│   │   ├── Models/
│   │   │   └── VoicePipelineState.ts
│   │   ├── Handlers/
│   │   │   ├── AudioHandler.ts
│   │   │   ├── STTHandler.ts
│   │   │   ├── LLMHandler.ts
│   │   │   ├── TTSHandler.ts
│   │   │   └── VADHandler.ts
│   │   ├── Operations/
│   │   │   └── VoiceOperation.ts
│   │   ├── Services/
│   │   │   ├── VoiceCapabilityService.ts
│   │   │   ├── VoicePipelineService.ts
│   │   │   └── VoiceAgentService.ts
│   │   └── Strategies/
│   │       ├── VoiceStrategy.ts
│   │       └── PipelineStrategy.ts
│   ├── Memory/
│   │   ├── Models/
│   │   │   └── MemoryUsage.ts
│   │   └── Services/
│   │       ├── MemoryManager.ts
│   │       ├── MemoryMonitor.ts
│   │       └── MemoryService.ts
│   ├── ModelLoading/
│   │   ├── Models/
│   │   │   └── ModelLoadResult.ts
│   │   └── Services/
│   │       └── ModelLoadingService.ts
│   ├── Registry/
│   │   ├── Services/
│   │   │   ├── RegistryService.ts
│   │   │   └── ModelRegistryService.ts
│   │   └── Storage/
│   │       ├── ModelStorage.ts
│   │       └── RegistryStorage.ts
│   ├── Routing/
│   │   ├── Models/
│   │   │   ├── RoutingDecision.ts
│   │   │   ├── ExecutionTarget.ts
│   │   │   └── RoutingPolicy.ts
│   │   └── Services/
│   │       └── RoutingService.ts
│   ├── DeviceCapability/
│   │   ├── Models/
│   │   │   ├── DeviceCapabilities.ts
│   │   │   ├── HardwareInfo.ts
│   │   │   └── PlatformInfo.ts
│   │   └── Services/
│   │       ├── DeviceCapabilityService.ts
│   │       └── HardwareDetector.ts
│   ├── StructuredOutput/
│   │   └── Services/
│   │       └── StructuredOutputService.ts
│   └── Analytics/
│       ├── Generation/
│       │   └── GenerationAnalyticsService.ts
│       ├── STT/
│       │   └── STTAnalyticsService.ts
│       ├── TTS/
│       │   └── TTSAnalyticsService.ts
│       └── Voice/
│           └── VoiceAnalyticsService.ts
```

#### 1.4 Create Data Folder
```
src/
├── Data/
│   ├── Network/
│   │   ├── Models/
│   │   │   ├── AuthModels.ts
│   │   │   ├── DeviceInfoModels.ts
│   │   │   ├── ModelInfoModels.ts
│   │   │   └── TelemetryModels.ts
│   │   ├── Protocols/
│   │   │   └── NetworkService.ts
│   │   └── Services/
│   │       ├── APIClient.ts
│   │       ├── AuthenticationService.ts (move from services/)
│   │       └── NetworkServiceFactory.ts
│   ├── Storage/
│   │   ├── Analysis/
│   │   │   └── StorageAnalyzer.ts
│   │   ├── Database/
│   │   │   ├── DatabaseManager.ts
│   │   │   └── Models.ts
│   │   └── FileSystem/
│   │       └── FileStorage.ts
│   ├── Repositories/
│   │   ├── ConfigurationRepository.ts
│   │   ├── DeviceInfoRepository.ts
│   │   ├── ModelInfoRepository.ts
│   │   └── TelemetryRepository.ts
│   ├── DataSources/
│   │   ├── Configuration/
│   │   │   ├── LocalConfigurationDataSource.ts
│   │   │   └── RemoteConfigurationDataSource.ts
│   │   ├── DeviceInfo/
│   │   │   ├── LocalDeviceInfoDataSource.ts
│   │   │   └── RemoteDeviceInfoDataSource.ts
│   │   ├── ModelInfo/
│   │   │   ├── LocalModelInfoDataSource.ts
│   │   │   └── RemoteModelInfoDataSource.ts
│   │   └── Telemetry/
│   │       ├── LocalTelemetryDataSource.ts
│   │       └── RemoteTelemetryDataSource.ts
│   ├── Services/
│   │   ├── ConfigurationService.ts (move from services/)
│   │   ├── DeviceInfoService.ts
│   │   ├── ModelAssignmentService.ts
│   │   ├── ModelInfoService.ts
│   │   └── TelemetryService.ts
│   ├── Sync/
│   │   └── SyncCoordinator.ts
│   └── Models/
│       ├── DeviceInfoData.ts
│       ├── Downloading/
│       │   ├── DownloadProgress.ts
│       │   ├── DownloadRequest.ts
│       │   └── DownloadResult.ts
│       ├── DTOs/
│       │   └── DataTransferObjects.ts
│       ├── Entities/
│       │   ├── ModelEntity.ts
│       │   └── DeviceEntity.ts
│       └── Storage/
│           ├── FileMetadata.ts
│           └── StorageInfo.ts
```

#### 1.5 Create Foundation Folder
```
src/
├── Foundation/
│   ├── DependencyInjection/
│   │   ├── ServiceContainer.ts
│   │   ├── AdapterRegistry.ts
│   │   └── ServiceLifecycle.ts
│   ├── Logging/
│   │   ├── Logger/
│   │   │   └── SDKLogger.ts
│   │   ├── Models/
│   │   │   ├── LogLevel.ts
│   │   │   └── LogEntry.ts
│   │   ├── Protocols/
│   │   │   └── LoggerProtocol.ts
│   │   └── Services/
│   │       ├── ConsoleLogger.ts
│   │       └── FileLogger.ts
│   ├── Analytics/
│   │   ├── AnalyticsQueueManager.ts
│   │   └── Models/
│   │       ├── AnalyticsEvent.ts
│   │       └── TelemetryDeviceInfo.ts
│   ├── Security/
│   │   └── KeychainManager.ts (React Native SecureStore)
│   ├── DeviceIdentity/
│   │   ├── DeviceManager.ts
│   │   └── PersistentDeviceIdentity.ts
│   ├── Configuration/
│   │   └── RunAnywhereConstants.ts
│   ├── Constants/
│   │   ├── BuildToken.ts
│   │   ├── ErrorCodes.ts
│   │   └── SDKConstants.ts
│   ├── ErrorTypes/
│   │   ├── ErrorType.ts
│   │   ├── FrameworkError.ts
│   │   └── UnifiedModelError.ts
│   ├── Context/
│   │   └── RunAnywhereScope.ts
│   └── FileOperations/
│       └── ArchiveUtility.ts
```

#### 1.6 Create Public Folder
```
src/
├── Public/
│   ├── RunAnywhere.ts (move from root)
│   ├── Extensions/
│   │   ├── RunAnywhere+Components.ts
│   │   ├── RunAnywhere+Pipelines.ts
│   │   └── RunAnywhere+Utilities.ts
│   ├── Events/
│   │   ├── EventBus.ts (move from events/)
│   │   └── SDKEvent.ts
│   ├── Models/
│   │   ├── GenerationResult.ts
│   │   ├── STTResult.ts
│   │   ├── TTSResult.ts
│   │   └── ModelInfo.ts
│   ├── Configuration/
│   │   ├── PrivacyMode.ts
│   │   ├── RoutingPolicy.ts
│   │   └── SDKEnvironment.ts
│   ├── Errors/
│   │   ├── RunAnywhereError.ts
│   │   └── SDKError.ts (move from errors/)
│   ├── StructuredOutput/
│   │   └── Generatable.ts
│   └── Utilities/
│       └── AudioCapture.ts
```

#### 1.7 Create Infrastructure Folder
```
src/
├── Infrastructure/
│   └── Voice/
│       └── Platform/
│           ├── ReactNativeAudioSession.ts
│           └── AudioSessionAdapter.ts
```

### Phase 2: Implement Missing Components

#### 2.1 VoiceAgentComponent
- Reference: `sdk/runanywhere-swift/Sources/RunAnywhere/Components/VoiceAgent/VoiceAgentComponent.swift`
- Features: Complete voice pipeline orchestration (VAD → STT → LLM → TTS)
- Implementation: TypeScript class extending BaseComponent

#### 2.2 WakeWordComponent
- Reference: `sdk/runanywhere-swift/Sources/RunAnywhere/Components/WakeWord/WakeWordComponent.swift`
- Features: Wake word detection
- Implementation: TypeScript class extending BaseComponent

#### 2.3 SpeakerDiarizationComponent
- Reference: `sdk/runanywhere-swift/Sources/RunAnywhere/Components/SpeakerDiarization/SpeakerDiarizationComponent.swift`
- Features: Multi-speaker identification
- Implementation: TypeScript class extending BaseComponent

#### 2.4 VLMComponent
- Reference: `sdk/runanywhere-swift/Sources/RunAnywhere/Components/VLM/VLMComponent.swift`
- Features: Vision-language model inference
- Implementation: TypeScript class extending BaseComponent

### Phase 3: Implement Missing Capabilities

All capabilities must match iOS SDK exactly:
1. TextGeneration - GenerationService, StreamingService
2. Voice - VoiceCapabilityService, VoicePipelineService
3. Memory - MemoryManager, MemoryMonitor
4. ModelLoading - ModelLoadingService
5. Registry - RegistryService
6. Routing - RoutingService
7. DeviceCapability - DeviceCapabilityService
8. StructuredOutput - StructuredOutputService
9. Analytics - All analytics services

### Phase 4: Implement Missing Data Layer

1. Network - Complete APIClient, NetworkServiceFactory
2. Storage - DatabaseManager, FileStorage
3. Repositories - All repository implementations
4. DataSources - Local and remote data sources
5. Services - All data services
6. Sync - SyncCoordinator

### Phase 5: Implement Missing Foundation Services

1. DependencyInjection - ServiceContainer (critical)
2. Logging - Complete logging system
3. Analytics - AnalyticsQueueManager
4. Security - KeychainManager (using React Native SecureStore)
5. DeviceIdentity - DeviceManager, PersistentDeviceIdentity
6. Configuration - Constants
7. ErrorTypes - All error types
8. Context - RunAnywhereScope
9. FileOperations - ArchiveUtility

### Phase 6: Update Public API

1. Move RunAnywhere.ts to Public/
2. Create Extensions (Components, Pipelines, Utilities)
3. Organize Events properly
4. Organize Models properly
5. Organize Configuration properly
6. Organize Errors properly
7. Add StructuredOutput
8. Add Utilities

### Phase 7: Update Sample App Structure

Match iOS sample app exactly:
```
src/
├── App/
│   ├── App.tsx (main entry)
│   └── AppState.tsx
├── Core/
│   ├── DesignSystem/
│   │   ├── AppColors.ts
│   │   ├── AppSpacing.ts
│   │   └── Typography.ts
│   ├── Models/
│   │   └── AppTypes.ts
│   ├── Services/
│   │   ├── ConversationStore.ts
│   │   ├── DeviceInfoService.ts
│   │   ├── KeychainService.ts
│   │   └── ModelManager.ts
│   └── Utilities/
│       └── Constants.ts
├── Features/
│   ├── Chat/
│   │   ├── ChatInterfaceView.tsx
│   │   └── ChatViewModel.ts
│   ├── Models/
│   │   ├── AddModelFromURLView.tsx
│   │   ├── ModelComponents.tsx
│   │   ├── ModelListViewModel.ts
│   │   ├── ModelSelectionSheet.tsx
│   │   ├── ModelStatusComponents.tsx
│   │   └── SimplifiedModelsView.tsx
│   ├── Quiz/
│   │   ├── GenerationProgressView.tsx
│   │   ├── QuizCardView.tsx
│   │   ├── QuizInputView.tsx
│   │   ├── QuizResultsView.tsx
│   │   ├── QuizSwipeView.tsx
│   │   ├── QuizView.tsx
│   │   └── QuizViewModel.ts
│   ├── Settings/
│   │   └── CombinedSettingsView.tsx
│   ├── Storage/
│   │   ├── StorageView.tsx
│   │   └── StorageViewModel.ts
│   └── Voice/
│       ├── FluidAudioIntegration.tsx
│       ├── SpeechToTextView.tsx
│       ├── TextToSpeechView.tsx
│       ├── TranscriptionView.tsx
│       ├── TranscriptionViewModel.ts
│       ├── VoiceAssistantView.tsx
│       └── VoiceAssistantViewModel.ts
└── Helpers/
    └── AdaptiveLayout.ts
```

---

## Implementation Order

1. **Phase 1**: Restructure folders (create all folders, move existing files)
2. **Phase 2**: Implement missing Components (4 components)
3. **Phase 3**: Implement missing Capabilities (9 capability modules)
4. **Phase 4**: Implement missing Data layer (complete data infrastructure)
5. **Phase 5**: Implement missing Foundation services (complete foundation)
6. **Phase 6**: Update Public API (organize public surface)
7. **Phase 7**: Update Sample App (match iOS sample app structure)

---

## Translation Patterns

### Swift → TypeScript

1. **Protocol → Interface**
   ```swift
   protocol STTService {
       func transcribe(...) async throws -> STTResult
   }
   ```
   ```typescript
   interface STTService {
       transcribe(...): Promise<STTResult>;
   }
   ```

2. **async/await → Promise**
   - Swift async/await → TypeScript Promise
   - Swift throws → TypeScript throws Error

3. **Struct → Interface/Type**
   ```swift
   struct STTConfiguration {
       let modelId: String?
   }
   ```
   ```typescript
   interface STTConfiguration {
       modelId?: string;
   }
   ```

4. **Enum → Enum/Union Type**
   ```swift
   enum ComponentState {
       case notInitialized
   }
   ```
   ```typescript
   enum ComponentState {
       NotInitialized = 'not_initialized'
   }
   ```

5. **Class → Class**
   - Swift classes → TypeScript classes
   - Maintain same inheritance patterns

---

## Success Criteria

✅ All folders match iOS SDK structure exactly  
✅ All 8 Components implemented  
✅ All 9 Capabilities implemented  
✅ Complete Data layer implemented  
✅ Complete Foundation services implemented  
✅ Public API matches iOS SDK  
✅ Sample app matches iOS sample app structure  
✅ All TypeScript code follows iOS patterns exactly  

---

## Next Steps

1. Create this plan document ✅
2. Start Phase 1: Restructure folders
3. Continue with remaining phases systematically

