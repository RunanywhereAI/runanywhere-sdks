package com.runanywhere.sdk.components.stt

import com.runanywhere.sdk.components.base.*
import com.runanywhere.sdk.components.vad.VADOutput
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.coroutines.flow.Flow

// MARK: - Audio Format

enum class AudioFormat {
    PCM,
    WAV,
    MP3,
    FLAC,
    OGG
}

/**
 * Enum to specify preferred audio format for the service (matches iOS STTServiceAudioFormat)
 */
enum class STTServiceAudioFormat {
    /** Service prefers raw ByteArray data */
    DATA,
    /** Service prefers FloatArray samples */
    FLOAT_ARRAY
}

// MARK: - STT Mode

/**
 * Transcription mode for speech-to-text (matches iOS STTMode exactly)
 */
enum class STTMode(val value: String) {
    /**
     * Batch mode: Record all audio first, then transcribe everything at once
     * Best for: Short recordings, offline processing, higher accuracy
     */
    BATCH("batch"),

    /**
     * Live/Streaming mode: Transcribe audio in real-time as it's recorded
     * Best for: Live captions, real-time feedback, long recordings
     */
    LIVE("live");

    /**
     * Display name for UI (matches iOS displayName)
     */
    val displayName: String
        get() = when (this) {
            BATCH -> "Batch"
            LIVE -> "Live"
        }

    /**
     * Description of the mode (matches iOS description)
     */
    val description: String
        get() = when (this) {
            BATCH -> "Record audio, then transcribe all at once"
            LIVE -> "Real-time transcription as you speak"
        }

