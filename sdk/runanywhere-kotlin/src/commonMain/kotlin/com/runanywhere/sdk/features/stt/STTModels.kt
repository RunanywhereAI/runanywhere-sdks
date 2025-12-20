package com.runanywhere.sdk.features.stt

import com.runanywhere.sdk.core.AudioFormat
import com.runanywhere.sdk.core.capabilities.*
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.features.vad.VADOutput
import com.runanywhere.sdk.models.enums.InferenceFramework
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.coroutines.flow.Flow

// AudioFormat is imported from core package (core/AudioTypes.kt)

/**
 * Enum to specify preferred audio format for the service (matches iOS STTServiceAudioFormat)
 */
enum class STTServiceAudioFormat {
    /** Service prefers raw ByteArray data */
    DATA,

    /** Service prefers FloatArray samples */
    FLOAT_ARRAY,
}

// MARK: - STT Mode

/**
 * Transcription mode for speech-to-text (matches iOS STTMode exactly)
 */
enum class STTMode(
    val value: String,
) {
    /**
     * Batch mode: Record all audio first, then transcribe everything at once
     * Best for: Short recordings, offline processing, higher accuracy
     */
    BATCH("batch"),

    /**
     * Live/Streaming mode: Transcribe audio in real-time as it's recorded
     * Best for: Live captions, real-time feedback, long recordings
     */
    LIVE("live"),
    ;

    /**
     * Display name for UI (matches iOS displayName)
     */
    val displayName: String
        get() =
            when (this) {
                BATCH -> "Batch"
                LIVE -> "Live"
            }

    /**
     * Description of the mode (matches iOS description)
     */
    val description: String
        get() =
            when (this) {
                BATCH -> "Record audio, then transcribe all at once"
                LIVE -> "Real-time transcription as you speak"
            }

    /**
     * Icon identifier for the mode (matches iOS icon)
     * Uses SF Symbol names for cross-platform icon lookup
     */
    val icon: String
        get() =
            when (this) {
                BATCH -> "waveform.badge.mic"
                LIVE -> "waveform"
            }

    companion object {
        /**
         * Create STTMode from string value
         */
        fun fromValue(value: String): STTMode? = entries.find { it.value == value }
    }
}

// MARK: - STT Result (matches iOS STTResult exactly)

/**
 * Result from speech-to-text transcription
 */
data class STTResult(
    val text: String,
    val segments: List<STTSegment> = emptyList(),
    val language: String? = null,
    val confidence: Float = 1.0f,
    val duration: Double = 0.0,
    val alternatives: List<STTAlternative> = emptyList(),
)

/**
 * A segment of transcribed text with timing (matches iOS STTSegment)
 */
data class STTSegment(
    val text: String,
    val startTime: Double,
    val endTime: Double,
    val confidence: Float = 1.0f,
    val speaker: Int? = null,
)

/**
 * Alternative transcription result (matches iOS STTAlternative)
 */
data class STTAlternative(
    val text: String,
    val confidence: Float,
)

// MARK: - STT Options

/**
 * Options for speech-to-text transcription (matches iOS STTOptions exactly)
 */
data class STTOptions(
    /** Language code for transcription (e.g., "en", "es", "fr") */
    val language: String = "en",
    /** Whether to auto-detect the spoken language */
    val detectLanguage: Boolean = false,
    /** Enable automatic punctuation in transcription */
    val enablePunctuation: Boolean = true,
    /** Enable speaker diarization (identify different speakers) */
    val enableDiarization: Boolean = false,
    /** Maximum number of speakers to identify (requires enableDiarization) */
    val maxSpeakers: Int? = null,
    /** Enable word-level timestamps */
    val enableTimestamps: Boolean = true,
    /** Custom vocabulary words to improve recognition */
    val vocabularyFilter: List<String> = emptyList(),
    /** Audio format of input data */
    val audioFormat: AudioFormat = AudioFormat.PCM,
    /** Sample rate of input audio (default: 16000 Hz for STT models) */
    val sampleRate: Int = 16000,
    /** Preferred framework for transcription (WhisperKit, ONNX, etc.) - matches iOS */
    val preferredFramework: InferenceFramework? = null,
) {
    companion object {
        /**
         * Create options with default settings for a specific language (matches iOS)
         */
        fun default(language: String = "en"): STTOptions = STTOptions(language = language)
    }
}

// MARK: - STT Configuration

/**
 * Configuration for STT component (matches iOS STTConfiguration exactly)
 */
