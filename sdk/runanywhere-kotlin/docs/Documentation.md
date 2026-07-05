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

The starter app uses these specific model IDs and URLs. Loading is done
through the canonical proto-backed lifecycle service (`loadModel`); the
removed v1 helpers (`loadLLMModel` / `loadSTTModel` / `loadTTSVoice`) no
longer exist.

```kotlin
import ai.runanywhere.proto.v1.ModelCategory
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.registerModel
import com.runanywhere.sdk.public.extensions.downloadModel
import com.runanywhere.sdk.public.extensions.loadModel
import com.runanywhere.sdk.public.types.RAInferenceFramework
import com.runanywhere.sdk.public.types.RAModelLoadRequest

// LLM Model - SmolLM2 360M (small, fast, good for demos)
RunAnywhere.registerModel(
    id = "smollm2-360m-instruct-q8_0",
    name = "SmolLM2 360M Instruct Q8_0",
    url = "https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct-GGUF/resolve/main/smollm2-360m-instruct-q8_0.gguf",
    framework = RAInferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    modality = ModelCategory.MODEL_CATEGORY_LANGUAGE,
    memoryRequirement = 400_000_000, // ~400MB
)

// STT Model - Whisper Tiny English (fast transcription)
RunAnywhere.registerModel(
    id = "sherpa-onnx-whisper-tiny.en",
    name = "Sherpa Whisper Tiny (ONNX)",
    url = "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz",
    framework = RAInferenceFramework.INFERENCE_FRAMEWORK_ONNX,
    modality = ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
)

// TTS Model - Piper TTS (US English - Medium quality)
RunAnywhere.registerModel(
    id = "vits-piper-en_US-lessac-medium",
    name = "Piper TTS (US English - Medium)",
    url = "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz",
    framework = RAInferenceFramework.INFERENCE_FRAMEWORK_ONNX,
    modality = ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
)

// Download model (returns Flow<DownloadProgress>)
RunAnywhere.downloadModel("smollm2-360m-instruct-q8_0")
    .catch { e -> println("Download failed: ${e.message}") }
    .collect { progress ->
        println("Download: ${(progress.progress * 100).toInt()}%")
    }

// Load through the proto-backed lifecycle service.
val loadResult = RunAnywhere.loadModel(
    RAModelLoadRequest(
        model_id = "smollm2-360m-instruct-q8_0",
        category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
    ),
)
require(loadResult.success) { "load failed: ${loadResult.error_message}" }
```

### Text Generation (LLM)

```kotlin
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.generate
import com.runanywhere.sdk.public.types.RALLMGenerationOptions

// Canonical generation API: returns RALLMGenerationResult with text +
// metrics. There is no longer a separate `chat()` helper.
val result = RunAnywhere.generate(
    prompt = "What is AI?",
    options = RALLMGenerationOptions(max_tokens = 64),
)
println(result.text)
```

### Speech-to-Text (STT)

```kotlin
import ai.runanywhere.proto.v1.ModelCategory
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.loadModel
import com.runanywhere.sdk.public.extensions.transcribe
import com.runanywhere.sdk.public.types.RAModelLoadRequest
import com.runanywhere.sdk.public.types.RASTTOptions

// Load STT model through the canonical lifecycle service.
RunAnywhere.loadModel(
    RAModelLoadRequest(
        model_id = "sherpa-onnx-whisper-tiny.en",
        category = ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    ),
)

// Transcribe audio (16kHz, mono, 16-bit PCM ByteArray).
val output = RunAnywhere.transcribe(audioData, RASTTOptions(language = "en"))
println("You said: ${output.text}")
```

### Text-to-Speech (TTS)

