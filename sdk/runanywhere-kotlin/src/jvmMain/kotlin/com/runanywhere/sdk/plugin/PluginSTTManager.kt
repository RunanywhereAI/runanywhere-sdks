package com.runanywhere.sdk.plugin

import com.runanywhere.sdk.components.stt.*
import com.runanywhere.sdk.components.vad.*
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.services.ValidationService
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlin.coroutines.CoroutineContext

/**
 * Simple STT Manager designed specifically for JetBrains plugin integration
 *
 * Usage in JetBrains Plugin:
 * ```kotlin
 * // Initialize once in plugin
 * PluginSTTManager.initialize("your-api-key")
 *
 * // Process audio data when available
 * PluginSTTManager.processAudio(audioBytes) { result ->
 *     println("STT Result: ${result.text}")
 * }
 * ```
 */
object PluginSTTManager : CoroutineScope {
    private val logger = SDKLogger("PluginSTTManager")
    private val job = SupervisorJob()

    override val coroutineContext: CoroutineContext
        get() = Dispatchers.Default + job

    // State management
    private var isInitialized = false
    private var isProcessing = false

    // Components
    private lateinit var sttComponent: STTComponent
    private lateinit var vadComponent: VADComponent
    private lateinit var serviceContainer: ServiceContainer

    // Events
    private val _statusEvents = MutableSharedFlow<STTStatus>()
    val statusEvents: SharedFlow<STTStatus> = _statusEvents.asSharedFlow()

    /**
     * STT Status events for the plugin
     */
    sealed class STTStatus {
        object Initializing : STTStatus()
        object Ready : STTStatus()
        object DownloadingModel : STTStatus()
        data class DownloadProgress(val progress: Float) : STTStatus()
        object Processing : STTStatus()
        data class Result(val text: String, val confidence: Float = 0.95f) : STTStatus()
        data class Error(val message: String, val exception: Throwable? = null) : STTStatus()
    }

    /**
     * Simple callback interface for STT results
     */
    fun interface STTResultCallback {
        fun onResult(result: STTResult)
    }

    /**
     * STT Result data class
     */
    data class STTResult(
        val text: String,
        val confidence: Float = 0.95f,
        val processingTimeMs: Long = 0,
        val audioLengthMs: Long = 0
    )

    /**
     * Initialize the STT manager - call once during plugin initialization
     */
    suspend fun initialize(
        apiKey: String,
        environment: SDKEnvironment = SDKEnvironment.DEVELOPMENT
    ) {
        if (isInitialized) {
            logger.info("PluginSTTManager already initialized")
            return
        }

        try {
            _statusEvents.emit(STTStatus.Initializing)
            logger.info("Initializing PluginSTTManager")

            // Initialize the main SDK
            RunAnywhere.initialize(apiKey, environment = environment)

            // Get service container
            serviceContainer = ServiceContainer.shared

            // Initialize STT component with default configuration
            val sttConfig = STTConfiguration()
            sttComponent = STTComponent(sttConfig)

            // Initialize VAD component
            val vadConfig = VADConfiguration()
            vadComponent = VADComponent(vadConfig)

            // Ensure we have a model available
            ensureModelAvailable()

            isInitialized = true
            _statusEvents.emit(STTStatus.Ready)
            logger.info("PluginSTTManager initialized successfully")

        } catch (e: Exception) {
            logger.error("Failed to initialize PluginSTTManager", e)
            _statusEvents.emit(STTStatus.Error("Initialization failed: ${e.message}", e))
            throw e
        }
    }

