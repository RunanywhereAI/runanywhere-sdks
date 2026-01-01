# Swift Models Analysis

This document analyzes all structs and enums in the Swift SDK codebase to determine:
1. Whether they should stay in Swift (public-facing)
2. Whether they should be moved to C++ (internal/business logic)
3. What purpose they serve

## Summary Statistics

| Category | Count | Public | Internal | Can Move to C++ |
|----------|-------|--------|----------|-----------------|
| Structs  | 58    | 52     | 6        | ~20             |
| Enums    | 32    | 27     | 5        | ~15             |

---

## 1. MODEL MANAGEMENT DOMAIN (`Infrastructure/ModelManagement/Models/Domain/`)

These are **duplicates of C++ types** - the C++ layer already has complete definitions in `rac_model_types.h`.

| File | Swift Type | C++ Equivalent | Recommendation |
|------|------------|----------------|----------------|
| `ModelInfo.swift` | `ModelInfo` | `rac_model_info_t` | **KEEP** - Public API, conversion helpers |
| `ModelInfo.swift` | `ModelSource` | `rac_model_source_t` | **SIMPLIFY** - Just conversion extension |
| `InferenceFramework.swift` | `InferenceFramework` | `rac_inference_framework_t` | **SIMPLIFY** - Keep conversion helpers only |
| `ModelCategory.swift` | `ModelCategory` | `rac_model_category_t` | **SIMPLIFY** - Keep conversion helpers only |
| `ModelFormat.swift` | `ModelFormat` | `rac_model_format_t` | **SIMPLIFY** - Keep conversion helpers only |
| `ModelArtifactType.swift` | `ModelArtifactType` | `rac_model_artifact_info_t` | **SIMPLIFY** - Keep conversion helpers only |
| `ModelArtifactType.swift` | `ArchiveType` | `rac_archive_type_t` | **SIMPLIFY** - Keep conversion helpers only |
| `ModelArtifactType.swift` | `ArchiveStructure` | `rac_archive_structure_t` | **SIMPLIFY** - Keep conversion helpers only |
| `ModelArtifactType.swift` | `ExpectedModelFiles` | `rac_expected_model_files_t` | **SIMPLIFY** - Keep conversion helpers only |
| `ModelArtifactType.swift` | `ModelFileDescriptor` | `rac_model_file_descriptor_t` | **SIMPLIFY** - Keep conversion helpers only |

**Action:** These files have extensive Swift-specific logic (computed properties, convenience initializers, Codable conformance). The Swift types should remain but be **thin wrappers** that convert to/from C++ types. Remove any business logic that's duplicated in C++.

---

## 2. LLM MODELS (`Features/LLM/Models/`)

| File | Swift Type | C++ Equivalent | Recommendation |
|------|------------|----------------|----------------|
| `LLMConfiguration.swift` | `LLMConfiguration` | `rac_llm_config_t` | **KEEP** - Public API |
| `LLMGenerationOptions.swift` | `LLMGenerationOptions` | `rac_llm_options_t` | **KEEP** - Public API, has `withCOptions()` |
| `LLMGenerationResult.swift` | `LLMGenerationResult` | `rac_llm_result_t` | **KEEP** - Public API |
| `LLMStreamingResult.swift` | `LLMStreamingResult` | `rac_llm_stream_token_t` | **KEEP** - Public API |
| `ThinkingTagPattern.swift` | `ThinkingTagPattern` | N/A | **KEEP** - Swift convenience |

**Status:** Already correctly structured with `withCOptions()` conversion helpers. No changes needed.

---

## 3. STT MODELS (`Features/STT/Models/`)

| File | Swift Type | C++ Equivalent | Recommendation |
|------|------------|----------------|----------------|
| `STTConfiguration.swift` | `STTConfiguration` | `rac_stt_config_t` | **KEEP** - Public API |
| `STTOptions.swift` | `STTOptions` | `rac_stt_options_t` | **KEEP** - Public API |
| `STTOutput.swift` | `STTOutput` | `rac_stt_output_t` | **KEEP** - Public API |
| `STTOutput.swift` | `TranscriptionMetadata` | N/A | **KEEP** - Part of STTOutput |
| `STTOutput.swift` | `WordTimestamp` | `rac_stt_word_timestamp_t` | **KEEP** - Part of STTOutput |
| `STTOutput.swift` | `TranscriptionAlternative` | N/A | **KEEP** - Part of STTOutput |
| `STTTranscriptionResult.swift` | `STTTranscriptionResult` | `rac_stt_result_t` | **KEEP** - Public API |

