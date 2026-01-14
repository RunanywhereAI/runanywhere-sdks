# RunAnywhere Kotlin SDK - API Documentation

Complete API reference for the RunAnywhere Kotlin SDK. All public APIs are accessible through the `RunAnywhere` object via extension functions.

---

## Table of Contents

1. [Core API](#core-api)
2. [Text Generation (LLM)](#text-generation-llm)
3. [Speech-to-Text (STT)](#speech-to-text-stt)
4. [Text-to-Speech (TTS)](#text-to-speech-tts)
5. [Voice Activity Detection (VAD)](#voice-activity-detection-vad)
6. [Voice Agent](#voice-agent)
7. [Model Management](#model-management)
8. [Event System](#event-system)
9. [Types & Enums](#types--enums)
10. [Error Handling](#error-handling)

---

## Core API

### RunAnywhere Object

The main entry point for all SDK functionality.

```kotlin
package com.runanywhere.sdk.public

object RunAnywhere
```

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `isInitialized` | `Boolean` | Whether Phase 1 initialization is complete |
| `isSDKInitialized` | `Boolean` | Alias for `isInitialized` |
| `areServicesReady` | `Boolean` | Whether Phase 2 (services) initialization is complete |
| `isActive` | `Boolean` | Whether SDK is initialized and has an environment |
| `version` | `String` | Current SDK version string |
| `environment` | `SDKEnvironment?` | Current environment (null if not initialized) |
| `events` | `EventBus` | Event subscription system |

#### Initialization

```kotlin
/**
 * Initialize the RunAnywhere SDK (Phase 1).
 * Fast synchronous initialization (~1-5ms).
 *
 * @param apiKey API key (optional for development)
 * @param baseURL Backend API base URL (optional)
 * @param environment SDK environment (default: DEVELOPMENT)
 */
fun initialize(
    apiKey: String? = null,
    baseURL: String? = null,
    environment: SDKEnvironment = SDKEnvironment.DEVELOPMENT
)

/**
 * Initialize SDK for development mode (convenience method).
 */
fun initializeForDevelopment(apiKey: String? = null)

/**
 * Complete services initialization (Phase 2).
 * Called automatically on first API call, or can be awaited explicitly.
 */
suspend fun completeServicesInitialization()
```

#### Lifecycle

```kotlin
/**
 * Reset SDK state. Clears all initialization state and releases resources.
 */
suspend fun reset()

/**
 * Cleanup SDK resources without full reset.
 */
suspend fun cleanup()
```

### SDKEnvironment

```kotlin
enum class SDKEnvironment {
    DEVELOPMENT,  // Debug logging, local testing
    STAGING,      // Info logging, staging backend
    PRODUCTION    // Warning logging only, production backend
}
```

---

## Text Generation (LLM)

Extension functions for text generation using Large Language Models.

### Basic Generation

```kotlin
/**
 * Simple text generation.
 *
 * @param prompt The text prompt
 * @return Generated response text
 */
suspend fun RunAnywhere.chat(prompt: String): String

/**
 * Generate text with full metrics.
 *
 * @param prompt The text prompt
 * @param options Generation options (optional)
 * @return LLMGenerationResult with text and metrics
 */
suspend fun RunAnywhere.generate(
    prompt: String,
    options: LLMGenerationOptions? = null
): LLMGenerationResult
```

### Streaming Generation

```kotlin
/**
 * Streaming text generation.
 * Returns a Flow of tokens for real-time display.
 *
 * @param prompt The text prompt
 * @param options Generation options (optional)
 * @return Flow of tokens as they are generated
 */
fun RunAnywhere.generateStream(
    prompt: String,
    options: LLMGenerationOptions? = null
): Flow<String>

/**
 * Streaming with metrics.
 * Returns token stream AND deferred metrics.
 *
 * @param prompt The text prompt
 * @param options Generation options (optional)
 * @return LLMStreamingResult with stream and deferred result
 */
suspend fun RunAnywhere.generateStreamWithMetrics(
    prompt: String,
    options: LLMGenerationOptions? = null
): LLMStreamingResult
```

### Generation Control

```kotlin
/**
 * Cancel any ongoing text generation.
 */
fun RunAnywhere.cancelGeneration()
```

### LLM Types

#### LLMGenerationOptions

```kotlin
data class LLMGenerationOptions(
    val maxTokens: Int = 100,
    val temperature: Float = 0.8f,
    val topP: Float = 1.0f,
    val stopSequences: List<String> = emptyList(),
    val streamingEnabled: Boolean = false,
    val preferredFramework: InferenceFramework? = null,
    val structuredOutput: StructuredOutputConfig? = null,
    val systemPrompt: String? = null
)
```

#### LLMGenerationResult

```kotlin
data class LLMGenerationResult(
    val text: String,                    // Generated text
    val thinkingContent: String?,        // Reasoning content (if model supports)
    val inputTokens: Int,                // Prompt tokens
    val tokensUsed: Int,                 // Output tokens
    val modelUsed: String,               // Model ID
    val latencyMs: Double,               // Total time in ms
    val framework: String?,              // Framework used
    val tokensPerSecond: Double,         // Generation speed
    val timeToFirstTokenMs: Double?,     // TTFT (streaming only)
    val thinkingTokens: Int?,            // Thinking tokens (if applicable)
    val responseTokens: Int              // Response tokens
)
```

#### LLMStreamingResult

```kotlin
data class LLMStreamingResult(
    val stream: Flow<String>,            // Token stream
    val result: Deferred<LLMGenerationResult>  // Final metrics
)
```

#### LLMConfiguration

```kotlin
data class LLMConfiguration(
    val modelId: String? = null,
    val contextLength: Int = 2048,
    val temperature: Double = 0.7,
    val maxTokens: Int = 100,
    val systemPrompt: String? = null,
    val streamingEnabled: Boolean = true,
    val preferredFramework: InferenceFramework? = null
)
```

---

## Speech-to-Text (STT)

Extension functions for speech recognition.

### Basic Transcription

```kotlin
/**
 * Simple voice transcription using default model.
 *
 * @param audioData Audio data to transcribe
 * @return Transcribed text
 */
suspend fun RunAnywhere.transcribe(audioData: ByteArray): String
```

### Model Management

```kotlin
/**
 * Load an STT model.
 *
 * @param modelId Model identifier
 */
suspend fun RunAnywhere.loadSTTModel(modelId: String)

/**
 * Unload the currently loaded STT model.
 */
suspend fun RunAnywhere.unloadSTTModel()

/**
 * Check if an STT model is loaded.
 */
suspend fun RunAnywhere.isSTTModelLoaded(): Boolean

/**
 * Get the currently loaded STT model ID (synchronous).
 */
val RunAnywhere.currentSTTModelId: String?

/**
 * Check if STT model is loaded (non-suspend version).
 */
val RunAnywhere.isSTTModelLoadedSync: Boolean
```

### Advanced Transcription

```kotlin
/**
 * Transcribe with options.
 *
 * @param audioData Raw audio data
 * @param options Transcription options
 * @return STTOutput with text and metadata
 */
suspend fun RunAnywhere.transcribeWithOptions(
    audioData: ByteArray,
    options: STTOptions
): STTOutput

/**
 * Streaming transcription with callbacks.
 *
 * @param audioData Audio data to transcribe
 * @param options Transcription options
 * @param onPartialResult Callback for partial results
 * @return Final transcription output
 */
suspend fun RunAnywhere.transcribeStream(
    audioData: ByteArray,
    options: STTOptions = STTOptions(),
    onPartialResult: (STTTranscriptionResult) -> Unit
): STTOutput

/**
 * Process audio samples for streaming transcription.
 */
suspend fun RunAnywhere.processStreamingAudio(samples: FloatArray)

/**
 * Stop streaming transcription.
 */
suspend fun RunAnywhere.stopStreamingTranscription()
```

### STT Types

#### STTOptions

```kotlin
data class STTOptions(
    val language: String = "en",
    val detectLanguage: Boolean = false,
    val enablePunctuation: Boolean = true,
    val enableDiarization: Boolean = false,
    val maxSpeakers: Int? = null,
    val enableTimestamps: Boolean = true,
    val vocabularyFilter: List<String> = emptyList(),
    val audioFormat: AudioFormat = AudioFormat.PCM,
    val sampleRate: Int = 16000,
    val preferredFramework: InferenceFramework? = null
)
```

#### STTOutput

```kotlin
data class STTOutput(
    val text: String,                              // Transcribed text
    val confidence: Float,                         // Confidence (0.0-1.0)
    val wordTimestamps: List<WordTimestamp>?,      // Word-level timing
    val detectedLanguage: String?,                 // Auto-detected language
    val alternatives: List<TranscriptionAlternative>?,
    val metadata: TranscriptionMetadata,
    val timestamp: Long
)
```

#### TranscriptionMetadata

```kotlin
data class TranscriptionMetadata(
    val modelId: String,
    val processingTime: Double,    // Processing time in seconds
    val audioLength: Double        // Audio length in seconds
) {
    val realTimeFactor: Double     // processingTime / audioLength
}
```

#### WordTimestamp

```kotlin
data class WordTimestamp(
    val word: String,
    val startTime: Double,         // Start time in seconds
    val endTime: Double,           // End time in seconds
    val confidence: Float
)
```

---

## Text-to-Speech (TTS)

Extension functions for speech synthesis.

### Voice Management

```kotlin
/**
 * Load a TTS voice.
 *
 * @param voiceId Voice identifier
 */
suspend fun RunAnywhere.loadTTSVoice(voiceId: String)

/**
 * Unload the currently loaded TTS voice.
 */
suspend fun RunAnywhere.unloadTTSVoice()

/**
 * Check if a TTS voice is loaded.
 */
suspend fun RunAnywhere.isTTSVoiceLoaded(): Boolean

/**
 * Get the currently loaded TTS voice ID (synchronous).
 */
val RunAnywhere.currentTTSVoiceId: String?

/**
 * Check if TTS voice is loaded (non-suspend version).
 */
val RunAnywhere.isTTSVoiceLoadedSync: Boolean

/**
 * Get available TTS voices.
 */
suspend fun RunAnywhere.availableTTSVoices(): List<String>
```

### Synthesis

```kotlin
/**
 * Synthesize text to speech audio.
 *
 * @param text Text to synthesize
 * @param options Synthesis options
 * @return TTSOutput with audio data
 */
suspend fun RunAnywhere.synthesize(
    text: String,
    options: TTSOptions = TTSOptions()
): TTSOutput

/**
 * Stream synthesis for long text.
 *
 * @param text Text to synthesize
 * @param options Synthesis options
 * @param onAudioChunk Callback for each audio chunk
 * @return TTSOutput with full audio data
 */
suspend fun RunAnywhere.synthesizeStream(
    text: String,
    options: TTSOptions = TTSOptions(),
    onAudioChunk: (ByteArray) -> Unit
): TTSOutput

/**
 * Stop current TTS synthesis.
 */
suspend fun RunAnywhere.stopSynthesis()
```

### Simple Speak API

```kotlin
/**
 * Speak text aloud - handles synthesis and playback.
 *
 * @param text Text to speak
 * @param options Synthesis options
 * @return TTSSpeakResult with metadata
 */
suspend fun RunAnywhere.speak(
    text: String,
    options: TTSOptions = TTSOptions()
): TTSSpeakResult

/**
 * Check if speech is currently playing.
 */
suspend fun RunAnywhere.isSpeaking(): Boolean

/**
 * Stop current speech playback.
 */
suspend fun RunAnywhere.stopSpeaking()
```

### TTS Types

#### TTSOptions

```kotlin
data class TTSOptions(
    val voice: String? = null,
    val language: String = "en-US",
    val rate: Float = 1.0f,           // 0.0 to 2.0
    val pitch: Float = 1.0f,          // 0.0 to 2.0
    val volume: Float = 1.0f,         // 0.0 to 1.0
    val audioFormat: AudioFormat = AudioFormat.PCM,
    val sampleRate: Int = 22050,
    val useSSML: Boolean = false
)
```

#### TTSOutput

```kotlin
data class TTSOutput(
    val audioData: ByteArray,                      // Synthesized audio
    val format: AudioFormat,                       // Audio format
    val duration: Double,                          // Duration in seconds
    val phonemeTimestamps: List<TTSPhonemeTimestamp>?,
    val metadata: TTSSynthesisMetadata,
    val timestamp: Long
) {
    val audioSizeBytes: Int
    val hasPhonemeTimestamps: Boolean
}
```

#### TTSSynthesisMetadata

```kotlin
data class TTSSynthesisMetadata(
    val voice: String,
    val language: String,
    val processingTime: Double,        // Processing time in seconds
    val characterCount: Int
) {
    val charactersPerSecond: Double
}
```

#### TTSSpeakResult

```kotlin
data class TTSSpeakResult(
    val duration: Double,              // Duration in seconds
    val format: AudioFormat,
    val audioSizeBytes: Int,
    val metadata: TTSSynthesisMetadata,
    val timestamp: Long
)
```

---

## Voice Activity Detection (VAD)

Extension functions for detecting speech in audio.

### Detection

```kotlin
/**
 * Detect voice activity in audio data.
 *
 * @param audioData Audio data to analyze
 * @return VADResult with detection info
 */
suspend fun RunAnywhere.detectVoiceActivity(audioData: ByteArray): VADResult

/**
 * Stream VAD results from audio samples.
 *
 * @param audioSamples Flow of audio samples
 * @return Flow of VAD results
 */
fun RunAnywhere.streamVAD(audioSamples: Flow<FloatArray>): Flow<VADResult>
```

### Configuration

```kotlin
/**
 * Configure VAD settings.
 *
 * @param configuration VAD configuration
 */
suspend fun RunAnywhere.configureVAD(configuration: VADConfiguration)

/**
 * Get current VAD statistics.
 */
suspend fun RunAnywhere.getVADStatistics(): VADStatistics

/**
 * Calibrate VAD with ambient noise.
 *
 * @param ambientAudioData Audio data of ambient noise
 */
suspend fun RunAnywhere.calibrateVAD(ambientAudioData: ByteArray)

/**
 * Reset VAD state.
 */
suspend fun RunAnywhere.resetVAD()
```

### VAD Types

#### VADConfiguration

```kotlin
data class VADConfiguration(
    val threshold: Float = 0.5f,
    val minSpeechDurationMs: Int = 250,
    val minSilenceDurationMs: Int = 300,
    val sampleRate: Int = 16000,
    val frameSizeMs: Int = 30
)
```

#### VADResult

```kotlin
data class VADResult(
    val hasSpeech: Boolean,            // Speech detected
    val confidence: Float,             // Detection confidence
    val speechStartMs: Long?,          // Speech start time
    val speechEndMs: Long?,            // Speech end time
    val frameIndex: Int,               // Audio frame index
    val timestamp: Long
)
```

---

## Voice Agent

Extension functions for full voice conversation pipelines.

### Configuration

```kotlin
/**
 * Configure the voice agent.
 *
 * @param configuration Voice agent configuration
 */
suspend fun RunAnywhere.configureVoiceAgent(configuration: VoiceAgentConfiguration)

/**
 * Get current voice agent component states.
 */
suspend fun RunAnywhere.voiceAgentComponentStates(): VoiceAgentComponentStates

/**
 * Check if voice agent is fully ready.
 */
suspend fun RunAnywhere.isVoiceAgentReady(): Boolean

/**
 * Initialize voice agent with currently loaded models.
 */
suspend fun RunAnywhere.initializeVoiceAgentWithLoadedModels()
```

### Voice Processing

```kotlin
/**
 * Process audio through full pipeline (VAD → STT → LLM → TTS).
 *
 * @param audioData Audio data to process
 * @return VoiceAgentResult with full response
 */
suspend fun RunAnywhere.processVoice(audioData: ByteArray): VoiceAgentResult
```

### Voice Session

```kotlin
/**
 * Start a voice session.
 * Returns a Flow of voice session events.
 *
 * @param config Session configuration
 * @return Flow of VoiceSessionEvent
 */
fun RunAnywhere.startVoiceSession(
    config: VoiceSessionConfig = VoiceSessionConfig.DEFAULT
): Flow<VoiceSessionEvent>

/**
 * Stop the current voice session.
 */
suspend fun RunAnywhere.stopVoiceSession()

/**
 * Check if a voice session is active.
 */
suspend fun RunAnywhere.isVoiceSessionActive(): Boolean
```

### Conversation History

```kotlin
/**
 * Clear the voice agent conversation history.
 */
suspend fun RunAnywhere.clearVoiceConversation()

/**
 * Set the system prompt for LLM responses.
 *
 * @param prompt System prompt text
 */
suspend fun RunAnywhere.setVoiceSystemPrompt(prompt: String)
```

### Voice Agent Types

#### VoiceAgentConfiguration

```kotlin
data class VoiceAgentConfiguration(
    val sttModelId: String,
    val llmModelId: String,
    val ttsVoiceId: String,
    val systemPrompt: String? = null,
    val vadConfiguration: VADConfiguration? = null,
    val interruptionEnabled: Boolean = true
)
```

#### VoiceSessionEvent

```kotlin
sealed class VoiceSessionEvent {
    object Listening : VoiceSessionEvent()
    data class Transcribed(val text: String) : VoiceSessionEvent()
    object Thinking : VoiceSessionEvent()
    data class Responded(val text: String) : VoiceSessionEvent()
    object Speaking : VoiceSessionEvent()
    object Idle : VoiceSessionEvent()
    data class Error(val message: String) : VoiceSessionEvent()
}
```

#### VoiceAgentResult

```kotlin
data class VoiceAgentResult(
    val transcription: String,
    val response: String,
    val audioData: ByteArray?,
    val totalLatencyMs: Double,
    val sttLatencyMs: Double,
    val llmLatencyMs: Double,
    val ttsLatencyMs: Double
)
```

---

## Model Management

Extension functions for model registration, download, and lifecycle.

### Model Registration

```kotlin
/**
 * Register a model from a download URL.
 *
 * @param id Explicit model ID (optional, generated from URL if null)
 * @param name Display name for the model
 * @param url Download URL
 * @param framework Target inference framework
 * @param modality Model category (default: LANGUAGE)
 * @param artifactType How model is packaged (inferred if null)
 * @param memoryRequirement Estimated memory in bytes
 * @param supportsThinking Whether model supports reasoning
 * @return Created ModelInfo
 */
fun RunAnywhere.registerModel(
    id: String? = null,
    name: String,
    url: String,
    framework: InferenceFramework,
    modality: ModelCategory = ModelCategory.LANGUAGE,
    artifactType: ModelArtifactType? = null,
    memoryRequirement: Long? = null,
    supportsThinking: Boolean = false
): ModelInfo
```

### Model Discovery

```kotlin
/**
 * Get all available models.
 */
suspend fun RunAnywhere.availableModels(): List<ModelInfo>

/**
 * Get models by category.
 *
 * @param category Model category to filter by
 */
suspend fun RunAnywhere.models(category: ModelCategory): List<ModelInfo>

/**
 * Get downloaded models only.
 */
suspend fun RunAnywhere.downloadedModels(): List<ModelInfo>

/**
 * Get model info by ID.
 *
 * @param modelId Model identifier
 * @return ModelInfo or null if not found
 */
suspend fun RunAnywhere.model(modelId: String): ModelInfo?
```

### Model Downloads

```kotlin
/**
 * Download a model.
 *
 * @param modelId Model identifier
 * @return Flow of DownloadProgress
 */
fun RunAnywhere.downloadModel(modelId: String): Flow<DownloadProgress>

/**
 * Cancel a model download.
 *
 * @param modelId Model identifier
 */
suspend fun RunAnywhere.cancelDownload(modelId: String)

/**
 * Check if a model is downloaded.
 *
 * @param modelId Model identifier
 */
suspend fun RunAnywhere.isModelDownloaded(modelId: String): Boolean
```

### Model Lifecycle

```kotlin
/**
 * Delete a downloaded model.
 */
suspend fun RunAnywhere.deleteModel(modelId: String)

/**
 * Delete all downloaded models.
 */
suspend fun RunAnywhere.deleteAllModels()

/**
 * Refresh the model registry from remote.
 */
suspend fun RunAnywhere.refreshModelRegistry()
```

### LLM Model Loading

```kotlin
/**
 * Load an LLM model.
 */
suspend fun RunAnywhere.loadLLMModel(modelId: String)

/**
 * Unload the currently loaded LLM model.
 */
suspend fun RunAnywhere.unloadLLMModel()

/**
 * Check if an LLM model is loaded.
 */
suspend fun RunAnywhere.isLLMModelLoaded(): Boolean

/**
 * Get the currently loaded LLM model ID (synchronous).
 */
val RunAnywhere.currentLLMModelId: String?

/**
 * Get the currently loaded LLM model info.
 */
suspend fun RunAnywhere.currentLLMModel(): ModelInfo?

/**
 * Get the currently loaded STT model info.
 */
suspend fun RunAnywhere.currentSTTModel(): ModelInfo?
```

### Model Types

#### ModelInfo

```kotlin
data class ModelInfo(
    val id: String,
    val name: String,
    val category: ModelCategory,
    val format: ModelFormat,
    val downloadURL: String?,
    var localPath: String?,
    val artifactType: ModelArtifactType,
    val downloadSize: Long?,
    val framework: InferenceFramework,
    val contextLength: Int?,
    val supportsThinking: Boolean,
    val thinkingPattern: ThinkingTagPattern?,
    val description: String?,
    val source: ModelSource,
    val createdAt: Long,
    var updatedAt: Long
) {
    val isDownloaded: Boolean
    val isAvailable: Boolean
    val isBuiltIn: Boolean
}
```

#### DownloadProgress

```kotlin
data class DownloadProgress(
    val modelId: String,
    val progress: Float,               // 0.0 to 1.0
    val bytesDownloaded: Long,
    val totalBytes: Long?,
    val state: DownloadState,
    val error: String?
)

enum class DownloadState {
    PENDING, DOWNLOADING, EXTRACTING, COMPLETED, ERROR, CANCELLED
}
```

#### ModelCategory

```kotlin
enum class ModelCategory {
    LANGUAGE,              // LLMs (text-to-text)
    SPEECH_RECOGNITION,    // STT (voice-to-text)
    SPEECH_SYNTHESIS,      // TTS (text-to-voice)
    VISION,                // Image understanding
    IMAGE_GENERATION,      // Text-to-image
    MULTIMODAL,            // Multiple modalities
    AUDIO                  // Audio processing
}
```

#### ModelFormat

```kotlin
enum class ModelFormat {
    ONNX,      // ONNX Runtime format
    ORT,       // Optimized ONNX Runtime
    GGUF,      // llama.cpp format
    BIN,       // Generic binary
    UNKNOWN
}
```

---

## Event System

### EventBus

```kotlin
object EventBus {
    val allEvents: SharedFlow<SDKEvent>
    val llmEvents: SharedFlow<LLMEvent>
    val sttEvents: SharedFlow<STTEvent>
    val ttsEvents: SharedFlow<TTSEvent>
    val modelEvents: SharedFlow<ModelEvent>
    val errorEvents: SharedFlow<ErrorEvent>
}
```

### Event Types

#### SDKEvent (Interface)

```kotlin
interface SDKEvent {
    val id: String
    val type: String
    val category: EventCategory
    val timestamp: Long
    val sessionId: String?
    val destination: EventDestination
    val properties: Map<String, String>
}
```

#### LLMEvent

```kotlin
data class LLMEvent(
    val eventType: LLMEventType,
    val modelId: String?,
    val tokensGenerated: Int?,
    val latencyMs: Double?,
    val error: String?
) : SDKEvent

enum class LLMEventType {
    GENERATION_STARTED, GENERATION_COMPLETED, GENERATION_FAILED,
    STREAM_TOKEN, STREAM_COMPLETED
}
```

#### STTEvent

```kotlin
data class STTEvent(
    val eventType: STTEventType,
    val modelId: String?,
    val transcript: String?,
    val confidence: Float?,
    val error: String?
) : SDKEvent

enum class STTEventType {
    TRANSCRIPTION_STARTED, TRANSCRIPTION_COMPLETED, TRANSCRIPTION_FAILED,
    PARTIAL_RESULT
}
```

#### TTSEvent

```kotlin
data class TTSEvent(
    val eventType: TTSEventType,
    val voice: String?,
    val durationMs: Double?,
    val error: String?
) : SDKEvent

enum class TTSEventType {
    SYNTHESIS_STARTED, SYNTHESIS_COMPLETED, SYNTHESIS_FAILED,
    PLAYBACK_STARTED, PLAYBACK_COMPLETED
}
```

#### ModelEvent

```kotlin
data class ModelEvent(
    val eventType: ModelEventType,
    val modelId: String,
    val progress: Float?,
    val error: String?
) : SDKEvent

enum class ModelEventType {
    DOWNLOAD_STARTED, DOWNLOAD_PROGRESS, DOWNLOAD_COMPLETED, DOWNLOAD_FAILED,
    LOADED, UNLOADED, DELETED
}
```

---

## Types & Enums

### InferenceFramework

```kotlin
enum class InferenceFramework {
    ONNX,              // ONNX Runtime (STT/TTS/VAD)
    LLAMA_CPP,         // llama.cpp (LLM)
    FOUNDATION_MODELS, // Platform foundation models
    SYSTEM_TTS,        // System text-to-speech
    FLUID_AUDIO,       // FluidAudio engine
    BUILT_IN,          // Simple built-in services
    NONE,              // No model needed
    UNKNOWN
}
```

### SDKComponent

```kotlin
enum class SDKComponent {
    LLM,        // Language Model
    STT,        // Speech to Text
    TTS,        // Text to Speech
    VAD,        // Voice Activity Detection
    VOICE,      // Voice Agent
    EMBEDDING   // Embedding model
}
```

### AudioFormat

```kotlin
enum class AudioFormat {
    PCM, WAV, MP3, AAC, OGG, OPUS, FLAC
}
```

---

## Error Handling

### SDKError

```kotlin
data class SDKError(
    val code: ErrorCode,
    val category: ErrorCategory,
    override val message: String,
    override val cause: Throwable?
) : Exception(message, cause)
```

### Error Factory Methods

```kotlin
// General
SDKError.general(message, code?, cause?)
SDKError.unknown(message, cause?)

// Initialization
SDKError.notInitialized(component, cause?)
SDKError.alreadyInitialized(component, cause?)

// Model
SDKError.modelNotFound(modelId, cause?)
SDKError.modelNotLoaded(modelId?, cause?)
SDKError.modelLoadFailed(modelId, reason?, cause?)

// LLM
SDKError.llm(message, code?, cause?)
SDKError.llmGenerationFailed(reason?, cause?)

// STT
SDKError.stt(message, code?, cause?)
SDKError.sttTranscriptionFailed(reason?, cause?)

// TTS
SDKError.tts(message, code?, cause?)
SDKError.ttsSynthesisFailed(reason?, cause?)

// VAD
SDKError.vad(message, code?, cause?)
SDKError.vadDetectionFailed(reason?, cause?)

// Network
SDKError.network(message, code?, cause?)
SDKError.networkUnavailable(cause?)
SDKError.timeout(operation, timeoutMs?, cause?)

// Download
SDKError.downloadFailed(url, reason?, cause?)
SDKError.downloadCancelled(url, cause?)

// Storage
SDKError.insufficientStorage(requiredBytes?, cause?)
SDKError.fileNotFound(path, cause?)

// From C++ error codes
SDKError.fromRawValue(rawValue, message?, cause?)
SDKError.fromErrorCode(errorCode, message?, cause?)
```

### ErrorCategory

```kotlin
enum class ErrorCategory {
    GENERAL, CONFIGURATION, INITIALIZATION, FILE_RESOURCE, MEMORY,
    STORAGE, OPERATION, NETWORK, MODEL, PLATFORM, LLM, STT, TTS,
    VAD, VOICE_AGENT, DOWNLOAD, AUTHENTICATION
}
```

### ErrorCode

Common error codes include:
- `SUCCESS`, `UNKNOWN`, `INVALID_ARGUMENT`
- `NOT_INITIALIZED`, `ALREADY_INITIALIZED`
- `MODEL_NOT_FOUND`, `MODEL_NOT_LOADED`, `MODEL_LOAD_FAILED`
- `LLM_GENERATION_FAILED`, `STT_TRANSCRIPTION_FAILED`, `TTS_SYNTHESIS_FAILED`
- `NETWORK_ERROR`, `NETWORK_UNAVAILABLE`, `TIMEOUT`
- `DOWNLOAD_FAILED`, `DOWNLOAD_CANCELLED`
- `INSUFFICIENT_STORAGE`, `FILE_NOT_FOUND`, `OUT_OF_MEMORY`

---

## Usage Examples

### Complete LLM Chat

```kotlin
// Initialize
RunAnywhere.initialize(environment = SDKEnvironment.DEVELOPMENT)

// Register and download model
val model = RunAnywhere.registerModel(
    name = "Qwen 0.5B",
    url = "https://huggingface.co/...",
    framework = InferenceFramework.LLAMA_CPP
)

RunAnywhere.downloadModel(model.id).collect { progress ->
    println("Download: ${(progress.progress * 100).toInt()}%")
}

// Load and use
RunAnywhere.loadLLMModel(model.id)

val result = RunAnywhere.generate(
    prompt = "Explain AI in simple terms",
    options = LLMGenerationOptions(maxTokens = 200)
)
println("Response: ${result.text}")
println("Speed: ${result.tokensPerSecond} tok/s")

// Cleanup
RunAnywhere.unloadLLMModel()
```

### Voice Agent Session

```kotlin
// Configure
RunAnywhere.configureVoiceAgent(VoiceAgentConfiguration(
    sttModelId = "whisper-tiny",
    llmModelId = "qwen-0.5b",
    ttsVoiceId = "en-us-default"
))

// Start session
lifecycleScope.launch {
    RunAnywhere.startVoiceSession().collect { event ->
        when (event) {
            is VoiceSessionEvent.Listening -> updateUI("Listening...")
            is VoiceSessionEvent.Transcribed -> updateUI("You: ${event.text}")
            is VoiceSessionEvent.Thinking -> updateUI("Thinking...")
            is VoiceSessionEvent.Responded -> updateUI("AI: ${event.text}")
            is VoiceSessionEvent.Speaking -> updateUI("Speaking...")
            is VoiceSessionEvent.Error -> showError(event.message)
        }
    }
}
```

---

## See Also

- [README.md](./README.md) - Getting started guide
- [ARCHITECTURE.md](./ARCHITECTURE.md) - SDK architecture details
- [Sample App](../../examples/android/RunAnywhereAI/) - Working example
