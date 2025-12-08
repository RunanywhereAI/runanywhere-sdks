# Components Module - Complete File Analysis

**Analysis Date:** December 7, 2025
**SDK Version:** 0.15.8
**Total Files Analyzed:** 8

---

## Overview

This document provides a comprehensive analysis of all Swift files in the `Sources/RunAnywhere/Components/` module. Each component follows a clean architecture pattern with service protocols, configurations, input/output models, and component implementations.

---

## Component Readiness Status

| Component | Status | Notes |
|-----------|--------|-------|
| LLMComponent | Fully Functional | Works with external providers (llama.cpp) |
| STTComponent | Fully Functional | Works with external providers (WhisperKit) |
| TTSComponent | Fully Functional | System TTS fallback + external providers |
| VADComponent | Fully Functional | Default SimpleEnergyVAD implementation |
| VoiceAgentComponent | Partially Functional | Works but needs telemetry, concurrency control |
| SpeakerDiarizationComponent | Partially Functional | Basic implementation, needs improvement |
| VLMComponent | Non-Functional | Throws error, requires implementation |
| WakeWordComponent | Non-Functional | Default service always returns false |

---

## `Components/LLM/LLMComponent.swift`

**Role / Responsibility**
- Defines the Language Model (LLM) component for text generation
- Provides protocol-based abstraction for LLM services (allows pluggable implementations)
- Implements component lifecycle management (initialization, model loading, cleanup)
- Handles both streaming and batch text generation
- Manages conversation context and message history

**Key Types**
- `LLMService` (protocol) – Defines interface for language model services with initialize, generate, streamGenerate methods
- `LLMConfiguration` (struct) – Configuration for LLM component including model parameters (context length, temperature, quantization, GPU usage)
- `LLMInput` (struct) – Input model containing messages, system prompt, context, and generation options
- `LLMOutput` (struct) – Output model with generated text, token usage statistics, metadata, and finish reason
- `LLMServiceProvider` (protocol) – Provider pattern for registering external LLM implementations
- `LLMServiceWrapper` (class) – Wrapper to allow protocol-based services to work with BaseComponent
- `LLMComponent` (class) – Main component class extending BaseComponent
- `TokenUsage` (struct) – Token counting for prompt and completion
- `GenerationMetadata` (struct) – Model ID, temperature, generation time, tokens per second
- `FinishReason` (enum) – Completion reason (completed, maxTokens, stopSequence, contentFilter, error)
- `QuantizationLevel` (enum) – Model quantization levels (Q4_0 through F32)

**Key Public APIs**
- `func generate(_ prompt: String, systemPrompt: String?) async throws -> LLMOutput` – Simple text generation
- `func generateWithHistory(_ messages: [Message], systemPrompt: String?) async throws -> LLMOutput` – Generate with conversation history
- `func process(_ input: LLMInput) async throws -> LLMOutput` – Process structured LLM input
- `func streamGenerate(_ prompt: String, systemPrompt: String?) -> AsyncThrowingStream<String, Error>` – Stream tokens
- `func getService() -> LLMService?` – Access underlying service

**Important Internal Logic**
- Model caching via `ModelLifecycleTracker` for cached services before creating new ones
- Provider registry via `ModuleRegistry.shared.llmProvider()` to find registered providers
- Prompt building concatenates messages without role markers, letting LLM service handle formatting
- Token estimation as rough `text.count / 4`

**Dependencies**
- Internal: BaseComponent, ComponentConfiguration, SDKComponent, ModuleRegistry, ModelLifecycleTracker, SDKLogger, EventBus
- External: Foundation

**Usage & Callers**
- Part of main public API for text generation
- Used by VoiceAgentComponent for response generation

**Potential Issues / Smells**
- Token estimation is rough (`text.count / 4`)
- `buildPrompt()` strips role markers – coupling to service implementation
- `@unchecked Sendable` – thread safety verification needed
- `downloadModel()` is simulation code never called
- `conversationContext` property set but never used

**Unused / Dead Code**
- `conversationContext` property – **candidate for removal**
- `modelPath` property – set but never passed to service
- `modelLoadProgress` property – updated but not exposed
- `downloadModel()` method – simulation code

---

## `Components/STT/STTComponent.swift`

**Role / Responsibility**
- Implements Speech-to-Text (STT) component for audio transcription
- Supports both batch and live/streaming transcription modes
- Handles audio format conversion (buffers to data)
- Integrates with telemetry system for transcription analytics
- Manages microphone permissions and audio session configuration

