package com.runanywhere.sdk.native.bridge.providers

import com.runanywhere.sdk.core.STTServiceProvider
import com.runanywhere.sdk.features.stt.STTConfiguration
import com.runanywhere.sdk.features.stt.STTOptions
import com.runanywhere.sdk.features.stt.STTService
import com.runanywhere.sdk.features.stt.STTTranscriptionResult
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.enums.InferenceFramework
import com.runanywhere.sdk.native.bridge.NativeBridgeException
import com.runanywhere.sdk.native.bridge.ONNXCoreService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * ONNX-based STT Service Provider
 *
 * Provides speech-to-text capabilities using the ONNX Runtime backend
 * through the RunAnywhere Core JNI bridge.
 *
 * Supports models like:
 * - Whisper (whisper-tiny, whisper-base, whisper-small, etc.)
 * - Zipformer (sherpa-onnx variants)
 * - Paraformer
 */
class ONNXSTTProvider : STTServiceProvider {
    private val logger = SDKLogger("ONNXSTTProvider")

    override val name: String = "ONNX STT"
    override val framework: InferenceFramework = InferenceFramework.ONNX

    override fun canHandle(modelId: String?): Boolean {
        if (modelId == null) return true

        // Handle models that are known to work with ONNX
        val onnxModels =
            listOf(
                "whisper",
                "zipformer",
                "paraformer",
                "sherpa-onnx",
                "onnx-whisper",
            )
        return onnxModels.any { modelId.lowercase().contains(it) }
    }

    override suspend fun createSTTService(configuration: STTConfiguration): STTService {
        logger.info("Creating ONNX STT service for model: ${configuration.modelId}")
        return ONNXSTTService(configuration)
    }
}

/**
 * ONNX-based STT Service implementation
 */
class ONNXSTTService(
    private val configuration: STTConfiguration,
) : STTService {
    private val logger = SDKLogger("ONNXSTTService")
    private val json = Json { ignoreUnknownKeys = true }

    private val coreService = ONNXCoreService()
    private var modelPath: String? = null

    override val isReady: Boolean
        get() = coreService.isInitialized && coreService.isSTTModelLoaded

    override val currentModel: String?
        get() = if (isReady) configuration.modelId else null

    override val supportsStreaming: Boolean
        get() = coreService.supportsSTTStreaming

    override suspend fun initialize(modelPath: String?) {
        logger.info("Initializing ONNX STT service with model: $modelPath")

        try {
            // Initialize the core service
            coreService.initialize()

            // Load the model if path is provided
            if (modelPath != null) {
                this.modelPath = modelPath

                // Determine model type from path or configuration
                val modelType = determineModelType(modelPath)
                coreService.loadSTTModel(modelPath, modelType)

                logger.info("✅ ONNX STT service initialized with model: $modelPath")
            }
        } catch (e: NativeBridgeException) {
            logger.error("Failed to initialize ONNX STT service", e)
            throw e
        }
    }

    override suspend fun transcribe(
        audioData: ByteArray,
        options: STTOptions,
    ): STTTranscriptionResult =
        withContext(Dispatchers.IO) {
            if (!isReady) {
                throw IllegalStateException("STT service not ready. Call initialize() first.")
            }

            // Convert ByteArray to FloatArray samples
            val samples = audioDataToFloatArray(audioData, options.audioFormat)

            // Call native transcription
            val resultJson =
                coreService.transcribe(
                    audioSamples = samples,
                    sampleRate = options.sampleRate,
                    language = if (options.detectLanguage) null else options.language,
                )

            // Parse JSON result
            parseTranscriptionResult(resultJson)
        }

    override suspend fun streamTranscribe(
        audioStream: Flow<ByteArray>,
        options: STTOptions,
        onPartial: (String) -> Unit,
    ): STTTranscriptionResult =
        withContext(Dispatchers.IO) {
            if (!isReady) {
                throw IllegalStateException("STT service not ready. Call initialize() first.")
            }

            // If streaming is not supported, fall back to batch mode
            if (!supportsStreaming) {
                logger.info("Streaming not supported, falling back to batch mode")
                val allAudio = audioStream.toList().reduce { acc, bytes -> acc + bytes }
                return@withContext transcribe(allAudio, options)
            }

            // TODO: Implement streaming transcription using ra_stt_create_stream, etc.
            // For now, fall back to batch mode
            val allAudio = audioStream.toList().reduce { acc, bytes -> acc + bytes }
            transcribe(allAudio, options)
        }

    override suspend fun cleanup() {
        logger.info("Cleaning up ONNX STT service")
        try {
            if (coreService.isSTTModelLoaded) {
                coreService.unloadSTTModel()
            }
            coreService.destroy()
        } catch (e: Exception) {
            logger.error("Error during cleanup", e)
        }
    }

    // =============================================================================
    // Private Helpers
    // =============================================================================

    private fun determineModelType(modelPath: String): String {
        val path = modelPath.lowercase()
        return when {
            path.contains("whisper") -> "whisper"
            path.contains("zipformer") -> "zipformer"
            path.contains("paraformer") -> "paraformer"
            else -> "whisper" // Default to whisper
        }
    }

    @Suppress("UNUSED_PARAMETER")
    private fun audioDataToFloatArray(
        audioData: ByteArray,
        format: com.runanywhere.sdk.core.AudioFormat,
    ): FloatArray {
        // Assume 16-bit PCM audio
        // Convert byte pairs to float samples in range [-1.0, 1.0]
        val sampleCount = audioData.size / 2
        val samples = FloatArray(sampleCount)

        for (i in 0 until sampleCount) {
            val low = audioData[i * 2].toInt() and 0xFF
            val high = audioData[i * 2 + 1].toInt()
            val sample = (high shl 8 or low).toShort()
            samples[i] = sample.toFloat() / 32768.0f
        }

        return samples
    }

    private fun parseTranscriptionResult(jsonResult: String): STTTranscriptionResult =
        try {
            val parsed = json.decodeFromString<TranscriptionResponse>(jsonResult)
            STTTranscriptionResult(
                transcript = parsed.text,
                confidence = parsed.confidence,
                timestamps =
                    parsed.segments?.map {
                        STTTranscriptionResult.TimestampInfo(
                            word = it.text,
                            startTime = it.start,
                            endTime = it.end,
                            confidence = it.confidence,
                        )
                    },
                language = parsed.language,
            )
        } catch (e: Exception) {
            // If parsing fails, return raw text
            STTTranscriptionResult(
                transcript = jsonResult.trim().removeSurrounding("\""),
                confidence = null,
            )
        }

    @Serializable
    private data class TranscriptionResponse(
        val text: String,
        val confidence: Float? = null,
        val language: String? = null,
        val segments: List<SegmentResponse>? = null,
    )

    @Serializable
    private data class SegmentResponse(
        val text: String,
        val start: Double,
        val end: Double,
        val confidence: Float? = null,
    )
}
