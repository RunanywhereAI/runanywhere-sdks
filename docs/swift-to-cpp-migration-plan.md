# RunAnywhere SDK: Swift Minimization & Rearchitecture Plan

## Executive Summary

This plan outlines the **elimination of unnecessary Swift wrapper layers** and **direct consumption of C++ APIs from the Public layer**. The goal is to reduce Swift code by ~60% while maintaining the same public API.

---

## COMPLETE FILE INVENTORY (EVERY FILE)

### Legend: File Status Categories

| Symbol | Category | Description |
|--------|----------|-------------|
| 🔴 DELETE | Remove | Pure wrappers with no unique logic - delete entirely |
| 🟢 BRIDGE | Thin Wrapper | Become thin wrapper over C++ type with `toCOptions()`/`init(from:)` |
| ✅ KEEP-SWIFT | Swift-Only | Uses Swift-specific features (AsyncStream, Codable, protocols) |
| ✅ KEEP-PLATFORM | Platform API | Uses Apple APIs (AVFoundation, Security) - CANNOT move to C++ |
| 🟡 SIMPLIFY | Reduce | Keep but simplify or merge with another file |

---

### Features/ Directory - File-by-File Analysis with C++ Bridge Pattern

```
Features/
├── LLM/ (15 files, ~2,249 lines)
│   ├── Analytics/
│   │   ├── GenerationAnalyticsService.swift   436 lines  🔴 DELETE
│   │   │   WHY: Pure wrapper that only calls rac_llm_analytics_* C++ functions.
│   │   │   C++ BRIDGE: N/A - Not a data type, just a service wrapper.
│   │   │   ACTION: Delete. Move EventPublisher.shared.track() to Public layer.
│   │   │
│   │   └── LLMEvent.swift                     212 lines  ✅ KEEP-SWIFT
│   │       WHY: Defines Swift event types with TelemetryEventProperties conformance.
│   │       C++ BRIDGE: NO - Uses Swift enum with associated values, SDKEvent protocol.
│   │       ACTION: Keep as-is. Events are Swift-native for Combine/EventBus.
│   │
│   ├── Models/
│   │   ├── LLMConfiguration.swift             142 lines  🔴 DELETE
│   │   │   WHY: Duplicates C++ rac_llm_config_t with validate() now in C++.
│   │   │   C++ BRIDGE: N/A - Configuration validation is in C++.
│   │   │   ACTION: Delete. Use rac_llm_config_t directly via options types.
│   │   │
│   │   ├── LLMGenerationOptions.swift          66 lines  🟢 BRIDGE
│   │   │   WHY: Public API input type (maxTokens, temperature, stopSequences).
│   │   │   C++ BRIDGE: YES → Add `func withCOptions<T>(_ body:) -> T` to convert
│   │   │              to rac_llm_options_t. Match defaults to RAC_LLM_DEFAULT_*.
│   │   │   FIELDS TO VERIFY IN C++:
│   │   │     - maxTokens: Int → max_tokens: int32_t ✅
│   │   │     - temperature: Float → temperature: float ✅
│   │   │     - topP: Float → top_p: float ✅
│   │   │     - stopSequences: [String] → stop_sequences: const char** 🔴 ADD
│   │   │     - streamingEnabled: Bool → streaming_enabled: rac_bool_t ✅
│   │   │     - preferredFramework → preferred_framework 🔴 ADD
│   │   │     - structuredOutput → structured_output 🔴 ADD
│   │   │     - systemPrompt: String? → system_prompt: const char* ✅
│   │   │   ACTION: Add C conversion method, ensure C++ has all fields.
│   │   │
│   │   ├── LLMGenerationResult.swift           81 lines  🟢 BRIDGE
│   │   │   WHY: Public API return type (text, tokensUsed, latencyMs).
│   │   │   C++ BRIDGE: YES → Add `init(from cResult: rac_llm_result_t)`.
│   │   │   FIELDS TO VERIFY IN C++:
│   │   │     - text: String → text: const char* ✅
│   │   │     - thinkingContent: String? → thinking_content: const char* 🔴 ADD
│   │   │     - inputTokens: Int → input_tokens: int32_t ✅
│   │   │     - tokensUsed: Int → output_tokens: int32_t ✅
│   │   │     - modelUsed: String → model_id: const char* ✅
│   │   │     - latencyMs: TimeInterval → latency_ms: double ✅
│   │   │     - tokensPerSecond: Double → tokens_per_second: double ✅
│   │   │     - timeToFirstTokenMs: Double? → time_to_first_token_ms 🔴 ADD
│   │   │     - thinkingTokens: Int? → thinking_tokens: int32_t 🔴 ADD
│   │   │     - responseTokens: Int → response_tokens: int32_t 🔴 ADD
│   │   │     - structuredOutputValidation → validation 🔴 ADD
│   │   │   ACTION: Add init(from:), ensure C++ has all fields.
│   │   │
│   │   ├── LLMStreamingResult.swift            28 lines  ✅ KEEP-SWIFT
│   │   │   WHY: Contains AsyncThrowingStream<String, Error> - Swift concurrency.
│   │   │   C++ BRIDGE: NO - Uses Task<>, AsyncThrowingStream<> which are Swift-only.
│   │   │   ACTION: Keep as-is. Streaming uses Swift concurrency primitives.
│   │   │
│   │   └── ThinkingTagPattern.swift            37 lines  🟢 BRIDGE
│   │       WHY: Pattern for extracting thinking content from LLM output.
│   │       C++ BRIDGE: YES → Add rac_thinking_pattern_t to C++ headers.
│   │       FIELDS TO ADD TO C++:
│   │         - openingTag: String → opening_tag: const char*
│   │         - closingTag: String → closing_tag: const char*
│   │       ACTION: Add C++ type, add `func withCPattern<T>(_ body:) -> T`.
│   │
│   ├── Protocol/
│   │   └── LLMService.swift                   100 lines  🔴 DELETE
│   │       WHY: Protocol with single C++ implementation. No DI needed.
│   │       C++ BRIDGE: N/A - Not a data type.
│   │       ACTION: Delete. Remove protocol conformance from capability.
│   │
│   ├── StructuredOutput/
│   │   ├── Generatable.swift                   40 lines  ✅ KEEP-SWIFT
│   │   │   WHY: Swift protocol with Codable conformance, metatype usage.
│   │   │   C++ BRIDGE: NO - Uses Swift generics, metatypes, Codable.
│   │   │   ACTION: Keep. This is Swift-specific for type-safe JSON generation.
│   │   │   NOTE: StructuredOutputConfig uses Generatable.Type which is Swift-only.
│   │   │
│   │   ├── GenerationHints.swift               25 lines  🔴 DELETE
│   │   │   WHY: Simple struct (temperature, maxTokens). Merge into options.
│   │   │   C++ BRIDGE: N/A - Being merged/deleted.
│   │   │   ACTION: Merge fields into LLMGenerationOptions, delete file.
│   │   │
│   │   ├── StreamAccumulator.swift             39 lines  🔴 DELETE
│   │   │   WHY: Actor that just appends strings. Trivial.
│   │   │   C++ BRIDGE: N/A - Just string concatenation.
│   │   │   ACTION: Delete. Use String directly.
│   │   │
│   │   ├── StreamToken.swift                   26 lines  🔴 DELETE
│   │   │   WHY: Simple struct (text, timestamp, index). Internal only.
│   │   │   C++ BRIDGE: N/A - Internal helper type.
│   │   │   ACTION: Delete. Inline where needed.
│   │   │
│   │   ├── StructuredOutputGenerationService.swift  205 lines  🟡 SIMPLIFY
│   │   │   WHY: Needed for Generatable<T> API but should call C++ functions.
│   │   │   C++ BRIDGE: PARTIAL - Keep service but call rac_structured_output_*
│   │   │              instead of StructuredOutputHandler.
│   │   │   ACTION: Update to call C++ functions, remove internal logic.
│   │   │
│   │   └── StructuredOutputHandler.swift      297 lines  🔴 DELETE
│   │       WHY: JSON extraction now in C++ structured_output.cpp.
│   │       C++ BRIDGE: N/A - Logic already migrated to C++.
│   │       ACTION: Delete. Call rac_structured_output_extract_json() directly.
│   │
│   └── LLMCapability.swift                    541 lines  🔴 DELETE
│       WHY: Actor wrapper over C++ handle management.
│       C++ BRIDGE: N/A - Not a data type, just a service.
│       ACTION: Delete. Merge handle management into RunAnywhere+TextGeneration.
│
├── STT/ (11 files, ~1,703 lines)
│   ├── Analytics/
│   │   ├── STTAnalyticsService.swift          296 lines  🔴 DELETE
│   │   │   WHY: Pure wrapper calling rac_stt_analytics_* functions.
│   │   │   C++ BRIDGE: N/A - Not a data type.
│   │   │   ACTION: Delete. Move event emission to Public layer.
│   │   │
│   │   └── STTEvent.swift                     234 lines  ✅ KEEP-SWIFT
│   │       WHY: Swift event types for EventBus.
│   │       C++ BRIDGE: NO - Uses Swift enum with associated values.
│   │       ACTION: Keep. Events are Swift-native.
│   │
│   ├── Models/
│   │   ├── STTConfiguration.swift              58 lines  🔴 DELETE
│   │   │   WHY: Duplicates rac_stt_config_t.
│   │   │   C++ BRIDGE: N/A - Delete in favor of C++.
│   │   │   ACTION: Delete. Use rac_stt_config_t directly.
│   │   │
│   │   ├── STTInput.swift                      68 lines  🔴 DELETE
│   │   │   WHY: Just wraps audioData + format. Pass as separate params.
│   │   │   C++ BRIDGE: N/A - Delete.
│   │   │   ACTION: Delete. Use separate parameters in API.
│   │   │
│   │   ├── STTOptions.swift                    73 lines  🟢 BRIDGE
│   │   │   WHY: Public API input type (language, enableTimestamps, etc.).
│   │   │   C++ BRIDGE: YES → Add `func withCOptions<T>(_ body:) -> T`.
│   │   │   FIELDS TO VERIFY IN C++:
│   │   │     - language: String → language: const char* ✅
│   │   │     - detectLanguage: Bool → detect_language: rac_bool_t 🔴 ADD
│   │   │     - enablePunctuation: Bool → enable_punctuation 🔴 ADD
│   │   │     - enableDiarization: Bool → enable_diarization 🔴 ADD
│   │   │     - maxSpeakers: Int? → max_speakers: int32_t 🔴 ADD
│   │   │     - enableTimestamps: Bool → enable_timestamps 🔴 ADD
│   │   │     - vocabularyFilter: [String] → vocabulary_filter 🔴 ADD
│   │   │     - audioFormat → audio_format 🔴 ADD
│   │   │     - sampleRate: Int → sample_rate: int32_t ✅
│   │   │     - preferredFramework → preferred_framework 🔴 ADD
│   │   │   ACTION: Add C conversion method, add missing fields to C++.
│   │   │
│   │   ├── STTOutput.swift                     99 lines  🟢 BRIDGE
│   │   │   WHY: Public API return type (text, confidence, wordTimestamps).
│   │   │   C++ BRIDGE: YES → Add `init(from cResult: rac_stt_result_t)`.
│   │   │   FIELDS TO VERIFY IN C++:
│   │   │     - text: String → text: const char* ✅
│   │   │     - confidence: Float → confidence: float ✅
│   │   │     - wordTimestamps: [WordTimestamp]? → word_timestamps 🔴 ADD
│   │   │     - detectedLanguage: String? → detected_language 🔴 ADD
│   │   │     - alternatives: [Alternative]? → alternatives 🔴 ADD
│   │   │     - metadata → embedded in result fields 🔴 ADD
│   │   │   NESTED TYPES TO ADD TO C++:
│   │   │     - rac_word_timestamp_t (word, startTime, endTime, confidence)
│   │   │     - rac_stt_alternative_t (text, confidence)
│   │   │     - rac_stt_metadata_t (modelId, processingTime, audioLength)
│   │   │   ACTION: Add init(from:), add nested types to C++.
│   │   │
│   │   ├── STTResult.swift                     74 lines  🔴 DELETE
│   │   │   WHY: Duplicate of STTOutput with slightly different fields.
│   │   │   C++ BRIDGE: N/A - Delete duplicate.
│   │   │   ACTION: Delete. Merge any unique fields into STTOutput.
│   │   │
│   │   └── STTTranscriptionResult.swift        59 lines  🔴 DELETE
│   │       WHY: Internal type used only by STTService protocol.
│   │       C++ BRIDGE: N/A - Delete.
│   │       ACTION: Delete with protocol. Merge fields into STTOutput if needed.
│   │
│   ├── Protocol/
│   │   └── STTService.swift                    47 lines  🔴 DELETE
│   │       WHY: Protocol with single implementation.
│   │       C++ BRIDGE: N/A - Not a data type.
│   │       ACTION: Delete.
│   │
│   ├── Services/
│   │   └── AudioCaptureManager.swift          262 lines  ✅ KEEP-PLATFORM
│   │       WHY: Uses AVAudioEngine, AVAudioSession, AVAudioConverter.
│   │       C++ BRIDGE: NO - Apple platform APIs cannot be in C++.
│   │       ACTION: Keep as-is. Platform-specific audio capture.
│   │
│   └── STTCapability.swift                    433 lines  🔴 DELETE
│       WHY: Actor wrapper over C++ handle.
│       C++ BRIDGE: N/A - Not a data type.
│       ACTION: Delete. Merge into RunAnywhere+STT.
│
├── TTS/ (10 files, ~1,978 lines)
│   ├── Analytics/
│   │   ├── TTSAnalyticsService.swift          264 lines  🔴 DELETE
│   │   │   WHY: Pure wrapper over rac_tts_analytics_*.
│   │   │   C++ BRIDGE: N/A - Not a data type.
│   │   │   ACTION: Delete. Move events to Public layer.
│   │   │
│   │   └── TTSEvent.swift                     200 lines  ✅ KEEP-SWIFT
│   │       WHY: Swift event types for EventBus.
│   │       C++ BRIDGE: NO - Swift enum with associated values.
│   │       ACTION: Keep.
│   │
│   ├── Models/
│   │   ├── TTSConfiguration.swift             165 lines  🔴 DELETE
│   │   │   WHY: Duplicates rac_tts_config_t.
│   │   │   C++ BRIDGE: N/A - Delete.
│   │   │   ACTION: Delete. Use C++ config directly.
│   │   │
│   │   ├── TTSInput.swift                      77 lines  🔴 DELETE
│   │   │   WHY: Just wraps text + voiceId. Pass as separate params.
│   │   │   C++ BRIDGE: N/A - Delete.
│   │   │   ACTION: Delete.
│   │   │
│   │   ├── TTSOptions.swift                    85 lines  🟢 BRIDGE
│   │   │   WHY: Public API input type (voice, rate, pitch, volume).
│   │   │   C++ BRIDGE: YES → Add `func withCOptions<T>(_ body:) -> T`.
│   │   │   FIELDS TO VERIFY IN C++:
│   │   │     - voice: String? → voice: const char* ✅
│   │   │     - language: String → language: const char* 🔴 ADD
│   │   │     - rate: Float → speaking_rate: float 🔴 ADD
│   │   │     - pitch: Float → pitch: float 🔴 ADD
│   │   │     - volume: Float → volume: float 🔴 ADD
│   │   │     - audioFormat → output_format: rac_audio_format_t 🔴 ADD
│   │   │     - sampleRate: Int → sample_rate: int32_t 🔴 ADD
│   │   │     - useSSML: Bool → use_ssml: rac_bool_t 🔴 ADD
│   │   │   ACTION: Add C conversion, add missing fields to C++.
│   │   │
│   │   └── TTSOutput.swift                    176 lines  🟢 BRIDGE
│   │       WHY: Public API return type (audioData, duration, format).
│   │       C++ BRIDGE: YES → Add `init(from cResult: rac_tts_result_t)`.
│   │       FIELDS TO VERIFY IN C++:
│   │         - audioData: Data → audio_data: uint8_t*, audio_size: size_t ✅
│   │         - format: AudioFormat → format: rac_audio_format_t 🔴 ADD
│   │         - duration: TimeInterval → duration_ms: double 🔴 ADD
│   │         - phonemeTimestamps → phoneme_timestamps 🔴 ADD
│   │         - metadata → embedded fields 🔴 ADD
│   │       NESTED TYPES TO ADD TO C++:
│   │         - rac_tts_phoneme_t (phoneme, startTime, endTime)
│   │         - rac_tts_metadata_t (voice, language, processingTime, charCount)
│   │       ALSO: TTSSpeakResult (176 lines) is defined here - keep for speak() API.
│   │       ACTION: Add init(from:), add nested types to C++.
│   │
│   ├── Protocol/
│   │   └── TTSService.swift                    51 lines  🔴 DELETE
│   │       WHY: Protocol with single implementation.
│   │       C++ BRIDGE: N/A - Not a data type.
│   │       ACTION: Delete.
│   │
│   ├── Services/
│   │   └── AudioPlaybackManager.swift         260 lines  ✅ KEEP-PLATFORM
│   │       WHY: Uses AVAudioPlayer, AVAudioSession - Apple APIs.
│   │       C++ BRIDGE: NO - Platform-specific.
│   │       ACTION: Keep. Audio playback is platform-specific.
│   │
│   ├── System/
│   │   ├── SystemTTSModule.swift               85 lines  ✅ KEEP-PLATFORM
│   │   │   WHY: Module registration for Apple TTS.
│   │   │   C++ BRIDGE: NO - Platform-specific.
│   │   │   ACTION: Keep.
│   │   │
│   │   └── SystemTTSService.swift             179 lines  ✅ KEEP-PLATFORM
│   │       WHY: Uses AVSpeechSynthesizer - Apple TTS API.
│   │       C++ BRIDGE: NO - Platform-specific.
│   │       ACTION: Keep.
│   │
│   └── TTSCapability.swift                    436 lines  🔴 DELETE
│       WHY: Actor wrapper over C++ handle.
│       C++ BRIDGE: N/A - Not a data type.
│       ACTION: Delete. Merge into RunAnywhere+TTS.
│
├── VAD/ (10 files, ~1,495 lines)
│   ├── Analytics/
│   │   ├── VADAnalyticsService.swift          245 lines  🔴 DELETE
│   │   │   WHY: Pure wrapper over rac_vad_analytics_*.
│   │   │   C++ BRIDGE: N/A - Not a data type.
│   │   │   ACTION: Delete. Move events to Public.
│   │   │
│   │   └── VADEvent.swift                     202 lines  ✅ KEEP-SWIFT
│   │       WHY: Swift event types for EventBus.
│   │       C++ BRIDGE: NO - Swift enum.
│   │       ACTION: Keep.
│   │
│   ├── Models/
│   │   ├── SpeechActivityEvent.swift           17 lines  ✅ KEEP-SWIFT
│   │   │   WHY: Simple enum (started, ended) for Swift callbacks.
│   │   │   C++ BRIDGE: NO - Maps to rac_speech_activity_t but Swift needs enum.
│   │   │   ACTION: Keep. Tiny file, used for Swift callback signatures.
│   │   │
│   │   ├── VADConfiguration.swift             166 lines  🔴 DELETE
│   │   │   WHY: Validation now in C++ rac_vad_component_configure().
│   │   │   C++ BRIDGE: N/A - Delete.
│   │   │   ACTION: Delete. Use rac_vad_config_t directly.
│   │   │
│   │   ├── VADInput.swift                      83 lines  🔴 DELETE
│   │   │   WHY: Just wraps audioBuffer. Pass Data directly.
│   │   │   C++ BRIDGE: N/A - Delete.
│   │   │   ACTION: Delete.
│   │   │
│   │   ├── VADOutput.swift                     48 lines  🟢 BRIDGE
│   │   │   WHY: Public API return type (isSpeechDetected, energyLevel).
│   │   │   C++ BRIDGE: YES → Add `init(from cResult: rac_vad_result_t)`.
│   │   │   FIELDS TO VERIFY IN C++:
│   │   │     - isSpeechDetected: Bool → is_speech: rac_bool_t ✅
│   │   │     - energyLevel: Float → energy_level: float ✅
│   │   │     - timestamp: Date → timestamp_ms: int64_t ✅
│   │   │   ACTION: Add init(from:). C++ types already complete! ✅
│   │   │
│   │   └── VADStatistics.swift                 58 lines  🟢 BRIDGE
│   │       WHY: Maps to rac_energy_vad_stats_t for debugging.
│   │       C++ BRIDGE: YES → Add `init(from cStats: rac_energy_vad_stats_t)`.
│   │       FIELDS (all exist in C++):
│   │         - current: Float → current_energy: float ✅
│   │         - threshold: Float → threshold: float ✅
│   │         - ambient: Float → ambient_noise: float ✅
│   │         - recentAvg: Float → recent_avg: float ✅
│   │         - recentMax: Float → recent_max: float ✅
│   │       ACTION: Add init(from:). C++ types complete! ✅
│   │
│   ├── Protocol/
│   │   └── VADService.swift                    83 lines  🔴 DELETE
│   │       WHY: Protocol with single implementation.
│   │       C++ BRIDGE: N/A - Not a data type.
│   │       ACTION: Delete.
│   │
│   ├── Services/
│   │   └── SimpleEnergyVADService.swift       311 lines  🔴 DELETE
│   │       WHY: Thin wrapper over rac_energy_vad_* functions.
│   │       C++ BRIDGE: N/A - Not a data type.
│   │       ACTION: Delete. Call C++ directly from Public layer.
│   │
│   └── VADCapability.swift                    282 lines  🔴 DELETE
│       WHY: Actor wrapper over C++ handle.
│       C++ BRIDGE: N/A - Not a data type.
│       ACTION: Delete. Merge into RunAnywhere+VAD.
│
├── VoiceAgent/ (6 files, ~859 lines)
│   ├── Models/
│   │   ├── AudioPipelineState.swift           202 lines  🔴 DELETE
│   │   │   WHY: State machine now in C++ voice_agent.cpp.
│   │   │   C++ BRIDGE: N/A - Logic migrated to C++.
│   │   │   ACTION: Delete. Call rac_audio_pipeline_* functions directly.
│   │   │
│   │   ├── VoiceAgentComponentState.swift     127 lines  ✅ KEEP-SWIFT
│   │   │   WHY: ComponentLoadState enum for tracking STT/LLM/TTS load states.
│   │   │   C++ BRIDGE: NO - Uses Swift enum with associated values, SDKEvent.
│   │   │   ACTION: Keep. UI binding for model load progress.
│   │   │
│   │   ├── VoiceAgentConfiguration.swift       51 lines  🟢 BRIDGE
│   │   │   WHY: Public API config (vadConfig, sttConfig, llmConfig, ttsConfig).
│   │   │   C++ BRIDGE: YES → Create rac_voice_agent_config_t in C++.
│   │   │   FIELDS TO ADD TO C++:
│   │   │     - vadConfig → vad_config: rac_vad_config_t*
│   │   │     - sttConfig → stt_config: rac_stt_config_t*
│   │   │     - llmConfig → llm_config: rac_llm_config_t*
│   │   │     - ttsConfig → tts_config: rac_tts_config_t*
│   │   │   ACTION: Add C++ type, add `func withCConfig<T>(_ body:) -> T`.
│   │   │   NOTE: Currently uses Swift Configuration types (🔴 DELETE targets).
│   │   │         Will need to change to use C++ configs directly.
│   │   │
│   │   ├── VoiceAgentResult.swift              58 lines  🟢 BRIDGE
│   │   │   WHY: Public API return type (transcription, response, audio).
│   │   │   C++ BRIDGE: YES → Add `init(from cResult: rac_voice_agent_result_t)`.
│   │   │   FIELDS TO ADD TO C++:
│   │   │     - speechDetected: Bool → speech_detected: rac_bool_t
│   │   │     - transcription: String? → transcription: const char*
│   │   │     - response: String? → response: const char*
│   │   │     - synthesizedAudio: Data? → audio_data: uint8_t*, audio_size: size_t
│   │   │   ACTION: Create rac_voice_agent_result_t in C++, add init(from:).
│   │   │   NOTE: VoiceAgentEvent enum (also in file) is ✅ KEEP-SWIFT.
│   │   │
│   │   └── VoiceAudioChunk.swift               56 lines  🟢 BRIDGE
│   │       WHY: Audio chunk for streaming processing.
│   │       C++ BRIDGE: YES → Create rac_audio_chunk_t in C++.
│   │       FIELDS TO ADD TO C++:
│   │         - samples: [Float] → samples: float*, samples_count: size_t
│   │         - timestamp: TimeInterval → timestamp_ms: double
│   │         - sampleRate: Int → sample_rate: int32_t
│   │         - channels: Int → channels: int32_t
│   │         - sequenceNumber: Int → sequence_number: int32_t
│   │         - isFinal: Bool → is_final: rac_bool_t
│   │       ACTION: Create C++ type, add init(from:) and toCChunk().
│   │
│   └── VoiceAgentCapability.swift             365 lines  🔴 DELETE
│       WHY: Actor orchestrating STT→LLM→TTS pipeline.
│       C++ BRIDGE: N/A - Not a data type.
│       ACTION: Delete. Merge into RunAnywhere+VoiceAgent.

TOTAL: 52 files, ~8,284 lines
```

