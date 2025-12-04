package com.runanywhere.sdk.core.onnx

import com.runanywhere.sdk.components.TTSOptions
import com.runanywhere.sdk.components.stt.STTConfiguration
import com.runanywhere.sdk.components.stt.STTOptions
import com.runanywhere.sdk.components.stt.STTService
import com.runanywhere.sdk.components.stt.STTStreamEvent
import com.runanywhere.sdk.components.stt.STTStreamingOptions
import com.runanywhere.sdk.components.stt.STTTranscriptionResult
import com.runanywhere.sdk.components.vad.VADConfiguration
import com.runanywhere.sdk.components.vad.VADResult
import com.runanywhere.sdk.components.vad.VADService
import com.runanywhere.sdk.components.vad.SpeechActivityEvent
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.utils.PlatformUtils
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.util.UUID

private val logger = SDKLogger("ONNXServiceProviderImpl")

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
 * Parse native STT JSON result and extract just the text
 * Returns the raw string if JSON parsing fails (fallback)
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
 * JVM/Android implementation of ONNX STT service creation
 *
 * NOTE: The actual model loading happens when the caller provides a model path.
 * The configuration.modelId can be either:
 * - A full file path (e.g., /data/.../model.onnx)
 * - A model ID that requires the caller to load the model separately
 */
actual suspend fun createONNXSTTService(configuration: STTConfiguration): STTService {
    logger.info("Creating ONNX STT service with configuration: ${configuration.modelId}")

    val service = ONNXCoreService()
    service.initialize()

    var loadedModelPath: String? = null

    // Load model if the modelId looks like a path (contains / or ends with common model extensions)
    configuration.modelId?.let { modelId ->
        try {
            if (modelId.contains("/") || modelId.endsWith(".onnx") || modelId.endsWith(".gguf")) {
                // modelId is actually a path - load it directly
                logger.info("Loading STT model from path: $modelId")
                val modelType = detectSTTModelType(modelId)
                service.loadSTTModel(modelId, modelType)
                loadedModelPath = modelId  // Track the path for telemetry
                logger.info("STT model loaded successfully from path: $loadedModelPath")
            } else {
                // modelId is just an ID - the model needs to be loaded via a different mechanism
                // Log this but don't fail - the service will return an error when transcribe is called
                logger.info("Model ID specified: $modelId - model path should be provided for actual loading")
            }
        } catch (e: Exception) {
            logger.error("Failed to load STT model: ${e.message}")
            // Don't throw - let the service return an error when transcribe is called
        }
    }

    // Create wrapper and pass the loaded model path for telemetry
    val wrapper = ONNXSTTServiceWrapper(service)
    // Set the model path in the wrapper for telemetry tracking
    if (loadedModelPath != null) {
        wrapper.setModelPath(loadedModelPath!!)
    }
    return wrapper
}

// Cached ONNX TTS service for reuse
private var cachedTTSCoreService: ONNXCoreService? = null
private var cachedTTSModelPath: String? = null

/**
 * JVM/Android implementation of ONNX TTS synthesis
 * Matches iOS ONNXTTSService.synthesize() behavior
 */
