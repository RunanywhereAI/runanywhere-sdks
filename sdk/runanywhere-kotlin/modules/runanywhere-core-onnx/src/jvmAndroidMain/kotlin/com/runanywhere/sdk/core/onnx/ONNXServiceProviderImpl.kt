package com.runanywhere.sdk.core.onnx

import com.runanywhere.sdk.features.tts.TTSOptions
import com.runanywhere.sdk.features.stt.STTConfiguration
import com.runanywhere.sdk.features.stt.STTOptions
import com.runanywhere.sdk.features.stt.STTService
import com.runanywhere.sdk.features.stt.STTStreamEvent
import com.runanywhere.sdk.features.stt.STTStreamingOptions
import com.runanywhere.sdk.features.stt.STTTranscriptionResult
import com.runanywhere.sdk.features.vad.VADConfiguration
import com.runanywhere.sdk.features.vad.VADResult
import com.runanywhere.sdk.features.vad.VADService
import com.runanywhere.sdk.features.vad.VADStatistics
import com.runanywhere.sdk.features.vad.SpeechActivityEvent
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.utils.PlatformUtils
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.util.UUID

private val logger = SDKLogger("ONNXServiceProviderImpl")

// Module-level telemetry scope for fire-and-forget telemetry operations (avoids GlobalScope)
// Uses SupervisorJob to prevent failures from affecting other telemetry operations
private val telemetryScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

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

/**
 * JVM/Android implementation of ONNX TTS service creation
 * Follows the same pattern as LLM/STT service providers
 */
actual suspend fun createONNXTTSService(
    configuration: com.runanywhere.sdk.features.tts.TTSConfiguration
): com.runanywhere.sdk.features.tts.TTSService {
    logger.info("Creating ONNX TTS service with configuration: ${configuration.voice}")
    return ONNXTTSServiceImpl(configuration)
}

/**
 * ONNX TTS Service Implementation
 * Implements TTSService interface following the same pattern as LLM/STT services
 */
private class ONNXTTSServiceImpl(
    private val configuration: com.runanywhere.sdk.features.tts.TTSConfiguration
) : com.runanywhere.sdk.features.tts.TTSService {
    private val implLogger = SDKLogger("ONNXTTSServiceImpl")
    private var coreService: ONNXCoreService? = null
    private var _isInitialized = false
    private var _isSynthesizing = false
    private var loadedModelPath: String? = null

    override val inferenceFramework: String = "ONNX Runtime"
    override val isSynthesizing: Boolean get() = _isSynthesizing
    override val availableVoices: List<String> = emptyList()

    override suspend fun initialize() {
        implLogger.info("Initializing ONNX TTS service")
        val service = ONNXCoreService()
        service.initialize()
        coreService = service
        _isInitialized = true
        implLogger.info("✅ ONNX TTS service initialized")
    }

    override suspend fun synthesize(
        text: String,
        options: com.runanywhere.sdk.features.tts.TTSOptions
    ): ByteArray {
        if (!_isInitialized) {
            initialize()
        }

        val service = coreService
            ?: throw IllegalStateException("TTS service not initialized")

        _isSynthesizing = true
        try {
            // Resolve model path from options.voice or configuration.voice
            val voice = options.voice ?: configuration.voice
            val modelPath = resolveModelPath(voice)

            if (modelPath.isNullOrEmpty()) {
                throw IllegalStateException("No TTS model path provided. Please select a TTS model first.")
            }

            // Load model if not already loaded or if path changed
            if (loadedModelPath != modelPath) {
                implLogger.info("Loading TTS model from: $modelPath")
                service.loadTTSModel(modelPath, "vits")
                loadedModelPath = modelPath
            }

            // Synthesize
            val result = service.synthesize(
                text = text,
                voiceId = "0",
                speedRate = options.rate,
                pitchShift = options.pitch
            )

            implLogger.info("Synthesized ${result.samples.size} samples at ${result.sampleRate} Hz")

            return convertToWav(result.samples, result.sampleRate)
        } finally {
            _isSynthesizing = false
        }
    }

    override fun synthesizeStream(
        text: String,
        options: com.runanywhere.sdk.features.tts.TTSOptions
    ): Flow<ByteArray> = flow {
        val audio = synthesize(text, options)
        // Split into chunks for streaming delivery
        val chunkSize = options.sampleRate * 2
        var offset = 0
        while (offset < audio.size) {
            val end = minOf(offset + chunkSize, audio.size)
            emit(audio.copyOfRange(offset, end))
            offset = end
        }
    }

    override fun stop() {
        _isSynthesizing = false
    }

    override suspend fun cleanup() {
        coreService?.let { service ->
            if (service.isTTSModelLoaded) {
                service.unloadTTSModel()
            }
            service.destroy()
        }
        coreService = null
        _isInitialized = false
        loadedModelPath = null
    }

    private fun resolveModelPath(voice: String?): String? {
        return when {
            voice.isNullOrEmpty() -> null
            voice.contains("/") -> voice // Already a full path
            else -> {
                // Model ID - look up the full path from the model registry
                val modelInfo = ServiceContainer.shared.modelRegistry.getModel(voice)
                modelInfo?.localPath ?: voice
            }
        }
    }
}

// Cached ONNX TTS service for reuse (thread-safe access via Mutex)
@Volatile
private var cachedTTSCoreService: ONNXCoreService? = null
@Volatile
private var cachedTTSModelPath: String? = null
private val ttsCacheMutex = Mutex()  // Mutex for thread-safe cache access with suspend support

