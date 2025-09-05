package com.runanywhere.sdk.components.vad

import com.runanywhere.sdk.components.base.*
import com.runanywhere.sdk.data.models.SDKError
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant

// MARK: - VAD Configuration

/**
 * Configuration for VAD component
 */
data class VADConfiguration(
    // Component type
    override val componentType: SDKComponent = SDKComponent.VAD,

    // Model ID (optional for VAD)
    override val modelId: String? = null,

    // VAD parameters
    val aggressiveness: Int = 2, // 0-3, higher = more aggressive
    val sampleRate: Int = 16000,
    val frameDuration: Int = 30, // ms
    val silenceThreshold: Int = 500, // ms of silence to stop
    val energyThreshold: Float = 0.5f,
    val useEnhancedModel: Boolean = false
) : ComponentConfiguration, ComponentInitParameters {

    override fun validate() {
        if (aggressiveness !in 0..3) {
            throw SDKError.ValidationFailed("Aggressiveness must be between 0 and 3")
        }
        if (sampleRate <= 0 || sampleRate > 48000) {
            throw SDKError.ValidationFailed("Sample rate must be between 1 and 48000 Hz")
        }
        if (frameDuration !in listOf(10, 20, 30)) {
            throw SDKError.ValidationFailed("Frame duration must be 10, 20, or 30 ms")
        }
        if (silenceThreshold <= 0) {
            throw SDKError.ValidationFailed("Silence threshold must be positive")
        }
    }
}

// MARK: - VAD Input

/**
 * Input for Voice Activity Detection
 */
data class VADInput(
    // Audio samples to process
    val audioSamples: FloatArray,

    // Sample rate (optional, uses config if not specified)
    val sampleRate: Int? = null,

    // Frame duration in ms (optional)
    val frameDuration: Int? = null
) : ComponentInput {

    override fun validate() {
        if (audioSamples.isEmpty()) {
            throw SDKError.ValidationFailed("Audio samples cannot be empty")
        }
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is VADInput) return false
        return audioSamples.contentEquals(other.audioSamples) &&
                sampleRate == other.sampleRate &&
                frameDuration == other.frameDuration
    }

    override fun hashCode(): Int {
        var result = audioSamples.contentHashCode()
        result = 31 * result + (sampleRate ?: 0)
        result = 31 * result + (frameDuration ?: 0)
        return result
    }
}

// MARK: - VAD Output

/**
 * Output from Voice Activity Detection
 */
data class VADOutput(
    // Whether speech is detected
    val isSpeech: Boolean,

    // Confidence score (0.0 to 1.0)
    val confidence: Float,

    // Energy level of the audio
    val energyLevel: Float,

    // Speech probability (0.0 to 1.0)
    val speechProbability: Float,

    // Processing metadata
    val metadata: VADMetadata,

    // Timestamp (required by ComponentOutput)
    override val timestamp: Instant = Clock.System.now()
) : ComponentOutput

// MARK: - VAD Metadata

/**
 * VAD processing metadata
 */
data class VADMetadata(
    val frameDuration: Int, // ms
    val sampleRate: Int,
    val aggressiveness: Int,
    val processingTime: Double // in seconds
)

// MARK: - VAD Service Protocol

/**
 * Protocol for Voice Activity Detection services
 */
interface VADService {
    // Initialize the service
    suspend fun initialize(configuration: VADConfiguration)

    // Process audio chunk for voice activity
    fun processAudioChunk(audioSamples: FloatArray): VADResult

    // Reset VAD state
    fun reset()

    // Check if service is ready
    val isReady: Boolean

    // Get current configuration
    val configuration: VADConfiguration?

    // Cleanup resources
    suspend fun cleanup()
}

// MARK: - VAD Result (for compatibility)

/**
 * VAD Result data class (kept for compatibility)
 */
data class VADResult(
    val isSpeech: Boolean,
    val confidence: Float,
    val timestamp: Long = Clock.System.now().toEpochMilliseconds()
)

// MARK: - VAD Service Wrapper

/**
 * Wrapper class to allow protocol-based VAD service to work with BaseComponent
 */
class VADServiceWrapper(service: VADService? = null) : ServiceWrapper<VADService> {
    override var wrappedService: VADService? = service
}

// MARK: - VAD Errors

sealed class VADError : Exception() {
    object ServiceNotInitialized : VADError()
    data class ProcessingFailed(override val cause: Throwable) : VADError()
    object InvalidAudioFormat : VADError()
    object ConfigurationError : VADError()

    override val message: String
        get() = when (this) {
            is ServiceNotInitialized -> "VAD service is not initialized"
            is ProcessingFailed -> "VAD processing failed: $cause"
            is InvalidAudioFormat -> "Invalid audio format for VAD"
            is ConfigurationError -> "VAD configuration error"
        }
}
