package com.runanywhere.sdk.capabilities.vad

import com.runanywhere.sdk.components.vad.VADComponent
import com.runanywhere.sdk.components.vad.VADConfiguration
import com.runanywhere.sdk.components.vad.VADInput
import com.runanywhere.sdk.components.vad.VADOutput as ComponentVADOutput
import com.runanywhere.sdk.components.vad.SpeechActivityEvent
import com.runanywhere.sdk.components.base.ComponentState
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/**
 * VAD Capability - Public API wrapper for Voice Activity Detection operations
 *
 * Aligned with iOS VADCapability pattern:
 * - Service lifecycle management (initialize, cleanup)
 * - Detection API (detectSpeech)
 * - Control API (start, stop, reset, pause, resume)
 * - Configuration updates (setEnergyThreshold, setSpeechActivityCallback)
 * - Event tracking (handled automatically by underlying component)
 *
 * This capability wraps VADComponent and provides the interface expected by
 * the public RunAnywhere+VAD.kt extension functions.
 *
 * Unlike STT/TTS/LLM, VAD is ServiceBasedCapability (not ModelLoadable) -
 * it doesn't require loading a model, just initializing the service.
 */
class VADCapability internal constructor(
    private val getComponent: () -> VADComponent
) {
    private val logger = SDKLogger("VADCapability")

    // ============================================================================
    // MARK: - State Properties (iOS ServiceBasedCapability pattern)
    // ============================================================================

    /**
     * Whether VAD is ready for use
     */
    val isReady: Boolean
        get() = getComponent().state == ComponentState.READY

    /**
     * Whether speech is currently active
     */
    val isSpeechActive: Boolean
        get() = getComponent().getService()?.isSpeechActive ?: false

    /**
     * Current energy threshold
     */
    val energyThreshold: Float
        get() = getComponent().getService()?.energyThreshold ?: 0.0f

    // ============================================================================
    // MARK: - Service Lifecycle (iOS ServiceBasedCapability pattern)
    // ============================================================================

    /**
     * Initialize VAD with default configuration
     *
     * @throws SDKError if initialization fails
     */
    suspend fun initialize() {
        initialize(VADConfiguration())
    }

    /**
     * Initialize VAD with custom configuration
     *
     * @param config VAD configuration
     * @throws SDKError if initialization fails
     */
    suspend fun initialize(config: VADConfiguration) {
        logger.info("Initializing VAD")

        try {
            val component = getComponent()
            component.initialize()

            logger.info("VAD initialized successfully")
        } catch (e: Exception) {
            logger.error("Failed to initialize VAD", e)
            throw SDKError.InitializationFailed("VAD initialization failed: ${e.message}")
        }
    }

    /**
     * Cleanup VAD resources
     */
    suspend fun cleanup() {
        logger.info("Cleaning up VAD")

        try {
            getComponent().cleanup()
            logger.info("VAD cleaned up")
        } catch (e: Exception) {
            logger.error("Failed to cleanup VAD", e)
            throw e
        }
    }

    // ============================================================================
    // MARK: - Detection API (iOS detectSpeech pattern)
    // ============================================================================

    /**
     * Detect speech in audio samples
     *
     * @param samples Float array of audio samples
     * @return VADOutput with detection result
     * @throws SDKError if VAD is not ready
     */
    fun detectSpeech(samples: FloatArray): VADOutput {
        ensureReady()

        val component = getComponent()
        val output = component.detectSpeech(samples)

        return output.toVADOutput()
    }

    /**
     * Detect speech with energy threshold override
     *
     * @param samples Float array of audio samples
     * @param energyThresholdOverride Optional threshold override for this detection
     * @return VADOutput with detection result
     * @throws SDKError if VAD is not ready
     */
    fun detectSpeech(samples: FloatArray, energyThresholdOverride: Float? = null): VADOutput {
        ensureReady()

        val component = getComponent()
        val input = VADInput(
            audioSamples = samples,
            energyThresholdOverride = energyThresholdOverride
        )
        val output = component.process(input)

        return output.toVADOutput()
    }

    /**
     * Stream VAD processing
     *
     * @param audioStream Flow of audio samples
     * @return Flow of VADOutput with detection results
     */
    fun streamDetectSpeech(audioStream: Flow<FloatArray>): Flow<VADOutput> {
        ensureReady()

        val component = getComponent()
        return component.streamProcess(audioStream).map { it.toVADOutput() }
    }

    /**
     * Detect speech segments with callbacks (matching iOS pattern)
     *
     * @param audioStream Flow of audio samples
     * @param onSpeechStart Callback when speech starts
     * @param onSpeechEnd Callback when speech ends
     * @return Flow of VADOutput with detection results
     */
    fun detectSpeechSegments(
        audioStream: Flow<FloatArray>,
        onSpeechStart: () -> Unit = {},
        onSpeechEnd: () -> Unit = {}
    ): Flow<VADOutput> {
        ensureReady()

        val component = getComponent()
        return component.detectSpeechSegments(audioStream, onSpeechStart, onSpeechEnd).map { it.toVADOutput() }
    }

    // ============================================================================
    // MARK: - Control API (iOS start/stop/reset pattern)
    // ============================================================================

    /**
     * Start VAD processing
     */
    fun start() {
        logger.info("Starting VAD")
        getComponent().start()
    }

    /**
     * Stop VAD processing
     */
    fun stop() {
        logger.info("Stopping VAD")
        getComponent().stop()
    }

    /**
     * Reset VAD state
     */
    fun reset() {
        logger.info("Resetting VAD")
        getComponent().reset()
    }

    // ============================================================================
    // MARK: - Configuration Updates (iOS pattern)
    // ============================================================================

    /**
     * Set energy threshold
     *
     * @param threshold New energy threshold (0.0 to 1.0)
     */
    fun setEnergyThreshold(threshold: Float) {
        getComponent().getService()?.energyThreshold = threshold
    }

    /**
     * Set speech activity callback
     *
     * @param callback Callback invoked when speech state changes
     */
    fun setSpeechActivityCallback(callback: (SpeechActivityEvent) -> Unit) {
        getComponent().setSpeechActivityCallback(callback)
    }

    /**
     * Set audio buffer callback
     *
     * @param callback Callback invoked for processed audio buffers
     */
    fun setAudioBufferCallback(callback: (ByteArray) -> Unit) {
        getComponent().setAudioBufferCallback(callback)
    }

    // ============================================================================
    // MARK: - Private Helpers
    // ============================================================================

    private fun ensureReady() {
        if (!isReady) {
            throw SDKError.ComponentNotReady("VAD not initialized. Call initializeVAD() first.")
        }
    }

    private fun ComponentVADOutput.toVADOutput(): VADOutput {
        return VADOutput(
            isSpeechDetected = this.isSpeechDetected,
            energyLevel = this.energyLevel,
            confidence = this.confidence,
            timestamp = this.timestamp
        )
    }
}