**Key Types**
- `STTService` (protocol) – Interface for speech-to-text services
- `STTConfiguration` (struct) – Configuration including model ID, language, sample rate, punctuation, diarization
- `STTInput` (struct) – Input with audio data/buffer, format, language, VAD output
- `STTOutput` (struct) – Output with transcribed text, confidence, timestamps, language, alternatives
- `STTOptions` (struct) – Transcription options
- `STTResult` / `STTSegment` / `STTAlternative` (structs) – Result structures
- `STTMode` (enum) – Batch vs Live transcription modes
- `STTError` (enum) – Specialized errors for STT
- `STTServiceProvider` (protocol) – Provider pattern for external implementations
- `TranscriptionMetadata` (struct) – Model ID, processing time, audio length, real-time factor

**Key Public APIs**
- `func transcribe(_ audioData: Data, options: STTOptions) async throws -> STTOutput` – Batch transcription
- `func transcribe(_ audioBuffer: AVAudioPCMBuffer, language: String?) async throws -> STTOutput` – From buffer
- `func transcribeWithVAD(_ audioData: Data, format: AudioFormat, vadOutput: VADOutput) async throws -> STTOutput`
- `func liveTranscribe<S: AsyncSequence>(_ audioStream: S, options: STTOptions) -> AsyncThrowingStream<String, Error>`
- `func streamTranscribe<S: AsyncSequence>(_ audioStream: S, language: String?) -> AsyncThrowingStream<String, Error>`
- `var supportsStreaming: Bool` – Check if service supports live mode

**Important Internal Logic**
- Service caching via ModelLifecycleTracker
- Telemetry integration with detailed metrics
- Audio conversion from AVAudioPCMBuffer to Data
- Audio length estimation based on format and sample rate
- Streaming fallback to batch if not supported (3-second chunks)

**Dependencies**
- Internal: BaseComponent, ModuleRegistry, ModelLifecycleTracker, EventBus, AnalyticsQueueManager
- External: Foundation, AVFoundation

**Usage & Callers**
- Public API for speech-to-text
- Used by VoiceAgentComponent for audio transcription

**Potential Issues / Smells**
- `downloadModel()` is simulation code
- Audio length estimation is rough approximation
- Telemetry code duplicated in batch vs streaming paths

**Unused / Dead Code**
- `downloadModel()` method – **candidate for removal**
- `STTServiceAudioFormat` enum – defined but not referenced

---

## `Components/TTS/TTSComponent.swift`

**Role / Responsibility**
- Implements Text-to-Speech (TTS) component for audio synthesis
- Provides system TTS fallback using AVSpeechSynthesizer
- Supports SSML markup for advanced speech control
- Integrates with telemetry for synthesis analytics

**Key Types**
- `TTSService` (protocol) – Interface with synthesize, synthesizeStream, stop, cleanup
- `TTSConfiguration` (struct) – Voice, language, speaking rate, pitch, volume, audio format
- `TTSInput` (struct) – Text, SSML, voice ID, language, options
- `TTSOutput` (struct) – Audio data, format, duration, phoneme timestamps, metadata
- `TTSOptions` (struct) – Synthesis options
- `SystemTTSService` (class) – Default using AVSpeechSynthesizer
- `TTSComponent` (class) – Main component
- `SynthesisMetadata` (struct) – Voice, language, processing time, character count

**Key Public APIs**
- `func synthesize(_ text: String, voice: String?, language: String?) async throws -> TTSOutput`
- `func synthesizeSSML(_ ssml: String, voice: String?, language: String?) async throws -> TTSOutput`
- `func process(_ input: TTSInput) async throws -> TTSOutput`
- `func streamSynthesize(_ text: String, voice: String?, language: String?) -> AsyncThrowingStream<Data, Error>`
- `func getAvailableVoices() -> [String]`
- `func stopSynthesis()`

**Important Internal Logic**
- Provider fallback uses system TTS if no provider registered
- Audio session handling (SystemTTS avoids changing session)
- Async delegate pattern using `CheckedContinuation`
- Thread safety via dedicated `speechQueue`
- Telemetry submission with success/failure metrics

**Dependencies**
- Internal: BaseComponent, ModuleRegistry, ModelLifecycleTracker, EventBus, AnalyticsQueueManager
- External: Foundation, AVFoundation

**Usage & Callers**
- Public API for text-to-speech
- Used by VoiceAgentComponent for audio generation
- SystemTTS available by default