@OptIn(DelicateCoroutinesApi::class)
actual suspend fun synthesizeWithONNX(text: String, options: TTSOptions): ByteArray {
    logger.info("Synthesizing with ONNX: ${text.take(50)}...")

    // Get the model path from options.voiceId (which contains the model path)
    val modelPath = options.voiceId

    if (modelPath.isNullOrEmpty()) {
        logger.error("No TTS model path provided in options.voiceId")
        throw IllegalStateException("TTS model not loaded. Please select a TTS model first.")
    }

    logger.info("Using TTS model path: $modelPath")

    // Track processing time - start before any telemetry to avoid blocking
    val startTime = getCurrentTimeMillis()

    // Extract model name from path for telemetry
    val modelName = modelPath.substringAfterLast("/").substringBeforeLast(".")

    // Generate synthesis ID for telemetry tracking
    val synthesisId = UUID.randomUUID().toString()
    val characterCount = text.length

    // Track synthesis started - fire and forget to avoid blocking synthesis
    // Use a try-catch and don't await to prevent any telemetry issues from blocking TTS
    val telemetryService = try {
        ServiceContainer.shared.telemetryService
    } catch (e: Exception) {
        logger.debug("Could not get telemetry service: ${e.message}")
        null
    }

    // Fire-and-forget telemetry tracking - don't block synthesis on telemetry
    logger.info("📊 TTS Telemetry check: telemetryService=${if (telemetryService != null) "AVAILABLE" else "NULL"}")
    if (telemetryService == null) {
        logger.warn("⚠️ TTS telemetry SKIPPED - telemetryService is NULL (check ServiceContainer initialization)")
    }
    kotlinx.coroutines.GlobalScope.launch(kotlinx.coroutines.Dispatchers.IO) {
        try {
            if (telemetryService != null) {
                logger.info("📊 TTS_SYNTHESIS_STARTED tracking: synthesisId=$synthesisId, model=$modelName")
            }
            telemetryService?.trackTTSSynthesisStarted(
                synthesisId = synthesisId,
                modelId = modelName,
                modelName = modelName,
                framework = "ONNX Runtime",
                language = options.language,
                voice = modelName,  // Use model name instead of full path (DB has 50 char limit)
                characterCount = characterCount,
                speakingRate = options.rate,
                pitch = options.pitch,
                device = PlatformUtils.getDeviceModel(),
                osVersion = PlatformUtils.getOSVersion()
            )
            logger.info("✅ TTS_SYNTHESIS_STARTED tracked successfully")
        } catch (e: Exception) {
            logger.warn("⚠️ Failed to track TTS synthesis started: ${e.message}")
        }
    }

    logger.info("Starting ONNX TTS synthesis...")

    // Check if we can reuse the cached service
    val service: ONNXCoreService
    if (cachedTTSCoreService != null && cachedTTSModelPath == modelPath) {
        logger.debug("Reusing cached TTS service")
        service = cachedTTSCoreService!!
    } else {
        // Create and initialize new service
        logger.info("Creating new ONNX TTS service...")
        service = ONNXCoreService()
        service.initialize()

        // Load the TTS model
        logger.info("Loading TTS model from: $modelPath")
        service.loadTTSModel(modelPath, "vits")
        logger.info("TTS model loaded successfully")

        // Cache for reuse
        cachedTTSCoreService = service
        cachedTTSModelPath = modelPath
    }

    // Synthesize
    val result = try {
        service.synthesize(
            text = text,
            voiceId = "0", // Speaker ID for multi-speaker models
            speedRate = options.rate,
            pitchShift = options.pitch
        )
    } catch (error: Exception) {
        // Track synthesis failure - fire and forget
        val endTime = getCurrentTimeMillis()
        val processingTimeMs = (endTime - startTime).toDouble()
        val errorMsg = error.message ?: error.toString()

        kotlinx.coroutines.GlobalScope.launch(kotlinx.coroutines.Dispatchers.IO) {
            try {
                telemetryService?.trackTTSSynthesisFailed(
                    synthesisId = synthesisId,
                    modelId = modelName,
                    modelName = modelName,
                    framework = "ONNX Runtime",
                    language = options.language ?: "en",
                    characterCount = characterCount,
                    processingTimeMs = processingTimeMs,
                    errorMessage = errorMsg,
                    device = PlatformUtils.getDeviceModel(),
                    osVersion = PlatformUtils.getOSVersion()
                )
            } catch (e: Exception) {
                logger.warn("⚠️ Failed to track TTS synthesis failure: ${e.message}")
            }
        }

        throw error
    }

    val processingTimeMs = (getCurrentTimeMillis() - startTime).toDouble()

    logger.info("Synthesized ${result.samples.size} samples at ${result.sampleRate} Hz")

    // Calculate audio duration in milliseconds
    val audioDurationMs = (result.samples.size.toDouble() / result.sampleRate.toDouble()) * 1000.0
    val realTimeFactor = if (audioDurationMs > 0) processingTimeMs / audioDurationMs else 0.0

    // Track successful synthesis completion - fire and forget
    kotlinx.coroutines.GlobalScope.launch(kotlinx.coroutines.Dispatchers.IO) {
        try {
            if (telemetryService != null) {
                logger.info("📊 TTS_SYNTHESIS_COMPLETED tracking: synthesisId=$synthesisId, duration=${audioDurationMs}ms")
            }
            telemetryService?.trackTTSSynthesisCompleted(
                synthesisId = synthesisId,
                modelId = modelName,
                modelName = modelName,
                framework = "ONNX Runtime",
                language = options.language ?: "en",
                characterCount = characterCount,
                audioDurationMs = audioDurationMs,
                processingTimeMs = processingTimeMs,
                realTimeFactor = realTimeFactor,
                device = PlatformUtils.getDeviceModel(),
                osVersion = PlatformUtils.getOSVersion()
            )
            if (telemetryService != null) {
                logger.info("✅ TTS_SYNTHESIS_COMPLETED tracked successfully")
            }
        } catch (e: Exception) {
            logger.warn("⚠️ Failed to track TTS synthesis completed: ${e.message}")
        }
    }

    // Convert samples to WAV format
    return convertToWav(result.samples, result.sampleRate)
}