// ============================================================================
// MARK: - Internal Types (Used by Capability, mapped from public types)
// ============================================================================

/**
 * VAD output with detection result
 * Aligned with iOS VADOutput
 */
data class VADOutput(
    /** Whether speech is detected */
    val isSpeechDetected: Boolean,
    /** Energy level of the audio (RMS value) */
    val energyLevel: Float,
    /** Confidence score (0.0 - 1.0) */
    val confidence: Float,
    /** Timestamp of detection */
    val timestamp: Long
) {
    companion object {
        /**
         * Create output for speech detected
         */
        fun speechDetected(energyLevel: Float): VADOutput {
            return VADOutput(
                isSpeechDetected = true,
                energyLevel = energyLevel,
                confidence = energyLevel.coerceIn(0.5f, 1.0f),
                timestamp = com.runanywhere.sdk.utils.getCurrentTimeMillis()
            )
        }

        /**
         * Create output for silence
         */
        fun silence(energyLevel: Float): VADOutput {
            return VADOutput(
                isSpeechDetected = false,
                energyLevel = energyLevel,
                confidence = (1.0f - energyLevel).coerceIn(0.5f, 1.0f),
                timestamp = com.runanywhere.sdk.utils.getCurrentTimeMillis()
            )
        }
    }
}

/**
 * VAD configuration for capability layer
 * Aligned with iOS VADConfiguration
 */
data class VADCapabilityConfiguration(
    /** Energy threshold for voice detection (0.0 to 1.0) */
    val energyThreshold: Float = 0.015f,
    /** Sample rate in Hz */
    val sampleRate: Int = 16000,
    /** Frame length in seconds */
    val frameLength: Float = 0.1f,
    /** Enable automatic calibration */
    val enableAutoCalibration: Boolean = false,
    /** Calibration multiplier */
    val calibrationMultiplier: Float = 2.0f
) {
    /**
     * Convert to component configuration
     */
    fun toComponentConfiguration(): VADConfiguration {
        return VADConfiguration(
            energyThreshold = energyThreshold,
            sampleRate = sampleRate,
            frameLength = frameLength
        )
    }

    companion object {
        /**
         * Builder pattern support
         */
        fun builder() = Builder()
    }

    class Builder {
        private var energyThreshold: Float = 0.015f
        private var sampleRate: Int = 16000
        private var frameLength: Float = 0.1f
        private var enableAutoCalibration: Boolean = false
        private var calibrationMultiplier: Float = 2.0f

        fun energyThreshold(threshold: Float) = apply { this.energyThreshold = threshold }
        fun sampleRate(rate: Int) = apply { this.sampleRate = rate }
        fun frameLength(length: Float) = apply { this.frameLength = length }
        fun enableAutoCalibration(enabled: Boolean) = apply { this.enableAutoCalibration = enabled }
        fun calibrationMultiplier(multiplier: Float) = apply { this.calibrationMultiplier = multiplier }

        fun build(): VADCapabilityConfiguration {
            return VADCapabilityConfiguration(
                energyThreshold = energyThreshold,
                sampleRate = sampleRate,
                frameLength = frameLength,
                enableAutoCalibration = enableAutoCalibration,
                calibrationMultiplier = calibrationMultiplier
            )
        }
    }
}
