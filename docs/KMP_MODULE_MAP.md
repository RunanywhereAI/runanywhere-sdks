# KMP SDK Module Map

> This document maps the target module structure for the Kotlin Multiplatform SDK.

## Module Overview

```
runanywhere-kotlin (main SDK)
├── Core SDK (commonMain)
│   └── All business logic, interfaces, and capabilities
│
├── Platform Implementations
│   ├── jvmMain        - JVM/Desktop specifics
│   ├── androidMain    - Android specifics
│   └── nativeMain     - iOS/Native specifics (future)
│
└── External Modules
    ├── runanywhere-core-llamacpp   - LlamaCPP integration
    ├── runanywhere-core-onnx       - ONNX Runtime integration
    ├── runanywhere-whisperkit      - WhisperKit STT
    └── runanywhere-llm-mlc         - MLC LLM integration
```

---

## Package → Responsibility Mapping

### `com.runanywhere.sdk.public`

| Package | Responsibility | Key Types |
|---------|----------------|-----------|
| `public/` | Main entry point | `RunAnywhere` |
| `public/configuration/` | SDK configuration | `SDKEnvironment`, `SDKInitParams` |
| `public/errors/` | Public error types | `RunAnywhereError` |
| `public/events/` | Public event bus | `EventBus` |
| `public/extensions/` | Feature APIs | `RunAnywhere+STT`, `RunAnywhere+LLM`, etc. |

### `com.runanywhere.sdk.core`

| Package | Responsibility | Key Types |
|---------|----------------|-----------|
| `core/module/` | Module registration | `ModuleRegistry`, `RunAnywhereModule`, `ModuleMetadata` |
| `core/` | Service registration | `ServiceRegistry`, `ServiceRegistration` |
| `core/types/` | Component types | `ComponentTypes`, `AudioTypes` |
| `core/capabilities/` | Capability protocols | `Capability`, `ModelLoadableCapability`, `ServiceBasedCapability` |

### `com.runanywhere.sdk.foundation`

| Package | Responsibility | Key Types |
|---------|----------------|-----------|
| `foundation/di/` | Dependency injection | `ServiceContainer` |
| `foundation/constants/` | SDK constants | `SDKConstants` |
| `foundation/errors/` | Internal errors | `SDKError`, `ErrorCategory` |
| `foundation/security/` | Secure storage | `SecureStorage`, `KeychainManager` |
| `foundation/utilities/` | Common utilities | `TimeUtils`, `NetworkRetry` |

### `com.runanywhere.sdk.infrastructure`

| Package | Responsibility | Key Types |
|---------|----------------|-----------|
| `infrastructure/events/` | Event system | `SDKEvent`, `EventPublisher` |
| `infrastructure/logging/` | Logging | `SDKLogger`, `LogLevel`, `LogDestination` |
| `infrastructure/analytics/` | Telemetry | `AnalyticsService`, `TelemetryRepository`, `AnalyticsQueueManager` |
| `infrastructure/download/` | File download | `DownloadService`, `DownloadProgress`, `DownloadState` |
| `infrastructure/filemanagement/` | File operations | `FileManager`, `StorageAnalyzer` |
| `infrastructure/device/` | Device info | `DeviceInfo`, `DeviceIdentity`, `DeviceRegistrationService` |
| `infrastructure/modelmanagement/` | Model lifecycle | `ModelInfo`, `ModelRegistry`, `ModelInfoService`, `InferenceFramework` |

### `com.runanywhere.sdk.data`

| Package | Responsibility | Key Types |
|---------|----------------|-----------|
| `data/network/` | Network layer | `APIClient`, `NetworkService`, `AuthenticationService` |
| `data/storage/` | Local storage | `DatabaseManager` |
| `data/protocols/` | Data protocols | `Repository`, `DataSource` |

### `com.runanywhere.sdk.features`

| Package | Responsibility | Key Types |
|---------|----------------|-----------|
| `features/stt/` | Speech-to-text | `STTCapability`, `STTService`, `STTConfiguration`, `STTOutput` |
| `features/tts/` | Text-to-speech | `TTSCapability`, `TTSService`, `TTSConfiguration`, `TTSOutput` |
| `features/llm/` | Language models | `LLMCapability`, `LLMService`, `LLMConfiguration`, `LLMGenerationResult` |
| `features/vad/` | Voice activity | `VADCapability`, `VADService`, `VADConfiguration`, `VADOutput` |
| `features/speakerdiarization/` | Speaker ID | `SpeakerDiarizationCapability`, `SpeakerDiarizationService` |
| `features/voiceagent/` | Voice pipeline | `VoiceAgentCapability`, `VoiceAgentConfiguration` |

---

## Dependency Graph

```
                              ┌─────────────┐
                              │   public/   │
                              │ RunAnywhere │
                              └──────┬──────┘
                                     │
                    ┌────────────────┼────────────────┐
                    │                │                │
              ┌─────▼─────┐    ┌─────▼─────┐    ┌─────▼─────┐
              │   core/   │    │ features/ │    │  events   │
              │ Registries│    │Capabilities│    │  system   │
              └─────┬─────┘    └─────┬─────┘    └─────┬─────┘
                    │                │                │
                    └────────────────┼────────────────┘
                                     │
                         ┌───────────▼───────────┐
                         │    infrastructure/    │
                         │ Events, Logging, etc. │
                         └───────────┬───────────┘
                                     │
                    ┌────────────────┼────────────────┐
                    │                │                │
              ┌─────▼─────┐    ┌─────▼─────┐    ┌─────▼─────┐
              │   data/   │    │foundation/│    │ External  │
              │  Network  │    │   DI, etc │    │  Modules  │
              └───────────┘    └───────────┘    └───────────┘
```