---

### Summary by Category

| Category | Symbol | Files | Lines | Action |
|----------|--------|-------|-------|--------|
| **🔴 DELETE** | Remove entirely | 26 | ~4,100 | Delete after merging logic to Public |
| **🟢 BRIDGE** | Thin C++ wrapper | 11 | ~800 | Add `withCOptions()`/`init(from:)` methods |
| **✅ KEEP-SWIFT** | Swift-only features | 9 | ~850 | Keep - uses Swift generics/async/enum |
| **✅ KEEP-PLATFORM** | Apple APIs | 6 | ~1,200 | Keep - AVFoundation/Security |
| **🟡 SIMPLIFY** | Reduce/merge | 1 | ~200 | Update to call C++ functions |

---

### Files Requiring C++ Bridge Pattern (🟢 BRIDGE)

These 11 files will become **thin wrappers** with C++ conversion methods:

| File | C++ Type | Swift → C++ Method | C++ → Swift Method |
|------|----------|--------------------|--------------------|
| `LLMGenerationOptions.swift` | `rac_llm_options_t` | `withCOptions()` | N/A (input only) |
| `LLMGenerationResult.swift` | `rac_llm_result_t` | N/A (output only) | `init(from:)` |
| `ThinkingTagPattern.swift` | `rac_thinking_pattern_t` | `withCPattern()` | `init(from:)` |
| `STTOptions.swift` | `rac_stt_options_t` | `withCOptions()` | N/A |
| `STTOutput.swift` | `rac_stt_result_t` | N/A | `init(from:)` |
| `TTSOptions.swift` | `rac_tts_options_t` | `withCOptions()` | N/A |
| `TTSOutput.swift` | `rac_tts_result_t` | N/A | `init(from:)` |
| `VADOutput.swift` | `rac_vad_result_t` | N/A | `init(from:)` |
| `VADStatistics.swift` | `rac_energy_vad_stats_t` | N/A | `init(from:)` |
| `VoiceAgentConfiguration.swift` | `rac_voice_agent_config_t` | `withCConfig()` | N/A |
| `VoiceAgentResult.swift` | `rac_voice_agent_result_t` | N/A | `init(from:)` |
| `VoiceAudioChunk.swift` | `rac_audio_chunk_t` | `toCChunk()` | `init(from:)` |