data class STTConfiguration(
    // Component type
    override val componentType: SDKComponent = SDKComponent.STT,
    // Model ID
    override val modelId: String? = null,
    // Model parameters
    val language: String = "en-US",
    val sampleRate: Int = 16000,
    val enablePunctuation: Boolean = true,
    val enableDiarization: Boolean = false,
    val vocabularyList: List<String> = emptyList(),
    val maxAlternatives: Int = 1,
    val enableTimestamps: Boolean = true,
    val useGPUIfAvailable: Boolean = true,
) : ComponentConfiguration,
    ComponentInitParameters {
    override fun validate() {
        if (sampleRate <= 0 || sampleRate > 48000) {
            throw SDKError.ValidationFailed("Sample rate must be between 1 and 48000 Hz")
        }
        if (maxAlternatives <= 0 || maxAlternatives > 10) {
            throw SDKError.ValidationFailed("Max alternatives must be between 1 and 10")
        }
    }
}

// MARK: - STT Input/Output Models

/**
 * Input for Speech-to-Text (conforms to ComponentInput protocol)
 */
data class STTInput(
    // Audio data to transcribe
    val audioData: ByteArray = byteArrayOf(),
    // Audio buffer (alternative to data)
    val audioBuffer: FloatArray? = null,
    // Audio format information
    val format: AudioFormat = AudioFormat.WAV,
    // Language code override (e.g., "en-US")
    val language: String? = null,
    // Optional VAD output for context
    val vadOutput: VADOutput? = null,
    // Custom options override
    val options: STTOptions? = null,
) : ComponentInput {
    override fun validate() {
        if (audioData.isEmpty() && audioBuffer == null) {
            throw SDKError.ValidationFailed("STTInput must contain either audioData or audioBuffer")
        }
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is STTInput) return false
        return audioData.contentEquals(other.audioData) &&
            audioBuffer?.contentEquals(
                other.audioBuffer ?: floatArrayOf(),
            ) ?: (other.audioBuffer == null) &&
            format == other.format &&
            language == other.language &&
            vadOutput == other.vadOutput &&
            options == other.options
    }

    override fun hashCode(): Int {
        var result = audioData.contentHashCode()
        result = 31 * result + (audioBuffer?.contentHashCode() ?: 0)
        result = 31 * result + format.hashCode()
        result = 31 * result + (language?.hashCode() ?: 0)
        result = 31 * result + (vadOutput?.hashCode() ?: 0)
        result = 31 * result + (options?.hashCode() ?: 0)
        return result
    }
}

/**
 * Output from Speech-to-Text (matches iOS STTOutput exactly)
 */
data class STTOutput(
    /** Transcribed text */
    val text: String,
    /** Confidence score (0.0 to 1.0) */
    val confidence: Float,
    /** Word-level timestamps if available */
    val wordTimestamps: List<WordTimestamp>? = null,
    /** Detected language if auto-detected */
    val detectedLanguage: String? = null,
    /** Alternative transcriptions if available */
    val alternatives: List<TranscriptionAlternative>? = null,
    /** Processing metadata */
    val metadata: TranscriptionMetadata,
    /** Timestamp (required by ComponentOutput) */
    override val timestamp: Long = getCurrentTimeMillis(),
) : ComponentOutput

// MARK: - Supporting Data Classes

/**
 * Transcription metadata (matches iOS TranscriptionMetadata exactly)
 */
data class TranscriptionMetadata(
    val modelId: String,
    val processingTime: Double, // in seconds
    val audioLength: Double, // in seconds
    val realTimeFactor: Double = if (audioLength > 0) processingTime / audioLength else 0.0,
)

/**
 * Word timestamp information (matches iOS WordTimestamp exactly)
 */
data class WordTimestamp(
    val word: String,
    val startTime: Double, // in seconds
    val endTime: Double, // in seconds
    val confidence: Float,
)

/**
 * Alternative transcription (matches iOS TranscriptionAlternative exactly)
 */
data class TranscriptionAlternative(
    val text: String,
    val confidence: Float,
)

/**
 * Transcription result from service
 */
data class STTTranscriptionResult(
    val transcript: String,
    val confidence: Float? = null,
    val timestamps: List<TimestampInfo>? = null,
    val language: String? = null,
    val alternatives: List<AlternativeTranscription>? = null,
) {
    data class TimestampInfo(
        val word: String,
        val startTime: Double, // in seconds
        val endTime: Double, // in seconds
        val confidence: Float? = null,
    )

    data class AlternativeTranscription(
        val transcript: String,
        val confidence: Float,
    )
}

// MARK: - STT Errors (matches iOS STTError exactly)

sealed class STTError : Exception() {
    object serviceNotInitialized : STTError()

    data class transcriptionFailed(
        override val cause: Throwable,
    ) : STTError()

    object streamingNotSupported : STTError()

    data class languageNotSupported(
        val language: String,
    ) : STTError()

    data class modelNotFound(
        val model: String,
    ) : STTError()

    object audioFormatNotSupported : STTError()

