package com.runanywhere.sdk.features.vad

import com.konovalov.vad.webrtc.VadWebRTC
import com.konovalov.vad.webrtc.config.FrameSize
import com.konovalov.vad.webrtc.config.Mode
import com.konovalov.vad.webrtc.config.SampleRate
import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Platform-specific VAD service creation for Android
 */
actual fun createPlatformVADService(): VADService = WebRTCVADService()

/**
 * WebRTC VAD Service implementation using the android-vad library
 * Provides robust voice activity detection using the WebRTC GMM-based algorithm
 */
class WebRTCVADService : VADService {

    private val logger = SDKLogger("WebRTCVADService")
    private var config: VADConfiguration? = null
    private var vadInstance: VadWebRTC? = null
    private var isInitialized = false
    private var isActive = false
    private var currentSpeechState = false

    // Properties matching iOS VADService protocol
    override var energyThreshold: Float = 0.022f // Not used by WebRTC but required by interface

    override val sampleRate: Int
        get() = config?.sampleRate ?: 16000

    override val frameLength: Float
        get() = config?.frameLength ?: 0.1f

    override val isSpeechActive: Boolean
        get() = currentSpeechState

    // Callbacks matching iOS VADService protocol
    override var onSpeechActivity: ((SpeechActivityEvent) -> Unit)? = null
    override var onAudioBuffer: ((ByteArray) -> Unit)? = null

    override suspend fun initialize(configuration: VADConfiguration) {
        withContext(Dispatchers.IO) {
            logger.info("Initializing WebRTC VAD Service")
            config = configuration

            try {
                // Map our configuration to WebRTC VAD configuration
                val sampleRate = mapSampleRate(configuration.sampleRate)
                val frameSize = mapFrameSize(configuration.sampleRate, configuration.frameLength)
                val mode = Mode.AGGRESSIVE // Default to aggressive mode

                // Create VAD instance with speech and silence duration settings
                vadInstance = VadWebRTC(
                    sampleRate = sampleRate,
                    frameSize = frameSize,
                    mode = mode,
                    speechDurationMs = 50, // Minimum speech duration in ms
                    silenceDurationMs = 500 // Default silence duration in ms
                )

                isInitialized = true
                logger.info("WebRTC VAD Service initialized successfully")
                logger.info("Sample Rate: ${sampleRate.value}Hz, Frame Size: ${frameSize.value}, Mode: $mode")

            } catch (e: Exception) {
                logger.error("Failed to initialize WebRTC VAD", e)
                throw VADError.ConfigurationError
            }
        }
    }

    override fun start() {
        isActive = true
        currentSpeechState = false
        logger.info("WebRTC VAD started")
    }

    override fun stop() {
        if (currentSpeechState) {
            currentSpeechState = false
            onSpeechActivity?.invoke(SpeechActivityEvent.ENDED)
        }
        isActive = false
        logger.info("WebRTC VAD stopped")
    }

    override fun processAudioData(audioData: FloatArray): Boolean {
        return processAudioChunk(audioData).isSpeechDetected
    }

    override fun processAudioChunk(audioSamples: FloatArray): VADResult {
        if (!isInitialized || vadInstance == null || !isActive) {
            return VADResult(isSpeechDetected = false, confidence = 0.0f)
        }

        return try {
            // WebRTC VAD expects different audio formats, it can handle FloatArray directly
            val isSpeech = vadInstance!!.isSpeech(audioSamples)

            // Update speech state and trigger callbacks
            updateSpeechState(isSpeech)

            // Call audio buffer callback if set
            onAudioBuffer?.invoke(floatArrayToByteArray(audioSamples))

            // Calculate confidence based on the audio energy
            val confidence = if (isSpeech) {
                0.85f // WebRTC VAD doesn't provide confidence, use high value for speech
            } else {
                0.15f // Low confidence for non-speech
            }

            VADResult(
                isSpeechDetected = isSpeech,
                confidence = confidence,
                timestamp = System.currentTimeMillis()
            )
        } catch (e: Exception) {
            logger.error("Error processing audio chunk", e)
            throw VADError.ProcessingFailed(e)
        }
    }

