package com.runanywhere.sdk.native.bridge.providers

import com.runanywhere.sdk.core.AudioFormat
import com.runanywhere.sdk.features.tts.TTSOptions
import com.runanywhere.sdk.core.TTSServiceProvider
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.enums.InferenceFramework
import com.runanywhere.sdk.native.bridge.NativeBridgeException
import com.runanywhere.sdk.native.bridge.ONNXCoreService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext

/**
 * ONNX-based TTS Service Provider
 *
 * Provides text-to-speech capabilities using the ONNX Runtime backend
 * through the RunAnywhere Core JNI bridge.
 *
 * Supports models like:
 * - VITS (vits-piper, vits-coqui, etc.)
 * - Tacotron2 + WaveGlow
 * - FastSpeech2
 * - Piper TTS
 */
class ONNXTTSProvider : TTSServiceProvider {

    private val logger = SDKLogger("ONNXTTSProvider")
    private val coreService = ONNXCoreService()
    private var isInitialized = false
    private var currentModelPath: String? = null

    override val name: String = "ONNX TTS"
    override val framework: InferenceFramework = InferenceFramework.ONNX

    override fun canHandle(modelId: String): Boolean {
        // Handle models that are known to work with ONNX TTS
        val onnxTTSModels = listOf(
            "vits", "piper", "tacotron", "fastspeech",
            "waveglow", "hifigan", "onnx-tts"
        )
        return onnxTTSModels.any { modelId.lowercase().contains(it) }
    }

    /**
     * Initialize the TTS service with a model
     */
    suspend fun initialize(modelPath: String, modelType: String = "vits") {
        if (!coreService.isInitialized) {
            coreService.initialize()
        }

        if (!coreService.isTTSModelLoaded || currentModelPath != modelPath) {
            coreService.loadTTSModel(modelPath, modelType)
            currentModelPath = modelPath
        }

        isInitialized = true
        logger.info("✅ ONNX TTS provider initialized with model: $modelPath")
    }

    override suspend fun synthesize(text: String, options: TTSOptions): ByteArray =
        withContext(Dispatchers.IO) {
            ensureInitialized()

            try {
                val result = coreService.synthesize(
                    text = text,
                    voiceId = options.voice ?: "default",
                    speedRate = options.rate,
                    pitchShift = options.pitch
                )

                // Convert to output format if needed
                convertToFormat(result.samples, result.sampleRate, options.audioFormat)
            } catch (e: NativeBridgeException) {
                logger.error("TTS synthesis failed", e)
                throw e
            }
        }

    override fun synthesizeStream(text: String, options: TTSOptions): Flow<ByteArray> = flow {
        // For ONNX, we synthesize the whole text and emit it
        // True streaming would require model support
        val audioData = synthesize(text, options)

        // Split into chunks for streaming delivery
        val chunkSize = options.sampleRate * 2 // 1 second of audio at 16-bit (sampleRate is already in Hz)
        var offset = 0

        while (offset < audioData.size) {
            val end = minOf(offset + chunkSize, audioData.size)
            emit(audioData.copyOfRange(offset, end))
            offset = end
        }
    }

    /**
     * Get available voices as JSON
     */
    suspend fun getAvailableVoices(): String = withContext(Dispatchers.IO) {
        if (coreService.isInitialized) {
            coreService.getVoices()
        } else {
            "[]"
        }
    }

    /**
     * Cleanup resources
     */
    suspend fun cleanup() {
        if (coreService.isTTSModelLoaded) {
            coreService.unloadTTSModel()
        }
        coreService.destroy()
        isInitialized = false
        currentModelPath = null
    }

    // =============================================================================
    // Private Helpers
    // =============================================================================

    private fun ensureInitialized() {
        if (!isInitialized || !coreService.isTTSModelLoaded) {
            throw NativeBridgeException(
                com.runanywhere.sdk.native.bridge.NativeResultCode.ERROR_MODEL_LOAD_FAILED,
                "TTS model not loaded. Call initialize() with a model path first."
            )
        }
    }