**Potential Issues / Smells**
- `speechContinuation` mutable and accessed from multiple threads
- SystemTTS doesn't support true streaming
- Telemetry hardcoded to "ONNX" framework even for system TTS
- `_isSynthesizing` flag separate from `synthesizer.isSpeaking`

**Unused / Dead Code**
- `currentVoice` property – set but never used
- Phoneme timestamps always nil – feature not implemented

---

## `Components/VAD/VADComponent.swift`

**Role / Responsibility**
- Implements Voice Activity Detection (VAD) to detect speech in audio
- Supports energy-based detection with configurable thresholds
- Provides calibration functionality for adaptive threshold adjustment
- Can process audio buffers or sample arrays
- Supports pause/resume for temporary suspension

**Key Types**
- `VADService` (protocol) – processAudioBuffer, processAudioData, start, stop, reset
- `VADConfiguration` (struct) – Energy threshold, sample rate, frame length, calibration settings
- `VADInput` (struct) – Audio buffer/samples with optional threshold override
- `VADOutput` (struct) – Speech detection boolean, energy level, timestamp
- `SpeechActivityEvent` (enum) – Speech started/ended events
- `VADComponent` (class) – Main component

**Key Public APIs**
- `func detectSpeech(in buffer: AVAudioPCMBuffer) async throws -> VADOutput`
- `func detectSpeech(in samples: [Float]) async throws -> VADOutput`
- `func process(_ input: VADInput) async throws -> VADOutput`
- `func processAudioStream<S: AsyncSequence>(_ stream: S) -> AsyncThrowingStream<VADOutput, Error>`
- `func reset()`, `func start()`, `func stop()`, `func pause()`, `func resume()`
- `func startCalibration() async throws`
- `func getStatistics() -> (current, threshold, ambient, recentAvg, recentMax)?`

**Important Internal Logic**
- Dynamic threshold override per input
- State tracking for speech change detection
- Calibration API for adaptive threshold adjustment
- Statistics from SimpleEnergyVAD for debugging

**Dependencies**
- Internal: BaseComponent, SDKError, SimpleEnergyVAD
- External: Foundation, AVFoundation

**Usage & Callers**
- Used by VoiceAgentComponent for voice activity detection
- Can be used standalone for voice detection

**Potential Issues / Smells**
- No registry/provider pattern – hardcoded to SimpleEnergyVAD
- `isPaused` flag tracked separately from service state
- VADOutput returns `energyThreshold` instead of measured energy (misleading)
- Calibration methods cast to `SimpleEnergyVAD` – tight coupling

**Unused / Dead Code**
- `VADFrameworkAdapter` protocol – defined but no registry
- `lastSpeechState` tracking – tracked but not exposed

---

## `Components/VLM/VLMComponent.swift`

**Role / Responsibility**
- Implements Vision Language Model (VLM) for image understanding
- Processes images with text prompts for analysis, description, Q&A
- Supports object detection and region identification
- **Currently uses placeholder implementation (throws error)**

**Key Types**
- `VLMService` (protocol) – processImage, initialize, cleanup
- `VLMConfiguration` (struct) – Model ID, image size, max tokens, GPU usage, preprocessing
- `VLMInput` (struct) – Image data, prompt, image format, options
- `VLMOutput` (struct) – Text, detected objects, regions, confidence, metadata
- `DetectedObject` / `ImageRegion` / `BoundingBox` (structs) – Object detection results
- `ImagePreprocessing` (enum) – Preprocessing modes
- `MockVLMService` (class) – Mock for testing
- `UnavailableVLMService` (class) – Placeholder that throws error

**Key Public APIs**
- `func analyze(image: Data, prompt: String, format: ImageFormat) async throws -> VLMOutput`
- `func describeImage(_ image: Data, format: ImageFormat) async throws -> VLMOutput`
- `func answerQuestion(about image: Data, question: String, format: ImageFormat) async throws -> VLMOutput`
- `func detectObjects(in image: Data, format: ImageFormat) async throws -> [DetectedObject]`

**Important Internal Logic**
- **NON-FUNCTIONAL**: Throws error during service creation
- Event emission for checking/download even though not functional
- Image preprocessing placeholder (always returns original data)
- Mock service exists for testing with simulated delays

**Dependencies**
- Internal: BaseComponent, SDKError, EventBus, ImageFormat
- External: Foundation, CoreGraphics

**Usage & Callers**
- **Not currently functional** – requires external vision model implementation
- Public API defined but will throw errors

