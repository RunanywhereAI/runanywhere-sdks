package com.runanywhere.sdk.features.vad

import com.runanywhere.sdk.core.capabilities.*
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.utils.getCurrentTimeMillis

// MARK: - VAD Configuration

/**
 * Configuration for VAD component - simplified to match iOS SimpleEnergyVAD
 * Based on iOS VADConfiguration: energyThreshold: 0.022, sampleRate: 16000, frameLength: 0.1
 */
data class VADConfiguration(
    // Component type
    override val componentType: SDKComponent = SDKComponent.VAD,

    // Model ID (optional for VAD)
    override val modelId: String? = null,

    // Core VAD parameters matching iOS SimpleEnergyVAD
    val energyThreshold: Float = 0.022f,  // Default matches iOS exactly
    val sampleRate: Int = 16000,          // Default matches iOS exactly
    val frameLength: Float = 0.1f         // Default matches iOS exactly (100ms)
) : ComponentConfiguration, ComponentInitParameters {

    // Computed properties for compatibility and internal use
    val frameDurationMs: Int get() = (frameLength * 1000).toInt()
    val frameLengthSamples: Int get() = (frameLength * sampleRate).toInt()

    override fun validate() {
        if (energyThreshold < 0.0f || energyThreshold > 1.0f) {
            throw SDKError.ValidationFailed("Energy threshold must be between 0.0 and 1.0")
        }
        if (sampleRate <= 0 || sampleRate > 48000) {
            throw SDKError.ValidationFailed("Sample rate must be between 1 and 48000 Hz")
        }
        if (frameLength <= 0.0f || frameLength > 1.0f) {
            throw SDKError.ValidationFailed("Frame length must be between 0.0 and 1.0 seconds")
        }
    }
}

// MARK: - VAD Input

/**
 * Input for Voice Activity Detection - matching iOS VADInput exactly
 */
data class VADInput(
    // Audio samples to process (primary input like iOS [Float] audio samples)
    val audioSamples: FloatArray,

    // Optional override for energy threshold (matching iOS)
    val energyThresholdOverride: Float? = null
) : ComponentInput {

    override fun validate() {
        if (audioSamples.isEmpty()) {
            throw SDKError.ValidationFailed("Audio samples cannot be empty")
        }
        // Validate threshold override if provided (matching iOS validation)
        energyThresholdOverride?.let { threshold ->
            if (threshold < 0.0f || threshold > 1.0f) {
                throw SDKError.ValidationFailed("Energy threshold override must be between 0.0 and 1.0")
            }
        }
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is VADInput) return false
        return audioSamples.contentEquals(other.audioSamples)
    }

    override fun hashCode(): Int {
        return audioSamples.contentHashCode()
    }
}

// MARK: - VAD Output

/**
 * Output from Voice Activity Detection - matching iOS VADOutput exactly
 */
data class VADOutput(
    // Whether speech is detected (matching iOS property name)
    val isSpeechDetected: Boolean,

    // Energy level of the audio (calculated RMS)
    val energyLevel: Float,

    // Confidence score (0.0 to 1.0) - derived from energy level
    val confidence: Float = if (isSpeechDetected) energyLevel.coerceIn(0.5f, 1.0f) else energyLevel.coerceIn(0.0f, 0.5f),

    // Timestamp (required by ComponentOutput)
    override val timestamp: Long = getCurrentTimeMillis()
) : ComponentOutput

// MARK: - VAD Metadata (simplified)

/**
 * VAD processing metadata - simplified to essential information
 */
data class VADMetadata(
    val frameLength: Float,     // Frame length in seconds
    val sampleRate: Int,        // Sample rate
    val energyThreshold: Float, // Energy threshold used
    val processingTime: Double  // Processing time in seconds
)

// MARK: - Speech Activity Events (matching iOS patterns)

/**
 * Speech activity events matching iOS SpeechActivityEvent
 */
enum class SpeechActivityEvent {
    STARTED,  // Equivalent to iOS .started
    ENDED     // Equivalent to iOS .ended
}

// MARK: - VAD Service Protocol

/**
 * Protocol for Voice Activity Detection services - exactly matching iOS VADService
 */
interface VADService {
    // Properties matching iOS VADService protocol
    var energyThreshold: Float
    val sampleRate: Int
    val frameLength: Float
    val isSpeechActive: Boolean

    // Callbacks matching iOS VADService protocol
    var onSpeechActivity: ((SpeechActivityEvent) -> Unit)?
    var onAudioBuffer: ((ByteArray) -> Unit)?

    // Initialize the service
    suspend fun initialize(configuration: VADConfiguration)

    // Start processing (matching iOS)
    fun start()

    // Stop processing (matching iOS)
    fun stop()

    // Reset VAD state
    fun reset()

    // Process audio chunk for voice activity (primary method)
    fun processAudioChunk(audioSamples: FloatArray): VADResult

    // Process audio data - alternative method matching iOS
    fun processAudioData(audioData: FloatArray): Boolean

    // Check if service is ready
    val isReady: Boolean

    // Get current configuration
    val configuration: VADConfiguration?

    // Cleanup resources
    suspend fun cleanup()
}

// MARK: - VAD Result (for compatibility)

/**
 * VAD Result data class - aligned with iOS output expectations
 */
data class VADResult(
    val isSpeechDetected: Boolean,
    val confidence: Float = 0.0f,
    val timestamp: Long = getCurrentTimeMillis()
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