### Public/ Directory - File Analysis with Reasoning

```
Public/
├── Configuration/
│   └── SDKEnvironment.swift                   260 lines  ✅ KEEP
│       WHY: SDK-wide configuration (apiKey, baseURL, logLevel). Platform detection,
│            environment switching. Foundation of SDK initialization.
│
├── Events/
│   └── EventBus.swift                          76 lines  ✅ KEEP
│       WHY: Combine-based pub/sub system for SDK events. Swift-specific API using
│            PassthroughSubject. Apps subscribe to events via this interface.
│
├── Extensions/
│   ├── RunAnywhere+Frameworks.swift            79 lines  ✅ KEEP
│   │   WHY: Lists available InferenceFrameworks. Calls ServiceRegistry for discovery.
│   │        Small utility - no changes needed.
│   │
│   ├── RunAnywhere+Logging.swift               57 lines  ✅ KEEP
│   │   WHY: Public logging API (setLogLevel, enableSDKLogs). Wraps SDKLogger.
│   │        Small utility - no changes needed.
│   │
│   ├── RunAnywhere+ModelAssignments.swift     159 lines  ✅ KEEP
│   │   WHY: Model assignment API (assignModel, getAssignedModel). Uses ModelRegistry.
│   │        Business logic stays in Swift for model management.
│   │
│   ├── RunAnywhere+ModelManagement.swift      147 lines  ✅ KEEP
│   │   WHY: Model download/list API. Calls DownloadService, ModelRegistry.
│   │        File system operations need Swift APIs.
│   │
│   ├── RunAnywhere+Storage.swift               99 lines  ✅ KEEP
│   │   WHY: Storage utilities (getStorageInfo, clearCache). Platform file system API.
│   │        Uses FileManager which is Swift-only.
│   │
│   ├── RunAnywhere+StructuredOutput.swift      77 lines  🟡 EXPAND
│   │   WHY: Currently delegates to StructuredOutputGenerationService. Should call
│   │        C++ rac_structured_output_* functions directly for JSON extraction.
│   │        CHANGE: Add rac_structured_output_extract_json() calls.
│   │
│   ├── RunAnywhere+STT.swift                  143 lines  🟡 EXPAND (~180 lines after)
│   │   WHY: Currently calls serviceContainer.sttCapability.transcribe().
│   │        CHANGE: Absorb STTCapability logic - manage handle, call rac_stt_*,
│   │        emit events. Keep AudioCaptureManager reference for platform audio.
│   │
│   ├── RunAnywhere+TextGeneration.swift        88 lines  🟡 EXPAND (~250 lines after)
│   │   WHY: Currently calls serviceContainer.llmCapability.generate().
│   │        CHANGE: Absorb LLMCapability - manage handle, build rac_llm_options_t,
│   │        call rac_llm_component_generate(), emit LLMEvent, return result.
│   │
│   ├── RunAnywhere+TTS.swift                  139 lines  🟡 EXPAND (~200 lines after)
│   │   WHY: Currently calls serviceContainer.ttsCapability.synthesize().
│   │        CHANGE: Absorb TTSCapability - manage handle, call rac_tts_*,
│   │        emit events. Keep AudioPlaybackManager for platform playback.
│   │
│   ├── RunAnywhere+VAD.swift                  109 lines  🟡 EXPAND (~180 lines after)
│   │   WHY: Currently calls serviceContainer.vadCapability.process().
│   │        CHANGE: Absorb VADCapability - manage handle, call rac_vad_*,
│   │        call rac_energy_vad_* directly, emit events.
│   │
│   ├── RunAnywhere+VoiceAgent.swift           197 lines  🟡 EXPAND (~250 lines after)
│   │   WHY: Currently calls serviceContainer.voiceAgentCapability.processVoiceTurn().
│   │        CHANGE: Absorb VoiceAgentCapability, call rac_voice_agent_* and
│   │        rac_audio_pipeline_* functions, coordinate STT→LLM→TTS pipeline.
│   │
│   └── RunAnywhere+VoiceSession.swift         413 lines  ✅ KEEP
│       WHY: VoiceSession class managing continuous voice conversation. Complex
│            coordination with timers, state, callbacks. Keep as-is initially.
│
├── Sessions/
│   └── LiveTranscriptionSession.swift         282 lines  ✅ KEEP
│       WHY: Manages live STT session with AudioCaptureManager callbacks.
│            Continuous streaming transcription. Keep - uses platform audio capture.
│
└── RunAnywhere.swift                          434 lines  ✅ KEEP
    WHY: Main SDK class with initialize(), shutdown(), isInitialized.
         Coordinates all components. Entry point - no changes needed.

TOTAL: 16 files, ~2,759 lines → ~3,500 lines after absorbing capabilities
```

### Foundation/ Directory - File Analysis with Reasoning

```
Foundation/
├── Constants/
│   ├── DevelopmentConfig.swift                 44 lines  ✅ KEEP
│   │   WHY: Dev-mode constants (baseURL, debug flags). Environment config.
│   │
│   └── SDKConstants.swift                      36 lines  ✅ KEEP
│       WHY: SDK version, bundle ID, default values. Shared constants.
│
├── DependencyInjection/
│   └── ServiceContainer.swift                 236 lines  🟡 SIMPLIFY (~150 lines after)
│       WHY: Currently has lazy llmCapability, sttCapability, ttsCapability, etc.
│            CHANGE: Remove all capability properties. Keep only:
│            - modelRegistry (model file discovery)
│            - fileManager (file operations)
│            - audioPlaybackManager (platform audio)
│            - audioCaptureManager (platform audio)
│
├── Errors/
│   ├── ErrorCategory.swift                     56 lines  ✅ KEEP
│   │   WHY: Error category enum (llm, stt, tts, vad, voice, general).
│   │        Used throughout SDK for error classification.
│   │
│   ├── ErrorCode.swift                        318 lines  ✅ KEEP
│   │   WHY: All error codes (LLMError, STTError, TTSError, etc.).
│   │        Maps to C++ error codes. Swift API needs these.
│   │
│   └── SDKError.swift                         488 lines  ✅ KEEP
│       WHY: Main error type with factory methods. Handles error conversion
│            from C++ rac_result_t. LocalizedError conformance.
│
├── Security/
│   └── KeychainManager.swift                  208 lines  ✅ KEEP
│       WHY: Uses Security framework (SecItemAdd, SecItemCopyMatching).
│            Apple Keychain API - CANNOT implement in C++.
│
└── Utilities/
    ├── NetworkHelpers.swift                    35 lines  ✅ KEEP
    │   WHY: URL validation, network check utilities. Small helpers.
    │
    └── NetworkRetry.swift                     111 lines  ✅ KEEP
        WHY: Retry logic with exponential backoff. Used for downloads.

TOTAL: 9 files, ~1,532 lines → ~1,450 lines after simplifying ServiceContainer
```

---

## C++ AS CANONICAL SOURCE OF TRUTH (Cross-Platform Types)

### Architecture: Single Source of Truth

All **public API types** (options, results, configurations) will be defined in C++ headers.
Platform SDKs (Swift, Kotlin, React Native, Flutter) create **thin wrappers** that convert to/from C types.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    C/C++ Headers (SINGLE SOURCE OF TRUTH)                   │
│                                                                             │
│  runanywhere-commons/include/rac/public/                                   │
│  ├── rac_llm_public.h      → LLM options, result, config                   │
│  ├── rac_stt_public.h      → STT options, result, config                   │
│  ├── rac_tts_public.h      → TTS options, result, config                   │
│  ├── rac_vad_public.h      → VAD options, result, config                   │
│  └── rac_voice_agent_public.h → VoiceAgent options, result, config         │
│                                                                             │
│  Each header defines:                                                       │
│  - Options struct (input to API)                                           │
│  - Result struct (output from API)                                         │
│  - Configuration struct (initialization params)                            │
│  - Default values and validation ranges                                    │
└─────────────────────────────────┬───────────────────────────────────────────┘
                                  │
        ┌─────────────────────────┼─────────────────────────┐
        │                         │                         │
        ▼                         ▼                         ▼