/**
 * JVM/Android implementation of ONNX TTS synthesis (legacy support)
 * Kept for backwards compatibility with direct synthesis calls
 */
@OptIn(DelicateCoroutinesApi::class)
private suspend fun synthesizeWithONNXInternal(text: String, options: com.runanywhere.sdk.features.tts.TTSOptions): ByteArray {
    logger.info("Synthesizing with ONNX: ${text.take(50)}...")

    // Resolve model path from options.voice
    // options.voice may contain either:
    // 1. A full filesystem path (e.g., /data/user/0/.../model.onnx)
    // 2. A model ID that needs to be resolved to a path (e.g., "piper-en-us-lessac-medium")
    val voice = options.voice
    val modelPath: String? = when {
        voice.isNullOrEmpty() -> null
        voice.contains("/") -> {
            // Already a full path
            logger.debug("Using voice as direct path: $voice")
            voice
        }
        else -> {
            // Model ID - look up the full path from the model registry
            logger.info("Resolving model ID to path: $voice")
            val modelInfo = ServiceContainer.shared.modelRegistry.getModel(voice)
            val resolvedPath = modelInfo?.localPath
            if (resolvedPath != null) {
                logger.info("Resolved model path: $resolvedPath")
            } else {
                logger.warn("Could not resolve model ID '$voice' to a path - model may not be downloaded")
            }
            resolvedPath ?: voice
        }
    }

    if (modelPath.isNullOrEmpty()) {
        logger.error("No TTS model path provided in options.voice")
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
    telemetryScope.launch {
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

    // Thread-safe access to cached service to prevent race conditions
    // Using Mutex.withLock instead of synchronized to support suspend functions
    val service: ONNXCoreService = ttsCacheMutex.withLock {
        val cached = cachedTTSCoreService
        if (cached != null && cachedTTSModelPath == modelPath) {
            logger.debug("Reusing cached TTS service")
            cached
        } else {
            // Create and initialize new service
            logger.info("Creating new ONNX TTS service...")
            val newService = ONNXCoreService()
            newService.initialize()

            // Load the TTS model
            logger.info("Loading TTS model from: $modelPath")
            newService.loadTTSModel(modelPath, "vits")
            logger.info("TTS model loaded successfully")

            // Cache for reuse
            cachedTTSCoreService = newService
            cachedTTSModelPath = modelPath
            newService
        }
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

        telemetryScope.launch {
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
    telemetryScope.launch {
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

    // Kotlin-specific: supported languages for this implementation
    val supportedLanguages: List<String> = listOf("en", "es", "fr", "de", "it", "pt", "zh", "ja", "ko")

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

    // Kotlin-specific: Enhanced streaming with typed events
    fun transcribeStream(
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

    // Kotlin-specific: Language detection
    suspend fun detectLanguage(audioData: ByteArray): Map<String, Float> {
        // ONNX doesn't support standalone language detection - return default
        return mapOf("en" to 1.0f)
    }

    // Kotlin-specific: Language support check
    fun supportsLanguage(languageCode: String): Boolean {
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
            voiceId = options.voice ?: "0",
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

    // TTS feedback prevention (matching iOS)
    override var isTTSActive: Boolean = false
        private set
    private var baseEnergyThreshold: Float = 0.0f
    private var ttsThresholdMultiplier: Float = 3.0f

    // Debug statistics tracking
    private val recentConfidenceValues = mutableListOf<Float>()
    private val maxRecentValues = 20

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
        // Block all processing during TTS (matching iOS TTS feedback prevention)
        if (isTTSActive) {
            return VADResult(isSpeechDetected = false, confidence = 0.0f)
        }

        // Use runBlocking since processVAD is suspend but this isn't
        val result = runBlocking(kotlinx.coroutines.Dispatchers.Default) { coreService.processVAD(audioSamples, sampleRate) }
        val wasActive = isSpeechActive
        isSpeechActive = result.isSpeech

        // Track for statistics
        recentConfidenceValues.add(result.probability)
        if (recentConfidenceValues.size > maxRecentValues) {
            recentConfidenceValues.removeAt(0)
        }

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

    // =========================================================================
    // MARK: - TTS Feedback Prevention (matching iOS VADService protocol)
    // =========================================================================

    override fun notifyTTSWillStart() {
        isTTSActive = true
        baseEnergyThreshold = energyThreshold

        // End any current speech detection
        if (isSpeechActive) {
            isSpeechActive = false
            onSpeechActivity?.invoke(SpeechActivityEvent.ENDED)
        }
    }

    override fun notifyTTSDidFinish() {
        isTTSActive = false
        energyThreshold = baseEnergyThreshold
        recentConfidenceValues.clear()
        isSpeechActive = false
    }

    override fun setTTSThresholdMultiplier(multiplier: Float) {
        ttsThresholdMultiplier = multiplier.coerceIn(2.0f, 5.0f)
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
        // ONNX VAD uses pre-trained models and doesn't support runtime calibration
        return false
    }

    // =========================================================================
    // MARK: - Debug Statistics (matching iOS getStatistics)
    // =========================================================================

    override fun getStatistics(): VADStatistics {
        val recent = if (recentConfidenceValues.isEmpty()) 0.0f
                     else recentConfidenceValues.sum() / recentConfidenceValues.size
        val maxValue = recentConfidenceValues.maxOrNull() ?: 0.0f

        return VADStatistics(
            current = recentConfidenceValues.lastOrNull() ?: 0.0f,
            threshold = energyThreshold,
            ambient = 0.0f, // ONNX VAD doesn't track ambient
            recentAvg = recent,
            recentMax = maxValue
        )
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