    override fun reset() {
        // WebRTC VAD maintains internal state for continuous speech detection
        // Creating a new instance is the safest way to reset
        if (vadInstance != null && config != null) {
            try {
                vadInstance?.close()

                val sampleRate = mapSampleRate(config!!.sampleRate)
                val frameSize = mapFrameSize(config!!.sampleRate, config!!.frameLength)
                val mode = Mode.AGGRESSIVE // Default to aggressive mode

                vadInstance = VadWebRTC(
                    sampleRate = sampleRate,
                    frameSize = frameSize,
                    mode = mode,
                    speechDurationMs = 50,
                    silenceDurationMs = 500 // Default silence duration
                )

                logger.debug("VAD state reset")
            } catch (e: Exception) {
                logger.error("Failed to reset VAD", e)
            }
        }
    }

    override val isReady: Boolean
        get() = isInitialized && vadInstance != null

    override val configuration: VADConfiguration?
        get() = config

    override suspend fun cleanup() {
        withContext(Dispatchers.IO) {
            logger.info("Cleaning up WebRTC VAD Service")

            vadInstance?.close()
            vadInstance = null
            isInitialized = false
            config = null
        }
    }

    /**
     * Map our sample rate to WebRTC VAD sample rate
     */
    private fun mapSampleRate(sampleRate: Int): SampleRate {
        return when (sampleRate) {
            8000 -> SampleRate.SAMPLE_RATE_8K
            16000 -> SampleRate.SAMPLE_RATE_16K
            32000 -> SampleRate.SAMPLE_RATE_32K
            48000 -> SampleRate.SAMPLE_RATE_48K
            else -> {
                logger.warning("Unsupported sample rate $sampleRate, defaulting to 16kHz")
                SampleRate.SAMPLE_RATE_16K
            }
        }
    }

    /**
     * Map frame duration to WebRTC VAD frame size based on sample rate
     */
    private fun mapFrameSize(sampleRate: Int, frameLength: Float): FrameSize {
        val frameDurationMs = (frameLength * 1000).toInt()
        // Calculate frame size in samples
        val frameSizeSamples = (sampleRate * frameDurationMs) / 1000

        return when (sampleRate) {
            8000 -> when (frameSizeSamples) {
                80 -> FrameSize.FRAME_SIZE_80
                160 -> FrameSize.FRAME_SIZE_160
                240 -> FrameSize.FRAME_SIZE_240
                else -> FrameSize.FRAME_SIZE_160 // Default for 8kHz
            }

            16000 -> when (frameSizeSamples) {
                160 -> FrameSize.FRAME_SIZE_160
                320 -> FrameSize.FRAME_SIZE_320
                480 -> FrameSize.FRAME_SIZE_480
                else -> FrameSize.FRAME_SIZE_320 // Default for 16kHz
            }

            32000 -> when (frameSizeSamples) {
                320 -> FrameSize.FRAME_SIZE_320
                640 -> FrameSize.FRAME_SIZE_640
                960 -> FrameSize.FRAME_SIZE_960
                else -> FrameSize.FRAME_SIZE_640 // Default for 32kHz
            }

            48000 -> when (frameSizeSamples) {
                480 -> FrameSize.FRAME_SIZE_480
                960 -> FrameSize.FRAME_SIZE_960
                1440 -> FrameSize.FRAME_SIZE_1440
                else -> FrameSize.FRAME_SIZE_960 // Default for 48kHz
            }

            else -> {
                logger.warning("Using default frame size for sample rate $sampleRate")
                FrameSize.FRAME_SIZE_320
            }
        }
    }

    private fun updateSpeechState(isSpeech: Boolean) {
        if (isSpeech != currentSpeechState) {
            currentSpeechState = isSpeech
            onSpeechActivity?.invoke(
                if (isSpeech) SpeechActivityEvent.STARTED else SpeechActivityEvent.ENDED
            )
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

    // Aggressiveness mapping removed - using default Mode.AGGRESSIVE
}