/**
 * JVM/Android implementation of ONNX TTS streaming
 */
actual fun synthesizeStreamWithONNX(text: String, options: TTSOptions): Flow<ByteArray> {
    return flow {
        // ONNX TTS doesn't support true streaming, so we return full audio as single chunk
        val audio = synthesizeWithONNX(text, options)
        emit(audio)
    }
}

/**
 * JVM/Android implementation of ONNX VAD service creation
 */
actual suspend fun createONNXVADService(configuration: VADConfiguration): VADService {
    logger.info("Creating ONNX VAD service")

    val service = ONNXCoreService()
    service.initialize()

    // Load VAD model if path provided
    configuration.modelId?.let { modelId ->
        service.loadVADModel(modelId)
    }

    return ONNXVADServiceWrapper(service, configuration)
}

/**
 * Create ONNX STT service from model path (for ONNXAdapter)
 */
actual suspend fun createONNXSTTServiceFromPath(modelPath: String): Any {
    logger.info("Creating ONNX STT service from path: $modelPath")

    val service = ONNXCoreService()
    service.initialize()

    // Detect model type from path
    val modelType = detectSTTModelType(modelPath)
    service.loadSTTModel(modelPath, modelType)

    // Create wrapper and set model path for telemetry
    val wrapper = ONNXSTTServiceWrapper(service)
    wrapper.setModelPath(modelPath)
    return wrapper
}

/**
 * Create ONNX TTS service from model path (for ONNXAdapter)
 */
actual suspend fun createONNXTTSServiceFromPath(modelPath: String): Any {
    logger.info("Creating ONNX TTS service from path: $modelPath")

    val service = ONNXCoreService()
    service.initialize()
    service.loadTTSModel(modelPath, "vits")

    return ONNXTTSServiceWrapper(service)
}

// MARK: - Service Wrappers

/**
 * Wrapper for ONNX STT Service implementing STTService interface
 */
