package com.runanywhere.sdk.core.onnx

import com.runanywhere.sdk.core.AudioUtils
import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.features.stt.STTConfiguration
import com.runanywhere.sdk.features.stt.STTOptions
import com.runanywhere.sdk.features.stt.STTService
import com.runanywhere.sdk.features.stt.STTTranscriptionResult
import com.runanywhere.sdk.features.tts.TTSConfiguration
import com.runanywhere.sdk.features.tts.TTSOptions
import com.runanywhere.sdk.features.tts.TTSService
import com.runanywhere.sdk.features.vad.SpeechActivityEvent
import com.runanywhere.sdk.features.vad.VADConfiguration
import com.runanywhere.sdk.features.vad.VADResult
import com.runanywhere.sdk.features.vad.VADService
import com.runanywhere.sdk.features.vad.VADStatistics
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.models.enums.InferenceFramework
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

private val logger = SDKLogger("ONNXServices")

// JSON parser for native results
private val jsonParser =
    Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

@Serializable
private data class NativeSTTResult(
    val text: String = "",
    val confidence: Double = 0.0,
    val detected_language: String = "",
    val audio_duration_ms: Double = 0.0,
    val inference_time_ms: Double = 0.0,
    val is_final: Boolean = true,
)

// =============================================================================
// MARK: - Service Creation Functions (actual implementations for expect)
// =============================================================================

internal actual suspend fun createONNXSTTService(configuration: STTConfiguration): STTService {
    logger.info("Creating ONNX STT service: ${configuration.modelId}")

    val service = ONNXCoreService()
    service.initialize()

    // Resolve and load model using storage strategy pattern
    configuration.modelId?.let { modelId ->
        val registryPath = getRegistryPath(modelId)
        logger.info("Registry path for STT: $registryPath")

        // Use storage strategy to find actual model path (handles nested directories)
        val modelPath = resolveModelPath(modelId, registryPath)

        logger.info("Resolved STT model path: $modelPath")

        if (!modelPath.isNullOrEmpty()) {
            validateModelPath(modelPath, "STT")
            val modelType = detectSTTModelType(modelPath)
            service.loadSTTModel(modelPath, modelType)
            logger.info("STT model loaded: $modelPath (type: $modelType)")
        }
    }

    return ONNXSTTService(service).also { sttService ->
        configuration.modelId?.let { modelId ->
            val registryPath = getRegistryPath(modelId)
            val resolvedPath = resolveModelPath(modelId, registryPath)
            resolvedPath?.let { sttService.setModelPath(it) }
        }
    }
}

internal actual suspend fun createONNXTTSService(configuration: TTSConfiguration): TTSService {
    logger.info("Creating ONNX TTS service: ${configuration.modelId}")

    val service = ONNXCoreService()
    service.initialize()

    // Resolve and load model using storage strategy pattern
    configuration.modelId?.let { modelId ->
        val registryPath = getRegistryPath(modelId)
        logger.info("Registry path for TTS: $registryPath")

        // Use storage strategy to find actual model path (handles nested directories)
        val modelPath = resolveModelPath(modelId, registryPath)

        logger.info("Resolved TTS model path: $modelPath")

        if (!modelPath.isNullOrEmpty()) {
            validateModelPath(modelPath, "TTS")
            val modelType = detectTTSModelType(modelPath)
            service.loadTTSModel(modelPath, modelType)
            logger.info("TTS model loaded: $modelPath (type: $modelType)")
        }
    }

    return ONNXTTSService(configuration, service)
}

internal actual suspend fun createONNXVADService(configuration: VADConfiguration): VADService {
    logger.info("Creating ONNX VAD service")

    val service = ONNXCoreService()
    service.initialize()

    configuration.modelId?.let { modelId ->
        service.loadVADModel(modelId)
    }

    return ONNXVADService(service, configuration)
}

// =============================================================================
// MARK: - ONNX STT Service
// =============================================================================

