package com.runanywhere.sdk.features.vad

import com.runanywhere.sdk.foundation.SDKLogger
import kotlin.math.sqrt

/**
 * Simple Energy-based Voice Activity Detection implementation for Android
 * Based on iOS SimpleEnergyVADService - uses RMS energy threshold for detection
 */
class SimpleEnergyVADService : VADService {
    private val logger = SDKLogger("SimpleEnergyVADService")
    private var config: VADConfiguration? = null
    private var isInitialized = false
    private var isActive = false
    private var currentSpeechState = false

    // Energy threshold for voice detection
    override var energyThreshold: Float = 0.015f
    private var baseEnergyThreshold: Float = 0.015f
    private var ttsThresholdMultiplier: Float = 3.0f

    // TTS state
    override var isTTSActive: Boolean = false
        private set

    // State tracking for hysteresis
    private var consecutiveSilentFrames = 0
    private var consecutiveVoiceFrames = 0
    private val voiceStartThreshold = 1
    private val voiceEndThreshold = 12

    // Calibration
    private var isCalibrating = false
    private val calibrationSamples = mutableListOf<Float>()
    private var calibrationFrameCount = 0
    private val calibrationFramesNeeded = 20
    private var ambientNoiseLevel: Float = 0.0f
    private var calibrationMultiplier: Float = 2.0f

    // Debug statistics
    private val recentEnergyValues = mutableListOf<Float>()
    private val maxRecentValues = 50

    override val sampleRate: Int
        get() = config?.sampleRate ?: 16000

    override val frameLength: Float
        get() = config?.frameLength ?: 0.1f

    override val isSpeechActive: Boolean
        get() = currentSpeechState

    override var onSpeechActivity: ((SpeechActivityEvent) -> Unit)? = null
    override var onAudioBuffer: ((ByteArray) -> Unit)? = null

    override suspend fun initialize(configuration: VADConfiguration) {
        logger.info("Initializing SimpleEnergyVADService")
        config = configuration
        energyThreshold = configuration.energyThreshold
        baseEnergyThreshold = configuration.energyThreshold
        isInitialized = true
        logger.info("SimpleEnergyVADService initialized - sampleRate: ${configuration.sampleRate}, frameLength: ${configuration.frameLength}, threshold: $energyThreshold")
    }

    override fun start() {
        if (!isActive) {
            isActive = true
            currentSpeechState = false
            consecutiveSilentFrames = 0
            consecutiveVoiceFrames = 0
            logger.info("SimpleEnergyVADService started")
        }
    }

    override fun stop() {
        if (isActive) {
            if (currentSpeechState) {
                currentSpeechState = false
                onSpeechActivity?.invoke(SpeechActivityEvent.ENDED)
            }
            isActive = false
            consecutiveSilentFrames = 0
            consecutiveVoiceFrames = 0
            logger.info("SimpleEnergyVADService stopped")
        }
    }

    override fun processAudioData(audioData: FloatArray): Boolean =
        processAudioChunk(audioData).isSpeechDetected

    override fun processAudioChunk(audioSamples: FloatArray): VADResult {
        if (!isInitialized || !isActive) {
            return VADResult(isSpeechDetected = false, confidence = 0.0f)
        }

        // Block during TTS
        if (isTTSActive) {
            logger.debug("VAD blocked during TTS playback")
            return VADResult(isSpeechDetected = false, confidence = 0.0f)
        }

        // Calculate RMS energy
        val energy = calculateRMSEnergy(audioSamples)

        // Update debug statistics
        updateDebugStatistics(energy)

        // Handle calibration
        if (isCalibrating) {
            handleCalibrationFrame(energy)
            return VADResult(isSpeechDetected = false, confidence = 0.0f)
        }

        val hasVoice = energy > energyThreshold

        // Update state with hysteresis
        updateVoiceActivityState(hasVoice)

        // Call audio buffer callback
        onAudioBuffer?.invoke(floatArrayToByteArray(audioSamples))

        val confidence = if (hasVoice) {
            (energy / energyThreshold).coerceIn(0.5f, 1.0f)
        } else {
            (energy / energyThreshold).coerceIn(0.0f, 0.5f)
        }

        return VADResult(
            isSpeechDetected = currentSpeechState,
            confidence = confidence,
            timestamp = System.currentTimeMillis(),
        )
    }

    override fun reset() {
        currentSpeechState = false
        consecutiveSilentFrames = 0
        consecutiveVoiceFrames = 0
        recentEnergyValues.clear()
        logger.debug("VAD state reset")
    }

    override val isReady: Boolean
        get() = isInitialized

    override val configuration: VADConfiguration?
        get() = config

    override suspend fun cleanup() {
        logger.info("Cleaning up SimpleEnergyVADService")
        stop()
        isInitialized = false
        config = null
    }

    // MARK: - TTS Feedback Prevention

