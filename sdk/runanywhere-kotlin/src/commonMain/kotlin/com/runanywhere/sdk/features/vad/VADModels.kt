package com.runanywhere.sdk.features.vad

import com.runanywhere.sdk.core.capabilities.ComponentOutput
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.utils.getCurrentTimeMillis

// MARK: - VAD Configuration

/**
 * Configuration for VAD - matches iOS VADConfiguration exactly
 * Based on iOS SimpleEnergyVAD: energyThreshold: 0.015, sampleRate: 16000, frameLength: 0.1
 */
data class VADConfiguration(
    /** Model ID for VAD provider selection (optional for built-in VAD) */
    val modelId: String? = null,
    /** Energy threshold for voice detection (0.0 to 1.0) */
    val energyThreshold: Float = 0.015f,
    /** Sample rate of the audio in Hz */
    val sampleRate: Int = 16000,
    /** Frame length in seconds */
    val frameLength: Float = 0.1f,
    /** Enable automatic calibration */
    val enableAutoCalibration: Boolean = false,
    /** Calibration multiplier */
    val calibrationMultiplier: Float = 2.0f,
) {
    /** Frame duration in milliseconds */
    val frameDurationMs: Int get() = (frameLength * 1000).toInt()

    /** Frame length in samples */
    val frameLengthSamples: Int get() = (frameLength * sampleRate).toInt()

    /** Validate configuration */
    fun validate() {
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

    companion object {
        /** Default configuration */
        val default = VADConfiguration()
    }
}

// MARK: - VAD Input

/**
 * Input for Voice Activity Detection - matching iOS VADInput exactly
 */
data class VADInput(
    /** Audio samples to process */
    val audioSamples: FloatArray,
    /** Optional override for energy threshold */
    val energyThresholdOverride: Float? = null,
) {
    /** Validate input parameters */
    fun validate() {
        if (audioSamples.isEmpty()) {
            throw SDKError.ValidationFailed("Audio samples cannot be empty")
        }
        energyThresholdOverride?.let { threshold ->
            if (threshold < 0.0f || threshold > 1.0f) {
                throw SDKError.ValidationFailed("Energy threshold override must be between 0.0 and 1.0")
            }
        }
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is VADInput) return false
        return audioSamples.contentEquals(other.audioSamples) &&
            energyThresholdOverride == other.energyThresholdOverride
    }

    override fun hashCode(): Int {
        var result = audioSamples.contentHashCode()
        result = 31 * result + (energyThresholdOverride?.hashCode() ?: 0)
        return result
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
    override val timestamp: Long = getCurrentTimeMillis(),
) : ComponentOutput

// MARK: - VAD Metadata (simplified)

/**
 * VAD processing metadata - simplified to essential information
 */
data class VADMetadata(
    val frameLength: Float, // Frame length in seconds
    val sampleRate: Int, // Sample rate
    val energyThreshold: Float, // Energy threshold used
    val processingTime: Double, // Processing time in seconds
)

// MARK: - Speech Activity Events (matching iOS patterns)

/**
 * Speech activity events matching iOS SpeechActivityEvent
 */
enum class SpeechActivityEvent {
    STARTED, // Equivalent to iOS .started
    ENDED, // Equivalent to iOS .ended
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

    // Pause VAD processing (optional - default no-op)
    fun pause() {}

    // Resume VAD processing (optional - default no-op)
    fun resume() {}

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

    // =========================================================================
    // MARK: - TTS Integration (matching iOS VADService protocol)
    // =========================================================================

    /**
     * Notify VAD that TTS is about to start playing
     * This prevents TTS audio from triggering VAD (feedback prevention)
     *
     * Implementation should:
     * 1. Block all VAD processing during TTS
     * 2. Increase energy threshold to prevent false triggers
     * 3. End any current speech detection
     * 4. Reset detection counters
     */
    fun notifyTTSWillStart()

    /**
     * Notify VAD that TTS has finished playing
     * This restores VAD to normal operation
     *
     * Implementation should:
     * 1. Restore original energy threshold
     * 2. Reset state for immediate readiness
     * 3. Resume VAD processing
     */
    fun notifyTTSDidFinish()

    /**
     * Check if TTS is currently active (VAD processing blocked)
     */
    val isTTSActive: Boolean

    /**
     * Set the TTS threshold multiplier for feedback prevention
     * Default is 3.0x (threshold is multiplied during TTS)
     */
    fun setTTSThresholdMultiplier(multiplier: Float)

    // =========================================================================
    // MARK: - Calibration (matching iOS SimpleEnergyVADService)
    // =========================================================================

    /**
     * Start automatic calibration to determine ambient noise level.
     * Matching iOS SimpleEnergyVADService.startCalibration() exactly.
     *
     * Calibration samples ambient noise for a few seconds and dynamically
     * adjusts the energy threshold based on the detected noise floor.
     *
     * @return true if calibration started successfully, false if already calibrating
     */
    suspend fun startCalibration(): Boolean

    // =========================================================================
    // MARK: - Debug Statistics (matching iOS getStatistics)
    // =========================================================================

    /**
     * Get current VAD statistics for debugging
     * Returns null if statistics are not available
     */
    fun getStatistics(): VADStatistics?
}

// MARK: - VAD Result (for compatibility)

/**
 * VAD Result data class - aligned with iOS output expectations
 */
data class VADResult(
    val isSpeechDetected: Boolean,
    val confidence: Float = 0.0f,
    val timestamp: Long = getCurrentTimeMillis(),
)

// MARK: - VAD Errors (matches iOS VADError exactly)

sealed class VADError : Exception() {
    // Initialization Errors
    /** VAD service is not initialized */
    object NotInitialized : VADError()

    /** Initialization failed with specific reason (matches iOS) */
    data class InitializationFailed(
        val reason: String,
    ) : VADError()

    /** Invalid configuration with specific reason (matches iOS) */
    data class InvalidConfiguration(
        val reason: String,
    ) : VADError()

    // Runtime Errors

    /** Service is not available (matches iOS) */
    object ServiceNotAvailable : VADError()

    /** Processing failed with cause (matches iOS) */
    data class ProcessingFailed(
        val reason: String,
        override val cause: Throwable? = null,
    ) : VADError()

    /** Invalid audio format with expected/received info (matches iOS) */
    data class InvalidAudioFormat(
        val expected: String,
        val received: String,
    ) : VADError()

    /** Empty audio buffer (matches iOS) */
    object EmptyAudioBuffer : VADError()

    /** Invalid input with reason (matches iOS) */
    data class InvalidInput(
        val reason: String,
    ) : VADError()

    // Calibration Errors (matches iOS)

    /** Calibration failed with specific reason (matches iOS) */
    data class CalibrationFailed(
        val reason: String,
    ) : VADError()

    /** Calibration timed out (matches iOS) */
    object CalibrationTimeout : VADError()

    // Resource Errors

    /** Operation was cancelled (matches iOS) */
    object Cancelled : VADError()

    // Legacy compatibility - maps to NotInitialized
    @Deprecated("Use NotInitialized instead", ReplaceWith("NotInitialized"))
    val ServiceNotInitialized: VADError get() = NotInitialized

    // Legacy compatibility - maps to InvalidConfiguration
    @Deprecated("Use InvalidConfiguration instead")
    val ConfigurationError: VADError get() = InvalidConfiguration("Unknown configuration error")

    override val message: String
        get() =
            when (this) {
                is NotInitialized -> "VAD service is not initialized"
                is InitializationFailed -> "VAD initialization failed: $reason"
                is InvalidConfiguration -> "VAD configuration invalid: $reason"
                is ServiceNotAvailable -> "VAD service is not available"
                is ProcessingFailed -> "VAD processing failed: $reason"
                is InvalidAudioFormat -> "Invalid audio format: expected $expected, received $received"
                is EmptyAudioBuffer -> "Audio buffer is empty"
                is InvalidInput -> "Invalid input: $reason"
                is CalibrationFailed -> "Calibration failed: $reason"
                is CalibrationTimeout -> "Calibration timed out"
                is Cancelled -> "VAD operation was cancelled"
            }
}