**Potential Issues / Smells**
- **MAJOR**: Component is non-functional placeholder
- Mock and placeholder services in production code
- `preprocessImage()` does nothing
- No telemetry integration

**Unused / Dead Code**
- **ENTIRE COMPONENT** is placeholder/unused
- `MockVLMService`, `UnavailableVLMService` – testing/placeholder code
- `DefaultVLMAdapter`, `downloadModel()`, `preprocessImage()`
- **Candidate for removal**: Entire file until actual VLM implementation ready

---

## `Components/VoiceAgent/VoiceAgentComponent.swift`

**Role / Responsibility**
- Orchestrates VAD, STT, LLM, and TTS components into complete voice pipeline
- Provides end-to-end voice processing: audio → speech detection → transcription → response → synthesis
- Supports both full pipeline processing and individual component access
- Manages pipeline state and event emissions

**Key Types**
- `VoiceAgentService` (class) – Empty placeholder for BaseComponent compatibility
- `VoiceAgentComponent` (class) – Main orchestrator
- `VoiceAgentResult` (struct) – Pipeline result with all stages
- `VoiceAgentEvent` (enum) – Events for each pipeline stage

**Key Public APIs**
- `func processAudio(_ audioData: Data) async throws -> VoiceAgentResult` – Full pipeline
- `func processStream(_ audioStream: AsyncStream<Data>) -> AsyncThrowingStream<VoiceAgentEvent, Error>`
- `func detectVoiceActivity(_ audioData: Data) -> Bool` – VAD only
- `func transcribe(_ audioData: Data) async throws -> String?` – STT only
- `func generateResponse(_ prompt: String) async throws -> String?` – LLM only
- `func synthesizeSpeech(_ text: String) async throws -> Data?` – TTS only
- Public component properties: `vadComponent`, `sttComponent`, `llmComponent`, `ttsComponent`

**Important Internal Logic**
- Pipeline flow: VAD → STT → LLM → TTS with early exit if no speech
- All four components initialized during service initialization
- Event publishing at each pipeline stage
- Data conversion using helper extension

**Dependencies**
- Internal: BaseComponent, EventBus, VADComponent, STTComponent, LLMComponent, TTSComponent
- External: Foundation

**Usage & Callers**
- Main entry point for complete voice AI pipeline
- Components can be accessed individually for custom workflows

**Potential Issues / Smells**
- `VoiceAgentService` is empty placeholder
- `isProcessing` flag set but not used to prevent concurrent processing
- `processQueue` created but never used
- Direct service access via `getService()` – could use component APIs
- No validation that all components initialized successfully
- `Data.toFloatArray()` helper assumes specific memory layout – unsafe
- No telemetry tracking

**Unused / Dead Code**
- `isProcessing` property – **candidate for removal** (or implement concurrency control)
- `processQueue` property – created but never used
- `VoiceAgentService` class – empty placeholder

---

## `Components/WakeWord/WakeWordComponent.swift`

**Role / Responsibility**
- Implements wake word detection (e.g., "Hey Siri", "OK Google")
- Provides interface for always-listening voice activation
- **Currently uses default placeholder (always returns false)**

**Key Types**
- `WakeWordService` (protocol) – startListening, stopListening, processAudioBuffer
- `WakeWordConfiguration` (struct) – Model ID, wake words, sensitivity, buffer size, confidence threshold
- `WakeWordInput` (struct) – Audio buffer with optional timestamp
- `WakeWordOutput` (struct) – Detected boolean, wake word, confidence, metadata
- `WakeWordServiceProvider` (protocol) – Provider pattern
- `DefaultWakeWordService` (class) – Default that always returns false
- `WakeWordComponent` (class) – Main component

**Key Public APIs**
- `func startListening() async throws`
- `func stopListening() async throws`
- `func process(_ input: WakeWordInput) async throws -> WakeWordOutput`
- `var isListening: Bool`

**Important Internal Logic**
- **NON-FUNCTIONAL**: Default service always returns false for detection
- State tracking with `isDetecting` flag
- Measures processing time even though detection always false

**Dependencies**
- Internal: BaseComponent, SDKError, EventBus
- External: Foundation

**Usage & Callers**
- Designed for voice-activated features
- **Currently non-functional** – requires external wake word provider

**Potential Issues / Smells**
- **MAJOR**: Non-functional default implementation
- TODO comment indicates registry support not implemented
- No provider registry pattern implemented
- No telemetry integration

