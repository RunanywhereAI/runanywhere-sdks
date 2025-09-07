package com.runanywhere.sdk.voice.vad

import com.runanywhere.sdk.components.vad.VADService
import com.runanywhere.sdk.components.vad.VADConfiguration
import com.runanywhere.sdk.components.vad.VADResult
import com.runanywhere.sdk.components.vad.SpeechActivityEvent
import com.runanywhere.sdk.foundation.SDKLogger
import kotlin.math.sqrt

/**
 * Simple energy-based Voice Activity Detection
 * Simplified implementation exactly matching iOS SimpleEnergyVAD behavior
 * Based on iOS VADComponent with SimpleEnergyVAD service
 */
class SimpleEnergyVAD(
    private var vadConfig: VADConfiguration = VADConfiguration()
) : VADService {

    override val configuration: VADConfiguration
        get() = vadConfig

    private val logger = SDKLogger("SimpleEnergyVAD")

    // State tracking (matching iOS exactly)
    private var isActive = false
    private var isCurrentlySpeaking = false
    private var consecutiveSilentFrames = 0
    private var consecutiveVoiceFrames = 0

    // Hysteresis parameters (exactly matching iOS values)
    private val voiceStartThreshold = 2   // frames of voice to start (iOS value)
    private val voiceEndThreshold = 10    // frames of silence to end (iOS value)

    // Speech activity callback (matching iOS onSpeechActivity pattern)
    override var onSpeechActivity: ((SpeechActivityEvent) -> Unit)? = null

    init {
        logger.info("SimpleEnergyVAD initialized - frameLength: ${vadConfig.frameLength}, threshold: ${vadConfig.energyThreshold}")
    }

    // MARK: - VADService Protocol Implementation

    override suspend fun initialize(configuration: VADConfiguration) {
        this.vadConfig = configuration
        start()
        logger.info("SimpleEnergyVAD configuration updated - threshold: ${configuration.energyThreshold}")
    }

    override fun processAudioChunk(audioSamples: FloatArray): VADResult {
        if (!isActive) {
            return VADResult(isSpeech = false, confidence = 0.0f)
        }

        // Calculate RMS energy using iOS-style calculation
        val energy = calculateAverageEnergy(audioSamples)

        // Determine if this frame contains voice (exactly matching iOS logic)
        val hasVoice = energy > vadConfig.energyThreshold

        // Update state with hysteresis (exactly matching iOS updateSpeechState)
        updateSpeechState(hasVoice, energy)

        return VADResult(
            isSpeech = isCurrentlySpeaking, // Use state, not just current frame
            confidence = if (hasVoice) energy.coerceIn(0.5f, 1.0f) else energy.coerceIn(0.0f, 0.5f)
        )
    }

    override fun reset() {
        stop()
        isCurrentlySpeaking = false
        consecutiveSilentFrames = 0
        consecutiveVoiceFrames = 0
    }

    override val isReady: Boolean
        get() = isActive

    override suspend fun cleanup() {
        stop()
    }

    // MARK: - Public Methods

    /**
     * Start voice activity detection
     */
    fun start() {
        if (isActive) return

        isActive = true
        isCurrentlySpeaking = false
        consecutiveSilentFrames = 0
        consecutiveVoiceFrames = 0

        logger.info("SimpleEnergyVAD started")
    }

    /**
     * Stop voice activity detection
     */
    fun stop() {
        if (!isActive) return

        isActive = false

        // Notify if speech was active (matching iOS pattern)
        if (isCurrentlySpeaking) {
            onSpeechActivity?.invoke(SpeechActivityEvent.ENDED)
            isCurrentlySpeaking = false
        }

        logger.info("SimpleEnergyVAD stopped")
    }

    /**
     * Set the energy threshold for voice detection (matching iOS)
     */
    fun setEnergyThreshold(threshold: Float) {
        vadConfig = VADConfiguration(
            energyThreshold = threshold.coerceIn(0.0f, 1.0f),
            frameLength = vadConfig.frameLength
        )
        logger.debug("Energy threshold set to: ${vadConfig.energyThreshold}")
    }

    // MARK: - Private Methods

    /**
     * Calculate RMS energy of audio buffer - matching iOS calculateAverageEnergy
     * iOS uses vDSP_rmsqv but we implement equivalent manual calculation
     */
    private fun calculateAverageEnergy(signal: FloatArray): Float {
        if (signal.isEmpty()) return 0.0f

        // RMS energy calculation (exactly matching iOS formula)
        var rmsEnergy = 0.0f
        var sum = 0.0f

        for (sample in signal) {
            sum += sample * sample
        }

        rmsEnergy = sqrt(sum / signal.size)
        return rmsEnergy
    }

    /**
     * Update speech state with hysteresis
     */
    private fun updateSpeechState(hasVoice: Boolean, energy: Float) {
        if (hasVoice) {
            consecutiveVoiceFrames++
            consecutiveSilentFrames = 0

            // Start speech if threshold met
            if (!isCurrentlySpeaking && consecutiveVoiceFrames >= voiceStartThreshold) {
                isCurrentlySpeaking = true
                onSpeechActivity?.invoke(SpeechActivityEvent.STARTED)
                logger.debug("Speech started (energy: $energy)")
            }
        } else {
            consecutiveSilentFrames++
            consecutiveVoiceFrames = 0

            // End speech if threshold met
            if (isCurrentlySpeaking && consecutiveSilentFrames >= voiceEndThreshold) {
                isCurrentlySpeaking = false
                onSpeechActivity?.invoke(SpeechActivityEvent.ENDED)
                logger.debug("Speech ended (energy: $energy)")
            }
        }
    }

}