    override fun notifyTTSWillStart() {
        isTTSActive = true
        baseEnergyThreshold = energyThreshold
        energyThreshold = (energyThreshold * ttsThresholdMultiplier).coerceAtMost(0.1f)
        logger.info("TTS starting - VAD blocked, threshold increased")

        if (currentSpeechState) {
            currentSpeechState = false
            onSpeechActivity?.invoke(SpeechActivityEvent.ENDED)
        }
        consecutiveSilentFrames = 0
        consecutiveVoiceFrames = 0
    }

    override fun notifyTTSDidFinish() {
        isTTSActive = false
        energyThreshold = baseEnergyThreshold
        logger.info("TTS finished - VAD threshold restored")

        recentEnergyValues.clear()
        consecutiveSilentFrames = 0
        consecutiveVoiceFrames = 0
        currentSpeechState = false
    }

    override fun setTTSThresholdMultiplier(multiplier: Float) {
        ttsThresholdMultiplier = multiplier.coerceIn(2.0f, 5.0f)
        logger.info("TTS threshold multiplier set to ${ttsThresholdMultiplier}x")
    }

    // MARK: - Calibration

    override suspend fun startCalibration(): Boolean {
        if (isCalibrating) return false

        logger.info("Starting VAD calibration")
        isCalibrating = true
        calibrationSamples.clear()
        calibrationFrameCount = 0
        return true
    }

    private fun handleCalibrationFrame(energy: Float) {
        calibrationSamples.add(energy)
        calibrationFrameCount++

        if (calibrationFrameCount >= calibrationFramesNeeded) {
            completeCalibration()
        }
    }

    private fun completeCalibration() {
        if (!isCalibrating || calibrationSamples.isEmpty()) return

        val sortedSamples = calibrationSamples.sorted()
        val percentile90Index = (sortedSamples.size * 0.90).toInt().coerceAtMost(sortedSamples.size - 1)
        ambientNoiseLevel = sortedSamples[percentile90Index]

        val oldThreshold = energyThreshold
        val minimumThreshold = maxOf(ambientNoiseLevel * 2.0f, 0.003f)
        val calculatedThreshold = ambientNoiseLevel * calibrationMultiplier

        energyThreshold = maxOf(calculatedThreshold, minimumThreshold).coerceAtMost(0.020f)
        baseEnergyThreshold = energyThreshold

        logger.info("VAD Calibration Complete: ambient=$ambientNoiseLevel, threshold: $oldThreshold -> $energyThreshold")

        isCalibrating = false
        calibrationSamples.clear()
    }

    // MARK: - Statistics

    override fun getStatistics(): VADStatistics {
        val recent = if (recentEnergyValues.isEmpty()) 0.0f
        else recentEnergyValues.sum() / recentEnergyValues.size

        return VADStatistics(
            current = recentEnergyValues.lastOrNull() ?: 0.0f,
            threshold = energyThreshold,
            ambient = ambientNoiseLevel,
            recentAvg = recent,
            recentMax = recentEnergyValues.maxOrNull() ?: 0.0f,
        )
    }

    // MARK: - Private Helpers

    private fun calculateRMSEnergy(samples: FloatArray): Float {
        if (samples.isEmpty()) return 0.0f
        var sum = 0.0
        for (sample in samples) {
            sum += sample * sample
        }
        return sqrt(sum / samples.size).toFloat()
    }

    private fun updateVoiceActivityState(hasVoice: Boolean) {
        if (hasVoice) {
            consecutiveVoiceFrames++
            consecutiveSilentFrames = 0

            if (!currentSpeechState && consecutiveVoiceFrames >= voiceStartThreshold) {
                currentSpeechState = true
                logger.info("VAD: SPEECH STARTED")
                onSpeechActivity?.invoke(SpeechActivityEvent.STARTED)
            }
        } else {
            consecutiveSilentFrames++
            consecutiveVoiceFrames = 0

            if (currentSpeechState && consecutiveSilentFrames >= voiceEndThreshold) {
                currentSpeechState = false
                logger.info("VAD: SPEECH ENDED")
                onSpeechActivity?.invoke(SpeechActivityEvent.ENDED)
            }
        }
    }

    private fun updateDebugStatistics(energy: Float) {
        recentEnergyValues.add(energy)
        if (recentEnergyValues.size > maxRecentValues) {
            recentEnergyValues.removeAt(0)
        }
    }

    private fun floatArrayToByteArray(floatArray: FloatArray): ByteArray {
        val byteArray = ByteArray(floatArray.size * 4)
        for (i in floatArray.indices) {
            val intBits = java.lang.Float.floatToIntBits(floatArray[i])
            byteArray[i * 4] = (intBits and 0xFF).toByte()
            byteArray[i * 4 + 1] = ((intBits shr 8) and 0xFF).toByte()
            byteArray[i * 4 + 2] = ((intBits shr 16) and 0xFF).toByte()
            byteArray[i * 4 + 3] = ((intBits shr 24) and 0xFF).toByte()
        }
        return byteArray
    }
}