    object insufficientAudioData : STTError()

    object noVoiceServiceAvailable : STTError()

    object audioSessionNotConfigured : STTError()

    object audioSessionActivationFailed : STTError()

    object microphonePermissionDenied : STTError()

    /**
     * Localized error description (matches iOS errorDescription)
     */
    val errorDescription: String
        get() =
            when (this) {
                is serviceNotInitialized -> "STT service is not initialized"
                is transcriptionFailed -> "Transcription failed: ${cause.message ?: cause.toString()}"
                is streamingNotSupported -> "Streaming transcription is not supported"
                is languageNotSupported -> "Language not supported: $language"
                is modelNotFound -> "Model not found: $model"
                is audioFormatNotSupported -> "Audio format is not supported"
                is insufficientAudioData -> "Insufficient audio data for transcription"
                is noVoiceServiceAvailable -> "No STT service available for transcription"
                is audioSessionNotConfigured -> "Audio session is not configured"
                is audioSessionActivationFailed -> "Failed to activate audio session"
                is microphonePermissionDenied -> "Microphone permission was denied"
            }

    override val message: String get() = errorDescription
}

// MARK: - STT Service Protocol

/**
 * Protocol for speech-to-text services (matches iOS STTService exactly)
 */
interface STTService {
    /**
     * Initialize the service with optional model path
     */
    suspend fun initialize(modelPath: String?)

    /**
     * Transcribe audio data (batch mode)
     */
    suspend fun transcribe(
        audioData: ByteArray,
        options: STTOptions,
    ): STTTranscriptionResult

    /**
     * Stream transcription for real-time processing (live mode)
     * Falls back to batch mode if streaming is not supported
     */
    suspend fun streamTranscribe(
        audioStream: Flow<ByteArray>,
        options: STTOptions,
        onPartial: (String) -> Unit,
    ): STTTranscriptionResult

    /**
     * Check if service is ready
     */
    val isReady: Boolean

    /**
     * Get current model identifier
     */
    val currentModel: String?

    /**
     * Whether this service supports live/streaming transcription
     * If false, streamTranscribe will fall back to batch mode
     */
    val supportsStreaming: Boolean get() = true

    /**
     * Cleanup resources
     */
    suspend fun cleanup()
}

// Note: STTServiceProvider is defined in core.ModuleRegistry to avoid duplication

// MARK: - STT Service Wrapper

/**
 * Wrapper class to allow protocol-based STT service to work with BaseComponent
 */
class STTServiceWrapper(
    service: STTService? = null,
) : ServiceWrapper<STTService> {
    override var wrappedService: STTService? = service
}

// MARK: - Streaming Events (Kotlin-specific typed events)
// Note: iOS uses AsyncThrowingStream<String, Error> for streaming which only emits strings.
// In Kotlin, we provide typed events for richer streaming support while maintaining
// the same callback-based pattern in STTService.streamTranscribe for iOS compatibility.

/**
 * Events emitted during streaming transcription (Kotlin-specific extension for rich typing)
 * The core STTService.streamTranscribe uses callback pattern matching iOS exactly.
 */
sealed class STTStreamEvent {
    object SpeechStarted : STTStreamEvent()

    object SpeechEnded : STTStreamEvent()

    object SilenceDetected : STTStreamEvent()

    data class PartialTranscription(
        val text: String,
        val confidence: Float = 0.0f,
        val wordTimestamps: List<WordTimestamp>? = null,
        val isFinal: Boolean = false,
    ) : STTStreamEvent()

    data class FinalTranscription(
        val result: STTTranscriptionResult,
    ) : STTStreamEvent()

    data class LanguageDetected(
        val language: String,
        val confidence: Float,
    ) : STTStreamEvent()

    data class SpeakerChanged(
        val speakerId: String,
        val timestamp: Double,
    ) : STTStreamEvent()

    data class AudioLevelChanged(
        val level: Float, // 0.0 to 1.0
        val timestamp: Double,
    ) : STTStreamEvent()

    data class Error(
        val error: STTError,
    ) : STTStreamEvent()
}

/**
 * Streaming transcription configuration (Kotlin-specific extension)
 */
data class STTStreamingOptions(
    val language: String? = null,
    val detectLanguage: Boolean = true,
    val enablePartialResults: Boolean = true,
    val partialResultInterval: Double = 0.5, // seconds
    val maxSilenceDuration: Double = 3.0, // seconds before ending
    val enableSpeakerDiarization: Boolean = false,
    val enableAudioLevelMonitoring: Boolean = false,
    val audioLevelUpdateInterval: Double = 0.1, // seconds
    val minConfidenceThreshold: Float = 0.3f,
    val endOnSilence: Boolean = true,
    val maxDuration: Double? = null, // Max recording duration
)
