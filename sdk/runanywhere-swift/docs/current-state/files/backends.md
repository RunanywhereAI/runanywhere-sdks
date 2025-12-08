# Backend Modules - Complete File Analysis

**Analysis Date:** December 7, 2025
**SDK Version:** 0.15.8
**Total Files Analyzed:** 29 Swift files + 4 C headers = 33 files

---

## Overview

This document provides comprehensive analysis of all backend adapter modules:
- **ONNXRuntime** (8 files) - ONNX Runtime for STT/TTS
- **LlamaCPPRuntime** (4 files) - llama.cpp for LLM
- **WhisperKitTranscription** (6 files) - WhisperKit for STT
- **FoundationModelsAdapter** (3 files) - Apple Foundation Models for LLM
- **FluidAudioDiarization** (2 files) - FluidAudio for speaker diarization
- **CRunAnywhereCore** (4 C headers) - C bridge to native backends

---

## ONNXRuntime Module

### `Sources/ONNXRuntime/ONNXAdapter.swift`

**Role / Responsibility**
- Main adapter implementing UnifiedFrameworkAdapter protocol for ONNX Runtime
- Manages service lifecycle with caching and timeout-based cleanup
- Integrates with ModuleRegistry for STT and TTS service providers
- Handles model loading and hardware configuration

**Key Types**
- `ONNXAdapter` (class) – Singleton framework adapter supporting voiceToText, textToVoice, and textToText modalities

**Key Public APIs**
- `func canHandle(model: ModelInfo) -> Bool` – Checks if model is compatible with ONNX Runtime
- `func createService(for modality: FrameworkModality) -> Any?` – Creates cached STT/TTS service instances
- `func loadModel(_ model: ModelInfo, for modality: FrameworkModality) async throws -> Any` – Loads model and initializes service
- `func onRegistration()` – Registers ONNXSTTServiceProvider and ONNXTTSServiceProvider
- `func getDownloadStrategy() -> DownloadStrategy?` – Returns ONNXDownloadStrategy for .tar.bz2 archives

**Important Internal Logic**
- Caching mechanism with 5-minute timeout to avoid re-initialization overhead
- Smart cache cleanup based on last usage time
- STT service cached and reused across calls

**Dependencies**
- Internal: RunAnywhere (SDKLogger, ModelInfo, LLMFramework, FrameworkModality)
- Services: ONNXSTTService, ONNXTTSService, ONNXDownloadStrategy

**Potential Issues / Smells**
- Hardcoded 5-minute cache timeout (could be configurable)
- TTS always returns nil from createService (requires loadModel path)

---

### `Sources/ONNXRuntime/ONNXSTTService.swift`

**Role / Responsibility**
- ONNX Runtime implementation of STTService protocol
- Handles speech-to-text transcription using C bridge to runanywhere-core
- Supports both batch and streaming transcription
- Auto-detects model types (whisper, zipformer, paraformer)

**Key Types**
- `ONNXSTTService` (class) – Main STT service implementation
- `TranscriptionResult` (struct, private) – Codable result from C API
- `PartialResult` (struct, private) – Streaming partial results

**Key Public APIs**
- `func initialize(modelPath: String?) async throws` – Initializes backend and loads model
- `func transcribe(audioData: Data, options: STTOptions) async throws -> STTTranscriptionResult` – Batch transcription
- `func streamTranscribe<S>(...) async throws -> STTTranscriptionResult` – Streaming transcription
- `var supportsStreaming: Bool` – Checks if model supports streaming

**Important Internal Logic**
- Model type detection based on file patterns
- Audio conversion from Int16 PCM to Float32 at 16kHz with downsampling
- Fallback to periodic batch transcription if streaming not supported (3-second chunks)
- Archive extraction using ArchiveUtility for .tar.bz2 models

**Dependencies**
- Internal: RunAnywhere (STTService, STTOptions, SDKLogger)
- External: CRunAnywhereCore (ra_stt_*, RA_SUCCESS)

**Potential Issues / Smells**
- Hardcoded 3-second batch threshold for non-streaming models
- Model type detection relies on filename patterns (fragile)
- Downsampling uses simple stride (no proper resampling filter)

