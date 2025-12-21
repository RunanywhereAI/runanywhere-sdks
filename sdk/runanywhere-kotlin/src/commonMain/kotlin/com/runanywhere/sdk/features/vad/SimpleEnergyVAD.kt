package com.runanywhere.sdk.features.vad

import com.runanywhere.sdk.foundation.SDKLogger
import kotlin.math.sqrt

/**
 * Simple energy-based Voice Activity Detection
 * Simplified implementation exactly matching iOS SimpleEnergyVAD behavior
 * Based on iOS VADComponent with SimpleEnergyVAD service
 */
class SimpleEnergyVAD(
    private var vadConfig: VADConfiguration = VADConfiguration(),
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

    // Hysteresis parameters (aligned with iOS values)
    private val voiceStartThreshold = 1 // frames of voice to start (aligned with iOS)
    private val voiceEndThreshold = 12 // frames of silence to end (aligned with iOS)

    // TTS feedback prevention (matching iOS SimpleEnergyVADService)
    override var isTTSActive: Boolean = false
        private set
    private var baseEnergyThreshold: Float = 0.0f
    private var ttsThresholdMultiplier: Float = 3.0f

    // Debug statistics tracking (matching iOS)
    private val recentEnergyValues = mutableListOf<Float>()
    private val maxRecentValues = 20
    private var ambientNoiseLevel: Float = 0.0f

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
    override fun processAudioData(audioData: FloatArray): Boolean = processAudioChunk(audioData).isSpeechDetected

    override fun processAudioChunk(audioSamples: FloatArray): VADResult {
        if (!isActive) {
            return VADResult(isSpeechDetected = false, confidence = 0.0f)
        }

        // Block all processing during TTS (matching iOS lines 162-164, 221-224)
        if (isTTSActive) {
            logger.debug("VAD blocked during TTS playback")
            return VADResult(isSpeechDetected = false, confidence = 0.0f)
        }

        // Calculate RMS energy using iOS-style calculation
        val energy = calculateAverageEnergy(audioSamples)

        // Handle calibration frame if calibrating (matching iOS)
        if (isCalibrating) {
            handleCalibrationFrame(energy)
            // During calibration, don't trigger speech detection
            return VADResult(isSpeechDetected = false, confidence = 0.0f)
        }

        // Determine if this frame contains voice (exactly matching iOS logic)
        val hasVoice = energy > vadConfig.energyThreshold

        // Update state with hysteresis (exactly matching iOS updateSpeechState)
        updateSpeechState(hasVoice, energy)

        return VADResult(
            isSpeechDetected = isCurrentlySpeaking, // Use state, not just current frame
            confidence = if (hasVoice) energy.coerceIn(0.5f, 1.0f) else energy.coerceIn(0.0f, 0.5f),
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
    private fun updateSpeechState(
        hasVoice: Boolean,
        energy: Float,
    ) {
        // Update debug statistics
        updateDebugStatistics(energy)

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

    // =========================================================================
    // MARK: - TTS Feedback Prevention (matching iOS SimpleEnergyVADService)
    // =========================================================================

    /**
     * Notify VAD that TTS is about to start playing
     * Matching iOS SimpleEnergyVADService.notifyTTSWillStart() exactly
     */
    override fun notifyTTSWillStart() {
        isTTSActive = true

        // Save base threshold for restoration
        baseEnergyThreshold = energyThreshold

        // Increase threshold significantly to prevent TTS audio from triggering VAD
        val newThreshold = energyThreshold * ttsThresholdMultiplier
        energyThreshold = minOf(newThreshold, 0.1f)

        logger.info(
            "TTS starting - VAD completely blocked and threshold increased " +
                "from ${String.format("%.6f", baseEnergyThreshold)} " +
                "to ${String.format("%.6f", energyThreshold)}",
        )

        // End any current speech detection
        if (isCurrentlySpeaking) {
            isCurrentlySpeaking = false
            onSpeechActivity?.invoke(SpeechActivityEvent.ENDED)
        }

        // Reset counters
        consecutiveSilentFrames = 0
        consecutiveVoiceFrames = 0
    }

    /**
     * Notify VAD that TTS has finished playing
     * Matching iOS SimpleEnergyVADService.notifyTTSDidFinish() exactly
     */
    override fun notifyTTSDidFinish() {
        isTTSActive = false

        // Immediately restore threshold for instant response
        energyThreshold = baseEnergyThreshold

        logger.info("TTS finished - VAD threshold restored to ${String.format("%.6f", energyThreshold)}")

        // Reset state for immediate readiness
        recentEnergyValues.clear()
        consecutiveSilentFrames = 0
        consecutiveVoiceFrames = 0
        isCurrentlySpeaking = false
    }

    /**
     * Set TTS threshold multiplier for feedback prevention
     * Matching iOS SimpleEnergyVADService.setTTSThresholdMultiplier()
     */
    override fun setTTSThresholdMultiplier(multiplier: Float) {
        ttsThresholdMultiplier = multiplier.coerceIn(2.0f, 5.0f)
        logger.info("TTS threshold multiplier set to ${ttsThresholdMultiplier}x")
    }

    // =========================================================================
    // MARK: - Calibration (matching iOS SimpleEnergyVADService)
    // =========================================================================

    // Calibration state
    private var isCalibrating = false
    private val calibrationSamples = mutableListOf<Float>()
    private var calibrationFrameCount = 0
    private val calibrationFramesNeeded = 20 // ~2 seconds at 100ms frames
    private var calibrationMultiplier: Float = vadConfig.calibrationMultiplier

    /**
     * Start automatic calibration to determine ambient noise level.
     * Matching iOS SimpleEnergyVADService.startCalibration() exactly.
     *
     * Measures ambient noise for a few seconds and sets threshold dynamically.
     */
    override suspend fun startCalibration(): Boolean {
        if (isCalibrating) {
            logger.warning("Calibration already in progress")
            return false
        }

        val durationSeconds = calibrationFramesNeeded * frameLength
        logger.info("Starting VAD calibration - measuring ambient noise for $durationSeconds seconds...")

        isCalibrating = true
        calibrationSamples.clear()
        calibrationFrameCount = 0

        // Wait for calibration to complete (sampling happens in processAudioChunk)
        val timeoutMs = ((calibrationFramesNeeded * frameLength + 2.0f) * 1000).toLong()
        kotlinx.coroutines.delay(timeoutMs)

        // Complete calibration if still in progress
        if (isCalibrating) {
            completeCalibration()
        }

        return true
    }

    /**
     * Handle a frame during calibration (called from processAudioChunk)
     */
    private fun handleCalibrationFrame(energy: Float) {
        if (!isCalibrating) return

        calibrationSamples.add(energy)
        calibrationFrameCount++

        logger.debug("Calibration frame $calibrationFrameCount/$calibrationFramesNeeded: energy=${String.format("%.6f", energy)}")

        if (calibrationFrameCount >= calibrationFramesNeeded) {
            completeCalibration()
        }
    }

    /**
     * Complete the calibration process
     * Matching iOS SimpleEnergyVADService.completeCalibration() exactly
     */
    private fun completeCalibration() {
        if (!isCalibrating || calibrationSamples.isEmpty()) return

        // Calculate statistics from calibration samples (matching iOS)
        val sortedSamples = calibrationSamples.sorted()
        val mean = calibrationSamples.average().toFloat()
        val median = sortedSamples[sortedSamples.size / 2]
        val percentile75 = sortedSamples[minOf(sortedSamples.size - 1, (sortedSamples.size * 0.75).toInt())]
        val percentile90 = sortedSamples[minOf(sortedSamples.size - 1, (sortedSamples.size * 0.90).toInt())]
        val maxSample = sortedSamples.last()

        // Use 90th percentile as ambient noise level (robust to occasional spikes)
        ambientNoiseLevel = percentile90

        // Calculate dynamic threshold with better minimum
        val oldThreshold = energyThreshold
        val minimumThreshold = maxOf(ambientNoiseLevel * 2.0f, 0.003f)
        val calculatedThreshold = ambientNoiseLevel * calibrationMultiplier

        // Apply threshold with sensible bounds
        var newThreshold = maxOf(calculatedThreshold, minimumThreshold)

        // Cap at reasonable maximum
        if (newThreshold > 0.020f) {
            newThreshold = 0.020f
            logger.warning("Calibration detected high ambient noise. Capping threshold at 0.020")
        }

        energyThreshold = newThreshold
        baseEnergyThreshold = newThreshold

        logger.info("VAD Calibration Complete:")
        logger.info("  Statistics: Mean=${String.format("%.6f", mean)}, Median=${String.format("%.6f", median)}")
        logger.info("  Percentile75=${String.format("%.6f", percentile75)}, Percentile90=${String.format("%.6f", percentile90)}")
        logger.info("  Max=${String.format("%.6f", maxSample)}")
        logger.info("  Ambient noise level: ${String.format("%.6f", ambientNoiseLevel)}")
        logger.info("  Threshold: ${String.format("%.6f", oldThreshold)} -> ${String.format("%.6f", newThreshold)}")

        isCalibrating = false
        calibrationSamples.clear()
    }

    // =========================================================================
    // MARK: - Debug Statistics (matching iOS getStatistics)
    // =========================================================================

    /**
     * Get current VAD statistics for debugging
     * Matching iOS SimpleEnergyVADService.getStatistics()
     */
    override fun getStatistics(): VADStatistics {
        val recent =
            if (recentEnergyValues.isEmpty()) {
                0.0f
            } else {
                recentEnergyValues.sum() / recentEnergyValues.size
            }

        val maxValue =
            if (recentEnergyValues.isEmpty()) {
                0.0f
            } else {
                recentEnergyValues.maxOrNull() ?: 0.0f
            }

        return VADStatistics(
            current = recentEnergyValues.lastOrNull() ?: 0.0f,
            threshold = energyThreshold,
            ambient = ambientNoiseLevel,
            recentAvg = recent,
            recentMax = maxValue,
        )
    }

    /**
     * Update debug statistics with new energy value
     */
    private fun updateDebugStatistics(energy: Float) {
        recentEnergyValues.add(energy)
        if (recentEnergyValues.size > maxRecentValues) {
            recentEnergyValues.removeAt(0)
        }
    }
}
