package com.runanywhere.sdk.voice.vad

import com.runanywhere.sdk.features.vad.VADService
import com.runanywhere.sdk.features.vad.VADConfiguration
import com.runanywhere.sdk.features.vad.VADResult
import com.runanywhere.sdk.features.vad.SpeechActivityEvent
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

    // Properties matching iOS VADService protocol
    override var energyThreshold: Float
        get() = vadConfig.energyThreshold
        set(value) {
            vadConfig = vadConfig.copy(energyThreshold = value.coerceIn(0.0f, 1.0f))
            logger.debug("Energy threshold updated to: $energyThreshold")
        }

    override val sampleRate: Int
        get() = vadConfig.sampleRate

    override val frameLength: Float
        get() = vadConfig.frameLength

    override val isSpeechActive: Boolean
        get() = isCurrentlySpeaking

    // State tracking (matching iOS exactly)
    private var isActive = false
    private var isCurrentlySpeaking = false
    private var consecutiveSilentFrames = 0
    private var consecutiveVoiceFrames = 0

    // Hysteresis parameters (exactly matching iOS values)
    private val voiceStartThreshold = 2   // frames of voice to start (iOS value)
    private val voiceEndThreshold = 10    // frames of silence to end (iOS value)

    // Callbacks matching iOS VADService protocol
    override var onSpeechActivity: ((SpeechActivityEvent) -> Unit)? = null
    override var onAudioBuffer: ((ByteArray) -> Unit)? = null

    init {
        logger.info("SimpleEnergyVAD initialized - frameLength: ${vadConfig.frameLength}, threshold: ${vadConfig.energyThreshold}")
    }

    // MARK: - VADService Protocol Implementation

    override suspend fun initialize(configuration: VADConfiguration) {
        this.vadConfig = configuration
        start()
        logger.info("SimpleEnergyVAD configuration updated - threshold: ${configuration.energyThreshold}")
    }

    // Additional method matching iOS VADService
    override fun processAudioData(audioData: FloatArray): Boolean {
        return processAudioChunk(audioData).isSpeechDetected
    }

    override fun processAudioChunk(audioSamples: FloatArray): VADResult {
        if (!isActive) {
            return VADResult(isSpeechDetected = false, confidence = 0.0f)
        }

        // Calculate RMS energy using iOS-style calculation
        val energy = calculateAverageEnergy(audioSamples)

        // Determine if this frame contains voice (exactly matching iOS logic)
        val hasVoice = energy > vadConfig.energyThreshold

        // Update state with hysteresis (exactly matching iOS updateSpeechState)
        updateSpeechState(hasVoice, energy)

        return VADResult(
            isSpeechDetected = isCurrentlySpeaking, // Use state, not just current frame
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
     * Start voice activity detection (matching iOS VADService protocol)
     */
    override fun start() {
        if (isActive) return

        isActive = true
        isCurrentlySpeaking = false
        consecutiveSilentFrames = 0
        consecutiveVoiceFrames = 0

        logger.info("SimpleEnergyVAD started")
    }

    /**
     * Stop voice activity detection (matching iOS VADService protocol)
     */
    override fun stop() {
        if (!isActive) return

        isActive = false

        // Notify if speech was active (matching iOS pattern)
        if (isCurrentlySpeaking) {
            onSpeechActivity?.invoke(SpeechActivityEvent.ENDED)
            isCurrentlySpeaking = false
        }

        logger.info("SimpleEnergyVAD stopped")
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