**Status:** Already correctly structured. No changes needed.

---

## 4. TTS MODELS (`Features/TTS/Models/`)

| File | Swift Type | C++ Equivalent | Recommendation |
|------|------------|----------------|----------------|
| `TTSConfiguration.swift` | `TTSConfiguration` | `rac_tts_config_t` | **KEEP** - Public API |
| `TTSOptions.swift` | `TTSOptions` | `rac_tts_options_t` | **KEEP** - Public API |
| `TTSOutput.swift` | `TTSOutput` | `rac_tts_output_t` | **KEEP** - Public API |
| `TTSOutput.swift` | `TTSSynthesisMetadata` | N/A | **KEEP** - Part of TTSOutput |
| `TTSOutput.swift` | `TTSPhonemeTimestamp` | N/A | **KEEP** - Part of TTSOutput |
| `TTSOutput.swift` | `TTSSpeakResult` | N/A | **KEEP** - Public convenience |

**Status:** Already correctly structured. No changes needed.

---

## 5. VAD MODELS (`Features/VAD/Models/`)

| File | Swift Type | C++ Equivalent | Recommendation |
|------|------------|----------------|----------------|
| `VADConfiguration.swift` | `VADConfiguration` | `rac_vad_config_t` | **KEEP** - Public API |
| `VADStatistics.swift` | `VADStatistics` | `rac_vad_stats_t` | **KEEP** - Public API |
| `SpeechActivityEvent.swift` | `SpeechActivityEvent` | `rac_vad_event_type_t` | **KEEP** - Public API |

**Status:** Already correctly structured. No changes needed.

---

## 6. STRUCTURED OUTPUT (`Features/LLM/StructuredOutput/`)

| File | Swift Type | C++ Equivalent | Recommendation |
|------|------------|----------------|----------------|
| `Generatable.swift` | `StructuredOutputConfig` | `rac_llm_structured_output_config_t` | **KEEP** - Public API |
| `GenerationHints.swift` | `GenerationHints` | N/A | **KEEP** - Swift convenience |
| `StreamToken.swift` | `StreamToken` | N/A | **KEEP** - Public API |
| `StreamToken.swift` | `StructuredOutputStreamResult<T>` | N/A | **KEEP** - Generic Swift type |
| `StructuredOutputHandler.swift` | `StructuredOutputValidation` | N/A | **KEEP** - Public API |

**Status:** Swift-specific generics (Generatable protocol) cannot be ported to C++. Keep as-is.

---

## 7. DOWNLOAD MODELS (`Infrastructure/Download/Models/`)

| File | Swift Type | C++ Equivalent | Recommendation |
|------|------------|----------------|----------------|
| `DownloadConfiguration.swift` | `DownloadConfiguration` | `rac_download_config_t` | **KEEP** - Public API |
| `DownloadConfiguration.swift` | `DownloadPolicy` | `rac_download_policy_t` | **KEEP** - Public API |
| `DownloadProgress.swift` | `DownloadProgress` | `rac_download_progress_t` | **KEEP** - Public API |
| `DownloadProgress.swift` | `DownloadStage` | N/A | **KEEP** - Swift convenience |
| `DownloadTask.swift` | `DownloadTask` | N/A | **KEEP** - Swift async wrapper |
| `DownloadState.swift` | `DownloadState` | N/A | **KEEP** - Swift UI binding |
| `ExtractionService.swift` | `ExtractionResult` | N/A | **KEEP** - Internal helper |

**Status:** Download orchestration stays in Swift (uses Alamofire). C++ defines configs, Swift executes.

---

## 8. STORAGE/FILE MANAGEMENT (`Infrastructure/FileManagement/Models/`)

| File | Swift Type | C++ Equivalent | Recommendation |
|------|------------|----------------|----------------|
| `StorageConfiguration.swift` | `StorageConfiguration` | `rac_storage_config_t` | **KEEP** - Public API |
| `StorageConfiguration.swift` | `CacheEvictionPolicy` | N/A | **KEEP** - Public API |
| `StorageInfo.swift` | `StorageInfo` | N/A | **REVIEW** - May duplicate C++ |
| `StorageInfo.swift` | `ModelStorageMetrics` | N/A | **REVIEW** - May duplicate C++ |
| `StorageInfo.swift` | `ModelStorageSummary` | N/A | **DELETE** - User said not needed |
| `StorageInfo.swift` | `StoredModel` | N/A | **KEEP** - UI binding |
| `AppStorageInfo.swift` | `AppStorageInfo` | N/A | **KEEP** - Swift-specific |
| `DeviceStorageInfo.swift` | `DeviceStorageInfo` | N/A | **KEEP** - Swift-specific |
| `StorageAvailability.swift` | `StorageAvailability` | N/A | **KEEP** - Swift-specific |
| `FileOperationsUtilities.swift` | `FileOperationsUtilities` | N/A | **KEEP** - Platform-specific |

