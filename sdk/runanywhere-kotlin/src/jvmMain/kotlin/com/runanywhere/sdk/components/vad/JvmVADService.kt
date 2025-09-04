package com.runanywhere.sdk.components.vad

import com.runanywhere.sdk.foundation.SDKLogger
import kotlin.math.abs
import kotlin.math.sqrt

/**
 * JVM Voice Activity Detection Service
 * Simple energy-based VAD implementation for JVM platforms
 */
class JvmVADService : VADService {

    private val logger = SDKLogger("JvmVADService")
    private var isInitialized = false

    // VAD parameters
    private val energyThreshold = 0.01f
    private val minSpeechFrames = 3
    private val maxSilenceFrames = 10

    // State tracking
    private var consecutiveSpeechFrames = 0
    private var consecutiveSilenceFrames = 0
    private var currentlyInSpeech = false

    override suspend fun initialize(): Result<Unit> {
        return try {
            isInitialized = true
            logger.info("JVM VAD service initialized with energy-based detection")
            Result.success(Unit)
        } catch (e: Exception) {
            logger.error("Failed to initialize JVM VAD service", e)
            Result.failure(e)
        }
    }

    override suspend fun processAudioChunk(audioData: FloatArray): VADResult {
        if (!isInitialized) {
            return VADResult(isSpeech = false, confidence = 0.0f)
        }

        val energy = calculateEnergy(audioData)
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
            confidence = confidence,
            speechProbability = minOf(energy / energyThreshold, 1.0f)
        )
    }

    override suspend fun cleanup() {
        isInitialized = false
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