```kotlin
import ai.runanywhere.proto.v1.ModelCategory
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.loadModel
import com.runanywhere.sdk.public.extensions.synthesize
import com.runanywhere.sdk.public.types.RAModelLoadRequest
import com.runanywhere.sdk.public.types.RATTSOptions

// Load TTS voice through the canonical lifecycle service.
RunAnywhere.loadModel(
    RAModelLoadRequest(
        model_id = "vits-piper-en_US-lessac-medium",
        category = ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
    ),
)

// Synthesize audio - returns TTSOutput with audioData
val output = RunAnywhere.synthesize("Hello, world!", RATTSOptions())
// output.audio_data carries the WAV audio bytes (a Wire `ByteString`).
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

// Ensure all 3 models are loaded first via the canonical lifecycle service.
import ai.runanywhere.proto.v1.ModelCategory
RunAnywhere.loadModel(
    RAModelLoadRequest(
        model_id = "sherpa-onnx-whisper-tiny.en",
        category = ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    ),
)
RunAnywhere.loadModel(
    RAModelLoadRequest(
        model_id = "smollm2-360m-instruct-q8_0",
        category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
    ),
)
RunAnywhere.loadModel(
    RAModelLoadRequest(
        model_id = "vits-piper-en_US-lessac-medium",
        category = ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
    ),
)

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
 * Generate text with full metrics. Returns the proto-backed
 * `RALLMGenerationResult` (alias for `ai.runanywhere.proto.v1.LLMGenerationResult`).
 *
 * @param prompt The text prompt
 * @param options Generation options (defaults to null → SDK defaults)
 * @return RALLMGenerationResult with text and metrics
 */
suspend fun RunAnywhere.generate(
    prompt: String,
    options: RALLMGenerationOptions? = null,
): RALLMGenerationResult
```

> The v1 `chat(prompt)` convenience helper has been removed. Construct the
> same call as `generate(prompt, RALLMGenerationOptions(...))` and read
> the resulting `result.text`.

### Streaming Generation

```kotlin
/**
 * Streaming text generation. One event per generated token plus a
 * terminal event with `is_final == true` carrying `finish_reason` and
 * any `error_message`. The v1 `generateStreamWithMetrics()` variant has
 * been removed; derive metrics from the event sequence (e.g. record TTFT
 * on the first non-empty `event.token_`).
 *
 * @param prompt The text prompt
 * @param options Generation options (defaults to null → SDK defaults)
 * @return Flow<RALLMStreamEvent>
 */
fun RunAnywhere.generateStream(
    prompt: String,
    options: RALLMGenerationOptions? = null,
): Flow<RALLMStreamEvent>
```

### Generation Control

```kotlin
/**
 * Cancel any ongoing text generation.
 */
fun RunAnywhere.cancelGeneration()
```

### LLM Types

`RALLMGenerationOptions` / `RALLMGenerationResult` / `RALLMStreamEvent`
are typealiases for the Wire-generated proto types under
`ai.runanywhere.proto.v1.*`. They are the canonical structured-options
surface — there are no longer hand-rolled value-types
(`LLMGenerationOptions`, `LLMStreamingResult`, `LLMConfiguration`).

```kotlin
// From sdk/runanywhere-kotlin/src/main/.../types/SwiftAliases.kt
typealias RALLMGenerationOptions = ai.runanywhere.proto.v1.LLMGenerationOptions
typealias RALLMGenerationResult  = ai.runanywhere.proto.v1.LLMGenerationResult
typealias RALLMStreamEvent       = ai.runanywhere.proto.v1.LLMStreamEvent
```

Common `RALLMGenerationOptions` fields (proto-snake_case in Kotlin):

```kotlin
val max_tokens: Int
val temperature: Float
val top_p: Float
val stop_sequences: List<String>
val system_prompt: String
```

`RALLMGenerationResult` carries text, token counts, latency, framework,
and tokens-per-second; see the proto definition for the full schema.

---

## Speech-to-Text (STT)

Extension functions for speech recognition.

### Transcription

```kotlin
/**
 * Transcribe a one-shot audio buffer. Returns the proto-backed `RASTTOutput`
 * (alias for `ai.runanywhere.proto.v1.STTOutput`).
 *
 * @param audio Raw audio data (16kHz PCM by default)
 * @param options Transcription options (defaults to `RASTTOptions()`)
 */
suspend fun RunAnywhere.transcribe(
    audio: ByteArray,
    options: RASTTOptions = RASTTOptions(),
): RASTTOutput
```

> The v1 helpers `loadSTTModel(modelId)` / `unloadSTTModel()` /
> `isSTTModelLoaded()` / `currentSTTModelId` / `transcribeWithOptions()`
> have been removed. Load STT models through the canonical lifecycle
> service (`loadModel(RAModelLoadRequest(category =
> MODEL_CATEGORY_SPEECH_RECOGNITION))`) and pass options directly to
> `transcribe()`.

### Streaming Transcription