internal class ONNXSTTService(
    private val coreService: ONNXCoreService,
) : STTService {
    private val sttLogger = SDKLogger("ONNXSTTService")
    private var modelPath: String? = null

    override val isReady: Boolean
        get() = coreService.isInitialized && coreService.isSTTModelLoaded

    override val currentModel: String?
        get() = modelPath?.substringAfterLast("/")?.substringBeforeLast(".")

    override val supportsStreaming: Boolean
        get() = coreService.supportsSTTStreaming

    override suspend fun initialize(modelPath: String?) {
        modelPath?.let { path ->
            val modelType = detectSTTModelType(path)
            coreService.loadSTTModel(path, modelType)
            this.modelPath = path
            sttLogger.info("STT model loaded: $path")
        }
    }

    override suspend fun transcribe(audioData: ByteArray, options: STTOptions): STTTranscriptionResult {
        if (!isReady) {
            throw IllegalStateException("STT service not ready - model not loaded")
        }

        val samples = AudioUtils.pcmBytesToFloatSamples(audioData)
        val jsonResult = coreService.transcribe(samples, options.sampleRate, options.language)
        return parseSTTResult(jsonResult)
    }

    override suspend fun streamTranscribe(
        audioStream: Flow<ByteArray>,
        options: STTOptions,
        onPartial: (String) -> Unit,
    ): STTTranscriptionResult {
        // Collect all audio and transcribe in batch (streaming not fully implemented)
        val allAudio = mutableListOf<Byte>()
        audioStream.collect { chunk ->
            allAudio.addAll(chunk.toList())
        }
        return transcribe(allAudio.toByteArray(), options)
    }

    override suspend fun cleanup() {
        if (coreService.isSTTModelLoaded) {
            coreService.unloadSTTModel()
        }
        coreService.destroy()
    }

    fun setModelPath(path: String) {
        this.modelPath = path
    }

    private fun parseSTTResult(jsonResult: String): STTTranscriptionResult {
        return try {
            val result = jsonParser.decodeFromString<NativeSTTResult>(jsonResult)
            STTTranscriptionResult(
                transcript = result.text.trim(),
                confidence = result.confidence.toFloat(),
                language = result.detected_language.ifEmpty { null },
            )
        } catch (e: Exception) {
            STTTranscriptionResult(transcript = jsonResult.trim(), confidence = 1.0f, language = null)
        }
    }
}

// =============================================================================
// MARK: - ONNX TTS Service
// =============================================================================

internal class ONNXTTSService(
    private val configuration: TTSConfiguration,
    private var coreService: ONNXCoreService? = null,
) : TTSService {
    private val ttsLogger = SDKLogger("ONNXTTSService")
    private var loadedModelPath: String? = null
    private var _isSynthesizing = false

    init {
        // If service was pre-initialized with a model, track the loaded path
        if (coreService?.isTTSModelLoaded == true) {
            loadedModelPath = resolveModelPathForVoice(configuration.modelId)
        }
    }

    override val inferenceFramework: String = "ONNX Runtime"
    override val isSynthesizing: Boolean get() = _isSynthesizing
    override val availableVoices: List<String> = emptyList()

    override suspend fun initialize() {
        if (coreService != null) {
            ttsLogger.info("ONNX TTS service already initialized")
            return
        }
        ttsLogger.info("Initializing ONNX TTS service")
        val service = ONNXCoreService()
        service.initialize()
        coreService = service
        ttsLogger.info("ONNX TTS service initialized")
    }

    override suspend fun synthesize(text: String, options: TTSOptions): ByteArray {
        if (coreService == null) {
            initialize()
        }

        val service = coreService ?: throw IllegalStateException("TTS service not initialized")

        _isSynthesizing = true
        try {
            val modelPath =
                resolveModelPathForVoice(options.voice ?: configuration.modelId)
                    ?: throw IllegalStateException("No TTS model path provided")

            // Load model if needed (should already be loaded by createONNXTTSService)
            if (loadedModelPath != modelPath || !service.isTTSModelLoaded) {
                ttsLogger.info("Loading TTS model: $modelPath")
                validateModelPath(modelPath, "TTS")
                val modelType = detectTTSModelType(modelPath)
                service.loadTTSModel(modelPath, modelType)
                loadedModelPath = modelPath
            }

            val result =
                service.synthesize(
                    text = text,
                    voiceId = "0",
                    speedRate = options.rate,
                    pitchShift = options.pitch,
                )

            ttsLogger.info("Synthesized ${result.samples.size} samples at ${result.sampleRate} Hz")
            return AudioUtils.floatSamplesToWav(result.samples, result.sampleRate)
        } finally {
            _isSynthesizing = false
        }
    }

    override fun synthesizeStream(text: String, options: TTSOptions): Flow<ByteArray> =
        flow {
            val audio = synthesize(text, options)
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
            if (service.isTTSModelLoaded) service.unloadTTSModel()
            service.destroy()
        }
        coreService = null
        loadedModelPath = null
    }

    private fun resolveModelPathForVoice(voice: String?): String? {
        if (voice.isNullOrEmpty()) return null
        val registryPath = getRegistryPath(voice)
        return resolveModelPath(voice, registryPath)
    }
}

// =============================================================================
// MARK: - ONNX VAD Service
// =============================================================================

