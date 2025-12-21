package com.runanywhere.sdk.native.bridge.providers

import com.runanywhere.sdk.core.VADServiceProvider
import com.runanywhere.sdk.features.vad.SpeechActivityEvent
import com.runanywhere.sdk.features.vad.VADConfiguration
import com.runanywhere.sdk.features.vad.VADResult
import com.runanywhere.sdk.features.vad.VADService
import com.runanywhere.sdk.features.vad.VADStatistics
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.native.bridge.NativeBridgeException
import com.runanywhere.sdk.native.bridge.NativeResultCode
import com.runanywhere.sdk.native.bridge.ONNXCoreService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext

/**
 * ONNX-based VAD Service Provider
 *
 * Provides voice activity detection capabilities using the ONNX Runtime backend
 * through the RunAnywhere Core JNI bridge.
 *
 * Supports models like:
 * - Silero VAD
 * - WebRTC VAD (ONNX version)
 * - Custom VAD models
 */
class ONNXVADProvider : VADServiceProvider {
    private val logger = SDKLogger("ONNXVADProvider")

    override val name: String = "ONNX VAD"

    override fun canHandle(modelId: String): Boolean {
        // Handle models that are known to work with ONNX VAD
        val onnxVADModels =
            listOf(
                "silero",
                "vad",
                "webrtc",
                "onnx-vad",
            )
        return onnxVADModels.any { modelId.lowercase().contains(it) }
    }

    override suspend fun createVADService(configuration: VADConfiguration): VADService {
        logger.info("Creating ONNX VAD service")
        return ONNXVADService(configuration)
    }
}

/**
 * ONNX-based VAD Service implementation
 */
