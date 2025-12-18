package com.runanywhere.sdk.core.whispercpp

import com.runanywhere.sdk.components.stt.STTConfiguration
import com.runanywhere.sdk.components.stt.STTOptions
import com.runanywhere.sdk.components.stt.STTService
import com.runanywhere.sdk.components.stt.STTTranscriptionResult
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.native.bridge.NativeBridgeException
import com.runanywhere.sdk.native.bridge.NativeResultCode
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import kotlinx.coroutines.flow.Flow
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

private val logger = SDKLogger("WhisperCPPServiceProviderImpl")

/**
 * JSON structure returned by native STT transcription
 * Matches the format from runanywhere-core
 */
@Serializable
private data class NativeSTTResult(
    val text: String = "",
    val confidence: Double = 0.0,
    val detected_language: String = "",
    val audio_duration_ms: Double = 0.0,
    val inference_time_ms: Double = 0.0,
    val is_final: Boolean = true,
    val metadata: String? = null
)

private val jsonParser = Json {
    ignoreUnknownKeys = true
    isLenient = true
}

/**
 * Parse native STT JSON result and extract the transcription
 */
private fun parseSTTResult(jsonResult: String): STTTranscriptionResult {
    return try {
        val result = jsonParser.decodeFromString<NativeSTTResult>(jsonResult)
        STTTranscriptionResult(
            transcript = result.text.trim(),
            confidence = result.confidence.toFloat(),
            language = result.detected_language.ifEmpty { null }
        )
    } catch (e: Exception) {
        logger.warn("Failed to parse STT JSON result, using raw string: ${e.message}")
        // Fallback: return raw string if not JSON
        STTTranscriptionResult(
            transcript = jsonResult.trim(),
            confidence = 1.0f,
            language = null
        )
    }
}

/**
 * JVM/Android implementation of WhisperCPP STT service creation
 */
actual suspend fun createWhisperCPPSTTService(configuration: STTConfiguration): STTService {
    logger.info("Creating WhisperCPP STT service with configuration: ${configuration.modelId}")

    val service = WhisperCPPCoreService()
    service.initialize()

    var loadedModelPath: String? = null

    // Load model if the modelId looks like a path
    configuration.modelId?.let { modelId ->
        try {
            if (modelId.contains("/") || modelId.endsWith(".bin") || modelId.endsWith(".ggml")) {
                // modelId is actually a path - load it directly
                logger.info("Loading WhisperCPP STT model from path: $modelId")
                service.loadSTTModel(modelId, "whisper")
                loadedModelPath = modelId
                logger.info("WhisperCPP STT model loaded successfully from path: $loadedModelPath")
            } else {
                // modelId is just an ID - the model needs to be loaded via a different mechanism
                logger.info("Model ID specified: $modelId - model path should be provided for actual loading")
            }
        } catch (e: Exception) {
            logger.error("Failed to load WhisperCPP STT model: ${e.message}")
            // Don't throw - let the service return an error when transcribe is called
        }
    }

    // Create wrapper and pass the loaded model path
    val wrapper = WhisperCPPSTTServiceWrapper(service)
    if (loadedModelPath != null) {
        wrapper.setModelPath(loadedModelPath!!)
    }
    return wrapper
}

// MARK: - Service Wrapper

/**
 * Wrapper for WhisperCPP STT Service implementing STTService interface
 */
private class WhisperCPPSTTServiceWrapper(
    private val coreService: WhisperCPPCoreService
) : STTService {

    // Track the loaded model path
    private var loadedModelPath: String? = null

    override val isReady: Boolean
        get() = coreService.isInitialized && coreService.isSTTModelLoaded

    override val currentModel: String?
        get() {
            val modelName = loadedModelPath?.substringAfterLast("/")?.substringBeforeLast(".")
            return modelName
        }

    override val supportsStreaming: Boolean
        get() = coreService.supportsSTTStreaming

    override suspend fun initialize(modelPath: String?) {
        modelPath?.let { path ->
            coreService.loadSTTModel(path, "whisper")
            loadedModelPath = path
        }
    }

    /**
     * Set the model path for tracking.
     */
    fun setModelPath(path: String) {
        loadedModelPath = path
    }

    override suspend fun transcribe(
        audioData: ByteArray,
        options: STTOptions
    ): STTTranscriptionResult {
        val samples = convertToFloat32Samples(audioData)
        val jsonResult = coreService.transcribe(samples, 16000, options.language)

        // Parse JSON result from native code
        val result = parseSTTResult(jsonResult)

        // Use language from options if not detected
        return if (result.language.isNullOrEmpty()) {
            result.copy(language = options.language)
        } else {
            result
        }
    }

    override suspend fun streamTranscribe(
        audioStream: Flow<ByteArray>,
        options: STTOptions,
        onPartial: (String) -> Unit
    ): STTTranscriptionResult {
        // WhisperCPP supports streaming via state-based decoding
        // For now, fall back to batch processing with periodic results

        val allAudioChunks = mutableListOf<ByteArray>()
        var lastProcessedSize = 0

        // Process every ~3 seconds of audio (16kHz * 2 bytes * 3 sec = 96000 bytes)
        val batchThreshold = 16000 * 2 * 3

        logger.debug("Starting WhisperCPP pseudo-streaming transcription")

        audioStream.collect { chunk ->
            allAudioChunks.add(chunk)

            val totalSize = allAudioChunks.sumOf { it.size }
            val newDataSize = totalSize - lastProcessedSize

            // Process periodically when we have enough new audio
            if (newDataSize >= batchThreshold) {
                logger.debug("Processing batch chunk: $totalSize bytes total")

                try {
                    val combinedAudio = allAudioChunks.fold(byteArrayOf()) { acc, c -> acc + c }
                    val result = transcribe(combinedAudio, options)

                    if (result.transcript.isNotEmpty()) {
                        onPartial(result.transcript)
                        logger.debug("Partial transcription: ${result.transcript}")
                    }
                } catch (e: Exception) {
                    logger.error("Periodic batch transcription failed: ${e.message}")
                }

                lastProcessedSize = totalSize
            }
        }

        // Final transcription with all accumulated audio
        val combinedAudio = allAudioChunks.fold(byteArrayOf()) { acc, c -> acc + c }
        logger.info("Final batch transcription: ${combinedAudio.size} bytes")

        val finalResult = transcribe(combinedAudio, options)
        if (finalResult.transcript.isNotEmpty()) {
            onPartial(finalResult.transcript)
        }

        return finalResult
    }

    override suspend fun cleanup() {
        coreService.unloadSTTModel()
    }
}

// MARK: - Helper Functions

/**
 * Convert byte array to float32 samples
 */
private fun convertToFloat32Samples(audioData: ByteArray): FloatArray {
    // Assuming 16-bit PCM input
    val samples = FloatArray(audioData.size / 2)
    for (i in samples.indices) {
        val low = audioData[i * 2].toInt() and 0xFF
        val high = audioData[i * 2 + 1].toInt()
        val sample = (high shl 8) or low
        samples[i] = sample / 32768.0f
    }
    return samples
}