    /**
     * Process audio data for STT - this is the main API for plugins to use
     */
    suspend fun processAudio(audioData: ByteArray, callback: STTResultCallback) {
        if (!isInitialized) {
            throw IllegalStateException("PluginSTTManager not initialized. Call initialize() first")
        }

        if (isProcessing) {
            logger.warn("Already processing audio. Wait for current processing to finish.")
            return
        }

        try {
            _statusEvents.emit(STTStatus.Processing)
            isProcessing = true

            logger.info("Starting STT processing for ${audioData.size} bytes")

            // Process audio
            val processingStartTime = System.currentTimeMillis()
            val transcriptionResult = sttComponent.transcribe(audioData)
            val processingTime = System.currentTimeMillis() - processingStartTime

            logger.info("STT processing completed in ${processingTime}ms")

            val result = STTResult(
                text = transcriptionResult.text,
                confidence = transcriptionResult.confidence,
                processingTimeMs = processingTime,
                audioLengthMs = (audioData.size / 32).toLong() // Rough estimate assuming 16kHz 16-bit
            )

            _statusEvents.emit(STTStatus.Result(result.text, result.confidence))
            callback.onResult(result)

        } catch (e: Exception) {
            logger.error("Error during STT processing", e)
            _statusEvents.emit(STTStatus.Error("Processing failed: ${e.message}", e))
            throw e
        } finally {
            isProcessing = false
        }
    }

    /**
     * Check if system is ready
     */
    fun isReady(): Boolean = isInitialized

    /**
     * Check if currently processing
     */
    fun isProcessing(): Boolean = isProcessing

    /**
     * Get available models
     */
    suspend fun getAvailableModels(): List<ModelInfo> {
        if (!isInitialized) {
            throw IllegalStateException("PluginSTTManager not initialized")
        }

        return RunAnywhere.availableModels()
    }

    /**
     * Cleanup resources - call when plugin is unloaded
     */
    suspend fun cleanup() {
        logger.info("Cleaning up PluginSTTManager")

        if (isInitialized) {
            sttComponent.cleanup()
            vadComponent.cleanup()
            RunAnywhere.cleanup()
        }

        job.cancel()
        isInitialized = false

        logger.info("PluginSTTManager cleanup completed")
    }

    // Private implementation methods

    /**
     * Ensure we have a Whisper model available for STT
     */
    private suspend fun ensureModelAvailable() {
        val models = RunAnywhere.availableModels()
        val whisperModel = models.firstOrNull {
            it.name.contains("whisper", ignoreCase = true) ||
            it.id.contains("whisper", ignoreCase = true) ||
            it.category.name.contains("SPEECH", ignoreCase = true)
        }

        if (whisperModel != null) {
            logger.info("Found Whisper model: ${whisperModel.name} (${whisperModel.id})")

            // Check if model needs to be downloaded
            val modelDownloader = RunAnywhere.getModelDownloader()
            if (!modelDownloader.isModelDownloaded(whisperModel)) {
                logger.info("Downloading model: ${whisperModel.id}")
                _statusEvents.emit(STTStatus.DownloadingModel)

                try {
                    // Download the model with progress tracking
                    val modelPath = modelDownloader.downloadModel(whisperModel) { progress ->
                        launch {
                            _statusEvents.emit(STTStatus.DownloadProgress(progress))
                            logger.debug("Download progress: ${(progress * 100).toInt()}%")
                        }
                    }

                    logger.info("Model download completed: $modelPath")

                    // Validate the downloaded model
                    val validationResult = serviceContainer.validationService.validateModel(whisperModel, modelPath)
                    if (!validationResult.isValid) {
                        throw IllegalStateException("Model validation failed: ${(validationResult as ValidationService.ValidationResult.Invalid).reason}")
                    }

                    logger.info("Model validation successful")

                } catch (e: Exception) {
                    logger.error("Model download failed", e)
                    throw IllegalStateException("Failed to download model ${whisperModel.id}: ${e.message}")
                }
            } else {
                logger.info("Model already downloaded: ${whisperModel.id}")
            }

            // Initialize STT component with the model
            val modelPath = modelDownloader.getModelPath(whisperModel)
            if (modelPath != null) {
                // Initialize the STT service with the model path
                if (!sttComponent.isInitialized()) {
                    sttComponent.initialize()
                }

                logger.info("STT component initialized with model: ${whisperModel.name}")

                // Verify component is ready
                if (!sttComponent.isReady) {
                    throw IllegalStateException("STT component failed to initialize properly")
                }
            } else {
                throw IllegalStateException("Model path is null after download")
            }
        } else {
            throw IllegalStateException("No Whisper model found. Available models: ${models.map { "${it.name} (${it.category})" }}")
        }
    }
}