```kotlin
/**
 * Stream transcription results from a flow of audio chunks. One
 * `RASTTPartialResult` per incremental update; the stream closes after
 * the final event (`is_final == true`) or on error.
 *
 * @param audio Flow of audio chunk byte arrays
 * @param options Transcription options (null → SDK defaults)
 */
fun RunAnywhere.transcribeStream(
    audio: Flow<ByteArray>,
    options: RASTTOptions? = null,
): Flow<RASTTPartialResult>
```

### STT Types

`RASTTOptions` / `RASTTOutput` / `RASTTPartialResult` are typealiases for
the Wire-generated proto types under `ai.runanywhere.proto.v1.*`. Common
fields use the proto's snake_case names:

```kotlin
// RASTTOptions (= ai.runanywhere.proto.v1.STTOptions) — selected fields
val language: String           // e.g. "en"
val detect_language: Boolean
val enable_punctuation: Boolean
val enable_timestamps: Boolean
val sample_rate: Int           // default 16000

// RASTTOutput (= ai.runanywhere.proto.v1.STTOutput) — selected fields
val text: String
val confidence: Float
val detected_language: String
```

---

## Text-to-Speech (TTS)

Extension functions for speech synthesis.

### Voice Management

TTS voices are loaded through the canonical proto-backed lifecycle
service. The v1 helpers (`loadTTSVoice`, `unloadTTSVoice`,
`isTTSVoiceLoaded`, `currentTTSVoiceId`, `availableTTSVoices()`) have
been removed.

```kotlin
import ai.runanywhere.proto.v1.ModelCategory

RunAnywhere.loadModel(
    RAModelLoadRequest(
        model_id = "vits-piper-en_US-lessac-medium",
        category = ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
    ),
)
```

Below is the historical reference for the deleted v1 surface (not
present at HEAD):

```kotlin
/**
 * Check if a TTS voice is loaded.
 */
suspend fun RunAnywhere.isTTSVoiceLoaded(): Boolean

/**
 * Get the currently loaded TTS voice ID (synchronous).
 */
val RunAnywhere.currentTTSVoiceId: String?

/**
 * Get available TTS voices.
 */
suspend fun RunAnywhere.availableTTSVoices(): List<String>
```

### Synthesis

```kotlin
/**
 * Synthesize text to speech audio. Returns the proto-backed
 * `RATTSOutput` (alias for `ai.runanywhere.proto.v1.TTSOutput`).
 *
 * @param text Text to synthesize
 * @param options Synthesis options (defaults to `RATTSOptions()`)
 */
suspend fun RunAnywhere.synthesize(
    text: String,
    options: RATTSOptions = RATTSOptions(),
): RATTSOutput

/**
 * Stream synthesis for long text. One `RATTSOutput` chunk per
 * generated segment. The previous callback-based signature was
 * removed in favor of a Flow.
 */
fun RunAnywhere.synthesizeStream(
    text: String,
    options: RATTSOptions = RATTSOptions(),
): Flow<RATTSOutput>

/**
 * Stop current TTS synthesis.
 */
suspend fun RunAnywhere.stopSynthesis()
```

### Simple Speak API

```kotlin
/**
 * Speak text aloud — synthesizes and plays through the platform audio
 * output. Returns the proto `TTSSpeakResult` (latency, duration, etc).
 */
suspend fun RunAnywhere.speak(
    text: String,
    options: RATTSOptions = RATTSOptions(),
): TTSSpeakResult

/**
 * Whether speech is currently playing — sync property read.
 */
val RunAnywhere.isSpeaking: Boolean

/**
 * Stop current speech playback.
 */
suspend fun RunAnywhere.stopSpeaking()
```

### TTS Types

`RATTSOptions` / `RATTSOutput` / `TTSSpeakResult` are typealiases for
the Wire-generated proto types under `ai.runanywhere.proto.v1.*`. Common
fields use the proto's snake_case names:

```kotlin
typealias RATTSOptions = ai.runanywhere.proto.v1.TTSOptions
typealias RATTSOutput  = ai.runanywhere.proto.v1.TTSOutput

// RATTSOptions selected fields:
val voice: String          // optional voice id override
val language: String       // e.g. "en-US"
val rate: Float            // 0.0 .. 2.0
val pitch: Float           // 0.0 .. 2.0
val volume: Float          // 0.0 .. 1.0
val sample_rate: Int       // default 22050
val use_ssml: Boolean
```