private class ONNXSTTServiceWrapper(
    private val coreService: ONNXCoreService
) : STTService {

    // Track the loaded model path for telemetry
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

    override val supportedLanguages: List<String> = listOf("en", "es", "fr", "de", "it", "pt", "zh", "ja", "ko")

    override suspend fun initialize(modelPath: String?) {
        modelPath?.let { path ->
            val modelType = detectSTTModelType(path)
            coreService.loadSTTModel(path, modelType)
            loadedModelPath = path  // Track model path for telemetry
        } ?: run {
        }
    }

    /**
     * Set the model path for telemetry tracking.
     * Used when the model is loaded externally before the wrapper is created.
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

        // Parse JSON result from native code to extract just the text
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
        // iOS-style pseudo-streaming for Whisper (batch) models:
        // Periodically transcribe accumulated audio to provide partial results

        val allAudioChunks = mutableListOf<ByteArray>()
        var accumulatedTranscript = ""
        var lastProcessedSize = 0

        // Process every ~3 seconds of audio (16kHz * 2 bytes * 3 sec = 96000 bytes)
        val batchThreshold = 16000 * 2 * 3  // ~3 seconds at 16kHz Int16

        logger.debug("Starting pseudo-streaming transcription with batch threshold: $batchThreshold bytes")

        audioStream.collect { chunk ->
            allAudioChunks.add(chunk)

            // Calculate total accumulated size
            val totalSize = allAudioChunks.sumOf { it.size }
            val newDataSize = totalSize - lastProcessedSize

            // Process periodically when we have enough new audio
            if (newDataSize >= batchThreshold) {
                logger.debug("Processing batch chunk: $totalSize bytes total")

                try {
                    // Combine all accumulated audio
                    val combinedAudio = allAudioChunks.fold(byteArrayOf()) { acc, c -> acc + c }
                    val result = transcribe(combinedAudio, options)

                    if (result.transcript.isNotEmpty()) {
                        accumulatedTranscript = result.transcript
                        onPartial(accumulatedTranscript)
                        logger.debug("Partial transcription: $accumulatedTranscript")
                    }
                } catch (e: Exception) {
                    logger.error("Periodic batch transcription failed: ${e.message}")
                }

                lastProcessedSize = totalSize
            }
            // Note: iOS doesn't emit placeholders - only real transcription text
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

    override fun transcribeStream(
        audioStream: Flow<ByteArray>,
        options: STTStreamingOptions
    ): Flow<STTStreamEvent> {
        return flow {
            emit(STTStreamEvent.SpeechStarted)

            // iOS-style pseudo-streaming for Whisper (batch) models:
            // Periodically transcribe accumulated audio to provide partial results

            val allAudioChunks = mutableListOf<ByteArray>()
            var lastProcessedSize = 0

            // Process every ~3 seconds of audio (16kHz * 2 bytes * 3 sec = 96000 bytes)
            val batchThreshold = 16000 * 2 * 3  // ~3 seconds at 16kHz Int16

            logger.debug("Starting pseudo-streaming transcription (Flow version)")

            audioStream.collect { chunk ->
                allAudioChunks.add(chunk)

                // Calculate total accumulated size
                val totalSize = allAudioChunks.sumOf { it.size }
                val newDataSize = totalSize - lastProcessedSize

                // Process periodically when we have enough new audio
                if (newDataSize >= batchThreshold) {
                    logger.debug("Processing batch chunk: $totalSize bytes total")

                    try {
                        // Combine all accumulated audio
                        val combinedAudio = allAudioChunks.fold(byteArrayOf()) { acc, c -> acc + c }
                        val defaultOptions = STTOptions(language = options.language ?: "en")
                        val result = transcribe(combinedAudio, defaultOptions)

                        if (result.transcript.isNotEmpty()) {
                            emit(STTStreamEvent.PartialTranscription(
                                text = result.transcript,
                                confidence = result.confidence ?: 0.9f
                            ))
                            logger.debug("Partial transcription: ${result.transcript}")
                        }
                    } catch (e: Exception) {
                        logger.error("Periodic batch transcription failed: ${e.message}")
                    }

                    lastProcessedSize = totalSize
                }
                // Note: iOS doesn't emit placeholders - only real transcription text
            }

            // Final transcription with all accumulated audio
            val combinedAudio = allAudioChunks.fold(byteArrayOf()) { acc, c -> acc + c }
            logger.info("Final batch transcription: ${combinedAudio.size} bytes")

            val defaultOptions = STTOptions(language = options.language ?: "en")
            val result = transcribe(combinedAudio, defaultOptions)

            emit(STTStreamEvent.FinalTranscription(result))
            emit(STTStreamEvent.SpeechEnded)
        }
    }

    override suspend fun detectLanguage(audioData: ByteArray): Map<String, Float> {
        // ONNX doesn't support standalone language detection - return default
        return mapOf("en" to 1.0f)
    }

    override fun supportsLanguage(languageCode: String): Boolean {
        return supportedLanguages.contains(languageCode.lowercase().take(2))
    }

    override suspend fun cleanup() {
        coreService.unloadSTTModel()
    }
}

/**
 * Wrapper for ONNX TTS Service
 */
private class ONNXTTSServiceWrapper(
    private val coreService: ONNXCoreService
) {
    val isReady: Boolean
        get() = coreService.isInitialized && coreService.isTTSModelLoaded

    suspend fun synthesize(text: String, options: TTSOptions): ByteArray {
        val result = coreService.synthesize(
            text = text,
            voiceId = options.voiceId,
            speedRate = options.rate,
            pitchShift = options.pitch
        )
        return convertToWav(result.samples, result.sampleRate)
    }

    suspend fun cleanup() {
        coreService.unloadTTSModel()
    }
}

/**
 * Wrapper for ONNX VAD Service implementing VADService interface
 */
private class ONNXVADServiceWrapper(
    private val coreService: ONNXCoreService,
    private val initialConfiguration: VADConfiguration
) : VADService {

    // VADService properties
    override var energyThreshold: Float = initialConfiguration.energyThreshold
    override val sampleRate: Int = initialConfiguration.sampleRate
    override val frameLength: Float = initialConfiguration.frameLength
    override var isSpeechActive: Boolean = false
        private set

    override var onSpeechActivity: ((SpeechActivityEvent) -> Unit)? = null
    override var onAudioBuffer: ((ByteArray) -> Unit)? = null

    override val isReady: Boolean
        get() = coreService.isInitialized && coreService.isVADModelLoaded

    override val configuration: VADConfiguration
        get() = initialConfiguration

    override suspend fun initialize(configuration: VADConfiguration) {
        energyThreshold = configuration.energyThreshold
        // Load VAD model if path provided through model ID
        configuration.modelId?.let { modelId ->
            coreService.loadVADModel(modelId)
        }
    }

    override fun start() {
        // ONNX VAD doesn't require explicit start
    }

    override fun stop() {
        // ONNX VAD doesn't require explicit stop
    }

    override fun reset() {
        isSpeechActive = false
    }

    override fun processAudioChunk(audioSamples: FloatArray): VADResult {
        // Use runBlocking since processVAD is suspend but this isn't
        val result = runBlocking(kotlinx.coroutines.Dispatchers.Default) { coreService.processVAD(audioSamples, sampleRate) }
        val wasActive = isSpeechActive
        isSpeechActive = result.isSpeech

        // Fire callbacks on state change
        if (isSpeechActive && !wasActive) {
            onSpeechActivity?.invoke(SpeechActivityEvent.STARTED)
        } else if (!isSpeechActive && wasActive) {
            onSpeechActivity?.invoke(SpeechActivityEvent.ENDED)
        }

        return VADResult(
            isSpeechDetected = result.isSpeech,
            confidence = result.probability
        )
    }

    override fun processAudioData(audioData: FloatArray): Boolean {
        return processAudioChunk(audioData).isSpeechDetected
    }

    override suspend fun cleanup() {
        coreService.unloadVADModel()
    }
}

// MARK: - Helper Functions

/**
 * Detect STT model type from path
 */
private fun detectSTTModelType(modelPath: String): String {
    val lowercased = modelPath.lowercase()
    return when {
        lowercased.contains("zipformer") -> "zipformer"
        lowercased.contains("whisper") -> "whisper"
        lowercased.contains("paraformer") -> "paraformer"
        lowercased.contains("sherpa") -> "zipformer" // Default for sherpa-onnx
        else -> "zipformer" // Default
    }
}

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

/**
 * Convert float samples to WAV byte array
 */
private fun convertToWav(samples: FloatArray, sampleRate: Int): ByteArray {
    val numSamples = samples.size
    val numChannels = 1
    val bitsPerSample = 16
    val byteRate = sampleRate * numChannels * bitsPerSample / 8
    val blockAlign = numChannels * bitsPerSample / 8
    val dataSize = numSamples * blockAlign
    val fileSize = 36 + dataSize

    val buffer = ByteArray(44 + dataSize)
    var offset = 0

    // RIFF header
    "RIFF".toByteArray().copyInto(buffer, offset); offset += 4
    writeInt32LE(buffer, offset, fileSize); offset += 4
    "WAVE".toByteArray().copyInto(buffer, offset); offset += 4

    // fmt chunk
    "fmt ".toByteArray().copyInto(buffer, offset); offset += 4
    writeInt32LE(buffer, offset, 16); offset += 4  // Chunk size
    writeInt16LE(buffer, offset, 1); offset += 2   // PCM format
    writeInt16LE(buffer, offset, numChannels); offset += 2
    writeInt32LE(buffer, offset, sampleRate); offset += 4
    writeInt32LE(buffer, offset, byteRate); offset += 4
    writeInt16LE(buffer, offset, blockAlign); offset += 2
    writeInt16LE(buffer, offset, bitsPerSample); offset += 2

    // data chunk
    "data".toByteArray().copyInto(buffer, offset); offset += 4
    writeInt32LE(buffer, offset, dataSize); offset += 4

    // Write samples
    for (sample in samples) {
        val intSample = (sample * 32767).toInt().coerceIn(-32768, 32767)
        writeInt16LE(buffer, offset, intSample)
        offset += 2
    }

    return buffer
}

private fun writeInt16LE(buffer: ByteArray, offset: Int, value: Int) {
    buffer[offset] = (value and 0xFF).toByte()
    buffer[offset + 1] = ((value shr 8) and 0xFF).toByte()
}

private fun writeInt32LE(buffer: ByteArray, offset: Int, value: Int) {
    buffer[offset] = (value and 0xFF).toByte()
    buffer[offset + 1] = ((value shr 8) and 0xFF).toByte()
    buffer[offset + 2] = ((value shr 16) and 0xFF).toByte()
    buffer[offset + 3] = ((value shr 24) and 0xFF).toByte()
}