┌───────────────────┐   ┌───────────────────┐   ┌───────────────────┐
│      Swift        │   │      Kotlin       │   │   Flutter/Dart    │
│  (iOS/macOS)      │   │    (Android)      │   │   (Cross-plat)    │
│                   │   │                   │   │                   │
│ struct LLMOptions │   │ data class        │   │ class LLMOptions  │
│ {                 │   │ LLMOptions(       │   │ {                 │
│   let maxTokens   │   │   maxTokens: Int  │   │   final maxTokens │
│   let temperature │   │   temperature     │   │   final temperature│
│ }                 │   │ )                 │   │ }                 │
│                   │   │                   │   │                   │
│ // Converts to C  │   │ // Converts via   │   │ // Converts via   │
│ func toCOptions() │   │ // JNI bridge     │   │ // dart:ffi       │
└───────────────────┘   └───────────────────┘   └───────────────────┘
```

### Benefits of This Approach

| Benefit | Description |
|---------|-------------|
| **Single Definition** | Change once in C++, all platforms get it |
| **Consistency** | All platforms have identical field names, types, defaults |
| **Validation** | C++ validates once, all platforms benefit |
| **Documentation** | Document once in C++ headers |
| **No Drift** | Platforms can't accidentally diverge |
| **Testing** | Test once in C++, validated across all platforms |

### Types to Move to C++ (Currently in Swift)

#### LLM Types

| Swift Type | C++ Type | Status | Action |
|------------|----------|--------|--------|
| `LLMGenerationOptions` | `rac_llm_options_t` | 🟡 Partial | Add missing fields to C++ |
| `LLMGenerationResult` | `rac_llm_result_t` | 🟡 Partial | Add thinkingContent, validation |
| `LLMConfiguration` | `rac_llm_config_t` | ✅ Exists | Use directly |
| `ThinkingTagPattern` | `rac_thinking_pattern_t` | ❌ Missing | Add to C++ |

**Swift `LLMGenerationOptions` fields to ensure exist in C++:**
```c
typedef struct rac_llm_options {
    int32_t max_tokens;           // ✅ Exists
    float temperature;            // ✅ Exists
    float top_p;                  // ✅ Exists
    const char* system_prompt;    // ✅ Exists
    rac_bool_t streaming_enabled; // ✅ Exists
    const char** stop_sequences;  // 🔴 ADD
    size_t stop_sequences_count;  // 🔴 ADD
    rac_structured_output_config_t* structured_output; // 🔴 ADD
    rac_inference_framework_t preferred_framework;     // 🔴 ADD
} rac_llm_options_t;
```

**Swift `LLMGenerationResult` fields to ensure exist in C++:**
```c
typedef struct rac_llm_result {
    const char* text;              // ✅ Exists
    const char* thinking_content;  // 🔴 ADD
    int32_t input_tokens;          // ✅ Exists
    int32_t output_tokens;         // ✅ Exists
    double latency_ms;             // ✅ Exists
    double tokens_per_second;      // ✅ Exists
    double time_to_first_token_ms; // 🔴 ADD (for streaming)
    int32_t thinking_tokens;       // 🔴 ADD
    int32_t response_tokens;       // 🔴 ADD
    rac_structured_output_validation_t validation; // 🔴 ADD
} rac_llm_result_t;
```

#### STT Types

| Swift Type | C++ Type | Status | Action |
|------------|----------|--------|--------|
| `STTOptions` | `rac_stt_options_t` | 🟡 Partial | Add missing fields |
| `STTOutput` | `rac_stt_result_t` | 🟡 Partial | Add segments, timestamps |

**Swift `STTOptions` fields to ensure exist in C++:**
```c
typedef struct rac_stt_options {
    const char* language;          // ✅ Exists
    rac_bool_t enable_timestamps;  // 🔴 ADD
    rac_bool_t enable_punctuation; // 🔴 ADD
    int32_t max_alternatives;      // 🔴 ADD
    rac_inference_framework_t preferred_framework; // 🔴 ADD
} rac_stt_options_t;
```

**Swift `STTOutput` fields to ensure exist in C++:**
```c
typedef struct rac_stt_result {
    const char* text;              // ✅ Exists
    float confidence;              // ✅ Exists
    const char* language;          // 🔴 ADD
    rac_stt_segment_t* segments;   // 🔴 ADD
    size_t segments_count;         // 🔴 ADD
    double duration_ms;            // 🔴 ADD
    double real_time_factor;       // 🔴 ADD
} rac_stt_result_t;

typedef struct rac_stt_segment {
    const char* text;
    double start_time_ms;
    double end_time_ms;
    float confidence;
} rac_stt_segment_t;
```

#### TTS Types

| Swift Type | C++ Type | Status | Action |
|------------|----------|--------|--------|
| `TTSOptions` | `rac_tts_options_t` | 🟡 Partial | Add rate, pitch, volume |
| `TTSOutput` | `rac_tts_result_t` | 🟡 Partial | Add format info |

**Swift `TTSOptions` fields to ensure exist in C++:**
```c
typedef struct rac_tts_options {
    const char* voice;             // ✅ Exists
    const char* language;          // 🔴 ADD
    float speaking_rate;           // 🔴 ADD (0.5-2.0)
    float pitch;                   // 🔴 ADD (0.5-2.0)
    float volume;                  // 🔴 ADD (0.0-1.0)
    rac_audio_format_t output_format; // 🔴 ADD
} rac_tts_options_t;
```

**Swift `TTSOutput` fields to ensure exist in C++:**
```c
typedef struct rac_tts_result {
    const uint8_t* audio_data;     // ✅ Exists
    size_t audio_data_size;        // ✅ Exists
    double duration_ms;            // 🔴 ADD
    int32_t sample_rate;           // 🔴 ADD
    rac_audio_format_t format;     // 🔴 ADD
} rac_tts_result_t;
```

#### VAD Types

| Swift Type | C++ Type | Status | Action |
|------------|----------|--------|--------|
| `VADOutput` | `rac_vad_result_t` | ✅ Complete | Use directly |
| `VADStatistics` | `rac_energy_vad_stats_t` | ✅ Complete | Use directly |
| `SpeechActivityEvent` | `rac_speech_activity_t` | ✅ Exists | Use directly |

#### VoiceAgent Types

| Swift Type | C++ Type | Status | Action |
|------------|----------|--------|--------|
| `VoiceAgentConfiguration` | `rac_voice_agent_config_t` | 🔴 Missing | Add to C++ |
| `VoiceAgentResult` | `rac_voice_agent_result_t` | 🔴 Missing | Add to C++ |

**Swift `VoiceAgentConfiguration` to add to C++:**
```c
typedef struct rac_voice_agent_config {
    double cooldown_duration_ms;   // Default: 800
    double max_tts_duration_ms;    // Default: 30000
    rac_bool_t strict_transitions; // Default: true
} rac_voice_agent_config_t;
```

**Swift `VoiceAgentResult` to add to C++:**
```c
typedef struct rac_voice_agent_result {
    rac_stt_result_t transcription;
    rac_llm_result_t response;
    rac_tts_result_t audio_output;
    double total_latency_ms;
    rac_audio_pipeline_state_t final_state;
} rac_voice_agent_result_t;
```

### Swift Thin Wrapper Pattern

After C++ has all types, Swift types become **thin wrappers**:

```swift
// LLMGenerationOptions.swift - THIN WRAPPER over C++
public struct LLMGenerationOptions: Sendable {
    public let maxTokens: Int
    public let temperature: Float
    public let topP: Float
    public let systemPrompt: String?
    public let streamingEnabled: Bool
    public let stopSequences: [String]
    public let preferredFramework: InferenceFramework?

    // Default initializer mirrors C++ defaults
    public init(
        maxTokens: Int = 100,       // RAC_LLM_DEFAULT_MAX_TOKENS
        temperature: Float = 0.8,   // RAC_LLM_DEFAULT_TEMPERATURE
        topP: Float = 1.0,          // RAC_LLM_DEFAULT_TOP_P
        systemPrompt: String? = nil,
        streamingEnabled: Bool = false,
        stopSequences: [String] = [],
        preferredFramework: InferenceFramework? = nil
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.systemPrompt = systemPrompt
        self.streamingEnabled = streamingEnabled
        self.stopSequences = stopSequences
        self.preferredFramework = preferredFramework
    }

    // MARK: - C Conversion

    /// Convert to C struct for API calls
    func withCOptions<T>(_ body: (UnsafePointer<rac_llm_options_t>) throws -> T) rethrows -> T {
        var cOptions = rac_llm_options_t()
        cOptions.max_tokens = Int32(maxTokens)
        cOptions.temperature = temperature
        cOptions.top_p = topP
        cOptions.streaming_enabled = streamingEnabled ? RAC_TRUE : RAC_FALSE
        // ... handle strings and arrays
        return try body(&cOptions)
    }
}

// LLMGenerationResult.swift - THIN WRAPPER over C++
public struct LLMGenerationResult: Sendable {
    public let text: String
    public let thinkingContent: String?
    public let inputTokens: Int
    public let outputTokens: Int
    public let latencyMs: TimeInterval
    public let tokensPerSecond: Double
    public let timeToFirstTokenMs: Double?

    // MARK: - C Conversion

    /// Create from C result struct
    init(from cResult: rac_llm_result_t) {
        self.text = cResult.text.map { String(cString: $0) } ?? ""
        self.thinkingContent = cResult.thinking_content.map { String(cString: $0) }
        self.inputTokens = Int(cResult.input_tokens)
        self.outputTokens = Int(cResult.output_tokens)
        self.latencyMs = cResult.latency_ms
        self.tokensPerSecond = cResult.tokens_per_second
        self.timeToFirstTokenMs = cResult.time_to_first_token_ms > 0
            ? cResult.time_to_first_token_ms : nil
    }
}
```

### Kotlin Thin Wrapper Pattern (Example)

```kotlin
// LLMGenerationOptions.kt - THIN WRAPPER over C++
data class LLMGenerationOptions(
    val maxTokens: Int = 100,
    val temperature: Float = 0.8f,
    val topP: Float = 1.0f,
    val systemPrompt: String? = null,
    val streamingEnabled: Boolean = false,
    val stopSequences: List<String> = emptyList()
) {
    // JNI conversion handled by bridge layer
    internal fun toNative(): Long = nativeCreateOptions(
        maxTokens, temperature, topP, systemPrompt,
        streamingEnabled, stopSequences.toTypedArray()
    )

    private external fun nativeCreateOptions(...): Long
}

// LLMGenerationResult.kt - THIN WRAPPER over C++
data class LLMGenerationResult(
    val text: String,
    val thinkingContent: String?,
    val inputTokens: Int,
    val outputTokens: Int,
    val latencyMs: Double,
    val tokensPerSecond: Double
) {
    companion object {
        // Created from JNI
        internal fun fromNative(ptr: Long): LLMGenerationResult {
            return nativeGetResult(ptr)
        }
        private external fun nativeGetResult(ptr: Long): LLMGenerationResult
    }
}
```

### Flutter/Dart Thin Wrapper Pattern (Example)

```dart
// llm_options.dart - THIN WRAPPER over C++
class LLMGenerationOptions {
  final int maxTokens;
  final double temperature;
  final double topP;
  final String? systemPrompt;
  final bool streamingEnabled;

  const LLMGenerationOptions({
    this.maxTokens = 100,
    this.temperature = 0.8,
    this.topP = 1.0,
    this.systemPrompt,
    this.streamingEnabled = false,
  });

  // FFI conversion
  Pointer<rac_llm_options_t> toNative(Arena arena) {
    final options = arena<rac_llm_options_t>();
    options.ref.max_tokens = maxTokens;
    options.ref.temperature = temperature;
    options.ref.top_p = topP;
    options.ref.streaming_enabled = streamingEnabled ? 1 : 0;
    // ... handle strings
    return options;
  }
}

// llm_result.dart - THIN WRAPPER over C++
class LLMGenerationResult {
  final String text;
  final String? thinkingContent;
  final int inputTokens;
  final int outputTokens;
  final double latencyMs;
  final double tokensPerSecond;

  LLMGenerationResult._({
    required this.text,
    this.thinkingContent,
    required this.inputTokens,
    required this.outputTokens,
    required this.latencyMs,
    required this.tokensPerSecond,
  });

  // Create from FFI result
  factory LLMGenerationResult.fromNative(Pointer<rac_llm_result_t> ptr) {
    return LLMGenerationResult._(
      text: ptr.ref.text.toDartString(),
      thinkingContent: ptr.ref.thinking_content?.toDartString(),
      inputTokens: ptr.ref.input_tokens,
      outputTokens: ptr.ref.output_tokens,
      latencyMs: ptr.ref.latency_ms,
      tokensPerSecond: ptr.ref.tokens_per_second,
    );
  }
}
```

### C++ Header Organization

```
runanywhere-commons/include/rac/
├── public/                              # PUBLIC API TYPES (shared across all SDKs)
│   ├── rac_public_types.h               # Common types: bool, result codes, etc.
│   ├── rac_llm_public.h                 # LLM: options, result, config
│   ├── rac_stt_public.h                 # STT: options, result, config
│   ├── rac_tts_public.h                 # TTS: options, result, config
│   ├── rac_vad_public.h                 # VAD: options, result, config
│   └── rac_voice_agent_public.h         # VoiceAgent: options, result, config
│
├── features/                            # INTERNAL IMPLEMENTATION (existing)
│   ├── llm/
│   ├── stt/
│   ├── tts/
│   ├── vad/
│   └── voice_agent/
│
└── core/                                # CORE TYPES (existing)
    ├── rac_types.h
    └── rac_result.h