internal class ONNXVADService(
    private val coreService: ONNXCoreService,
    private val initialConfiguration: VADConfiguration,
) : VADService {
    @Suppress("UnusedPrivateProperty")
    private val vadLogger = SDKLogger("ONNXVADService")

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

    // TTS feedback prevention
    override var isTTSActive: Boolean = false
        private set
    private var baseEnergyThreshold: Float = 0.0f
    private var ttsThresholdMultiplier: Float = 3.0f

    // Statistics
    private val recentConfidenceValues = mutableListOf<Float>()
    private val maxRecentValues = 20

    override suspend fun initialize(configuration: VADConfiguration) {
        energyThreshold = configuration.energyThreshold
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
        recentConfidenceValues.clear()
    }

    override fun processAudioChunk(audioSamples: FloatArray): VADResult {
        if (isTTSActive) {
            return VADResult(isSpeechDetected = false, confidence = 0.0f)
        }

        val result =
            runBlocking(Dispatchers.Default) {
                coreService.processVAD(audioSamples, sampleRate)
            }

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

        return VADResult(isSpeechDetected = result.isSpeech, confidence = result.probability)
    }

    override fun processAudioData(audioData: FloatArray): Boolean {
        return processAudioChunk(audioData).isSpeechDetected
    }

    override suspend fun cleanup() {
        coreService.unloadVADModel()
    }

    // TTS Feedback Prevention
    override fun notifyTTSWillStart() {
        isTTSActive = true
        baseEnergyThreshold = energyThreshold
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

    override suspend fun startCalibration(): Boolean {
        return false // ONNX VAD uses pre-trained models
    }

    override fun getStatistics(): VADStatistics {
        val recent =
            if (recentConfidenceValues.isEmpty()) {
                0.0f
            } else {
                recentConfidenceValues.sum() / recentConfidenceValues.size
            }

        return VADStatistics(
            current = recentConfidenceValues.lastOrNull() ?: 0.0f,
            threshold = energyThreshold,
            ambient = 0.0f,
            recentAvg = recent,
            recentMax = recentConfidenceValues.maxOrNull() ?: 0.0f,
        )
    }
}

// =============================================================================
// MARK: - Helper Functions (Path Resolution via Storage Strategy)
// =============================================================================

/**
 * Get the registry path for a model ID.
 * If modelId contains "/" it's already a path, otherwise look up in registry.
 */
private fun getRegistryPath(modelId: String): String? {
    return if (modelId.contains("/")) {
        modelId
    } else {
        ServiceContainer.shared.modelRegistry
            .getModel(modelId)
            ?.localPath
    }
}

/**
 * Resolve the actual model path using the ONNX storage strategy.
 * This handles nested directories from archive extraction.
 *
 * Uses ModuleRegistry.storageStrategy(ONNX).findModelPath() which is implemented
 * by ONNXDownloadStrategy and calls findONNXModelPath() for nested directory handling.
 */
private fun resolveModelPath(
    modelId: String,
    registryPath: String?,
): String? {
    if (registryPath.isNullOrEmpty()) return null

    // Use the ONNX storage strategy to find the actual model path
    val storageStrategy = ModuleRegistry.storageStrategy(InferenceFramework.ONNX)
    if (storageStrategy != null) {
        val resolved = storageStrategy.findModelPath(modelId, registryPath)
        if (resolved != null) {
            return resolved
        }
    }

    // Fallback: use findONNXModelPath directly (for cases where module not yet registered)
    return findONNXModelPath(modelId, registryPath) ?: registryPath
}

// =============================================================================
// MARK: - ONNX-Specific Model Type Detection
// =============================================================================

private fun detectSTTModelType(modelPath: String): String {
    val lowercased = modelPath.lowercase()
    return when {
        lowercased.contains("zipformer") -> "zipformer"
        lowercased.contains("whisper") -> "whisper"
        lowercased.contains("paraformer") -> "paraformer"
        lowercased.contains("sherpa") && !lowercased.contains("whisper") -> "zipformer"
        else -> "zipformer"
    }
}

private fun detectTTSModelType(modelPath: String): String {
    val lowercased = modelPath.lowercase()
    return when {
        lowercased.contains("vits") || lowercased.contains("piper") -> "vits"
        lowercased.contains("matcha") -> "matcha"
        lowercased.contains("kokoro") -> "kokoro"
        else -> "vits"
    }
}

// =============================================================================
// MARK: - ONNX-Specific Validation
// =============================================================================

/**
 * Validates that a model path exists and contains expected ONNX model files.
 * Throws a detailed exception if validation fails.
 */
private fun validateModelPath(
    modelPath: String,
    modelType: String,
) {
    val file = java.io.File(modelPath)
    if (!file.exists()) {
        throw IllegalStateException(
            "$modelType model path does not exist: $modelPath. " +
                "Please ensure the model is downloaded and extracted correctly.",
        )
    }

    if (file.isDirectory) {
        val files = file.listFiles()
        if (files.isNullOrEmpty()) {
            throw IllegalStateException(
                "$modelType model directory is empty: $modelPath. " +
                    "The model may not have been extracted correctly.",
            )
        }
        // Check for ONNX-specific model files
        val hasOnnxFiles = files.any { it.extension.lowercase() == "onnx" }
        val hasTokensFile = files.any { it.name.contains("tokens") }
        if (!hasOnnxFiles && !hasTokensFile) {
            val fileNames = files.take(10).joinToString(", ") { it.name }
            logger.warning(
                "$modelType model directory may be incomplete: $modelPath. " +
                    "Found files: $fileNames",
            )
        }
    }
}