`RATTSOutput` exposes the synthesized audio bytes as a Wire
`ByteString` on `audio_data`; convert with `.toByteArray()` for JVM
audio APIs.

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
 * @param audio Flow of raw PCM audio chunks
 * @return Flow of VAD results
 */
fun RunAnywhere.streamVAD(audio: Flow<ByteArray>, options: RAVADOptions? = null): Flow<RAVADResult>
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

LLM (and STT/TTS/VAD) loading goes through the canonical proto-backed
lifecycle service. The v1 per-modality helpers were deleted; use
`loadModel(RAModelLoadRequest(...))` plus the category enum.

```kotlin
/**
 * Load a model through the canonical lifecycle service. The C++
 * router resolves the path/framework from the registry by `model_id`.
 *
 * @param request RAModelLoadRequest (alias for proto ModelLoadRequest).
 *                Set `model_id` and `category`; other fields are optional.
 * @return RAModelLoadResult — `success`, `error_message`, etc.
 */
suspend fun RunAnywhere.loadModel(request: RAModelLoadRequest): RAModelLoadResult

/**
 * Unload one or all models. `ModelUnloadRequest.unload_all = true`
 * tears every loaded component down; otherwise pass `category`.
 */
suspend fun RunAnywhere.unloadModel(request: ModelUnloadRequest): ModelUnloadResult

/**
 * Snapshot the currently loaded model for a given category. The
 * returned `CurrentModelResult` has `found: Boolean` and `model_id`.
 */
suspend fun RunAnywhere.currentModel(request: CurrentModelRequest = CurrentModelRequest()): CurrentModelResult

/**
 * Per-component lifecycle snapshot — useful for asserting readiness
 * from tests.
 */
suspend fun RunAnywhere.componentLifecycleSnapshot(component: SDKComponent): ComponentLifecycleSnapshot

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

All event types are proto-generated via Wire. The SDK re-exports them as typealiases:

```kotlin
// All events use the proto-generated SDKEvent envelope
typealias SDKEvent = ai.runanywhere.proto.v1.SDKEvent
typealias EventCategory = ai.runanywhere.proto.v1.EventCategory
typealias EventDestination = ai.runanywhere.proto.v1.EventDestination

// Typed event payloads (proto-generated)
typealias GenerationEvent = ai.runanywhere.proto.v1.GenerationEvent
typealias ModelEvent = ai.runanywhere.proto.v1.ModelEvent
typealias DownloadEvent = ai.runanywhere.proto.v1.DownloadEvent
typealias VoiceEvent = ai.runanywhere.proto.v1.VoiceEvent
typealias PerformanceEvent = ai.runanywhere.proto.v1.PerformanceEvent
typealias FailureEvent = ai.runanywhere.proto.v1.FailureEvent
typealias NetworkEvent = ai.runanywhere.proto.v1.NetworkEvent
typealias StorageLifecycleEvent = ai.runanywhere.proto.v1.StorageLifecycleEvent
typealias ComponentInitializationEvent = ai.runanywhere.proto.v1.ComponentInitializationEvent
typealias ComponentLifecycleEvent = ai.runanywhere.proto.v1.ComponentLifecycleEvent
typealias ModelRegistryEvent = ai.runanywhere.proto.v1.ModelRegistryEvent
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
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelUnloadRequest
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.SDKEnvironment
import com.runanywhere.sdk.public.extensions.*
import com.runanywhere.sdk.public.types.RAInferenceFramework
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
import com.runanywhere.sdk.public.types.RAModelLoadRequest

// Initialize
RunAnywhere.initialize(environment = SDKEnvironment.DEVELOPMENT)

// Register model (same as starter app)
RunAnywhere.registerModel(
    id = "smollm2-360m-instruct-q8_0",
    name = "SmolLM2 360M Instruct Q8_0",
    url = "https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct-GGUF/resolve/main/smollm2-360m-instruct-q8_0.gguf",
    framework = RAInferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    modality = ModelCategory.MODEL_CATEGORY_LANGUAGE,
    memoryRequirement = 400_000_000,
)

// Download model
RunAnywhere.downloadModel("smollm2-360m-instruct-q8_0")
    .catch { e -> println("Download failed: ${e.message}") }
    .collect { progress ->
        println("Download: ${(progress.progress * 100).toInt()}%")
    }