class ONNXVADService(
    private val vadConfiguration: VADConfiguration,
) : VADService {
    private val logger = SDKLogger("ONNXVADService")

    private val coreService = ONNXCoreService()
    private var _isReady = false
    private var _isSpeechActive = false
    private var _energyThreshold = vadConfiguration.energyThreshold

    // Track speech state for hysteresis
    private var consecutiveSpeechFrames = 0
    private var consecutiveSilenceFrames = 0
    private val speechStartThreshold = 3 // Frames needed to confirm speech start
    private val speechEndThreshold = 10 // Frames needed to confirm speech end

    // TTS feedback prevention (matching iOS)
    override var isTTSActive: Boolean = false
        private set
    private var baseEnergyThreshold: Float = 0.0f
    private var ttsThresholdMultiplier: Float = 3.0f

    // Debug statistics tracking
    private val recentConfidenceValues = mutableListOf<Float>()
    private val maxRecentValues = 20

    override var energyThreshold: Float
        get() = _energyThreshold
        set(value) {
            _energyThreshold = value
        }

    override val sampleRate: Int
        get() = vadConfiguration.sampleRate

    override val frameLength: Float
        get() = vadConfiguration.frameLength

    override val isSpeechActive: Boolean
        get() = _isSpeechActive

    override var onSpeechActivity: ((SpeechActivityEvent) -> Unit)? = null
    override var onAudioBuffer: ((ByteArray) -> Unit)? = null

    override val isReady: Boolean
        get() = _isReady && coreService.isInitialized

    override val configuration: VADConfiguration
        get() = vadConfiguration

    override suspend fun initialize(configuration: VADConfiguration) =
        withContext(Dispatchers.IO) {
            logger.info("Initializing ONNX VAD service")

            try {
                // Initialize the core service
                if (!coreService.isInitialized) {
                    coreService.initialize()
                }

                // Load VAD model if specified, otherwise use built-in
                configuration.modelId?.let { modelPath ->
                    coreService.loadVADModel(modelPath)
                } ?: run {
                    // Load default/built-in VAD model
                    coreService.loadVADModel(null)
                }

                _isReady = true
                logger.info("✅ ONNX VAD service initialized")
            } catch (e: NativeBridgeException) {
                logger.error("Failed to initialize ONNX VAD service", e)
                throw e
            }
        }

    override fun start() {
        logger.debug("Starting VAD processing")
        consecutiveSpeechFrames = 0
        consecutiveSilenceFrames = 0
    }

    override fun stop() {
        logger.debug("Stopping VAD processing")
        if (_isSpeechActive) {
            _isSpeechActive = false
            onSpeechActivity?.invoke(SpeechActivityEvent.ENDED)
        }
    }

    override fun reset() {
        _isSpeechActive = false
        consecutiveSpeechFrames = 0
        consecutiveSilenceFrames = 0
    }

    override fun processAudioChunk(audioSamples: FloatArray): VADResult {
        if (!isReady) {
            throw NativeBridgeException(
                NativeResultCode.ERROR_INVALID_HANDLE,
                "VAD service not initialized",
            )
        }

        // Block all processing during TTS (matching iOS TTS feedback prevention)
        if (isTTSActive) {
            logger.debug("VAD blocked during TTS playback")
            return VADResult(isSpeechDetected = false, confidence = 0.0f)
        }

        // Process through native VAD
        val result =
            runBlocking {
                coreService.processVAD(audioSamples, sampleRate)
            }

        val speechDetected = result.isSpeech
        val confidence = result.probability

        // Track for statistics
        recentConfidenceValues.add(confidence)
        if (recentConfidenceValues.size > maxRecentValues) {
            recentConfidenceValues.removeAt(0)
        }

        // Apply hysteresis for stable speech detection
        updateSpeechState(speechDetected)

        return VADResult(
            isSpeechDetected = _isSpeechActive,
            confidence = confidence,
            timestamp = System.currentTimeMillis(),
        )
    }

    override fun processAudioData(audioData: FloatArray): Boolean {
        val result = processAudioChunk(audioData)
        return result.isSpeechDetected
    }

    override suspend fun cleanup() {
        logger.info("Cleaning up ONNX VAD service")
        try {
            if (coreService.isVADModelLoaded) {
                coreService.unloadVADModel()
            }
            coreService.destroy()
            _isReady = false
        } catch (e: Exception) {
            logger.error("Error during cleanup", e)
        }
    }

    // =============================================================================
    // Private Helpers
    // =============================================================================

    private fun updateSpeechState(speechDetected: Boolean) {
        if (speechDetected) {
            consecutiveSpeechFrames++
            consecutiveSilenceFrames = 0

            if (!_isSpeechActive && consecutiveSpeechFrames >= speechStartThreshold) {
                _isSpeechActive = true
                onSpeechActivity?.invoke(SpeechActivityEvent.STARTED)
            }
        } else {
            consecutiveSilenceFrames++
            consecutiveSpeechFrames = 0

            if (_isSpeechActive && consecutiveSilenceFrames >= speechEndThreshold) {
                _isSpeechActive = false
                onSpeechActivity?.invoke(SpeechActivityEvent.ENDED)
            }
        }
    }

    // =========================================================================
    // MARK: - TTS Feedback Prevention (matching iOS VADService protocol)
    // =========================================================================

    override fun notifyTTSWillStart() {
        isTTSActive = true
        baseEnergyThreshold = _energyThreshold

        // Increase threshold to prevent TTS audio from triggering VAD
        val newThreshold = _energyThreshold * ttsThresholdMultiplier
        _energyThreshold = minOf(newThreshold, 0.1f)

        logger.info("TTS starting - VAD blocked and threshold increased")

        // End any current speech detection
        if (_isSpeechActive) {
            _isSpeechActive = false
            onSpeechActivity?.invoke(SpeechActivityEvent.ENDED)
        }

        // Reset counters
        consecutiveSpeechFrames = 0
        consecutiveSilenceFrames = 0
    }

    override fun notifyTTSDidFinish() {
        isTTSActive = false
        _energyThreshold = baseEnergyThreshold

        logger.info("TTS finished - VAD threshold restored")

        // Reset state for immediate readiness
        recentConfidenceValues.clear()
        consecutiveSpeechFrames = 0
        consecutiveSilenceFrames = 0
        _isSpeechActive = false
    }

    override fun setTTSThresholdMultiplier(multiplier: Float) {
        ttsThresholdMultiplier = multiplier.coerceIn(2.0f, 5.0f)
        logger.info("TTS threshold multiplier set to ${ttsThresholdMultiplier}x")
    }

    // =========================================================================
    // MARK: - Calibration (matching iOS VADService protocol)
    // =========================================================================

    /**
     * Calibration is not supported by ONNX VAD.
     * ONNX VAD uses pre-trained models that don't require calibration.
     * Returns false to indicate calibration is not available.
     */
    override suspend fun startCalibration(): Boolean {
        logger.info("Calibration not supported by ONNX VAD (pre-trained model)")
        return false
    }

    // =========================================================================
    // MARK: - Debug Statistics (matching iOS getStatistics)
    // =========================================================================

    override fun getStatistics(): VADStatistics {
        val recent =
            if (recentConfidenceValues.isEmpty()) {
                0.0f
            } else {
                recentConfidenceValues.sum() / recentConfidenceValues.size
            }

        val maxValue = recentConfidenceValues.maxOrNull() ?: 0.0f

        return VADStatistics(
            current = recentConfidenceValues.lastOrNull() ?: 0.0f,
            threshold = _energyThreshold,
            ambient = 0.0f, // ONNX VAD doesn't track ambient
            recentAvg = recent,
            recentMax = maxValue,
        )
    }
}