---

### `Sources/ONNXRuntime/ONNXTTSService.swift`

**Role / Responsibility**
- ONNX Runtime implementation of TTSService for text-to-speech
- Uses Sherpa-ONNX VITS/Piper models via C bridge
- Converts float32 samples to WAV format

**Key Types**
- `ONNXTTSService` (class) – Main TTS service
- `ONNXTTSServiceProvider` (struct) – Service provider for TTS

**Key Public APIs**
- `func initialize() async throws` – Loads TTS model from modelPath
- `func synthesize(text: String, options: TTSOptions) async throws -> Data` – Generates WAV audio
- `func synthesizeStream(text: String, options: TTSOptions, onChunk: @escaping (Data) -> Void) async throws` – Batch-as-stream

**Important Internal Logic**
- WAV header generation with 16-bit PCM format
- Float to Int16 sample conversion with clamping
- Archive extraction for .tar.bz2 models

**Dependencies**
- Internal: RunAnywhere (TTSService, TTSOptions, SDKLogger)
- External: CRunAnywhereCore (ra_tts_*, RA_SUCCESS)

**Potential Issues / Smells**
- No true streaming support (synthesizes entire audio then returns)
- Hardcoded to "vits" model type

---

### `Sources/ONNXRuntime/AudioCaptureManager.swift`

**Role / Responsibility**
- Manages microphone audio capture using AVAudioEngine
- Handles platform-specific permission requests (iOS 17+, iOS legacy, tvOS, macOS)
- Converts audio to 16kHz mono Int16 PCM for STT
- Provides real-time audio level visualization

**Key Types**
- `AudioCaptureManager` (class) – ObservableObject for audio capture
- `AudioCaptureError` (enum) – Error types for capture operations

**Key Public APIs**
- `func requestPermission() async -> Bool` – Platform-specific permission request
- `func startRecording(onAudioData: @escaping (Data) -> Void) throws` – Starts capture with callback
- `func stopRecording()` – Stops capture and releases resources
- `@Published var isRecording: Bool` – Recording state
- `@Published var audioLevel: Float` – Normalized audio level (0-1)

**Important Internal Logic**
- AVAudioEngine with installTap on input node
- Real-time format conversion from input format to 16kHz mono Int16
- RMS calculation for audio level metering (-60dB to 0dB normalized)
- **watchOS NOT supported** (AVAudioEngine inputNode tap unreliable)

**Dependencies**
- Internal: RunAnywhere (SDKLogger)
- External: AVFoundation (AVAudioEngine, AVAudioSession)

---

### Other ONNXRuntime Files

| File | Purpose |
|------|---------|
| `ONNXError.swift` | Centralized error type definitions with LocalizedError |
| `ONNXRuntime.swift` | Module documentation and version info (v1.0.0, ONNX Runtime 1.23.2) |
| `ONNXDownloadStrategy.swift` | Handles .tar.bz2 archives and direct .onnx downloads |
| `ONNXServiceProvider.swift` | Service provider with two-tier model detection |

---

## LlamaCPPRuntime Module

### `Sources/LlamaCPPRuntime/LlamaCPPService.swift`

**Role / Responsibility**
- Core LlamaCPP service implementation using C bridge
- Handles model loading, text generation, and streaming
- Provides cancellation support

**Key Types**
- `LlamaCPPService` (class) – Main LLM service implementation
- `LlamaCPPGenerationConfig` (struct) – Configuration for text generation
- `LlamaCPPError` (enum) – Error types for operations

**Key Public APIs**
- `func initialize(modelPath: String?) async throws` – Initializes backend and optionally loads model
- `func loadModel(path: String, config: String?) async throws` – Loads GGUF model
- `func generate(prompt: String, config: LlamaCPPGenerationConfig) async throws -> String` – Synchronous generation
- `func generateStream(prompt: String, config: LlamaCPPGenerationConfig) -> AsyncThrowingStream<String, Error>` – Streaming generation
- `func cancel()` – Cancels ongoing generation