---

## 9. DEVICE (`Infrastructure/Device/Models/`)

| File | Swift Type | C++ Equivalent | Recommendation |
|------|------------|----------------|----------------|
| `DeviceInfo.swift` | `DeviceInfo` | `rac_device_registration_info_t` | **KEEP** - Platform-specific gathering |

**Status:** Device info gathering MUST stay in Swift (uses UIDevice, ProcessInfo, sysctlbyname).

---

## 10. EVENTS (`Infrastructure/Events/`)

| File | Swift Type | C++ Equivalent | Recommendation |
|------|------------|----------------|----------------|
| `SDKEvent.swift` | `EventDestination` | `rac_event_destination_t` | **SIMPLIFY** - Just conversion |
| `SDKEvent.swift` | `EventCategory` | `rac_event_category_t` | **SIMPLIFY** - Just conversion |
| `SDKEvent.swift` | `SDKEvent` (protocol) | N/A | **KEEP** - Swift protocol for subscribers |

---

## 11. BRIDGE TYPES (`Foundation/Bridge/Extensions/`)

| File | Swift Type | C++ Equivalent | Recommendation |
|------|------------|----------------|----------------|
| `CppBridge+ModelRegistry.swift` | `ModelDiscoveryResult` | N/A | **KEEP** - Swift wrapper |
| `CppBridge+Strategy.swift` | `ModelStorageDetails` | `rac_storage_details_t` | **KEEP** - Conversion wrapper |
| `CppBridge+Strategy.swift` | `ModelDownloadStrategyConfig` | `rac_download_strategy_config_t` | **KEEP** - Conversion wrapper |
| `CppBridge+Strategy.swift` | `DownloadResult` | `rac_download_result_t` | **KEEP** - Conversion wrapper |
| `CppBridge+Services.swift` | `ProviderInfo` | N/A | **KEEP** - Debug/inspection |
| `CppBridge+Services.swift` | `ModuleInfo` | N/A | **KEEP** - Debug/inspection |

---

## 12. PUBLIC API TYPES (`Public/`)

| File | Swift Type | C++ Equivalent | Recommendation |
|------|------------|----------------|----------------|
| `SDKEnvironment.swift` | `SDKEnvironment` | `rac_environment_t` | **KEEP** - Public API |
| `SDKEnvironment.swift` | `SDKInitParams` | N/A | **KEEP** - Swift-specific init |
| `RunAnywhere+VoiceAgent.swift` | `VoiceAgentResult` | `rac_voice_agent_result_t` | **KEEP** - Public API |
| `RunAnywhere+VoiceAgent.swift` | `VoiceAgentConfiguration` | `rac_voice_agent_config_t` | **KEEP** - Public API |
| `RunAnywhere+VoiceAgent.swift` | `VoiceAgentComponentStates` | N/A | **KEEP** - Swift UI state |
| `RunAnywhere+VoiceAgent.swift` | `ComponentLoadState` | N/A | **KEEP** - Swift UI state |
| `RunAnywhere+VoiceSession.swift` | `VoiceSessionConfig` | N/A | **KEEP** - Swift-specific |
| `RunAnywhere+VoiceSession.swift` | `VoiceSessionEvent` | N/A | **KEEP** - Swift-specific |
| `RunAnywhere+VoiceSession.swift` | `VoiceSessionError` | N/A | **KEEP** - Swift-specific |

---

## 13. LOGGING (`Infrastructure/Logging/`)

| File | Swift Type | C++ Equivalent | Recommendation |
|------|------------|----------------|----------------|
| `SDKLogger.swift` | `LogLevel` | `rac_log_level_t` | **KEEP** - Public API |
| `SDKLogger.swift` | `LogEntry` | N/A | **KEEP** - Swift-specific |
| `SDKLogger.swift` | `LoggingConfiguration` | N/A | **KEEP** - Swift-specific |
| `SDKLogger.swift` | `SDKLogger` | N/A | **KEEP** - Swift-specific |

---

## 14. ERRORS (`Foundation/Errors/`)

