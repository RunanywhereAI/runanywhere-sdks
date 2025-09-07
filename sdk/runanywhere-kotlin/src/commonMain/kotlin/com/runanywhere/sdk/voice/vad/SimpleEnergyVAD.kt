package com.runanywhere.sdk.voice.vad

import com.runanywhere.sdk.components.vad.VADService
import com.runanywhere.sdk.components.vad.VADConfiguration
import com.runanywhere.sdk.components.vad.VADResult
import com.runanywhere.sdk.foundation.SDKLogger
import kotlin.math.sqrt

/**
 * Simple energy-based Voice Activity Detection
 * Based on WhisperKit's EnergyVAD implementation but simplified for real-time audio processing
 */
class SimpleEnergyVAD(
    private val sampleRate: Int = 16000,
    frameLength: Float = 0.1f,
    private var energyThreshold: Float = 0.022f
) : VADService {

    private val logger = SDKLogger("SimpleEnergyVAD")

    // Frame configuration
    val frameLengthSamples: Int = (frameLength * sampleRate).toInt()

    // State tracking
    private var isActive = false
    private var isCurrentlySpeaking = false
    private var consecutiveSilentFrames = 0
    private var consecutiveVoiceFrames = 0

    // Hysteresis parameters to prevent rapid on/off switching
    private val voiceStartThreshold = 2  // frames of voice to start
    private val voiceEndThreshold = 10   // frames of silence to end

    // Callbacks
    var onSpeechActivity: ((SpeechActivityEvent) -> Unit)? = null
    var onAudioBuffer: ((ByteArray) -> Unit)? = null

    init {
        logger.info("SimpleEnergyVAD initialized - sampleRate: $sampleRate, frameLength: $frameLengthSamples samples, threshold: $energyThreshold")
    }

    // MARK: - VADService Protocol Implementation

    override suspend fun initialize(configuration: VADConfiguration) {
        // Update configuration if provided
        configuration.frameDuration?.let {
            // Update frame length if needed
        }
        start()
    }

    override fun processAudioChunk(audioSamples: FloatArray): VADResult {
        if (!isActive) {
            return VADResult(isSpeech = false, confidence = 0.0f)
        }

        // Calculate RMS energy
        val energy = calculateRMSEnergy(audioSamples)

        // Determine if this frame contains voice
        val hasVoice = energy > energyThreshold

        // Update state with hysteresis
        updateSpeechState(hasVoice, energy)

        return VADResult(
            isSpeech = hasVoice,
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

    override val configuration: VADConfiguration?
        get() = VADConfiguration(
            frameDuration = frameLengthSamples * 1000 / sampleRate,
            sampleRate = sampleRate,
            aggressiveness = 2
        )

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

        // Notify if speech was active
        if (isCurrentlySpeaking) {
            onSpeechActivity?.invoke(SpeechActivityEvent.SpeechEnd)
            isCurrentlySpeaking = false
        }

        logger.info("SimpleEnergyVAD stopped")
    }

    /**
     * Process audio buffer for voice activity
     */
    suspend fun processAudioBuffer(buffer: FloatArray): Boolean {
        if (!isActive) return false

        // Calculate RMS energy
        val energy = calculateRMSEnergy(buffer)

        // Determine if this frame contains voice
        val hasVoice = energy > energyThreshold

        // Update state with hysteresis
        updateSpeechState(hasVoice, energy)

        // Convert to byte array if callback is registered
        onAudioBuffer?.let { callback ->
            val byteBuffer = floatArrayToByteArray(buffer)
            callback(byteBuffer)
        }

        return hasVoice
    }

    /**
     * Process audio buffer (byte array version)
     */
    suspend fun processAudioBuffer(buffer: ByteArray): Boolean {
        val floatBuffer = byteArrayToFloatArray(buffer)
        return processAudioBuffer(floatBuffer)
    }

    /**
     * Set the energy threshold for voice detection
     */
    fun setEnergyThreshold(threshold: Float) {
        energyThreshold = threshold.coerceIn(0.0f, 1.0f)
        logger.debug("Energy threshold set to: $energyThreshold")
    }

    // MARK: - Private Methods

    /**
     * Calculate RMS energy of audio buffer
     */
    private fun calculateRMSEnergy(buffer: FloatArray): Float {
        if (buffer.isEmpty()) return 0.0f

        var sum = 0.0f
        for (sample in buffer) {
            sum += sample * sample
        }

        return sqrt(sum / buffer.size)
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
                onSpeechActivity?.invoke(SpeechActivityEvent.SpeechStart)
                logger.debug("Speech started (energy: $energy)")
            }
        } else {
            consecutiveSilentFrames++
            consecutiveVoiceFrames = 0

            // End speech if threshold met
            if (isCurrentlySpeaking && consecutiveSilentFrames >= voiceEndThreshold) {
                isCurrentlySpeaking = false
                onSpeechActivity?.invoke(SpeechActivityEvent.SpeechEnd)
                logger.debug("Speech ended (energy: $energy)")
            }
        }
    }

    /**
     * Convert float array to byte array
     */
    private fun floatArrayToByteArray(floats: FloatArray): ByteArray {
        val bytes = ByteArray(floats.size * 2) // 16-bit PCM

        for (i in floats.indices) {
            val sample = (floats[i] * 32767).toInt().coerceIn(-32768, 32767)
            bytes[i * 2] = (sample and 0xFF).toByte()
            bytes[i * 2 + 1] = (sample shr 8 and 0xFF).toByte()
        }

        return bytes
    }

    /**
     * Convert byte array to float array
     */
    private fun byteArrayToFloatArray(bytes: ByteArray): FloatArray {
        val floats = FloatArray(bytes.size / 2)

        for (i in floats.indices) {
            val sample = (bytes[i * 2 + 1].toInt() shl 8) or (bytes[i * 2].toInt() and 0xFF)
            floats[i] = sample / 32768.0f
        }

        return floats
    }
}

/**
 * Speech activity events
 */
sealed class SpeechActivityEvent {
    object SpeechStart : SpeechActivityEvent()
    object SpeechEnd : SpeechActivityEvent()
    data class EnergyUpdate(val energy: Float) : SpeechActivityEvent()
}