```

---

## CRITICAL RULES - MUST FOLLOW

> **iOS Swift SDK is the SINGLE SOURCE OF TRUTH**
>
> 1. **DO NOT INVENT NEW LOGIC** - Copy exact logic from corresponding Swift file
> 2. **DO NOT ADD FEATURES** - If not in Swift, don't add to C++
> 3. **DO NOT REFACTOR** - Translate as-is, preserving same structure
> 4. **DO NOT OPTIMIZE** - Keep same algorithm, same flow, same behavior
> 5. **NO STUBS** - Every function must have complete implementation
>
> **For EVERY C++ file:**
> 1. FIRST: Open the corresponding Swift file
> 2. READ: Understand the exact logic, state machine, edge cases
> 3. TRANSLATE: Convert Swift syntax to C/C++ syntax line-by-line
> 4. VERIFY: The C++ code should be a direct 1:1 port of Swift

---

## Current Architecture Analysis (PROBLEM)

### Unnecessary Layering

```
Current (OVER-ENGINEERED):
┌─────────────────────────────────────────────────────────────────┐
│ Public API (RunAnywhere+*.swift)                                │
│ - Just passes to serviceContainer.*Capability                   │
│ - NO actual work done here                                      │
└──────────────────────────────────────┬──────────────────────────┘
                                       │
┌──────────────────────────────────────▼──────────────────────────┐
│ ServiceContainer                                                 │
│ - Creates/manages Capability actors                             │
│ - Thread-safe lazy initialization                               │
└──────────────────────────────────────┬──────────────────────────┘
                                       │
┌──────────────────────────────────────▼──────────────────────────┐
│ Capability Actors (*Capability.swift) - 2,200 LINES             │
│ - LLMCapability: 542 lines                                      │
│ - STTCapability: 434 lines                                      │
│ - TTSCapability: 437 lines                                      │
│ - VADCapability: 283 lines                                      │
│ - VoiceAgentCapability: 366 lines                               │
│                                                                  │
│ What they do:                                                    │
│ - Manage C++ handle lifecycle                                    │
│ - Convert Swift types to C structs                              │
│ - Call C++ rac_* functions                                      │
│ - Track analytics                                                │
│ - Emit events                                                    │
│                                                                  │
│ ⚠️ ALL OF THIS CAN BE DONE IN PUBLIC LAYER                      │
└──────────────────────────────────────┬──────────────────────────┘
                                       │
┌──────────────────────────────────────▼──────────────────────────┐
│ Analytics Services (*AnalyticsService.swift) - 1,200 LINES      │
│ - GenerationAnalyticsService: 437 lines                         │
│ - STTAnalyticsService: 297 lines                                │
│ - TTSAnalyticsService: 265 lines                                │
│ - VADAnalyticsService: 246 lines                                │
│                                                                  │
│ What they do:                                                    │
│ - Wrap C++ rac_*_analytics_* functions                          │
│ - Convert Swift types to C structs                              │
│ - Emit Swift events                                              │
│                                                                  │
│ ⚠️ PURE WRAPPERS - CAN BE ELIMINATED                            │
└──────────────────────────────────────┬──────────────────────────┘
                                       │
┌──────────────────────────────────────▼──────────────────────────┐
│ C++ API (rac_* functions)                                       │
│ - All actual business logic                                      │
│ - State machines                                                 │
│ - Analytics calculation                                          │
│ - Validation                                                     │
└─────────────────────────────────────────────────────────────────┘
```

### Line Count Analysis

| Layer | Files | Lines | Purpose | Can Remove? |
|-------|-------|-------|---------|-------------|
| **Capability Actors** | 5 | ~2,200 | C++ handle wrapper | ✅ YES |
| **Analytics Services** | 4 | ~1,200 | C++ analytics wrapper | ✅ YES |
| **Model Types** | ~25 | ~1,500 | Swift types | 🟡 PARTIAL |
| **Protocols** | 4 | ~200 | Service interfaces | ✅ YES |
| **StructuredOutput** | 6 | ~600 | JSON handling | ✅ YES (in C++ now) |
| **Events** | 4 | ~400 | Event definitions | ❌ KEEP |
| **Platform (AVFoundation)** | 3 | ~700 | Audio capture/playback | ❌ KEEP |
| **Total Features/** | 51 | **8,310** | | **~4,500 removable** |

---

## Target Architecture (MINIMAL)

```
Target (MINIMAL):
┌─────────────────────────────────────────────────────────────────┐
│ Public API (RunAnywhere+*.swift) - DOES ALL THE WORK            │
│ ┌─────────────────────────────────────────────────────────────┐│
│ │ Handle Management                                            ││
│ │ - Create handles: rac_*_component_create()                   ││
│ │ - Store in static vars or actor                             ││
│ │ - Destroy on cleanup: rac_*_component_destroy()             ││
│ └─────────────────────────────────────────────────────────────┘│
│ ┌─────────────────────────────────────────────────────────────┐│
│ │ Direct C API Calls                                           ││
│ │ - rac_llm_component_generate()                              ││
│ │ - rac_stt_component_transcribe()                            ││
│ │ - rac_tts_component_synthesize()                            ││
│ │ - etc.                                                       ││
│ └─────────────────────────────────────────────────────────────┘│
│ ┌─────────────────────────────────────────────────────────────┐│
│ │ Inline Type Conversion                                       ││
│ │ - Swift options → rac_*_options_t (inline)                  ││
│ │ - rac_*_result_t → Swift result (inline)                    ││
│ └─────────────────────────────────────────────────────────────┘│
│ ┌─────────────────────────────────────────────────────────────┐│
│ │ Event Emission (minimal)                                     ││
│ │ - EventPublisher.shared.track() for user-facing events      ││
│ │ - C++ handles internal analytics                            ││
│ └─────────────────────────────────────────────────────────────┘│
└────────────────────────────────────┬────────────────────────────┘
                                     │
┌────────────────────────────────────▼────────────────────────────┐
│ Platform Adapters (MUST STAY IN SWIFT)                          │
│ - AudioCaptureManager (AVAudioEngine)                          │
│ - AudioPlaybackManager (AVAudioPlayer)                         │
│ - SystemTTSService (AVSpeechSynthesizer)                       │
│ - KeychainManager (Security framework)                          │
└─────────────────────────────────────────────────────────────────┘
                                     │
┌────────────────────────────────────▼────────────────────────────┐
│ C++ Layer (runanywhere-commons)                                 │
│ - All business logic                                            │
│ - All analytics                                                 │
│ - All validation                                                │
│ - All state machines                                            │
└─────────────────────────────────────────────────────────────────┘
```

---

## Files To REMOVE (Complete Elimination)

### 1. Capability Actors (~2,200 lines)

| File | Lines | Reason |
|------|-------|--------|
| `Features/LLM/LLMCapability.swift` | 542 | Public layer can call C++ directly |
| `Features/STT/STTCapability.swift` | 434 | Public layer can call C++ directly |
| `Features/TTS/TTSCapability.swift` | 437 | Public layer can call C++ directly |
| `Features/VAD/VADCapability.swift` | 283 | Public layer can call C++ directly |
| `Features/VoiceAgent/VoiceAgentCapability.swift` | 366 | Public layer can call C++ directly |

### 2. Analytics Services (~1,200 lines)

| File | Lines | Reason |
|------|-------|--------|
| `Features/LLM/Analytics/GenerationAnalyticsService.swift` | 437 | Pure C++ wrapper - call directly |
| `Features/STT/Analytics/STTAnalyticsService.swift` | 297 | Pure C++ wrapper - call directly |
| `Features/TTS/Analytics/TTSAnalyticsService.swift` | 265 | Pure C++ wrapper - call directly |
| `Features/VAD/Analytics/VADAnalyticsService.swift` | 246 | Pure C++ wrapper - call directly |

### 3. Protocols (~200 lines)

| File | Lines | Reason |
|------|-------|--------|
| `Features/LLM/Protocol/LLMService.swift` | ~20 | No multiple implementations |
| `Features/STT/Protocol/STTService.swift` | ~20 | No multiple implementations |
| `Features/TTS/Protocol/TTSService.swift` | ~20 | No multiple implementations |
| `Features/VAD/Protocol/VADService.swift` | ~20 | No multiple implementations |
| `Features/VAD/Services/SimpleEnergyVADService.swift` | ~150 | Uses C++ energy_vad |

### 4. StructuredOutput (Now in C++) (~500 lines)

| File | Lines | Reason |
|------|-------|--------|
| `Features/LLM/StructuredOutput/StructuredOutputHandler.swift` | 298 | Now in C++ `structured_output.cpp` |
| `Features/LLM/StructuredOutput/StreamAccumulator.swift` | 89 | Redundant with C++ |
| `Features/LLM/StructuredOutput/StreamToken.swift` | ~20 | Simple type, inline |
| `Features/LLM/StructuredOutput/GenerationHints.swift` | 26 | Move to C++ |

### 5. Duplicate Model Types (~600 lines)

| File | Lines | Reason |
|------|-------|--------|
| `Features/LLM/Models/LLMConfiguration.swift` | 143 | Use C++ config directly |
| `Features/STT/Models/STTConfiguration.swift` | ~50 | Use C++ config directly |
| `Features/TTS/Models/TTSConfiguration.swift` | ~50 | Use C++ config directly |
| `Features/VAD/Models/VADConfiguration.swift` | 167 | Use C++ config directly |
| `Features/VAD/Models/VADInput.swift` | 84 | C++ handles validation |

**Total Removable: ~4,700 lines**

---

## Files To KEEP (Platform-Specific)

### Platform APIs (CANNOT migrate to C++)

| File | Lines | Platform API |
|------|-------|--------------|
| `Features/STT/Services/AudioCaptureManager.swift` | 263 | AVAudioEngine, AVAudioSession |
| `Features/TTS/Services/AudioPlaybackManager.swift` | 260 | AVAudioPlayer |
| `Features/TTS/System/SystemTTSService.swift` | 180 | AVSpeechSynthesizer |
| `Features/TTS/System/SystemTTSModule.swift` | ~50 | Module registration |

### Model Types (Needed for Swift API)

| File | Lines | Purpose |
|------|-------|---------|
| `Features/LLM/Models/LLMGenerationOptions.swift` | 67 | Public API type |
| `Features/LLM/Models/LLMGenerationResult.swift` | 82 | Public API type |
| `Features/LLM/Models/LLMStreamingResult.swift` | ~30 | Async stream wrapper |
| `Features/STT/Models/STTOptions.swift` | ~30 | Public API type |
| `Features/STT/Models/STTOutput.swift` | 100 | Public API type |
| `Features/TTS/Models/TTSOptions.swift` | ~40 | Public API type |
| `Features/TTS/Models/TTSOutput.swift` | 177 | Public API type |
| `Features/VoiceAgent/Models/VoiceAgentResult.swift` | ~40 | Public API type |
| `Features/VoiceAgent/Models/VoiceAgentConfiguration.swift` | ~80 | Public API type |

### Events (Needed for Swift EventBus)

| File | Lines | Purpose |
|------|-------|---------|
| `Features/LLM/Analytics/LLMEvent.swift` | ~100 | Swift event definitions |
| `Features/STT/Analytics/STTEvent.swift` | ~80 | Swift event definitions |
| `Features/TTS/Analytics/TTSEvent.swift` | ~80 | Swift event definitions |
| `Features/VAD/Analytics/VADEvent.swift` | ~60 | Swift event definitions |

---

## Rearchitected Public API Example

### Before (Current - Multiple Layers)

```swift
// RunAnywhere+TextGeneration.swift (current)
public extension RunAnywhere {
    static func generate(_ prompt: String, options: LLMGenerationOptions?) async throws -> LLMGenerationResult {
        guard isInitialized else { throw SDKError.general(.notInitialized, "SDK not initialized") }
        try await ensureServicesReady()
        // Just passes to capability layer - NO ACTUAL WORK
        return try await serviceContainer.llmCapability.generate(prompt, options: options ?? LLMGenerationOptions())
    }
}

// LLMCapability.swift (current - 542 lines)
public actor LLMCapability {
    private var handle: rac_handle_t?
    private let analyticsService: GenerationAnalyticsService  // Another layer!

    public func generate(_ prompt: String, options: LLMGenerationOptions) async throws -> LLMGenerationResult {
        // Analytics service call
        let generationId = await analyticsService.startGeneration(...)

        // Build C options
        var cOptions = rac_llm_options_t()
        cOptions.max_tokens = Int32(options.maxTokens)
        // ... more conversion

        // Call C++ API
        var llmResult = rac_llm_result_t()
        let result = rac_llm_component_generate(handle, promptPtr, &cOptions, &llmResult)

        // Analytics service call
        await analyticsService.completeGeneration(...)

        // Build Swift result
        return LLMGenerationResult(...)
    }
}