    /**
     * Icon identifier for the mode (matches iOS icon)
     * Uses SF Symbol names for cross-platform icon lookup
     */
    val icon: String
        get() = when (this) {
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

// MARK: - STT Options

/**
 * Options for speech-to-text transcription (matches iOS STTOptions exactly)
 */
data class STTOptions(
    val language: String = "en",
    val detectLanguage: Boolean = true,
    val enablePunctuation: Boolean = true,
    val enableDiarization: Boolean = false,
    val maxSpeakers: Int? = null,
    val enableTimestamps: Boolean = true,
    val enableWordTimestamps: Boolean = true,
    val vocabularyFilter: List<String> = emptyList(),
    val audioFormat: AudioFormat = AudioFormat.PCM,
    val sampleRate: Int = 16000,
    val channels: Int = 1,
    // iOS parity - confidence and quality settings
    val minConfidenceThreshold: Float = 0.5f,
    val returnAlternatives: Boolean = false,
    val maxAlternatives: Int = 1,
    // Enhanced sensitivity settings
    val sensitivityMode: STTSensitivityMode = STTSensitivityMode.NORMAL,
    val beamSize: Int = 5,
    val temperature: Float = 0.0f,
    val suppressBlank: Boolean = true,
    val suppressNonSpeechTokens: Boolean = true,
    // iOS parity - language detection options
    val languageDetectionConfidenceThreshold: Float = 0.7f,
    val supportedLanguages: List<String> = emptyList(), // Empty means all languages
    // iOS parity - streaming options
    val enablePartialResults: Boolean = true,
    val partialResultInterval: Double = 0.5, // seconds
    val maxDuration: Double? = null, // Max recording duration in seconds
    val vadEnabled: Boolean = true,
    val vadSensitivity: Float = 0.5f
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
 * Output from Speech-to-Text (matches iOS STTTranscriptionResult exactly)
 */
data class STTOutput(
    // Transcribed text
    val text: String,

    // Confidence score (0.0 to 1.0)
    val confidence: Float,

    // Word-level timestamps if available
    val wordTimestamps: List<WordTimestamp>? = null,

    // Detected language with confidence if auto-detected
    val detectedLanguage: String? = null,
    val languageConfidence: Float? = null,
    val languageProbabilities: Map<String, Float>? = null,

    // Alternative transcriptions if available
    val alternatives: List<TranscriptionAlternative>? = null,

    // Speaker attribution segments (when diarization is enabled)
    val speakerSegments: List<SpeakerAttributedSegment>? = null,

    // Processing metadata
    val metadata: TranscriptionMetadata,

    // iOS parity - additional quality metrics
    val isFinal: Boolean = true,
    val isPartial: Boolean = false,
    val processingTimeMs: Long = 0,
    val audioLengthMs: Long = 0,
    val realTimeFactor: Float = 0.0f,

    // iOS parity - voice activity and quality
    val voiceActivityDetected: Boolean = true,
    val speechRate: Float? = null, // words per minute
    val pauseCount: Int = 0,
    val averagePauseLength: Double = 0.0,

    // Timestamp (required by ComponentOutput)
    override val timestamp: Long = getCurrentTimeMillis()
) : ComponentOutput

// MARK: - Supporting Data Classes

/**
 * Phoneme information for detailed speech analysis
 */
data class PhonemeInfo(
    val phoneme: String,
    val startTime: Double,
    val endTime: Double,
    val confidence: Float
)

/**
 * Device information for performance analysis
 */
data class DeviceInfo(
    val platform: String = "JVM",
    val osVersion: String? = null,
    val deviceModel: String? = null,
    val cpuInfo: String? = null,
    val memoryMB: Long? = null,
    val hasGPU: Boolean = false
)

/**
 * Performance metrics for transcription analysis
 */
data class PerformanceMetrics(
    val cpuUsage: Float? = null,
    val memoryUsage: Long? = null,
    val gpuUsage: Float? = null,
    val networkLatency: Long? = null,
    val modelLoadTime: Long? = null,
    val inferenceTime: Long? = null
)

/**
 * Quality metrics for transcription assessment
 */
data class QualityMetrics(
    val averageConfidence: Float,
    val lowConfidenceWordCount: Int = 0,
    val silenceRatio: Float = 0.0f,
    val speechRate: Float = 0.0f, // words per minute
    val signalToNoiseRatio: Float? = null,
    val audioQualityScore: Float? = null
)

/**
 * Transcription metadata (matches iOS TranscriptionMetadata)
 */
data class TranscriptionMetadata(
    val modelId: String,
    val processingTime: Double, // in seconds
    val audioLength: Double, // in seconds
    val realTimeFactor: Double = if (audioLength > 0) processingTime / audioLength else 0.0,
    // iOS parity - enhanced metadata
    val modelVersion: String? = null,
    val platform: String = "kotlin",
    val deviceInfo: DeviceInfo? = null,
    val performanceMetrics: PerformanceMetrics? = null,
    val qualityMetrics: QualityMetrics? = null
)

/**
 * Word timestamp information (matches iOS WordTimestamp exactly)
 */
data class WordTimestamp(
    val word: String,
    val startTime: Double, // in seconds
    val endTime: Double, // in seconds
    val confidence: Float,
    // iOS parity - additional word-level metadata
    val speakerId: String? = null, // When speaker diarization is enabled
    val phonemes: List<PhonemeInfo>? = null, // Phonetic information if available
    val isFillerWord: Boolean = false, // "um", "uh", etc.
    val isPunctuation: Boolean = false,
    val partOfSpeech: String? = null // Grammatical classification if available
) {
    init {
        require(endTime >= startTime) { "End time must be >= start time" }
        require(confidence >= 0.0f && confidence <= 1.0f) { "Confidence must be between 0.0 and 1.0" }
    }
}

/**
 * Alternative transcription (matches iOS TranscriptionAlternative)
 */
data class TranscriptionAlternative(
    val text: String,
    val confidence: Float,
    // iOS parity - additional alternative metadata
    val wordTimestamps: List<WordTimestamp>? = null,
    val language: String? = null,
    val languageConfidence: Float? = null
) {
    init {
        require(confidence >= 0.0f && confidence <= 1.0f) { "Confidence must be between 0.0 and 1.0" }
    }
}

/**
 * Speaker-attributed segment for transcription with speaker diarization
 */
data class SpeakerAttributedSegment(
    val speakerId: String,
    val text: String,
    val startTime: Double, // in seconds
    val endTime: Double, // in seconds
    val confidence: Float,
    val speakerName: String? = null
) {
    init {
        require(endTime >= startTime) { "End time must be >= start time" }
        require(confidence >= 0.0f && confidence <= 1.0f) { "Confidence must be between 0.0 and 1.0" }
    }
}

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

// MARK: - STT Errors (matches iOS STTError exactly)

sealed class STTError : Exception() {
    object serviceNotInitialized : STTError()
    data class transcriptionFailed(override val cause: Throwable) : STTError()
    object streamingNotSupported : STTError()
    data class languageNotSupported(val language: String) : STTError()
    data class modelNotFound(val model: String) : STTError()
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
        get() = when (this) {
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
     * Transcribe audio data (matches iOS exactly)
     */
    suspend fun transcribe(audioData: ByteArray, options: STTOptions): STTTranscriptionResult

    /**
     * Stream transcription for real-time processing with callback (matches iOS signature)
     */
    suspend fun streamTranscribe(
        audioStream: Flow<ByteArray>,
        options: STTOptions,
        onPartial: (String) -> Unit
    ): STTTranscriptionResult

    /**
     * Enhanced streaming transcription (matches iOS AsyncThrowingStream patterns)
     */
    fun transcribeStream(
        audioStream: Flow<ByteArray>,
        options: STTStreamingOptions = STTStreamingOptions()
    ): Flow<STTStreamEvent>

    /**
     * Language detection from audio (matches iOS signature)
     */
    suspend fun detectLanguage(audioData: ByteArray): Map<String, Float>

    /**
     * Check if service supports specific language (matches iOS)
     */
    fun supportsLanguage(languageCode: String): Boolean

    /**
     * Get list of supported languages (matches iOS)
     */
    val supportedLanguages: List<String>

    /**
     * Check if service is ready (matches iOS)
     */
    val isReady: Boolean

    /**
     * Get current model identifier (matches iOS)
     */
    val currentModel: String?

    /**
     * Check if streaming is supported (matches iOS)
     */
    val supportsStreaming: Boolean get() = true

    /**
     * Check if language detection is supported (matches iOS)
     */
    val supportsLanguageDetection: Boolean get() = true

    /**
     * Check if speaker diarization is supported (matches iOS)
     */
    val supportsSpeakerDiarization: Boolean get() = false

    /**
     * Get preferred audio format for this service (matches iOS STTServiceAudioFormat)
     */
    val preferredAudioFormat: STTServiceAudioFormat get() = STTServiceAudioFormat.DATA

    /**
     * Cleanup resources (matches iOS)
     */
    suspend fun cleanup()
}

// Note: STTServiceProvider is defined in core.ModuleRegistry to avoid duplication

// MARK: - STT Service Wrapper

/**
 * Wrapper class to allow protocol-based STT service to work with BaseComponent
 */
class STTServiceWrapper(service: STTService? = null) : ServiceWrapper<STTService> {
    override var wrappedService: STTService? = service
}

// MARK: - Streaming Events (matches iOS AsyncThrowingStream patterns)

/**
 * Events emitted during streaming transcription (matches iOS STTStreamEvent exactly)
 */
sealed class STTStreamEvent {
    object SpeechStarted : STTStreamEvent()
    object SpeechEnded : STTStreamEvent()
    object SilenceDetected : STTStreamEvent()

    data class PartialTranscription(
        val text: String,
        val confidence: Float = 0.0f,
        val wordTimestamps: List<WordTimestamp>? = null,
        val isFinal: Boolean = false
    ) : STTStreamEvent()

    data class FinalTranscription(val result: STTTranscriptionResult) : STTStreamEvent()

    data class LanguageDetected(
        val language: String,
        val confidence: Float
    ) : STTStreamEvent()

    data class SpeakerChanged(
        val speakerId: String,
        val timestamp: Double
    ) : STTStreamEvent()

    data class AudioLevelChanged(
        val level: Float, // 0.0 to 1.0
        val timestamp: Double
    ) : STTStreamEvent()

    data class Error(val error: STTError) : STTStreamEvent()
}

/**
 * Streaming transcription configuration (matches iOS)
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
    val maxDuration: Double? = null // Max recording duration
)

/**
 * Real-time transcription state (matches iOS)
 */
data class STTStreamingState(
    val isListening: Boolean = false,
    val currentLanguage: String? = null,
    val currentSpeaker: String? = null,
    val audioLevel: Float = 0.0f,
    val silenceDuration: Double = 0.0,
    val totalDuration: Double = 0.0,
    val partialText: String = "",
    val finalText: String = "",
    val averageConfidence: Float = 0.0f
)
