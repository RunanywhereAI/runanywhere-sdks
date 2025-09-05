package com.runanywhere.sdk.components.stt

import com.runanywhere.sdk.components.base.*
import com.runanywhere.sdk.components.vad.VADOutput
import com.runanywhere.sdk.data.models.SDKError
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant

// MARK: - Audio Format

enum class AudioFormat {
    PCM,
    WAV,
    MP3,
    FLAC,
    OGG
}

// MARK: - STT Options

/**
 * Options for speech-to-text transcription
 */
data class STTOptions(
    val language: String = "en",
    val detectLanguage: Boolean = false,
    val enablePunctuation: Boolean = true,
    val enableDiarization: Boolean = false,
    val maxSpeakers: Int? = null,
    val enableTimestamps: Boolean = true,
    val vocabularyFilter: List<String> = emptyList(),
    val audioFormat: AudioFormat = AudioFormat.PCM,
    // Enhanced sensitivity settings
    val sensitivityMode: STTSensitivityMode = STTSensitivityMode.NORMAL,
    val beamSize: Int = 5,
    val temperature: Float = 0.0f,
    val suppressBlank: Boolean = true,
    val suppressNonSpeechTokens: Boolean = true
) {
    companion object {
        /**
         * Create highly sensitive STT options for better detection of quiet or unclear speech
         */
        fun createSensitive(): STTOptions = STTOptions(
            language = "en",
            detectLanguage = false,
            enablePunctuation = true,
            enableTimestamps = true,
            sensitivityMode = STTSensitivityMode.HIGH,
            beamSize = 10,
            temperature = 0.3f,
            suppressBlank = false,
            suppressNonSpeechTokens = false
        )

        /**
         * Create default STT options
         */
        fun createDefault(): STTOptions = STTOptions()
    }
}

/**
 * Sensitivity modes for STT processing
 */
enum class STTSensitivityMode {
    /** Standard sensitivity - good for clear speech */
    NORMAL,
    /** Higher sensitivity - better for quiet or unclear speech */
    HIGH,
    /** Maximum sensitivity - for very quiet or distant speech */
    MAXIMUM
}

// MARK: - STT Configuration

/**
 * Configuration for STT component (conforms to ComponentConfiguration and ComponentInitParameters protocols)
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
    val useGPUIfAvailable: Boolean = true
) : ComponentConfiguration, ComponentInitParameters {

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
    val audioData: ByteArray,

    // Audio buffer (alternative to data)
    val audioBuffer: FloatArray? = null,

    // Audio format information
    val format: AudioFormat = AudioFormat.WAV,

    // Language code override (e.g., "en-US")
    val language: String? = null,

    // Optional VAD output for context
    val vadOutput: VADOutput? = null,

    // Custom options override
    val options: STTOptions? = null
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
                    other.audioBuffer ?: floatArrayOf()
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
 * Output from Speech-to-Text (conforms to ComponentOutput protocol)
 */
data class STTOutput(
    // Transcribed text
    val text: String,

    // Confidence score (0.0 to 1.0)
    val confidence: Float,

    // Word-level timestamps if available
    val wordTimestamps: List<WordTimestamp>? = null,

    // Detected language if auto-detected
    val detectedLanguage: String? = null,

    // Alternative transcriptions if available
    val alternatives: List<TranscriptionAlternative>? = null,

    // Processing metadata
    val metadata: TranscriptionMetadata,

    // Timestamp (required by ComponentOutput)
    override val timestamp: Instant = Clock.System.now()
) : ComponentOutput

// MARK: - Supporting Data Classes

/**
 * Transcription metadata
 */
data class TranscriptionMetadata(
    val modelId: String,
    val processingTime: Double, // in seconds
    val audioLength: Double, // in seconds
    val realTimeFactor: Double = if (audioLength > 0) processingTime / audioLength else 0.0
)

/**
 * Word timestamp information
 */
data class WordTimestamp(
    val word: String,
    val startTime: Double, // in seconds
    val endTime: Double, // in seconds
    val confidence: Float
)

/**
 * Alternative transcription
 */
data class TranscriptionAlternative(
    val text: String,
    val confidence: Float
)

/**
 * Transcription result from service
 */
data class STTTranscriptionResult(
    val transcript: String,
    val confidence: Float? = null,
    val timestamps: List<TimestampInfo>? = null,
    val language: String? = null,
    val alternatives: List<AlternativeTranscription>? = null
) {
    data class TimestampInfo(
        val word: String,
        val startTime: Double, // in seconds
        val endTime: Double, // in seconds
        val confidence: Float? = null
    )

    data class AlternativeTranscription(
        val transcript: String,
        val confidence: Float
    )
}

// MARK: - STT Errors

sealed class STTError : Exception() {
    object ServiceNotInitialized : STTError()
    data class TranscriptionFailed(override val cause: Throwable) : STTError()
    object StreamingNotSupported : STTError()
    data class LanguageNotSupported(val language: String) : STTError()
    data class ModelNotFound(val model: String) : STTError()
    object AudioFormatNotSupported : STTError()
    object InsufficientAudioData : STTError()
    object NoVoiceServiceAvailable : STTError()
    object AudioSessionNotConfigured : STTError()
    object AudioSessionActivationFailed : STTError()
    object MicrophonePermissionDenied : STTError()

    override val message: String
        get() = when (this) {
            is ServiceNotInitialized -> "STT service is not initialized"
            is TranscriptionFailed -> "Transcription failed: ${cause.localizedMessage}"
            is StreamingNotSupported -> "Streaming transcription is not supported"
            is LanguageNotSupported -> "Language not supported: $language"
            is ModelNotFound -> "Model not found: $model"
            is AudioFormatNotSupported -> "Audio format is not supported"
            is InsufficientAudioData -> "Insufficient audio data for transcription"
            is NoVoiceServiceAvailable -> "No STT service available for transcription"
            is AudioSessionNotConfigured -> "Audio session is not configured"
            is AudioSessionActivationFailed -> "Failed to activate audio session"
            is MicrophonePermissionDenied -> "Microphone permission was denied"
        }
}

// MARK: - STT Service Protocol

/**
 * Protocol for speech-to-text services
 */
interface STTService {
    // Initialize the service with optional model path
    suspend fun initialize(modelPath: String?)

    // Transcribe audio data
    suspend fun transcribe(audioData: ByteArray, options: STTOptions): STTTranscriptionResult

    // Stream transcription for real-time processing
    suspend fun <T> streamTranscribe(
        audioStream: kotlinx.coroutines.flow.Flow<ByteArray>,
        options: STTOptions,
        onPartial: (String) -> Unit
    ): STTTranscriptionResult

    // Check if service is ready
    val isReady: Boolean

    // Get current model identifier
    val currentModel: String?

    // Cleanup resources
    suspend fun cleanup()
}

// MARK: - STT Service Wrapper

/**
 * Wrapper class to allow protocol-based STT service to work with BaseComponent
 */
class STTServiceWrapper(service: STTService? = null) : ServiceWrapper<STTService> {
    override var wrappedService: STTService? = service
}