**Unused / Dead Code**
- `WakeWordServiceProvider` protocol – no registry to use it
- `isDetecting` property – tracked but never exposed
- **Candidate for removal/TODO**: Entire component until implementation ready

---

## `Components/SpeakerDiarization/SpeakerDiarizationComponent.swift`

**Role / Responsibility**
- Implements speaker diarization to identify and separate different speakers
- Segments audio by speaker with timestamps
- Creates labeled transcriptions when combined with STT output
- Maintains speaker profiles with embeddings and statistics

**Key Types**
- `SpeakerDiarizationService` (protocol) – processAudio, getAllSpeakers, reset
- `SpeakerInfo` (struct) – Speaker ID, name, confidence, embedding
- `SpeakerDiarizationConfiguration` (struct) – Max speakers, min speech duration, change threshold
- `SpeakerDiarizationInput` (struct) – Audio data, format, transcription, expected speakers
- `SpeakerDiarizationOutput` (struct) – Segments, profiles, labeled transcription, metadata
- `SpeakerSegment` / `SpeakerProfile` / `LabeledTranscription` (structs)
- `SpeakerDiarizationComponent` (class) – Main component

**Key Public APIs**
- `func diarize(_ audioData: Data, format: AudioFormat) async throws -> SpeakerDiarizationOutput`
- `func diarizeWithTranscription(_ audioData: Data, transcription: STTOutput, format: AudioFormat) async throws -> SpeakerDiarizationOutput`
- `func process(_ input: SpeakerDiarizationInput) async throws -> SpeakerDiarizationOutput`
- `func getSpeakerProfile(id: String) -> SpeakerProfile?`
- `func resetProfiles()`

**Important Internal Logic**
- Segmentation based on window size from configuration
- Profile building aggregates segments into speaker profiles
- Profile storage maintains dictionary of speaker profiles
- Labeled transcription matches word timestamps to speaker segments
- Simple energy-based method (basic implementation)

**Dependencies**
- Internal: BaseComponent, SDKError, EventBus, AudioFormat, STTOutput, DefaultSpeakerDiarization
- External: Foundation

**Usage & Callers**
- Used to identify different speakers in multi-speaker audio
- Can be combined with STT output for speaker-labeled transcriptions

**Potential Issues / Smells**
- No provider registry pattern – hardcoded to DefaultSpeakerDiarizationAdapter
- Simple segmentation uses fixed window size, doesn't detect speaker changes
- `speakerProfiles` dictionary grows unbounded
- Audio conversion assumes Float memory layout – unsafe
- Labeled transcription matching is O(n*m) complexity
- No telemetry integration

**Unused / Dead Code**
- `SpeakerDiarizationFrameworkAdapter` protocol – no registry
- `isServiceReady` property – set but never checked
- `downloadModel()` method – simulation code

---

## Cross-Cutting Analysis

### Common Patterns

1. **Architecture Pattern**: All components extend `BaseComponent<ServiceType>` with Service protocol + Configuration struct + Input/Output structs
2. **Threading Model**: All components marked `@MainActor`, many use `@unchecked Sendable`
3. **Lifecycle Management**: `createService()` → `initializeService()` → `performCleanup()` override pattern
4. **Telemetry Integration**: Only STT and TTS have telemetry (others missing)
5. **Configuration Validation**: All configurations implement `validate()` method

### Code Quality Issues

**Critical Issues**
1. VLMComponent entirely non-functional
2. WakeWordComponent non-functional
3. Thread safety – widespread `@unchecked Sendable` without verification
4. Data conversion – unsafe assumptions about memory layout

**Consistency Issues**
1. Telemetry only in 2/8 components (STT, TTS)
2. Provider registry used inconsistently
3. Model download simulation code in multiple files
4. Error handling varies

**Technical Debt**
1. Simulation/mock code in production
2. Unused properties
3. Rough estimations (token counts, audio duration)
4. Duplicated code

---

## Dependency Graph

```
VoiceAgentComponent
  ├── VADComponent → SimpleEnergyVAD
  ├── STTComponent → External STTService (WhisperKit)
  ├── LLMComponent → External LLMService (llama.cpp)
  └── TTSComponent → SystemTTSService | External TTSService

SpeakerDiarizationComponent → DefaultSpeakerDiarization
WakeWordComponent → DefaultWakeWordService (non-functional)
VLMComponent → UnavailableVLMService (non-functional)
```

---
*This document is part of the RunAnywhere Swift SDK current-state documentation.*