// GenerationAnalyticsService.swift (current - 437 lines)
public actor GenerationAnalyticsService {
    // Just wraps C++ analytics - REDUNDANT
    public func startGeneration(...) -> String {
        rac_llm_analytics_start_generation(...)  // Just calls C++!
        EventPublisher.shared.track(...)
    }
}
```

### After (Minimal - Single Layer)

```swift
// RunAnywhere+TextGeneration.swift (NEW - does everything)
public extension RunAnywhere {
    // State: handles managed here directly
    private static var llmHandle: rac_handle_t?

    static func generate(_ prompt: String, options: LLMGenerationOptions? = nil) async throws -> LLMGenerationResult {
        guard isInitialized else { throw SDKError.general(.notInitialized, "SDK not initialized") }

        // Ensure handle exists
        let handle = try getLLMHandle()
        let opts = options ?? LLMGenerationOptions()

        // Build C options inline
        var cOptions = rac_llm_options_t()
        cOptions.max_tokens = Int32(opts.maxTokens)
        cOptions.temperature = opts.temperature
        cOptions.top_p = opts.topP
        cOptions.streaming_enabled = RAC_FALSE

        // Call C++ API directly
        var llmResult = rac_llm_result_t()
        let startTime = Date()

        let result = prompt.withCString { promptPtr in
            rac_llm_component_generate(handle, promptPtr, &cOptions, &llmResult)
        }

        guard result == RAC_SUCCESS else {
            let error = SDKError.llm(.generationFailed, "Generation failed: \(result)")
            EventPublisher.shared.track(LLMEvent.generationFailed(error: error))
            throw error
        }

        // Build result inline
        let text = llmResult.text.map { String(cString: $0) } ?? ""
        let latencyMs = Date().timeIntervalSince(startTime) * 1000

        // Emit single event (C++ tracks detailed analytics internally)
        EventPublisher.shared.track(LLMEvent.generationCompleted(...))

        return LLMGenerationResult(
            text: text,
            tokensUsed: Int(llmResult.completion_tokens),
            latencyMs: latencyMs,
            ...
        )
    }

    private static func getLLMHandle() throws -> rac_handle_t {
        if let handle = llmHandle { return handle }
        var newHandle: rac_handle_t?
        guard rac_llm_component_create(&newHandle) == RAC_SUCCESS, let h = newHandle else {
            throw SDKError.llm(.notInitialized, "Failed to create LLM handle")
        }
        llmHandle = h
        return h
    }
}
```

**Benefits:**
- **Single file** instead of 3 files (Public + Capability + AnalyticsService)
- **~800 lines eliminated** for LLM alone
- **No actor overhead** for simple operations
- **Same public API** - no breaking changes

---

## Migration Steps

### Phase 1: Remove Analytics Services (Low Risk)

1. **Move event emission to Public layer**
   - Copy `EventPublisher.shared.track()` calls from AnalyticsService to Public API
   - C++ already tracks metrics internally via `rac_*_analytics_*`

2. **Delete Analytics Services:**
   - `GenerationAnalyticsService.swift`
   - `STTAnalyticsService.swift`
   - `TTSAnalyticsService.swift`
   - `VADAnalyticsService.swift`

**Estimated savings: ~1,200 lines**

### Phase 2: Merge Capability into Public (Medium Risk)

1. **For each capability (LLM, STT, TTS, VAD, VoiceAgent):**
   - Move handle management to Public layer (static var or actor)
   - Move type conversion inline
   - Move C API calls inline
   - Delete capability file

2. **Update ServiceContainer:**
   - Remove capability properties
   - Keep only platform services (modelRegistry, fileManager, etc.)

**Estimated savings: ~2,200 lines**

### Phase 3: Remove Redundant Types (Low Risk)

1. **Delete configuration types that mirror C++:**
   - `LLMConfiguration.swift`
   - `STTConfiguration.swift`
   - `TTSConfiguration.swift`
   - `VADConfiguration.swift`

2. **Keep output types (public API needs them):**
   - `LLMGenerationResult.swift`
   - `STTOutput.swift`
   - `TTSOutput.swift`

**Estimated savings: ~600 lines**

### Phase 4: Remove StructuredOutput Swift Code (Low Risk)

1. **Call C++ structured output functions directly:**
   - `rac_structured_output_extract_json()`
   - `rac_structured_output_validate()`
   - `rac_structured_output_get_system_prompt()`

2. **Delete:**
   - `StructuredOutputHandler.swift`
   - `StreamAccumulator.swift`
   - `GenerationHints.swift`

3. **Keep (Swift-specific):**
   - `Generatable.swift` (Codable protocol)
   - `StructuredOutputGenerationService.swift` (calls C++)

**Estimated savings: ~500 lines**

---

## Line Count Summary

| Current | After | Reduction |
|---------|-------|-----------|
| **Features/**: 8,310 lines | ~3,500 lines | **~58%** |
| **Public/**: ~2,800 lines | ~3,500 lines | +25% (absorbs capability logic) |
| **Total SDK**: ~25,962 lines | ~20,000 lines | **~23%** |

---

## ServiceContainer Changes

### Before
```swift
public class ServiceContainer {
    var llmCapability: LLMCapability { ... }
    var sttCapability: STTCapability { ... }
    var ttsCapability: TTSCapability { ... }
    var vadCapability: VADCapability { ... }
    var voiceAgentCapability: VoiceAgentCapability { ... }

    // Infrastructure
    var modelRegistry: ModelRegistry { ... }
    var fileManager: SimplifiedFileManager { ... }
}
```

### After
```swift
public class ServiceContainer {
    // NO CAPABILITY PROPERTIES - handled in Public layer

