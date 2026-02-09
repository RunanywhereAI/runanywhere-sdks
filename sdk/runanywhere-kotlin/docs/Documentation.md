# RunAnywhere Kotlin SDK - API Documentation

Complete API reference for the RunAnywhere Kotlin SDK. All public APIs are accessible through the `RunAnywhere` object via extension functions.

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Core API](#core-api)
3. [Text Generation (LLM)](#text-generation-llm)
4. [Speech-to-Text (STT)](#speech-to-text-stt)
5. [Text-to-Speech (TTS)](#text-to-speech-tts)
6. [Voice Activity Detection (VAD)](#voice-activity-detection-vad)
7. [Voice Agent](#voice-agent)
8. [Model Management](#model-management)
9. [Event System](#event-system)
10. [Types & Enums](#types--enums)
11. [Error Handling](#error-handling)

---

## Quick Start

### Installation (Maven Central)

```kotlin
// build.gradle.kts
dependencies {
    // Core SDK with native libraries
    implementation("io.github.sanchitmonga22:runanywhere-sdk-android:0.16.1")

    // LlamaCPP backend for LLM text generation
    implementation("io.github.sanchitmonga22:runanywhere-llamacpp-android:0.16.1")

    // ONNX backend for STT/TTS/VAD
    implementation("io.github.sanchitmonga22:runanywhere-onnx-android:0.16.1")
}
```

```kotlin
// settings.gradle.kts - add repositories
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
        // JitPack for transitive dependencies (android-vad, PRDownloader)
        maven { url = uri("https://jitpack.io") }
    }
}
```

### Initialize SDK

```kotlin
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.SDKEnvironment

// In your Application.onCreate() or Activity
RunAnywhere.initialize(environment = SDKEnvironment.DEVELOPMENT)
```

### Register & Load Models

The starter app uses these specific model IDs and URLs:

```kotlin
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.registerModel
import com.runanywhere.sdk.public.extensions.downloadModel
import com.runanywhere.sdk.public.extensions.loadLLMModel
import com.runanywhere.sdk.public.extensions.loadSTTModel
import com.runanywhere.sdk.public.extensions.loadTTSVoice
import com.runanywhere.sdk.public.extensions.Models.ModelCategory
import com.runanywhere.sdk.core.types.InferenceFramework

// LLM Model - SmolLM2 360M (small, fast, good for demos)
RunAnywhere.registerModel(
    id = "smollm2-360m-instruct-q8_0",
    name = "SmolLM2 360M Instruct Q8_0",
    url = "https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct-GGUF/resolve/main/smollm2-360m-instruct-q8_0.gguf",
    framework = InferenceFramework.LLAMA_CPP,
    modality = ModelCategory.LANGUAGE,
    memoryRequirement = 400_000_000 // ~400MB
)

// STT Model - Whisper Tiny English (fast transcription)
RunAnywhere.registerModel(
    id = "sherpa-onnx-whisper-tiny.en",
    name = "Sherpa Whisper Tiny (ONNX)",
    url = "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz",
    framework = InferenceFramework.ONNX,
    modality = ModelCategory.SPEECH_RECOGNITION
)

// TTS Model - Piper TTS (US English - Medium quality)
RunAnywhere.registerModel(
    id = "vits-piper-en_US-lessac-medium",
    name = "Piper TTS (US English - Medium)",
    url = "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz",
    framework = InferenceFramework.ONNX,
    modality = ModelCategory.SPEECH_SYNTHESIS
)

// Download model (returns Flow<DownloadProgress>)
RunAnywhere.downloadModel("smollm2-360m-instruct-q8_0")
    .catch { e -> println("Download failed: ${e.message}") }
    .collect { progress ->
        println("Download: ${(progress.progress * 100).toInt()}%")
    }

// Load model
RunAnywhere.loadLLMModel("smollm2-360m-instruct-q8_0")
```

### Text Generation (LLM)

```kotlin
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.chat

// Simple chat - returns String directly
val response = RunAnywhere.chat("What is AI?")
println(response)
```

### Speech-to-Text (STT)

```kotlin
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.transcribe

// Load STT model
RunAnywhere.loadSTTModel("sherpa-onnx-whisper-tiny.en")

// Transcribe audio (16kHz, mono, 16-bit PCM ByteArray)
val transcription = RunAnywhere.transcribe(audioData)
println("You said: $transcription")
```

### Text-to-Speech (TTS)

```kotlin
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.synthesize
import com.runanywhere.sdk.public.extensions.TTS.TTSOptions

// Load TTS voice
RunAnywhere.loadTTSVoice("vits-piper-en_US-lessac-medium")

// Synthesize audio - returns TTSOutput with audioData
val output = RunAnywhere.synthesize("Hello, world!", TTSOptions())
// output.audioData contains WAV audio bytes

// Play with Android AudioTrack (see example below)
```

### Voice Pipeline (STT → LLM → TTS)

#### Option 1: Streaming Voice Session (Recommended)

The `streamVoiceSession()` API handles everything automatically:
- Audio level calculation for visualization
- Speech detection (when audio level > threshold)
- Automatic silence detection (triggers processing after 1.5s of silence)
- Full STT → LLM → TTS orchestration
- Continuous conversation mode

```kotlin
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.streamVoiceSession
import com.runanywhere.sdk.public.extensions.VoiceAgent.VoiceSessionConfig
import com.runanywhere.sdk.public.extensions.VoiceAgent.VoiceSessionEvent
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

// Ensure all 3 models are loaded first
RunAnywhere.loadSTTModel("sherpa-onnx-whisper-tiny.en")
RunAnywhere.loadLLMModel("smollm2-360m-instruct-q8_0")
RunAnywhere.loadTTSVoice("vits-piper-en_US-lessac-medium")

// Your audio capture Flow (16kHz, mono, 16-bit PCM)
// See AudioCaptureService example below
val audioChunks: Flow<ByteArray> = audioCaptureService.startCapture()

// Configure voice session
val config = VoiceSessionConfig(
    silenceDuration = 1.5,      // 1.5 seconds of silence triggers processing
    speechThreshold = 0.1f,     // Audio level threshold for speech detection
    autoPlayTTS = false,        // We'll handle playback ourselves
    continuousMode = true       // Auto-resume listening after each turn
)

// Start the SDK voice session - all business logic is handled by the SDK
sessionJob = scope.launch {
    try {
        RunAnywhere.streamVoiceSession(audioChunks, config).collect { event ->
            when (event) {
                is VoiceSessionEvent.Started -> {
                    sessionState = VoiceSessionState.LISTENING
                }

                is VoiceSessionEvent.Listening -> {
                    audioLevel = event.audioLevel
                }

                is VoiceSessionEvent.SpeechStarted -> {
                    sessionState = VoiceSessionState.SPEECH_DETECTED
                }

                is VoiceSessionEvent.Processing -> {
                    sessionState = VoiceSessionState.PROCESSING
                    audioLevel = 0f
                }

                is VoiceSessionEvent.Transcribed -> {
                    // User's speech was transcribed
                    showTranscript(event.text)
                }

                is VoiceSessionEvent.Responded -> {
                    // LLM generated a response
                    showResponse(event.text)
                }

                is VoiceSessionEvent.Speaking -> {
                    sessionState = VoiceSessionState.SPEAKING
                }

                is VoiceSessionEvent.TurnCompleted -> {
                    // Play the synthesized audio
                    event.audio?.let { audio ->
                        sessionState = VoiceSessionState.SPEAKING
                        playWavAudio(audio)
                    }
                    // Resume listening state
                    sessionState = VoiceSessionState.LISTENING
                    audioLevel = 0f
                }

                is VoiceSessionEvent.Stopped -> {
                    sessionState = VoiceSessionState.IDLE
                    audioLevel = 0f
                }

                is VoiceSessionEvent.Error -> {
                    errorMessage = event.message
                    sessionState = VoiceSessionState.IDLE
                }
            }
        }
    } catch (e: CancellationException) {
        // Expected when stopping
    } catch (e: Exception) {
        errorMessage = "Session error: ${e.message}"
        sessionState = VoiceSessionState.IDLE
    }
}

// To stop the session:
fun stopSession() {
    sessionJob?.cancel()
    sessionJob = null
    audioCaptureService.stopCapture()
    sessionState = VoiceSessionState.IDLE
}
```

#### Audio Capture Service (Required for Voice Pipeline)

```kotlin
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.*

class AudioCaptureService {
    private var audioRecord: AudioRecord? = null

    @Volatile
    private var isCapturing = false

    companion object {
        const val SAMPLE_RATE = 16000
        const val CHUNK_SIZE_MS = 100 // Emit chunks every 100ms
    }

    fun startCapture(): Flow<ByteArray> = callbackFlow {
        val bufferSize = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        val chunkSize = (SAMPLE_RATE * 2 * CHUNK_SIZE_MS) / 1000

        try {
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                maxOf(bufferSize, chunkSize * 2)
            )

            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                close(IllegalStateException("AudioRecord initialization failed"))
                return@callbackFlow
            }

            audioRecord?.startRecording()
            isCapturing = true

            val readJob = launch(Dispatchers.IO) {
                val buffer = ByteArray(chunkSize)
                while (isActive && isCapturing) {
                    val bytesRead = audioRecord?.read(buffer, 0, chunkSize) ?: -1
                    if (bytesRead > 0) {
                        trySend(buffer.copyOf(bytesRead))
                    }
                }
            }

            awaitClose {
                readJob.cancel()
                stopCapture()
            }
        } catch (e: Exception) {
            stopCapture()
            close(e)
        }
    }

    fun stopCapture() {
        isCapturing = false
        try {
            audioRecord?.stop()
            audioRecord?.release()
        } catch (_: Exception) {}
        audioRecord = null
    }
}
```

#### Play WAV Audio (Required for Voice Pipeline)

```kotlin
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

suspend fun playWavAudio(wavData: ByteArray) = withContext(Dispatchers.IO) {
    if (wavData.size < 44) return@withContext

    val headerSize = if (wavData.size > 44 &&
        wavData[0] == 'R'.code.toByte() &&
        wavData[1] == 'I'.code.toByte()) 44 else 0

    val pcmData = wavData.copyOfRange(headerSize, wavData.size)
    val sampleRate = 22050 // Piper TTS default sample rate

    val bufferSize = AudioTrack.getMinBufferSize(
        sampleRate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT
    )

    val audioTrack = AudioTrack.Builder()
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
        )
        .setAudioFormat(
            AudioFormat.Builder()
                .setSampleRate(sampleRate)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .build()
        )
        .setBufferSizeInBytes(maxOf(bufferSize, pcmData.size))
        .setTransferMode(AudioTrack.MODE_STATIC)
        .build()

    audioTrack.write(pcmData, 0, pcmData.size)
    audioTrack.play()

    val durationMs = (pcmData.size.toLong() * 1000) / (sampleRate * 2)
    delay(durationMs + 100)

    audioTrack.stop()
    audioTrack.release()
}
```

#### Option 2: Manual Processing

For more control, use `processVoice()` with your own silence detection:

```kotlin
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.processVoice

// Record audio (app responsibility - use AudioRecord)
val audioData: ByteArray = recordAudio() // 16kHz, mono, 16-bit PCM

// Process through full pipeline - SDK handles orchestration
val result = RunAnywhere.processVoice(audioData)

if (result.speechDetected) {
    println("You said: ${result.transcription}")
    println("AI response: ${result.response}")

    // Play synthesized audio (app responsibility)
    result.synthesizedAudio?.let { playWavAudio(it) }
}
```

### Voice Session Events

| Event | Description |
|-------|-------------|
| `Started` | Session started and ready |
| `Listening(audioLevel)` | Listening with real-time audio level (0.0 - 1.0) |
| `SpeechStarted` | Speech detected, accumulating audio |
| `Processing` | Silence detected, processing audio |
| `Transcribed(text)` | STT completed |
| `Responded(text)` | LLM response generated |
| `Speaking` | Playing TTS audio |
| `TurnCompleted(transcript, response, audio)` | Full turn complete with audio |
| `Stopped` | Session ended |
| `Error(message)` | Error occurred |

### Complete Voice Pipeline Example

See the Kotlin Starter Example app for a complete working implementation:
`starter_apps/kotlinstarterexample/app/src/main/java/com/runanywhere/kotlin_starter_example/ui/screens/VoicePipelineScreen.kt`

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
    /** Session started and ready */
    data object Started : VoiceSessionEvent()

    /** Listening for speech with current audio level (0.0 - 1.0) */
    data class Listening(val audioLevel: Float) : VoiceSessionEvent()

    /** Speech detected, started accumulating audio */
    data object SpeechStarted : VoiceSessionEvent()

    /** Speech ended, processing audio */
    data object Processing : VoiceSessionEvent()

    /** Got transcription from STT */
    data class Transcribed(val text: String) : VoiceSessionEvent()

    /** Got response from LLM */
    data class Responded(val text: String) : VoiceSessionEvent()

    /** Playing TTS audio */
    data object Speaking : VoiceSessionEvent()

    /** Complete turn result with transcript, response, and audio */
    data class TurnCompleted(
        val transcript: String,
        val response: String,
        val audio: ByteArray?
    ) : VoiceSessionEvent()

    /** Session stopped */
    data object Stopped : VoiceSessionEvent()

    /** Error occurred */
    data class Error(val message: String) : VoiceSessionEvent()
}
```

#### VoiceAgentResult

```kotlin
data class VoiceAgentResult(
    /** Whether speech was detected in the input audio */
    val speechDetected: Boolean = false,
    /** Transcribed text from STT */
    val transcription: String? = null,
    /** Generated response text from LLM */
    val response: String? = null,
    /** Synthesized audio data from TTS (WAV format) */
    val synthesizedAudio: ByteArray? = null
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

### Complete LLM Chat (Matching Starter App)

```kotlin
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.SDKEnvironment
import com.runanywhere.sdk.public.extensions.*
import com.runanywhere.sdk.public.extensions.Models.ModelCategory
import com.runanywhere.sdk.core.types.InferenceFramework

// Initialize
RunAnywhere.initialize(environment = SDKEnvironment.DEVELOPMENT)

// Register model (same as starter app)
RunAnywhere.registerModel(
    id = "smollm2-360m-instruct-q8_0",
    name = "SmolLM2 360M Instruct Q8_0",
    url = "https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct-GGUF/resolve/main/smollm2-360m-instruct-q8_0.gguf",
    framework = InferenceFramework.LLAMA_CPP,
    modality = ModelCategory.LANGUAGE,
    memoryRequirement = 400_000_000
)

// Download model
RunAnywhere.downloadModel("smollm2-360m-instruct-q8_0")
    .catch { e -> println("Download failed: ${e.message}") }
    .collect { progress ->
        println("Download: ${(progress.progress * 100).toInt()}%")
    }

// Load and use
RunAnywhere.loadLLMModel("smollm2-360m-instruct-q8_0")

// Simple chat (returns String)
val response = RunAnywhere.chat("Explain AI in simple terms")
println("Response: $response")

// Cleanup
RunAnywhere.unloadLLMModel()
```

### Complete STT Example (Matching Starter App)

```kotlin
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.*

// Register STT model
RunAnywhere.registerModel(
    id = "sherpa-onnx-whisper-tiny.en",
    name = "Sherpa Whisper Tiny (ONNX)",
    url = "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz",
    framework = InferenceFramework.ONNX,
    modality = ModelCategory.SPEECH_RECOGNITION
)

// Download and load
RunAnywhere.downloadModel("sherpa-onnx-whisper-tiny.en").collect { progress ->
    println("Download: ${(progress.progress * 100).toInt()}%")
}
RunAnywhere.loadSTTModel("sherpa-onnx-whisper-tiny.en")

// Transcribe audio (16kHz, mono, 16-bit PCM)
val transcription = RunAnywhere.transcribe(audioData)
println("You said: $transcription")
```

### Complete TTS Example (Matching Starter App)

```kotlin
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.*
import com.runanywhere.sdk.public.extensions.TTS.TTSOptions

// Register TTS model
RunAnywhere.registerModel(
    id = "vits-piper-en_US-lessac-medium",
    name = "Piper TTS (US English - Medium)",
    url = "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz",
    framework = InferenceFramework.ONNX,
    modality = ModelCategory.SPEECH_SYNTHESIS
)

// Download and load
RunAnywhere.downloadModel("vits-piper-en_US-lessac-medium").collect { progress ->
    println("Download: ${(progress.progress * 100).toInt()}%")
}
RunAnywhere.loadTTSVoice("vits-piper-en_US-lessac-medium")

// Synthesize audio
val output = RunAnywhere.synthesize("Hello, world!", TTSOptions())
// output.audioData contains WAV audio bytes

// Play with playWavAudio() helper (see Voice Pipeline section)
playWavAudio(output.audioData)
```

### Voice Pipeline Session (Matching Starter App)

```kotlin
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.*
import com.runanywhere.sdk.public.extensions.VoiceAgent.VoiceSessionConfig
import com.runanywhere.sdk.public.extensions.VoiceAgent.VoiceSessionEvent

// Ensure all 3 models are loaded
val allModelsLoaded = RunAnywhere.isLLMModelLoaded() &&
                     RunAnywhere.isSTTModelLoaded() &&
                     RunAnywhere.isTTSVoiceLoaded()

if (allModelsLoaded) {
    // Create audio capture flow
    val audioCaptureService = AudioCaptureService()
    val audioChunks = audioCaptureService.startCapture()

    // Configure and start session
    val config = VoiceSessionConfig(
        silenceDuration = 1.5,
        speechThreshold = 0.1f,
        autoPlayTTS = false,
        continuousMode = true
    )

    scope.launch {
        RunAnywhere.streamVoiceSession(audioChunks, config).collect { event ->
            when (event) {
                is VoiceSessionEvent.Listening -> updateAudioLevel(event.audioLevel)
                is VoiceSessionEvent.SpeechStarted -> showSpeechDetected()
                is VoiceSessionEvent.Processing -> showProcessing()
                is VoiceSessionEvent.Transcribed -> showTranscript(event.text)
                is VoiceSessionEvent.Responded -> showResponse(event.text)
                is VoiceSessionEvent.TurnCompleted -> {
                    event.audio?.let { playWavAudio(it) }
                }
                is VoiceSessionEvent.Error -> showError(event.message)
                else -> { }
            }
        }
    }
}
```

---

## See Also

- [README.md](./README.md) - Getting started guide
- [ARCHITECTURE.md](./ARCHITECTURE.md) - SDK architecture details
- [Sample App](../../examples/android/RunAnywhereAI/) - Working example
