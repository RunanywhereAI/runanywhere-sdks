package com.runanywhere.sdk.components.vad

import com.runanywhere.sdk.foundation.SDKLogger
import kotlin.math.abs
import kotlin.math.sqrt

/**
 * Platform-specific VAD service creation for JVM
 */
actual fun createPlatformVADService(): VADService = JvmVADService()

/**
 * JVM Voice Activity Detection Service
 * Simple energy-based VAD implementation for JVM platforms
 */
class JvmVADService : VADService {

    private val logger = SDKLogger("JvmVADService")
    private var _isInitialized = false
    private var _configuration: VADConfiguration? = null

    // VAD parameters
    private var energyThreshold = 0.01f
    private var minSpeechFrames = 3
    private var maxSilenceFrames = 10

    // State tracking
    private var consecutiveSpeechFrames = 0
    private var consecutiveSilenceFrames = 0
    private var currentlyInSpeech = false

    override val isReady: Boolean
        get() = _isInitialized

    override val configuration: VADConfiguration?
        get() = _configuration

    override suspend fun initialize(configuration: VADConfiguration) {
        try {
            // Store configuration
            _configuration = configuration
            energyThreshold = configuration.energyThreshold

            _isInitialized = true
            logger.info("JVM VAD service initialized with energy-based detection")
        } catch (e: Exception) {
            logger.error("Failed to initialize JVM VAD service", e)
            throw VADError.ConfigurationError
        }
    }

    override fun processAudioChunk(audioSamples: FloatArray): VADResult {
        if (!_isInitialized) {
            return VADResult(isSpeech = false, confidence = 0.0f)
        }

        val energy = calculateEnergy(audioSamples)
        val isSpeechFrame = energy > energyThreshold

        // Apply smoothing logic
        when {
            isSpeechFrame -> {
                consecutiveSpeechFrames++
                consecutiveSilenceFrames = 0

                if (!currentlyInSpeech && consecutiveSpeechFrames >= minSpeechFrames) {
                    currentlyInSpeech = true
                    logger.debug("Speech detected (energy: $energy)")
                }
            }
            else -> {
                consecutiveSilenceFrames++
                consecutiveSpeechFrames = 0

                if (currentlyInSpeech && consecutiveSilenceFrames >= maxSilenceFrames) {
                    currentlyInSpeech = false
                    logger.debug("Speech ended (energy: $energy)")
                }
            }
        }

        // Calculate confidence based on energy level
        val confidence = when {
            energy > energyThreshold * 3 -> 0.9f
            energy > energyThreshold * 2 -> 0.7f
            energy > energyThreshold -> 0.5f
            else -> 0.1f
        }

        return VADResult(
            isSpeech = currentlyInSpeech,
            confidence = confidence
        )
    }

    override fun reset() {
        consecutiveSpeechFrames = 0
        consecutiveSilenceFrames = 0
        currentlyInSpeech = false
        logger.debug("JVM VAD service reset")
    }

    override suspend fun cleanup() {
        _isInitialized = false
        _configuration = null
        consecutiveSpeechFrames = 0
        consecutiveSilenceFrames = 0
        currentlyInSpeech = false
        logger.info("JVM VAD service cleaned up")
    }

    private fun calculateEnergy(audioData: FloatArray): Float {
        if (audioData.isEmpty()) return 0.0f

        // Calculate RMS energy
        var sum = 0.0
        for (sample in audioData) {
            sum += sample * sample
        }

        return sqrt(sum / audioData.size).toFloat()
    }

    /**
     * Update VAD parameters
     */
    fun updateParameters(
        energyThreshold: Float? = null,
        minSpeechFrames: Int? = null,
        maxSilenceFrames: Int? = null
    ) {
        energyThreshold?.let { this.energyThreshold = it }
        minSpeechFrames?.let { this.minSpeechFrames = it }
        maxSilenceFrames?.let { this.maxSilenceFrames = it }

        logger.info("VAD parameters updated - threshold: ${this.energyThreshold}, speech frames: ${this.minSpeechFrames}, silence frames: ${this.maxSilenceFrames}")
    }
}