**Important Internal Logic**
- Backend handle lifecycle management (create, initialize, destroy)
- Streaming via C callback converted to AsyncThrowingStream
- CallbackContext wrapper for continuation passing to C
- Temperature defaults to 0.8

**Dependencies**
- Internal: RunAnywhere (SDKLogger)
- External: CRunAnywhereCore (ra_text_*, ra_create_backend)

---

### `Sources/LlamaCPPRuntime/LlamaCPPCoreAdapter.swift`

**Role / Responsibility**
- Framework adapter for LlamaCPP backend
- Implements UnifiedFrameworkAdapter for textToText modality
- Manages LLMService lifecycle and registration

**Key Types**
- `LlamaCPPCoreAdapter` (class) – Main adapter implementation

**Key Public APIs**
- `func canHandle(model: ModelInfo) -> Bool` – Checks GGUF/GGML format and quantization support
- `func loadModel(_ model: ModelInfo, for modality: FrameworkModality) async throws -> Any`
- `func onRegistration()` – Registers LlamaCPPServiceProvider
- `func estimateMemoryUsage(for model: ModelInfo) -> Int64` – Estimates memory (base + 30% overhead)

**Important Internal Logic**
- Quantization validation for Q2-Q8 variants
- Memory check against 70% of physical memory
- Metal acceleration automatically enabled on iOS

**Dependencies**
- Internal: RunAnywhere (UnifiedFrameworkAdapter, ModelInfo, LLMService)
- Services: LlamaCPPService, LlamaCPPServiceProvider

---

### Other LlamaCPP Files

| File | Purpose |
|------|---------|
| `LlamaCPPRuntime.swift` | Module documentation (v1.0.0, llama.cpp b5390) |
| `LlamaCPPServiceProvider.swift` | Service provider with regex-based quantization detection |

---

## WhisperKitTranscription Module

### `Sources/WhisperKitTranscription/WhisperKitService.swift`

**Role / Responsibility**
- WhisperKit-based STT service implementation
- Handles Core ML Whisper models with garbled output detection
- Provides adaptive transcription parameters based on audio length

**Key Types**
- `WhisperKitService` (class) – Main STT service using WhisperKit framework

**Key Public APIs**
- `func initialize(modelPath: String?) async throws` – Initializes WhisperKit with model (fallback to base)
- `func transcribe(audioData: Data, options: STTOptions) async throws -> STTTranscriptionResult` – Batch transcription
- `var supportsStreaming: Bool` – Returns true but streaming incomplete

**Important Internal Logic**
- Model name mapping (whisper-tiny → openai_whisper-tiny)
- Audio padding for short samples (<1s) with low noise instead of zeros
- Adaptive noSpeechThreshold based on audio length (2.0s threshold)
- **Garbled output detection**: repetitive words (>40%), non-Latin scripts (>30%), excessive punctuation (>70%)
- DecodingOptions tuned to avoid artifacts: temp=0, skipSpecialTokens, withoutTimestamps
- Fallback to base model if specific model fails to load

**Dependencies**
- Internal: RunAnywhere (STTService, STTOptions, SDKLogger)
- External: WhisperKit (WhisperKit, DecodingOptions)

**Potential Issues / Smells**
- `streamTranscribe<S>` returns empty result (TODO implementation)
- Garbled detection heuristics might reject valid multilingual output
- Padding uses random noise which might confuse model

---

### `Sources/WhisperKitTranscription/WhisperKitStorageStrategy.swift`

**Role / Responsibility**
- Custom storage and download strategy for WhisperKit multi-file models
- Handles .mlmodelc directories with multiple components
- Downloads from HuggingFace repository

**Key Types**
- `WhisperKitStorageStrategy` (class) – Implements ModelStorageStrategy and DownloadStrategy

**Key Public APIs**
- `func download(model: ModelInfo, to: URL, progressHandler: ...) async throws -> URL` – Downloads all model files
- `func findModelPath(modelId: String, in modelFolder: URL) -> URL?` – Returns folder if AudioEncoder and TextDecoder exist
- `func detectModel(in modelFolder: URL) -> (format: ModelFormat, size: Int64)?`