// Load through the canonical lifecycle service.
RunAnywhere.loadModel(
    RAModelLoadRequest(
        model_id = "smollm2-360m-instruct-q8_0",
        category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
    ),
)

// Generate (the v1 `chat()` shortcut was deleted — use `generate`).
val result = RunAnywhere.generate(
    prompt = "Explain AI in simple terms",
    options = RALLMGenerationOptions(max_tokens = 128),
)
println("Response: ${result.text}")

// Cleanup
RunAnywhere.unloadModel(ModelUnloadRequest(unload_all = true))
```

### Complete STT Example (Matching Starter App)

```kotlin
import ai.runanywhere.proto.v1.ModelCategory
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.*
import com.runanywhere.sdk.public.types.RAInferenceFramework
import com.runanywhere.sdk.public.types.RAModelLoadRequest
import com.runanywhere.sdk.public.types.RASTTOptions

// Register STT model
RunAnywhere.registerModel(
    id = "sherpa-onnx-whisper-tiny.en",
    name = "Sherpa Whisper Tiny (ONNX)",
    url = "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz",
    framework = RAInferenceFramework.INFERENCE_FRAMEWORK_ONNX,
    modality = ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
)

// Download and load
RunAnywhere.downloadModel("sherpa-onnx-whisper-tiny.en").collect { progress ->
    println("Download: ${(progress.progress * 100).toInt()}%")
}
RunAnywhere.loadModel(
    RAModelLoadRequest(
        model_id = "sherpa-onnx-whisper-tiny.en",
        category = ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    ),
)

// Transcribe audio (16kHz, mono, 16-bit PCM).
val output = RunAnywhere.transcribe(audioData, RASTTOptions(language = "en"))
println("You said: ${output.text}")
```

### Complete TTS Example (Matching Starter App)

```kotlin
import ai.runanywhere.proto.v1.ModelCategory
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.*
import com.runanywhere.sdk.public.types.RAInferenceFramework
import com.runanywhere.sdk.public.types.RAModelLoadRequest
import com.runanywhere.sdk.public.types.RATTSOptions

// Register TTS model
RunAnywhere.registerModel(
    id = "vits-piper-en_US-lessac-medium",
    name = "Piper TTS (US English - Medium)",
    url = "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz",
    framework = RAInferenceFramework.INFERENCE_FRAMEWORK_ONNX,
    modality = ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
)

// Download and load
RunAnywhere.downloadModel("vits-piper-en_US-lessac-medium").collect { progress ->
    println("Download: ${(progress.progress * 100).toInt()}%")
}
RunAnywhere.loadModel(
    RAModelLoadRequest(
        model_id = "vits-piper-en_US-lessac-medium",
        category = ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
    ),
)

// Synthesize audio
val output = RunAnywhere.synthesize("Hello, world!", RATTSOptions())
// output.audio_data carries the WAV audio bytes (Wire ByteString).
playWavAudio(output.audio_data.toByteArray())
```

### Voice Pipeline Session (Matching Starter App)

```kotlin
import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.VoiceAgentConfig
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.*

// Ensure all 3 models are loaded via the canonical lifecycle service.
suspend fun isLoaded(category: ModelCategory): Boolean =
    RunAnywhere.currentModel(CurrentModelRequest(category = category)).found

val allModelsLoaded =
    isLoaded(ModelCategory.MODEL_CATEGORY_LANGUAGE) &&
        isLoaded(ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION) &&
        isLoaded(ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS)

if (allModelsLoaded) {
    // Initialize the voice agent and consume its unified event stream.
    RunAnywhere.initializeVoiceAgent(
        VoiceAgentConfig(
            stt_model_id = "sherpa-onnx-whisper-tiny.en",
            llm_model_id = "smollm2-360m-instruct-q8_0",
            tts_voice_id = "vits-piper-en_US-lessac-medium",
        ),
    )

    scope.launch {
        RunAnywhere.streamVoiceAgent().collect { event ->
            event.user_said?.let { showTranscript(it.text) }
            event.agent_said?.let { showResponse(it.text) }
            event.synthesized_audio?.let { audio ->
                playWavAudio(audio.audio_data.toByteArray())
            }
            event.state_change?.let { /* update UI state */ }
        }
    }
}
```

---

## See Also

- [README.md](./README.md) - Getting started guide
- [Sample App](../../examples/android/RunAnywhereAI/) - Working example