    // Infrastructure only
    var modelRegistry: ModelRegistry { ... }
    var fileManager: SimplifiedFileManager { ... }
    var audioPlayback: AudioPlaybackManager { ... }  // Platform-specific
    var audioCaptureManager: AudioCaptureManager { ... }  // Platform-specific
}
```

---

## Public API Changes (NONE)

The public API remains **exactly the same**:

```swift
// These all work identically after the refactor
try await RunAnywhere.generate("Hello")
try await RunAnywhere.transcribe(audioData)
try await RunAnywhere.speak("Hello world")
try await RunAnywhere.processVoiceTurn(audioData)
```

Only the **internal implementation** changes - the capability layer is eliminated and merged into the public layer.

---

## C++ Functions Already Available

The C++ layer already has all the functions needed:

### LLM
- `rac_llm_component_create()` / `_destroy()`
- `rac_llm_component_load_model()` / `_unload()`
- `rac_llm_component_generate()` / `_generate_stream()`
- `rac_llm_analytics_*` (metrics calculation)

### STT
- `rac_stt_component_create()` / `_destroy()`
- `rac_stt_component_load_model()` / `_unload()`
- `rac_stt_component_transcribe()` / `_transcribe_stream()`
- `rac_stt_analytics_*` (metrics calculation)

### TTS
- `rac_tts_component_create()` / `_destroy()`
- `rac_tts_component_load_voice()` / `_unload()`
- `rac_tts_component_synthesize()` / `_synthesize_stream()`
- `rac_tts_analytics_*` (metrics calculation)

### VAD
- `rac_vad_component_create()` / `_destroy()`
- `rac_vad_component_initialize()` / `_cleanup()`
- `rac_vad_component_process()`
- `rac_vad_analytics_*` (metrics calculation)

### VoiceAgent
- `rac_voice_agent_create()` / `_destroy()`
- `rac_voice_agent_initialize()`
- `rac_voice_agent_process_voice_turn()`
- `rac_audio_pipeline_*` (state machine)

### Structured Output
- `rac_structured_output_extract_json()`
- `rac_structured_output_validate()`
- `rac_structured_output_get_system_prompt()`
- `rac_structured_output_prepare_prompt()`

### Model Registry
- `rac_model_detect_format_from_extension()`
- `rac_model_detect_framework_from_format()`
- `rac_model_generate_id()`
- `rac_model_generate_name()`
- `rac_model_filter_models()`

---

## Checklist

### Phase 0: Move Types to C++ (FOUNDATION)
> ⚠️ DO THIS FIRST - Establishes C++ as canonical source of truth

#### Step 0.1: Create C++ Public Headers
- [ ] Create `include/rac/public/` directory structure
- [ ] Create `rac_public_types.h` (common enums, rac_audio_format_t)
- [ ] Create `rac_llm_public.h` (options, result, thinking_pattern)
- [ ] Create `rac_stt_public.h` (options, result, segment, alternative)
- [ ] Create `rac_tts_public.h` (options, result, phoneme, metadata)
- [ ] Create `rac_vad_public.h` (result, statistics - already complete ✅)
- [ ] Create `rac_voice_agent_public.h` (config, result, audio_chunk)

#### Step 0.2: Add Missing Fields to C++ Structs

**LLM Types:**
- [ ] Add `stop_sequences` + `stop_sequences_count` to `rac_llm_options_t`
- [ ] Add `structured_output` pointer to `rac_llm_options_t`
- [ ] Add `preferred_framework` to `rac_llm_options_t`
- [ ] Add `thinking_content` to `rac_llm_result_t`
- [ ] Add `time_to_first_token_ms` to `rac_llm_result_t`
- [ ] Add `thinking_tokens` + `response_tokens` to `rac_llm_result_t`
- [ ] Add `validation` to `rac_llm_result_t`
- [ ] Create `rac_thinking_pattern_t` struct

**STT Types:**
- [ ] Add `detect_language` to `rac_stt_options_t`
- [ ] Add `enable_punctuation` to `rac_stt_options_t`
- [ ] Add `enable_diarization` + `max_speakers` to `rac_stt_options_t`
- [ ] Add `enable_timestamps` to `rac_stt_options_t`
- [ ] Add `vocabulary_filter` + `vocabulary_count` to `rac_stt_options_t`
- [ ] Add `preferred_framework` to `rac_stt_options_t`
- [ ] Create `rac_word_timestamp_t` struct
- [ ] Create `rac_stt_alternative_t` struct
- [ ] Create `rac_stt_metadata_t` struct
- [ ] Add `word_timestamps` array to `rac_stt_result_t`
- [ ] Add `detected_language` to `rac_stt_result_t`
- [ ] Add `alternatives` array to `rac_stt_result_t`
- [ ] Add metadata fields to `rac_stt_result_t`

**TTS Types:**
- [ ] Add `language` to `rac_tts_options_t`
- [ ] Add `speaking_rate` to `rac_tts_options_t`
- [ ] Add `pitch` to `rac_tts_options_t`
- [ ] Add `volume` to `rac_tts_options_t`
- [ ] Add `output_format` to `rac_tts_options_t`
- [ ] Add `sample_rate` to `rac_tts_options_t`
- [ ] Add `use_ssml` to `rac_tts_options_t`
- [ ] Create `rac_tts_phoneme_t` struct
- [ ] Create `rac_tts_metadata_t` struct
- [ ] Add `format` to `rac_tts_result_t`
- [ ] Add `duration_ms` to `rac_tts_result_t`
- [ ] Add `phoneme_timestamps` array to `rac_tts_result_t`
- [ ] Add metadata fields to `rac_tts_result_t`

**VoiceAgent Types:**
- [ ] Create `rac_voice_agent_config_t` struct
- [ ] Create `rac_voice_agent_result_t` struct
- [ ] Create `rac_audio_chunk_t` struct

#### Step 0.3: Add Default Constants to C++
- [ ] Add `RAC_LLM_DEFAULT_MAX_TOKENS`, `RAC_LLM_DEFAULT_TEMPERATURE`, `RAC_LLM_DEFAULT_TOP_P`
- [ ] Add `RAC_STT_DEFAULT_LANGUAGE`, `RAC_STT_DEFAULT_MAX_ALTERNATIVES`
- [ ] Add `RAC_TTS_DEFAULT_SPEAKING_RATE`, `RAC_TTS_DEFAULT_PITCH`, `RAC_TTS_DEFAULT_VOLUME`
- [ ] Add `RAC_VOICE_AGENT_DEFAULT_COOLDOWN_MS`, `RAC_VOICE_AGENT_DEFAULT_MAX_TTS_MS`

#### Step 0.4: Add C++ Bridge Methods to Swift Types (🟢 BRIDGE files)
- [ ] `LLMGenerationOptions.swift`: Add `withCOptions<T>(_ body:) -> T`
- [ ] `LLMGenerationResult.swift`: Add `init(from cResult: rac_llm_result_t)`
- [ ] `ThinkingTagPattern.swift`: Add `withCPattern<T>(_ body:) -> T`
- [ ] `STTOptions.swift`: Add `withCOptions<T>(_ body:) -> T`
- [ ] `STTOutput.swift`: Add `init(from cResult: rac_stt_result_t)`
- [ ] `TTSOptions.swift`: Add `withCOptions<T>(_ body:) -> T`
- [ ] `TTSOutput.swift`: Add `init(from cResult: rac_tts_result_t)`
- [ ] `VADOutput.swift`: Add `init(from cResult: rac_vad_result_t)`
- [ ] `VADStatistics.swift`: Add `init(from cStats: rac_energy_vad_stats_t)`
- [ ] `VoiceAgentConfiguration.swift`: Add `withCConfig<T>(_ body:) -> T`
- [ ] `VoiceAgentResult.swift`: Add `init(from cResult: rac_voice_agent_result_t)`
- [ ] `VoiceAudioChunk.swift`: Add `toCChunk()` and `init(from:)`

#### Step 0.5: Update Build System
- [ ] Update CMakeLists.txt to install public headers
- [ ] Update RACommons.exports if new functions added
- [ ] Verify build: `./build_and_run.sh --build-cpp --build-sdk`

---

### Phase 1: Remove Analytics Services
- [ ] Move LLMEvent emission from GenerationAnalyticsService to RunAnywhere+TextGeneration
- [ ] Move STTEvent emission from STTAnalyticsService to RunAnywhere+STT
- [ ] Move TTSEvent emission from TTSAnalyticsService to RunAnywhere+TTS
- [ ] Move VADEvent emission from VADAnalyticsService to RunAnywhere+VAD
- [ ] Delete all 4 AnalyticsService files
- [ ] Test that analytics events still fire

### Phase 2: Merge Capabilities into Public
- [ ] Refactor RunAnywhere+TextGeneration to manage LLM handle directly
- [ ] Refactor RunAnywhere+STT to manage STT handle directly
- [ ] Refactor RunAnywhere+TTS to manage TTS handle directly
- [ ] Refactor RunAnywhere+VAD to manage VAD handle directly
- [ ] Refactor RunAnywhere+VoiceAgent to manage VoiceAgent handle directly
- [ ] Delete all 5 Capability files
- [ ] Update ServiceContainer to remove capability properties
- [ ] Test all public API functions

### Phase 3: Remove Redundant Types
- [ ] Delete LLMConfiguration.swift (use inline options)
- [ ] Delete STTConfiguration.swift (use inline options)
- [ ] Delete TTSConfiguration.swift (use inline options)
- [ ] Delete VADConfiguration.swift (use C++ validation)
- [ ] Delete VADInput.swift (C++ handles validation)
- [ ] Delete STTInput.swift (pass params directly)
- [ ] Delete TTSInput.swift (pass params directly)
- [ ] Delete STTResult.swift (merge into STTOutput)
- [ ] Delete STTTranscriptionResult.swift (merge into STTOutput)
- [ ] Delete protocol files (LLMService, STTService, TTSService, VADService)

### Phase 4: Remove StructuredOutput Swift Code
- [ ] Update StructuredOutputGenerationService to call C++ functions
- [ ] Delete StructuredOutputHandler.swift
- [ ] Delete StreamAccumulator.swift
- [ ] Delete StreamToken.swift
- [ ] Delete GenerationHints.swift

### Phase 5: Remove AudioPipelineState
- [ ] Update VoiceAgent Public layer to call C++ `rac_audio_pipeline_*` functions
- [ ] Delete AudioPipelineState.swift

### Phase 6: Remove VAD Services
- [ ] Delete SimpleEnergyVADService.swift (call C++ directly)

### Final Verification
- [ ] All public API tests pass
- [ ] Build succeeds with no warnings
- [ ] Line count reduced by ~4,500 lines
- [ ] All 🟢 BRIDGE files have C++ conversion methods
- [ ] C++ types are canonical source of truth

---

## Timeline Estimate

| Phase | Effort | Risk | Description |
|-------|--------|------|-------------|
| **Phase 0: Move Types to C++** | 2-3 days | Low | Add fields to C++ headers, add Swift bridge methods |
| Phase 1: Remove Analytics Services | 1 day | Low | Delete 4 service files, move events |
| Phase 2: Merge Capabilities | 3-4 days | Medium | Delete 5 capability actors, inline to Public |
| Phase 3: Remove Redundant Types | 1 day | Low | Delete configs, inputs, protocols |
| Phase 4: Remove StructuredOutput | 0.5 day | Low | Call C++ functions directly |
| Phase 5: Remove AudioPipelineState | 0.5 day | Low | Use C++ state machine |
| Phase 6: Remove VAD Services | 0.5 day | Low | Call C++ energy_vad directly |
| **Total** | **8-10 days** | |

---

## Success Metrics

After completion:

1. **Swift SDK Footprint:**
   - Features/ directory: ~3,500 lines (down from 8,310)
   - Total SDK: ~20,000 lines (down from ~26,000)
   - Reduction: **~23%**

2. **Architecture:**
   - Public layer calls C++ directly
   - No intermediate capability actors
   - No analytics service wrappers
   - Platform code unchanged

3. **Behavior:**
   - Same public API
   - Same events emitted
   - Same error handling
   - All tests pass

---

## DETAILED EXECUTION PLAN

### Prerequisites (Before Any Deletion)

1. **Verify Build Works**
   ```bash
   cd sdks/examples/ios/RunAnywhereAI/scripts
   ./build_and_run.sh --build-cpp --build-sdk
   ```

2. **Create Backup Branch**
   ```bash
   git checkout -b swift-cleanup-backup
   git push origin swift-cleanup-backup
   git checkout main
   ```

---

### Phase 0: Move Public Types to C++ (FOUNDATION - DO FIRST)

> **This phase establishes C++ as the canonical source of truth for all public API types.**
> All subsequent phases benefit from this foundation.

#### Step 0.1: Create Public Headers Directory Structure

```bash
mkdir -p runanywhere-commons/include/rac/public
```

Create these header files:
- [ ] `rac_public_types.h` - Common types (audio format, inference framework)
- [ ] `rac_llm_public.h` - LLM options, result, config
- [ ] `rac_stt_public.h` - STT options, result, config
- [ ] `rac_tts_public.h` - TTS options, result, config
- [ ] `rac_vad_public.h` - VAD options, result, config
- [ ] `rac_voice_agent_public.h` - VoiceAgent options, result, config

#### Step 0.2: Audit Swift Types vs C++ Types

For each Swift type, compare with existing C++ and add missing fields:

**LLM Types:**
- [ ] Compare `LLMGenerationOptions` → `rac_llm_options_t`
- [ ] Compare `LLMGenerationResult` → `rac_llm_result_t`
- [ ] Add `stop_sequences`, `structured_output`, `preferred_framework` to C++
- [ ] Add `thinking_content`, `time_to_first_token_ms`, `validation` to C++

**STT Types:**
- [ ] Compare `STTOptions` → `rac_stt_options_t`
- [ ] Compare `STTOutput` → `rac_stt_result_t`
- [ ] Add `enable_timestamps`, `enable_punctuation`, `max_alternatives` to C++
- [ ] Add `segments`, `duration_ms`, `real_time_factor` to C++
- [ ] Create `rac_stt_segment_t` struct

**TTS Types:**
- [ ] Compare `TTSOptions` → `rac_tts_options_t`
- [ ] Compare `TTSOutput` → `rac_tts_result_t`
- [ ] Add `language`, `speaking_rate`, `pitch`, `volume`, `output_format` to C++
- [ ] Add `duration_ms`, `sample_rate`, `format` to result

**VAD Types:**
- [ ] Verify `VADOutput` matches `rac_vad_result_t` ✅
- [ ] Verify `VADStatistics` matches `rac_energy_vad_stats_t` ✅

**VoiceAgent Types:**
- [ ] Create `rac_voice_agent_config_t` (cooldown_duration, max_tts_duration)
- [ ] Create `rac_voice_agent_result_t` (transcription, response, audio)

#### Step 0.3: Add Default Value Constants to C++

```c
// In rac_llm_public.h
#define RAC_LLM_DEFAULT_MAX_TOKENS      100
#define RAC_LLM_DEFAULT_TEMPERATURE     0.8f
#define RAC_LLM_DEFAULT_TOP_P           1.0f

// In rac_stt_public.h
#define RAC_STT_DEFAULT_LANGUAGE        "en-US"
#define RAC_STT_DEFAULT_MAX_ALTERNATIVES 1

// In rac_tts_public.h
#define RAC_TTS_DEFAULT_SPEAKING_RATE   1.0f
#define RAC_TTS_DEFAULT_PITCH           1.0f
#define RAC_TTS_DEFAULT_VOLUME          1.0f