**Important Internal Logic**
- Downloads 3 mlmodelc directories: AudioEncoder, MelSpectrogram, TextDecoder
- Each directory contains: coremldata.bin, metadata.json, model.mil, weights/weight.bin
- Skips 404 files (some models don't have all files)
- Model ID mapping to HuggingFace paths

**Potential Issues / Smells**
- Hardcoded file list (fragile if model structure changes)
- Continues on file download errors (might result in incomplete models)

---

### Other WhisperKit Files

| File | Purpose |
|------|---------|
| `WhisperKitAdapter.swift` | Framework adapter with 5-minute cache timeout |
| `WhisperKitTranscription.swift` | Module entry point with @_exported imports |
| `WhisperKitServiceProvider.swift` | Service provider that excludes ONNX models |
| `VoiceError.swift` | Centralized error definitions |

---

## FoundationModelsAdapter Module

### `Sources/FoundationModelsAdapter/FoundationModelsService.swift`

**Role / Responsibility**
- Service implementation for Apple Foundation Models LLM
- Checks Apple Intelligence availability
- Provides both sync and streaming generation

**Key Types**
- `FoundationModelsService` (class) – @available(iOS 26.0, macOS 26.0, *)

**Key Public APIs**
- `func initialize(modelPath: String?) async throws` – Checks availability and creates session
- `func generate(prompt: String, options: RunAnywhereGenerationOptions) async throws -> String`
- `func streamGenerate(prompt: String, options: RunAnywhereGenerationOptions, onToken: @escaping (String) -> Void) async throws`

**Important Internal Logic**
- SystemLanguageModel.default initialization
- Availability checking: .available, .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady
- Session with custom instructions for mobile context
- Streaming extracts deltas from cumulative response

**Dependencies**
- External: FoundationModels (iOS 26+)

---

### Other FoundationModels Files

| File | Purpose |
|------|---------|
| `FoundationModelsAdapter.swift` | Adapter with "foundation-models-default" built-in model |
| `FoundationModelsServiceProvider.swift` | Service provider with simple keyword matching |

---

## FluidAudioDiarization Module

### `Sources/FluidAudioDiarization/FluidAudioDiarization.swift`

**Role / Responsibility**
- Production-ready speaker diarization using FluidAudio library
- Achieves 17.7% DER (Diarization Error Rate)
- Manages speaker database and real-time detection

**Key Types**
- `FluidAudioDiarization` (class) – @available(iOS 16.0, macOS 13.0, *), implements SpeakerDiarizationService
- `SpeakerDiarizationResult` (struct) – Result with segments and speakers
- `DiarizedSegment` (struct) – Segment with speaker, time, and text
- `FluidAudioDiarizationConfig` (struct) – Configuration with threshold and limits

**Key Public APIs**
- `init(threshold: Float = 0.65) async throws` – Downloads models and initializes DiarizerManager
- `func detectSpeaker(from audioBuffer: [Float], sampleRate: Int) -> SpeakerInfo` – Real-time speaker detection
- `func performDetailedDiarization(audioBuffer: [Float]) async throws -> SpeakerDiarizationResult?` – Full analysis
- `func compareSpeakers(audio1: [Float], audio2: [Float]) async throws -> Float` – Similarity calculation
- `func updateSpeakerName(speakerId: String, name: String)` – Updates speaker name

**Important Internal Logic**
- DiarizerManager with configurable clustering threshold (default 0.65)
- Audio buffering for minimum 3-second chunks
- Concurrent queue for thread-safe speaker management
- Speaker assignment via embedding similarity

**Dependencies**
- Internal: RunAnywhere (SpeakerDiarizationService, SpeakerInfo, SDKLogger)
- External: FluidAudio (DiarizerManager, DiarizerConfig)

**Potential Issues / Smells**
- `processAudio` returns placeholder (TODO: API needs fixing)
- Local `SpeakerDiarizationResult` type (should be in SDK)

**Unused / Dead Code**
- `lastProcessedEmbedding` stored but never used
- `audioAccumulator` defined but accumulation logic not implemented

---

### `Sources/FluidAudioDiarization/FluidAudioDiarizationProvider.swift`

**Role / Responsibility**
- Service provider for FluidAudio diarization
- Handles all speaker diarization requests (canHandle always returns true)

**Key Types**
- `FluidAudioDiarizationProvider` (final class) – Singleton provider
- `FluidDiarizationService` (private class) – **Placeholder service implementation**

**Potential Issues / Smells**
- **Placeholder implementation**: `FluidDiarizationService` is a stub, should use `FluidAudioDiarization` class
- canHandle always true (no model validation)

**Unused / Dead Code**
- `FluidDiarizationService` entire class is placeholder (should be removed)

---

## CRunAnywhereCore Module (C Headers)

### `Sources/CRunAnywhereCore/include/ra_types.h`

**Role / Responsibility**
- Common type definitions for all capabilities and backends
- Defines error codes, device types, audio types, capability enums, handles, and callbacks

**Key Types**
- `ra_result_code` (enum) – Error codes (RA_SUCCESS, RA_ERROR_*)
- `ra_device_type` (enum) – CPU, GPU, NEURAL_ENGINE, METAL, CUDA, NNAPI, etc.
- `ra_audio_format` (enum) – PCM_F32, PCM_S16, WAV, MP3, FLAC, etc.
- `ra_audio_config` (struct) – Audio configuration
- `ra_capability_type` (enum) – TEXT_GENERATION, EMBEDDINGS, STT, TTS, VAD, DIARIZATION
- `ra_backend_handle` (void*) – Opaque backend instance handle
- Callbacks: ra_text_stream_callback, ra_stt_stream_callback, ra_tts_stream_callback

### `Sources/CRunAnywhereCore/include/ra_llamacpp_bridge.h`

**Role / Responsibility**
- Complete C API for unified backend capabilities
- Functions for TEXT_GENERATION, EMBEDDINGS, STT, TTS, VAD, DIARIZATION

**Key Public APIs**
- **Backend Lifecycle**: ra_create_backend, ra_initialize, ra_destroy, ra_get_backend_info
- **Capabilities**: ra_supports_capability, ra_get_capabilities
- **Text Generation**: ra_text_load_model, ra_text_generate, ra_text_generate_stream, ra_text_cancel
- **STT**: ra_stt_load_model, ra_stt_transcribe, ra_stt_create_stream, ra_stt_feed_audio, ra_stt_decode
- **TTS**: ra_tts_load_model, ra_tts_synthesize, ra_tts_get_voices
- **VAD**: ra_vad_process, ra_vad_detect_segments
- **Utilities**: ra_free_string, ra_get_last_error, ra_extract_archive

**Potential Issues / Smells**
- **Code duplication**: Identical to ra_onnx_bridge.h (should be unified)

### Other Headers

| File | Purpose |
|------|---------|
| `ra_core.h` | Umbrella header including all bridge headers |
| `ra_onnx_bridge.h` | Duplicate of ra_llamacpp_bridge.h (same API) |

---

## Key Patterns Across Backends

1. **Adapter Pattern**: All modules implement UnifiedFrameworkAdapter
2. **Service Provider Pattern**: ModuleRegistry integration for dependency injection
3. **Caching Strategy**: ONNXAdapter and WhisperKitAdapter use 5-minute timeout caches
4. **C Bridge Pattern**: ONNX and LlamaCPP use C API via CRunAnywhereCore
5. **Two-Tier Detection**: ModelInfoCache first, then fallback pattern matching

---

## Major Issues Identified

| Issue | Severity | Location |
|-------|----------|----------|
| Code Duplication | Medium | ra_onnx_bridge.h and ra_llamacpp_bridge.h identical |
| Placeholder Code | High | FluidDiarizationService is a stub |
| Incomplete Implementation | Medium | WhisperKitService.streamTranscribe returns empty |
| Missing Types | Medium | SpeakerDiarizationResult defined locally |
| Archive Extraction | Low | Mixed usage of ArchiveUtility vs ra_extract_archive |

---
*This document is part of the RunAnywhere Swift SDK current-state documentation.*