| File | Swift Type | C++ Equivalent | Recommendation |
|------|------------|----------------|----------------|
| `SDKError.swift` | `SDKError` | `rac_result_t` + `rac_error_*` | **KEEP** - Swift Error protocol |
| `ErrorCategory.swift` | `ErrorCategory` | N/A | **KEEP** - Swift-specific |
| `ErrorCode.swift` | `ErrorCode` | `rac_result_t` values | **KEEP** - Swift-specific |

---

## 15. NETWORK (`Data/Network/Models/`)

| File | Swift Type | C++ Equivalent | Recommendation |
|------|------------|----------------|----------------|
| `AuthenticationResponse.swift` | `AuthenticationResponse` | `rac_auth_response_t` | **KEEP** - JSON Codable convenience |

---

## 16. CORE TYPES (`Core/Types/`)

| File | Swift Type | C++ Equivalent | Recommendation |
|------|------------|----------------|----------------|
| `AudioTypes.swift` | `AudioFormat` | `rac_audio_format_t` | **KEEP** - Public API |
| `ComponentTypes.swift` | `SDKComponent` | `rac_component_type_t` | **KEEP** - Public API |

---

## 17. INTERNAL/PRIVATE TYPES

| File | Swift Type | Recommendation |
|------|------------|----------------|
| `EventBridge.swift` | `BridgedEvent` (private) | **DELETE** - Unused |
| `SystemFoundationModelsService.swift` | `LanguageSessionWrapper` (private) | **KEEP** - Internal |
| `SDKLogger.swift` | `State` (private) | **KEEP** - Internal |
| `RunAnywhere+TextGeneration.swift` | `Callbacks` (private) | **KEEP** - Internal |
| `RunAnywhere+TextGeneration.swift` | `LLMStreamCallbacks` (private) | **KEEP** - Internal |

---

## Recommended Actions

### Phase 1: Delete Unused Code
1. Delete `EventBridge.swift` - never started/used
2. Delete `ModelStorageSummary` from `StorageInfo.swift` - user explicitly said not needed

### Phase 2: Simplify Model Domain Types
Move business logic to C++, keep only:
- Swift type definition for public API
- `init(from cType:)` - C++ → Swift conversion
- `toCType()` or `withCType(_ body:)` - Swift → C++ conversion
- Codable conformance for JSON serialization

Files to simplify:
- `InferenceFramework.swift` - Remove `supportedFormats`, `usesDirectoryBasedModels`, etc. (already in C++)
- `ModelCategory.swift` - Remove `requiresContextLength`, `supportsThinking`, `from(framework:)` (already in C++)
- `ModelArtifactType.swift` - Remove `infer(from:)`, factory methods (already in C++)
- `ModelFormat.swift` - Already minimal, good as-is

### Phase 3: Verify C++ Coverage
For each Swift type, verify C++ has equivalent before removing Swift logic:
- [x] `rac_inference_framework_t` - Complete
- [x] `rac_model_category_t` - Complete
- [x] `rac_model_format_t` - Complete
- [x] `rac_model_artifact_info_t` - Complete
- [x] `rac_model_info_t` - Complete

---

## File-by-File Cleanup Checklist

### Infrastructure/ModelManagement/Models/Domain/

- [ ] `ModelInfo.swift` - Keep, verify `init(from:)` and `toCType()` exist
- [ ] `InferenceFramework.swift` - Remove duplicated logic (supportedFormats, etc.)
- [ ] `ModelCategory.swift` - Remove duplicated logic (requiresContextLength, etc.)
- [ ] `ModelFormat.swift` - Already minimal, no changes
- [ ] `ModelArtifactType.swift` - Remove duplicated logic (infer, factory methods)

### Infrastructure/Commons/

- [ ] `EventBridge.swift` - **DELETE** (unused)

### Infrastructure/FileManagement/Models/Domain/

- [ ] `StorageInfo.swift` - Remove `ModelStorageSummary`

---

## Summary

**Total structs analyzed:** 58
**Total enums analyzed:** 32

**Keep as-is:** ~60 types (public API, Swift-specific, platform-specific)
**Simplify:** ~10 types (remove duplicated business logic)
**Delete:** 2 types (`EventBridge`, `ModelStorageSummary`)

The key principle: **C++ defines business logic, Swift provides:**
1. Public API surface (type-safe, Swift-idiomatic)
2. Platform-specific implementations (UIDevice, FileManager, Keychain)
3. JSON serialization (Codable)
4. Swift-specific patterns (protocols, generics, async/await)