---

## External Module Structure

### runanywhere-core-llamacpp

```
modules/runanywhere-core-llamacpp/
├── commonMain/
│   └── LlamaCppModule.kt         # Module definition
│   └── LlamaCppServiceProvider.kt # LLM service factory
│   └── LlamaCppAdapter.kt        # Framework adapter
└── jvmAndroidMain/
    └── LlamaCppService.kt        # JNI bridge to llama.cpp
```

**Provides:**
- `LLMServiceProvider` implementation
- `InferenceFramework.LLAMACPP` support

### runanywhere-core-onnx

```
modules/runanywhere-core-onnx/
├── commonMain/
│   └── ONNXModule.kt
│   └── ONNXServiceProvider.kt
│   └── ONNXAdapter.kt
└── jvmAndroidMain/
    └── ONNXCoreService.kt
```

**Provides:**
- Multiple capability support (STT, LLM, VAD depending on model)
- `InferenceFramework.ONNX` support

### runanywhere-whisperkit

```
modules/runanywhere-whisperkit/
├── commonMain/
│   └── WhisperKitModule.kt
│   └── WhisperKitProvider.kt
│   └── WhisperStorageStrategy.kt
└── jvmAndroidMain/
    └── WhisperKitService.kt
```

**Provides:**
- `STTServiceProvider` implementation
- `InferenceFramework.WHISPER_KIT` support
- WhisperKit-specific storage strategy

### runanywhere-llm-mlc

```
modules/runanywhere-llm-mlc/
├── commonMain/
│   └── MLCModule.kt
│   └── MLCProvider.kt
└── androidMain/
    └── MLCEngine.kt
```

**Provides:**
- `LLMServiceProvider` implementation (Android only)
- `InferenceFramework.MLC` support

---

## Service Registration Map

| Module | Capability | Service Factory | Priority |
|--------|------------|-----------------|----------|
| runanywhere-core-llamacpp | LLM | `LlamaCppServiceProvider` | 100 |
| runanywhere-core-onnx | STT/LLM/VAD | `ONNXServiceProvider` | 90 |
| runanywhere-whisperkit | STT | `WhisperKitProvider` | 100 |
| runanywhere-llm-mlc | LLM | `MLCProvider` | 80 |
| Built-in (SimpleEnergyVAD) | VAD | Internal | 50 |
| Built-in (SystemTTS) | TTS | Internal | 50 |

---

## Platform Source Sets

### commonMain (>90% of code)

All business logic, interfaces, protocols:
- All capability interfaces and base implementations
- All service protocols
- Event system
- Module/Service registries
- Configuration types
- Error types
- Utilities

### jvmMain

JVM/Desktop specific:
- `RunAnywhere` platform initialization
- `SecureStorage` implementation (JVM preferences)
- `DeviceInfo` collection (JVM system properties)
- File paths

### androidMain

Android specific:
- `RunAnywhere` platform initialization (Context-based)
- `SecureStorage` implementation (Android Keystore)
- `DeviceInfo` collection (Android Build info)
- File paths (app directories)
- Database (Room implementation)
- Audio I/O (Android AudioRecord/AudioTrack)

### jvmAndroidMain

Shared JVM+Android code:
- JNI bridges to native libraries
- Ktor HTTP client configuration

### nativeMain (Future)

iOS/Native specific (for future use):
- Platform bindings
- File system access

---

## Capability → Service → Module Flow

```
RunAnywhere.stt.transcribe(audio)
       │
       ▼
STTCapability.transcribe()
       │
       ▼
ServiceRegistry.createSTT(modelId, config)
       │
       ▼
┌──────────────────────────────────────┐
│ Find factory where canHandle(modelId) │
│ is true, sorted by priority          │
└────────────────┬─────────────────────┘
                 │
       ┌─────────┴─────────┐
       │                   │
       ▼                   ▼
WhisperKitProvider    ONNXServiceProvider
(priority: 100)       (priority: 90)
       │
       ▼
WhisperKitSTT (STTService impl)
       │
       ▼
Return transcription result
```

---

## File Count Summary (Target)

| Package | Estimated Files |
|---------|-----------------|
| public/ | ~15 |
| core/ | ~10 |
| foundation/ | ~15 |
| infrastructure/ | ~35 |
| features/ | ~50 |
| data/ | ~15 |
| **Total commonMain** | **~140** |
| jvmMain | ~5 |
| androidMain | ~10 |
| jvmAndroidMain | ~5 |
| **Total platform** | **~20** |
| External modules | ~25 each |

---

## Migration Notes

### Current → Target Package Renames

| Current Location | Target Location |
|-----------------|-----------------|
| `com.runanywhere.sdk.components.base` | `com.runanywhere.sdk.core.capabilities` |
| `com.runanywhere.sdk.components.stt` | `com.runanywhere.sdk.features.stt` |
| `com.runanywhere.sdk.components.llm` | `com.runanywhere.sdk.features.llm` |
| `com.runanywhere.sdk.events` | `com.runanywhere.sdk.infrastructure.events` |
| `com.runanywhere.sdk.foundation` | `com.runanywhere.sdk.foundation` (keep) |
| `com.runanywhere.sdk.models` | `com.runanywhere.sdk.infrastructure.modelmanagement` |
| `com.runanywhere.sdk.services` | Distributed to `data/` and `infrastructure/` |