// In rac_voice_agent_public.h
#define RAC_VOICE_AGENT_DEFAULT_COOLDOWN_MS      800.0
#define RAC_VOICE_AGENT_DEFAULT_MAX_TTS_MS       30000.0
```

#### Step 0.4: Update Swift Types to Be Thin Wrappers

For each Swift type:
- [ ] Add `func withCOptions<T>(_ body:) -> T` for input types
- [ ] Add `init(from cResult:)` for output types
- [ ] Ensure Swift defaults match C++ `RAC_*_DEFAULT_*` constants
- [ ] Remove any validation logic (C++ handles it)

**Files to UPDATE (not delete):**
| File | Change |
|------|--------|
| `LLMGenerationOptions.swift` | Add `withCOptions()`, match C++ defaults |
| `LLMGenerationResult.swift` | Add `init(from:)` |
| `STTOptions.swift` | Add `withCOptions()`, match C++ defaults |
| `STTOutput.swift` | Add `init(from:)` |
| `TTSOptions.swift` | Add `withCOptions()`, match C++ defaults |
| `TTSOutput.swift` | Add `init(from:)` |
| `VADOutput.swift` | Add `init(from:)` |
| `VoiceAgentConfiguration.swift` | Add `withCConfig()`, match C++ defaults |
| `VoiceAgentResult.swift` | Add `init(from:)` |

#### Step 0.5: Update CMakeLists.txt

- [ ] Add new headers to `RAC_PUBLIC_HEADERS` list
- [ ] Ensure headers are installed to correct location

#### Step 0.6: Update Exports

- [ ] Add any new functions to `RACommons.exports`

#### Step 0.7: Verify Build

```bash
./build_and_run.sh --build-cpp --build-sdk
```

**Estimated Effort: 2-3 days**
**Risk: Low (additive changes, no deletions)**

---

### Phase 1: Remove Analytics Services (Safest First)

#### Step 1.1: Analyze Dependencies
- [ ] Check what calls `GenerationAnalyticsService`
- [ ] Check what calls `STTAnalyticsService`
- [ ] Check what calls `TTSAnalyticsService`
- [ ] Check what calls `VADAnalyticsService`

#### Step 1.2: Move Event Emission to Capability (Intermediate Step)
The capability files already call analytics services. We can:
1. Copy event emission directly into capability
2. Remove analytics service calls
3. Delete analytics service files

**Files to DELETE after step:**
- [ ] `Features/LLM/Analytics/GenerationAnalyticsService.swift` (436 lines)
- [ ] `Features/STT/Analytics/STTAnalyticsService.swift` (296 lines)
- [ ] `Features/TTS/Analytics/TTSAnalyticsService.swift` (264 lines)
- [ ] `Features/VAD/Analytics/VADAnalyticsService.swift` (245 lines)

**Estimated Savings: 1,241 lines**

---

### Phase 2: Remove Protocols (No Implementations)

#### Step 2.1: Verify No Multiple Implementations
- [ ] Search for `LLMService` conformances
- [ ] Search for `STTService` conformances
- [ ] Search for `TTSService` conformances
- [ ] Search for `VADService` conformances

#### Step 2.2: Remove Protocol Usage
- [ ] Remove `: LLMService` from LLMCapability
- [ ] Remove `: STTService` from STTCapability
- [ ] Remove `: TTSService` from TTSCapability
- [ ] Remove `: VADService` from VADCapability

**Files to DELETE:**
- [ ] `Features/LLM/Protocol/LLMService.swift` (100 lines)
- [ ] `Features/STT/Protocol/STTService.swift` (47 lines)
- [ ] `Features/TTS/Protocol/TTSService.swift` (51 lines)
- [ ] `Features/VAD/Protocol/VADService.swift` (83 lines)

**Estimated Savings: 281 lines**

---

### Phase 3: Remove StructuredOutput Swift Code (Now in C++)

#### Step 3.1: Update StructuredOutputGenerationService
- [ ] Replace Swift `StructuredOutputHandler` calls with C++ `rac_structured_output_*`
- [ ] Test JSON extraction still works
- [ ] Test validation still works

#### Step 3.2: Delete Redundant Files
**Files to DELETE:**
- [ ] `Features/LLM/StructuredOutput/StructuredOutputHandler.swift` (297 lines)
- [ ] `Features/LLM/StructuredOutput/StreamAccumulator.swift` (39 lines)
- [ ] `Features/LLM/StructuredOutput/StreamToken.swift` (26 lines)
- [ ] `Features/LLM/StructuredOutput/GenerationHints.swift` (25 lines)

**Files to KEEP:**
- `Generatable.swift` (Swift Codable protocol - cannot move)
- `StructuredOutputGenerationService.swift` (now calls C++)

**Estimated Savings: 387 lines**

---

### Phase 4: Remove Redundant Configuration Types

#### Step 4.1: Verify C++ Has Validation
- [ ] Confirm `rac_vad_component_configure()` validates all fields
- [ ] Confirm `rac_llm_component_configure()` validates all fields
- [ ] Confirm `rac_stt_component_configure()` validates all fields
- [ ] Confirm `rac_tts_component_configure()` validates all fields

#### Step 4.2: Update Capabilities to Use C++ Config
- [ ] LLMCapability: Use `rac_llm_config_t` directly
- [ ] STTCapability: Use `rac_stt_config_t` directly
- [ ] TTSCapability: Use `rac_tts_config_t` directly
- [ ] VADCapability: Use `rac_vad_config_t` directly

**Files to DELETE:**
- [ ] `Features/LLM/Models/LLMConfiguration.swift` (142 lines)
- [ ] `Features/STT/Models/STTConfiguration.swift` (58 lines)
- [ ] `Features/TTS/Models/TTSConfiguration.swift` (165 lines)
- [ ] `Features/VAD/Models/VADConfiguration.swift` (166 lines)
- [ ] `Features/VAD/Models/VADInput.swift` (83 lines)
- [ ] `Features/STT/Models/STTInput.swift` (68 lines)
- [ ] `Features/TTS/Models/TTSInput.swift` (77 lines)

**Estimated Savings: 759 lines**

---

### Phase 5: Remove SimpleEnergyVADService (Uses C++)

#### Step 5.1: Verify C++ Implementation
- [ ] Confirm `rac_energy_vad_*` functions exist and work
- [ ] Confirm VADCapability uses C++ directly

**Files to DELETE:**
- [ ] `Features/VAD/Services/SimpleEnergyVADService.swift` (311 lines)

**Estimated Savings: 311 lines**

---

### Phase 6: Remove AudioPipelineState (Now in C++)

#### Step 6.1: Update VoiceAgentCapability
- [ ] Replace `AudioPipelineStateManager` with `rac_audio_pipeline_*` calls
- [ ] Use `rac_audio_pipeline_is_valid_transition()`
- [ ] Use `rac_audio_pipeline_can_activate_microphone()`
- [ ] Use `rac_audio_pipeline_can_play_tts()`

**Files to DELETE:**
- [ ] `Features/VoiceAgent/Models/AudioPipelineState.swift` (202 lines)

**Estimated Savings: 202 lines**

---

### Phase 7: Merge Capabilities into Public (MAJOR PHASE)

This is the most complex phase. Do ONE capability at a time.

#### Step 7.1: LLM Capability → RunAnywhere+TextGeneration

**Current Flow:**
```
RunAnywhere+TextGeneration → ServiceContainer → LLMCapability → C++
```

**Target Flow:**
```
RunAnywhere+TextGeneration → C++ (direct)
```

- [ ] Add `llmHandle` static var to RunAnywhere+TextGeneration
- [ ] Add `getLLMHandle()` private function
- [ ] Move `generate()` logic from LLMCapability inline
- [ ] Move `generateStream()` logic inline
- [ ] Move `loadModel()` logic inline
- [ ] Add event emission directly
- [ ] Remove `llmCapability` from ServiceContainer
- [ ] Delete `LLMCapability.swift`

**Lines Moved: 541 → ~200 (net savings: ~341 lines)**

#### Step 7.2: STT Capability → RunAnywhere+STT

- [ ] Add `sttHandle` static var to RunAnywhere+STT
- [ ] Add `getSTTHandle()` private function
- [ ] Move `transcribe()` logic inline
- [ ] Move `transcribeStream()` logic inline
- [ ] Move `loadModel()` logic inline
- [ ] Add event emission directly
- [ ] Remove `sttCapability` from ServiceContainer
- [ ] Delete `STTCapability.swift`

**Lines Moved: 433 → ~180 (net savings: ~253 lines)**

#### Step 7.3: TTS Capability → RunAnywhere+TTS

- [ ] Add `ttsHandle` static var to RunAnywhere+TTS
- [ ] Add `getTTSHandle()` private function
- [ ] Move `synthesize()` logic inline
- [ ] Move `synthesizeStream()` logic inline
- [ ] Move `loadVoice()` logic inline
- [ ] Add event emission directly
- [ ] Remove `ttsCapability` from ServiceContainer
- [ ] Delete `TTSCapability.swift`

**Lines Moved: 436 → ~180 (net savings: ~256 lines)**

#### Step 7.4: VAD Capability → RunAnywhere+VAD

- [ ] Add `vadHandle` static var to RunAnywhere+VAD
- [ ] Add `getVADHandle()` private function
- [ ] Move `process()` logic inline
- [ ] Move `configure()` logic inline
- [ ] Add event emission directly
- [ ] Remove `vadCapability` from ServiceContainer
- [ ] Delete `VADCapability.swift`

**Lines Moved: 282 → ~150 (net savings: ~132 lines)**

#### Step 7.5: VoiceAgent Capability → RunAnywhere+VoiceAgent

- [ ] Add `voiceAgentHandle` static var to RunAnywhere+VoiceAgent
- [ ] Add `getVoiceAgentHandle()` private function
- [ ] Move `processVoiceTurn()` logic inline
- [ ] Move `initialize()` logic inline
- [ ] Add event emission directly
- [ ] Remove `voiceAgentCapability` from ServiceContainer
- [ ] Delete `VoiceAgentCapability.swift`

**Lines Moved: 365 → ~200 (net savings: ~165 lines)**

**Total Phase 7 Savings: ~1,147 lines**

---

### Phase 8: Clean Up Remaining Files

#### Step 8.1: Remove Duplicate Output Types
- [ ] Merge `STTResult.swift` into `STTOutput.swift` if duplicate
- [ ] Review `STTTranscriptionResult.swift` for merge

**Potential Additional Savings: ~133 lines**

#### Step 8.2: Update ServiceContainer
- [ ] Remove all capability lazy properties
- [ ] Keep only: modelRegistry, fileManager, audioPlayback, audioCaptureManager

---

### Phase 9: Final Verification

- [ ] Run full build: `./build_and_run.sh --build-cpp --build-sdk`
- [ ] Run all tests
- [ ] Verify all public API functions work
- [ ] Count final line totals

---

## DELETION SAFETY CHECKLIST

Before deleting ANY file, verify:

1. **No External References**
   ```bash
   grep -r "FileName" --include="*.swift" . | grep -v "FileName.swift"
   ```

2. **No Public API Dependencies**
   - Check if type is exposed in Public/ layer
   - Check if type is in any public function signature

3. **Build Succeeds**
   ```bash
   ./build_and_run.sh --build-sdk
   ```

---

## FINAL FILE DELETION LIST

### Phase 1 Deletions (Analytics Services) - 1,241 lines
| File | Lines | Risk |
|------|-------|------|
| `Features/LLM/Analytics/GenerationAnalyticsService.swift` | 436 | Low |
| `Features/STT/Analytics/STTAnalyticsService.swift` | 296 | Low |
| `Features/TTS/Analytics/TTSAnalyticsService.swift` | 264 | Low |
| `Features/VAD/Analytics/VADAnalyticsService.swift` | 245 | Low |

### Phase 2 Deletions (Protocols) - 281 lines
| File | Lines | Risk |
|------|-------|------|
| `Features/LLM/Protocol/LLMService.swift` | 100 | Low |
| `Features/STT/Protocol/STTService.swift` | 47 | Low |
| `Features/TTS/Protocol/TTSService.swift` | 51 | Low |
| `Features/VAD/Protocol/VADService.swift` | 83 | Low |

### Phase 3 Deletions (StructuredOutput) - 387 lines
| File | Lines | Risk |
|------|-------|------|
| `Features/LLM/StructuredOutput/StructuredOutputHandler.swift` | 297 | Low |
| `Features/LLM/StructuredOutput/StreamAccumulator.swift` | 39 | Low |
| `Features/LLM/StructuredOutput/StreamToken.swift` | 26 | Low |
| `Features/LLM/StructuredOutput/GenerationHints.swift` | 25 | Low |

### Phase 4 Deletions (Config Types) - 759 lines
| File | Lines | Risk |
|------|-------|------|
| `Features/LLM/Models/LLMConfiguration.swift` | 142 | Medium |
| `Features/STT/Models/STTConfiguration.swift` | 58 | Medium |
| `Features/TTS/Models/TTSConfiguration.swift` | 165 | Medium |
| `Features/VAD/Models/VADConfiguration.swift` | 166 | Medium |
| `Features/VAD/Models/VADInput.swift` | 83 | Low |
| `Features/STT/Models/STTInput.swift` | 68 | Low |
| `Features/TTS/Models/TTSInput.swift` | 77 | Low |

### Phase 5 Deletions (VAD Service) - 311 lines
| File | Lines | Risk |
|------|-------|------|
| `Features/VAD/Services/SimpleEnergyVADService.swift` | 311 | Medium |

### Phase 6 Deletions (AudioPipelineState) - 202 lines
| File | Lines | Risk |
|------|-------|------|
| `Features/VoiceAgent/Models/AudioPipelineState.swift` | 202 | Medium |

### Phase 7 Deletions (Capabilities) - 2,057 lines
| File | Lines | Risk |
|------|-------|------|
| `Features/LLM/LLMCapability.swift` | 541 | High |
| `Features/STT/STTCapability.swift` | 433 | High |
| `Features/TTS/TTSCapability.swift` | 436 | High |
| `Features/VAD/VADCapability.swift` | 282 | High |
| `Features/VoiceAgent/VoiceAgentCapability.swift` | 365 | High |

---

## TOTAL EXPECTED SAVINGS

| Phase | Lines Deleted | Lines Added | Net Savings | Description |
|-------|---------------|-------------|-------------|-------------|
| **Phase 0** | 0 | ~400 | -400 | C++ headers + Swift bridge methods (investment) |
| Phase 1 | 1,241 | 0 | 1,241 | Analytics services |
| Phase 2 | 281 | 0 | 281 | Protocol files |
| Phase 3 | 387 | 0 | 387 | StructuredOutput files |
| Phase 4 | 759 | 0 | 759 | Config/Input types |
| Phase 5 | 311 | 0 | 311 | VAD services |
| Phase 6 | 202 | 0 | 202 | AudioPipelineState |
| Phase 7 | 2,057 | ~910 | 1,147 | Capability actors → Public |
| **TOTAL** | **5,238** | **~1,310** | **~3,928** |

**Expected Reduction: ~47% of Features/ directory**

### Benefits of Phase 0 Investment

While Phase 0 adds ~400 lines (C++ headers + Swift bridge methods), it provides:

| Benefit | Impact |
|---------|--------|
| **Single Source of Truth** | No more Swift ↔ C++ type drift |
| **Cross-Platform Ready** | Kotlin, Flutter, React Native use same C++ types |
| **Documentation Once** | Document fields in C++ header, all platforms inherit |
| **Validation Once** | C++ validates, Swift/Kotlin/Dart trust it |
| **Consistent Defaults** | `RAC_LLM_DEFAULT_*` constants shared everywhere |
| **Easier Maintenance** | Change once in C++, all SDKs update |

### Files After Migration

| Category | Before | After | Change |
|----------|--------|-------|--------|
| **🔴 DELETE** | 26 files | 0 files | -26 files |
| **🟢 BRIDGE** | 11 files (no bridge) | 11 files (with bridge) | +C++ methods |
| **✅ KEEP-SWIFT** | 9 files | 9 files | No change |
| **✅ KEEP-PLATFORM** | 6 files | 6 files | No change |
| **Features/ Total** | 52 files | 26 files | **-50%** |