    private fun convertToFormat(
        audioData: FloatArray,
        sampleRate: Int,
        targetFormat: AudioFormat
    ): ByteArray {
        // Convert float samples to 16-bit PCM
        val pcmData = ByteArray(audioData.size * 2)
        for (i in audioData.indices) {
            val sample = (audioData[i] * 32767).toInt().coerceIn(-32768, 32767).toShort()
            pcmData[i * 2] = (sample.toInt() and 0xFF).toByte()
            pcmData[i * 2 + 1] = (sample.toInt() shr 8 and 0xFF).toByte()
        }

        return when (targetFormat) {
            AudioFormat.PCM, AudioFormat.PCM_16BIT -> pcmData
            AudioFormat.WAV -> addWavHeader(pcmData, sampleRate, 1, 16)
            else -> pcmData // For other formats, return PCM (would need encoding library)
        }
    }

    private fun addWavHeader(
        pcmData: ByteArray,
        sampleRate: Int,
        channels: Int,
        bitsPerSample: Int
    ): ByteArray {
        val byteRate = sampleRate * channels * bitsPerSample / 8
        val blockAlign = channels * bitsPerSample / 8
        val dataSize = pcmData.size
        val fileSize = 36 + dataSize

        val header = ByteArray(44)

        // RIFF header
        header[0] = 'R'.code.toByte()
        header[1] = 'I'.code.toByte()
        header[2] = 'F'.code.toByte()
        header[3] = 'F'.code.toByte()

        // File size
        header[4] = (fileSize and 0xFF).toByte()
        header[5] = (fileSize shr 8 and 0xFF).toByte()
        header[6] = (fileSize shr 16 and 0xFF).toByte()
        header[7] = (fileSize shr 24 and 0xFF).toByte()

        // WAVE header
        header[8] = 'W'.code.toByte()
        header[9] = 'A'.code.toByte()
        header[10] = 'V'.code.toByte()
        header[11] = 'E'.code.toByte()

        // fmt chunk
        header[12] = 'f'.code.toByte()
        header[13] = 'm'.code.toByte()
        header[14] = 't'.code.toByte()
        header[15] = ' '.code.toByte()

        // Subchunk1 size (16 for PCM)
        header[16] = 16
        header[17] = 0
        header[18] = 0
        header[19] = 0

        // Audio format (1 for PCM)
        header[20] = 1
        header[21] = 0

        // Channels
        header[22] = channels.toByte()
        header[23] = 0

        // Sample rate
        header[24] = (sampleRate and 0xFF).toByte()
        header[25] = (sampleRate shr 8 and 0xFF).toByte()
        header[26] = (sampleRate shr 16 and 0xFF).toByte()
        header[27] = (sampleRate shr 24 and 0xFF).toByte()

        // Byte rate
        header[28] = (byteRate and 0xFF).toByte()
        header[29] = (byteRate shr 8 and 0xFF).toByte()
        header[30] = (byteRate shr 16 and 0xFF).toByte()
        header[31] = (byteRate shr 24 and 0xFF).toByte()

        // Block align
        header[32] = blockAlign.toByte()
        header[33] = 0

        // Bits per sample
        header[34] = bitsPerSample.toByte()
        header[35] = 0

        // data chunk
        header[36] = 'd'.code.toByte()
        header[37] = 'a'.code.toByte()
        header[38] = 't'.code.toByte()
        header[39] = 'a'.code.toByte()

        // Data size
        header[40] = (dataSize and 0xFF).toByte()
        header[41] = (dataSize shr 8 and 0xFF).toByte()
        header[42] = (dataSize shr 16 and 0xFF).toByte()
        header[43] = (dataSize shr 24 and 0xFF).toByte()

        return header + pcmData
    }
}
