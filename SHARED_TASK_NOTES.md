# KMP SDK Hygiene Enforcement - Shared Task Notes

## Current Status: ITERATION 43 COMPLETE

**Last Updated**: 2025-12-20
**Current Phase**: Iteration 43 - Delete ModelLoadingService.kt (false iOS parity claim)
**Build Status**: PASSING (JVM compiles, detekt and ktlint pass)
**Detekt Issues**: 0
**ktlint Issues**: 0

## Build Commands
```bash
cd sdk/runanywhere-kotlin
./gradlew compileKotlinJvm    # Compile JVM target
./gradlew detekt              # Run detekt
./gradlew ktlintCheck         # Run ktlint
```

## What Was Done This Iteration (Iteration 43)

### Deleted ModelLoadingService.kt (~172 lines)

**iOS Truth (verified via LLMCapability.swift, ManagedLifecycle.swift, CapabilityProtocols.swift)**:
- iOS has NO `ModelLoadingService` class
- iOS model loading goes through `LLMCapability.loadModel()` which delegates to `ManagedLifecycle`
- iOS tracks model state via `LLMCapability.isModelLoaded` and `LLMCapability.currentModelId`

**Deleted:**
- `models/ModelLoadingService.kt` (~172 lines) - False parity claim ("EXACT copy of iOS ModelLoadingService" - doesn't exist)
- Also removed `LoadedModelWithService` data class that was only used by ModelLoadingService

**Updated files:**
- `ServiceContainer.kt` - Removed `modelLoadingService` lazy property and import
- `RunAnywhere+ModelManagement.kt` - Updated to use `LLMCapability.loadModel()` and `LLMCapability.unload()` instead
- `ModelManagementExtensions.kt` - Updated to use `LLMCapability` instead of `ModelLoadingService`
- Removed false "EXACT copy" claims from comments

### Build Verification
- JVM compilation: PASSING
- Detekt: 0 issues
- ktlint: 0 issues

## Next Iteration Focus: Iteration 44

### Potential Tasks (Ordered by Impact)
1. **models/GenerationResult.kt** - Check if this duplicates `features/llm/LLMCapability.LLMGenerationResult`
2. **models/ directory structure** - Review remaining 19 files for proper organization per iOS patterns
3. **DeviceInfo models** - Consider moving to `infrastructure/device/models/`

### Lower Priority
- Review `data/config/` for any unused code
- Review any remaining deprecated symbols

## Deletions Summary (All Iterations)

| Iteration | Deleted Items |
|-----------|---------------|
| 11 | `data/network/services/MockNetworkService.kt`, `services/deviceinfo/`, `network/AuthenticationService.kt`, `capabilities/device/` |
| 12 | `data/repository/`, `files/`, `audio/` (all platforms) |
| 13 | `data/models/ConfigurationModels.LLMFramework` enum |
| 14 | None (parity updates) |
| 15 | `models/ModelFormat.kt`, `storage/`, `routing/`, `pipeline/`, duplicate SecureStorageImpl classes |
| 16 | `models/GenerationResult.kt:LLMGenerationResult`, `LLMOutput.toGenerationResult()`, Fixed WhisperKit |
| 17 | `RunAnywhereGenerationOptions` typealias, duplicate `LLMGenerationOptions`, shadowing extension properties |
| 18 | VLM/WakeWord interfaces & code, SimpleDownloadService, 15+ unused private members/properties/functions |
| 19 | 60+ unused imports fixed, `voiceAnalytics` parameter, `processingTime` variable |
| 20 | OptionalUnit fixes (JvmDownloadImpl, LlamaCppCoreService) |
| 21 | `NetworkServiceImpl.kt`, duplicate `SpeakerDiarizationService` interface, duplicate `SpeakerInfo` class, duplicate `SpeakerDiarizationServiceProvider` |
| 22 | `APIClient.kt` (~600 lines), `STTAnalyticsService.kt` (~400 lines), `WhisperModelService.kt` (~360 lines), 2x `FileWriter.kt` |
| 23 | `network/NetworkService.kt`, `ThinkingParser.kt`, `ThinkingTagPattern.kt`, `StructuredOutputHandler.kt`, `TokenCounter.kt`, `EventCorrelation.kt`, `EventPersistence.kt`, dead code in `StreamingService.kt` |
| 24 | `core/ComponentAdapter.kt`, `core/ServiceWrapper.kt`, `voice/handlers/VADHandler.kt`, moved `SimpleEnergyVAD.kt` to `features/vad/` |
| 25 | Documentation refresh only (no code changes) |
| 26 | `network/` directory (5 files moved to data/network/), `jvmMain/network/JvmNetworkChecker.kt`, `androidMain/network/AndroidNetworkChecker.kt` |
| 27 | `services/AuthenticationService.kt` (moved to data/network/) |
| 28 | 3x duplicate `DeviceRegistrationResponse` classes consolidated to `data/network/models/AuthModels.kt` |
| 29 | Moved `DeviceRegistrationService` (3 files) from `services/` to `infrastructure/device/services/` |
| 30 | Moved `DeviceIdentity` (3 files) from `foundation/` to `infrastructure/device/services/` |
| 31 | Moved `events/` (4 files) to `infrastructure/events/` |
| 32 | Moved `services/download/` (5 files) to `infrastructure/download/`, deleted unused `models/download/DownloadProgress.kt` |
| 33 | Moved `services/analytics/` and `foundation/analytics/` (2 files) to `infrastructure/analytics/`, renamed `AnalyticsEvent` sealed class to `SDKAnalyticsEvent` |
| 34 | Moved `services/modelinfo/ModelInfoService.kt` to `infrastructure/modelmanagement/services/` |
| 35 | Moved `services/sync/SyncCoordinator.kt` to `data/sync/` |
| 36 | Deleted `services/Services.kt` (3 unused duplicate stub classes: ConfigurationService, MemoryService, AnalyticsService) |
| 37 | Moved `services/telemetry/TelemetryService.kt` to `infrastructure/analytics/TelemetryService.kt` |
| 38 | **DELETED ENTIRE services/ DIRECTORY**: ConfigurationService.kt, ConfigurationServiceProtocol.kt, ValidationService.kt (~620 lines of unused code claiming false iOS parity); also deleted orphaned MD5Service.kt (jvmAndroidMain) and NativeMD5.kt (nativeMain) |
| 39 | **DELETED ENTIRE memory/ DIRECTORY**: MemoryService.kt, MemoryMonitor.kt (expect+2 actuals), PressureHandler.kt, CacheEviction.kt, AllocationManager.kt (~400+ lines); iOS has NO memory management layer |
| 40 | **DELETED models/lifecycle/ DIRECTORY**: ModelLifecycleManager.kt (~370 lines - deprecated legacy lifecycle code); **REMOVED deprecated aliases**: LLAMACPP enum value, LLMFramework typealias, PersistentDeviceIdentity typealias |
| 41 | **DELETED SDKEventType**: Removed deprecated `SDKEventType` enum (~30 lines) and `SDKEvent.eventType` extension property (~20 lines) from `infrastructure/events/SDKEvent.kt`; iOS has no equivalent (uses EventCategory only) |
| 42 | **DELETED ENTIRE generation/ DIRECTORY**: GenerationService.kt (~350 lines), StreamingService.kt (~200 lines), GenerationOptionsResolver.kt (~100 lines) - ~650 lines total; also removed `toGenerationOptions()` method from GenerationOptions.kt; iOS has NO GenerationService |
| 43 | **DELETED ModelLoadingService.kt** (~172 lines) - False parity claim; iOS has no ModelLoadingService. Model loading handled by LLMCapability/ManagedLifecycle. Updated RunAnywhere+ModelManagement.kt and ModelManagementExtensions.kt to use LLMCapability. |

## Parity Rules

1. iOS is Source of Truth
2. Single type definitions - no duplicates
3. Delete rather than keep "just in case"
4. commonMain for all logic
5. `security/` package is canonical for SecureStorage
6. `models/LLMGenerationOptions` is canonical for generation options
7. `features/llm/LLMCapability.kt` contains canonical `LLMGenerationResult`
8. `features/speakerdiarization/SpeakerInfo` is canonical for speaker info
9. `core/ModuleRegistry.SpeakerDiarizationServiceProvider` is canonical for speaker diarization providers
10. `data/network/NetworkCheckerInterface.kt` is canonical for NetworkChecker interface (matching iOS Data/Network/)
11. `data/network/NetworkService.kt` is canonical for NetworkService interface
12. `features/vad/SimpleEnergyVAD.kt` is canonical for SimpleEnergyVAD (matches iOS Features/VAD/Services/)
13. `data/network/` contains ALL network-related code (matching iOS Data/Network/)
14. `data/network/AuthenticationService.kt` is canonical for auth (matching iOS Data/Network/Services/)
15. `data/network/models/AuthModels.kt:DeviceRegistrationResponse` is canonical (matching iOS Infrastructure/Device/Models/Network/)
16. `infrastructure/device/services/DeviceRegistrationService.kt` is canonical for device registration (matching iOS Infrastructure/Device/Services/)
17. `infrastructure/device/services/DeviceIdentity.kt` is canonical for device identity (matching iOS Infrastructure/Device/Services/)
18. `infrastructure/events/` contains ALL event-related code (matching iOS Infrastructure/Events/)
19. `infrastructure/download/` contains ALL download-related code (matching iOS Infrastructure/Download/)
20. `infrastructure/analytics/` contains ALL analytics-related code (matching iOS Infrastructure/Analytics/)
21. `infrastructure/modelmanagement/services/ModelInfoService.kt` is canonical for model info (matching iOS Infrastructure/ModelManagement/Services/)
22. `data/sync/SyncCoordinator.kt` is canonical for sync coordination (matching iOS Data/Sync/)
23. `infrastructure/analytics/TelemetryService.kt` is canonical for telemetry (matching iOS Infrastructure/Analytics/)
24. **NO services/ directory** - iOS has no equivalent top-level services/ package
25. **NO memory/ directory** - iOS has no memory management layer
26. **NO models/lifecycle/ directory** - Use `core/capabilities/ModelLifecycleManager.kt` instead (matches iOS)
27. **Use LLAMA_CPP not LLAMACPP** - Deprecated alias removed
28. **Use EventCategory not SDKEventType** - Deprecated SDKEventType enum removed
29. **NO generation/ directory** - iOS has no GenerationService; model lifecycle handled by LLMCapability/ManagedLifecycle
30. **NO ModelLoadingService** - iOS has no ModelLoadingService; model loading done via LLMCapability.loadModel()

## Current File Counts

| Package | Files | Status |
|---------|-------|--------|
| public/ | 12 | Aligned |
| core/ | 9 | Aligned |
| features/ | 31 | Aligned |
| data/ | 40 | Aligned (+1 SyncCoordinator) |
| foundation/ | 11 | Aligned |
| infrastructure/device/ | 4 | Aligned with iOS |
| infrastructure/events/ | 4 | Aligned with iOS |
| infrastructure/download/ | 5 | Aligned with iOS |
| infrastructure/analytics/ | 3 | Aligned with iOS (+1 TelemetryService) |
| infrastructure/modelmanagement/ | 1 | Aligned with iOS |
| models/ | 19 | Review (-1 ModelLoadingService) |
| native/ | 3 | Keep |
| **Total commonMain** | ~150 | |

## Current KMP Data/Sync Structure

```
data/
├── sync/              # Sync services (matches iOS)
│   └── SyncCoordinator.kt
├── cache/             # Cache layer
├── config/            # Configuration (ConfigurationLoader.kt)
├── datasources/       # Data sources
├── models/            # Data models
├── network/           # Network services
│   ├── models/
│   └── services/
└── repositories/      # Repository implementations
```

## Current KMP Infrastructure Structure

```
infrastructure/
├── analytics/           # Analytics services (matches iOS)
│   ├── AnalyticsQueueManager.kt
│   ├── AnalyticsService.kt
│   └── TelemetryService.kt
├── device/             # Device services
│   └── services/
│       ├── DeviceIdentity.kt
│       └── DeviceRegistrationService.kt
├── download/           # Download services
│   ├── DownloadService.kt
│   └── WhisperKitDownloadStrategy.kt
├── events/             # Event handling
│   ├── EventBus.kt
│   ├── EventPublisher.kt
│   ├── SDKEvent.kt
│   └── STTEvents.kt
└── modelmanagement/    # Model management (matches iOS)
    └── services/
        └── ModelInfoService.kt
```

## Tooling

**Detekt** (v1.23.7):
```bash
./gradlew detekt
```

**ktlint** (v12.1.2 plugin, v1.5.0 engine):
```bash
./gradlew ktlintCheck     # Check for violations
./gradlew ktlintFormat    # Auto-fix violations
```

Both tools run clean with 0 issues.
