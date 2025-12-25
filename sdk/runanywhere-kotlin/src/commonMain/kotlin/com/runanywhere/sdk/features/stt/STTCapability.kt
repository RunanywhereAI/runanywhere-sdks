package com.runanywhere.sdk.features.stt

import com.runanywhere.sdk.core.AudioFormat
import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.core.capabilities.CapabilityError
import com.runanywhere.sdk.core.capabilities.CapabilityResourceType
import com.runanywhere.sdk.core.capabilities.ManagedLifecycle
import com.runanywhere.sdk.core.capabilities.ModelLifecycleManager
import com.runanywhere.sdk.core.capabilities.ModelLoadableCapability
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.models.enums.InferenceFramework
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * STT Capability - Actor-like class for Speech-to-Text operations
 *
 * Aligned EXACTLY with iOS STTCapability pattern:
 * - Uses ManagedLifecycle<STTService> directly for model lifecycle
 * - No intermediate Component layer
 * - Model lifecycle management (loadModel, unload, isModelLoaded, cleanup)
 * - Transcription API (transcribe, streamTranscribe)
 * - Analytics API (getAnalyticsMetrics)
 * - Streaming support detection (supportsStreaming)
 * - Event tracking via STTAnalyticsService
 */
class STTCapability internal constructor(
    private val analyticsService: STTAnalyticsService = STTAnalyticsService(),
) : ModelLoadableCapability<STTConfiguration, STTService> {
    private val logger = SDKLogger("STTCapability")

    // Managed lifecycle with integrated event tracking (matches iOS)
    private val managedLifecycle: ManagedLifecycle<STTService> = createSTTManagedLifecycle()

    // Current configuration
    private var config: STTConfiguration? = null

    // ============================================================================
    // MARK: - Configuration (Capability Protocol)
    // ============================================================================

    override fun configure(config: STTConfiguration) {
        this.config = config
    }

    // ============================================================================
    // MARK: - Model Lifecycle (ModelLoadableCapability Protocol)
    // ============================================================================

    /**
     * Whether a model is currently loaded
     */
    override val isModelLoaded: Boolean
        get() = runCatching { kotlinx.coroutines.runBlocking { managedLifecycle.isLoaded() } }.getOrElse { false }

    /**
     * Get the currently loaded model ID
     */
    override val currentModelId: String?
        get() = runCatching { kotlinx.coroutines.runBlocking { managedLifecycle.currentResourceId() } }.getOrNull()

    /**
     * Whether the underlying STT service supports live/streaming transcription.
     * Matches iOS STTCapability.supportsStreaming property.
     */
    val supportsStreaming: Boolean
        get() = runCatching {
            kotlinx.coroutines.runBlocking {
                managedLifecycle.currentService()?.supportsStreaming ?: false
            }
        }.getOrElse { false }

    /**
     * Load an STT model by ID
     *
     * @param modelId The model identifier (e.g., "whisper-base", "whisper-small")
     * @throws SDKError if loading fails or no provider is available
     */
    override suspend fun loadModel(modelId: String) {
        logger.info("Loading STT model: $modelId")

        // Check if STT service is available
        if (!ModuleRegistry.hasSTT) {
            throw SDKError.ComponentNotInitialized(
                "No STT service registered for model: $modelId. " +
                    "Add ONNX or another STT module as a dependency.",
            )
        }

        try {
            managedLifecycle.load(modelId)
            logger.info("✅ STT model loaded: $modelId")
        } catch (e: CapabilityError) {
            logger.error("Failed to load STT model: $modelId", e)
            throw SDKError.ModelLoadingFailed("Failed to load STT model: ${e.message}")
        } catch (e: Exception) {
            logger.error("Failed to load STT model: $modelId", e)
            throw SDKError.ModelLoadingFailed("Failed to load STT model: ${e.message}")
        }
    }

    /**
     * Unload the currently loaded STT model
     */
    override suspend fun unload() {
        logger.info("Unloading STT model: $currentModelId")
        try {
            managedLifecycle.unload()
            logger.info("✅ STT model unloaded")
        } catch (e: Exception) {
            logger.error("Failed to unload STT model", e)
            throw e
        }
    }

    /**
     * Clean up resources used by the STT capability.
     * Matches iOS STTCapability.cleanup() method.
     */
    override suspend fun cleanup() {
        logger.info("Cleaning up STT capability")
        try {
            managedLifecycle.reset()
            logger.info("✅ STT capability cleaned up")
        } catch (e: Exception) {
            logger.error("Failed to cleanup STT capability", e)
            // Don't throw - cleanup should be best-effort
        }
    }

    // ============================================================================
    // MARK: - Transcription API
    // ============================================================================

    /**
     * Simple transcription with default options
     *
     * @param audioData Raw audio data (WAV, PCM, etc.)
     * @return STTOutput with transcribed text and metadata
     */
    suspend fun transcribe(audioData: ByteArray): STTOutput {
        return transcribe(audioData, STTOptions.default())
    }

    /**
     * Transcription with custom options
     *
     * @param audioData Raw audio data
     * @param options Transcription options (STTOptions from STTModels.kt)
     * @return STTOutput with transcribed text and metadata
     */
    suspend fun transcribe(
        audioData: ByteArray,
        options: STTOptions,
    ): STTOutput {
        val service = managedLifecycle.requireService()
        val modelId = managedLifecycle.resourceIdOrUnknown()

        logger.info("Transcribing audio with model: $modelId")

        // Merge options with config defaults
        val effectiveOptions = mergeOptions(options)

        // Calculate audio metrics
        val audioSizeBytes = audioData.size
        val audioLengthMs = estimateAudioLength(
            dataSize = audioSizeBytes,
            format = effectiveOptions.audioFormat,
            sampleRate = effectiveOptions.sampleRate,
        ) * 1000

        val startTime = getCurrentTimeMillis()

        // Start transcription tracking
        val transcriptionId = analyticsService.startTranscription(
            audioLengthMs = audioLengthMs,
            audioSizeBytes = audioSizeBytes,
            language = effectiveOptions.language,
        )

        // Perform transcription
        val result: STTTranscriptionResult
        try {
            result = service.transcribe(audioData = audioData, options = effectiveOptions)
        } catch (e: Exception) {
            logger.error("Transcription failed: $e")
            analyticsService.trackTranscriptionFailed(
                transcriptionId = transcriptionId,
                errorMessage = e.message ?: e.toString(),
            )
            managedLifecycle.trackOperationError(e, "transcribe")
            throw CapabilityError.OperationFailed("Transcription", e)
        }

        val processingTimeMs = (getCurrentTimeMillis() - startTime).toDouble()
        val processingTime = processingTimeMs / 1000.0

        // Complete transcription tracking
        analyticsService.completeTranscription(
            transcriptionId = transcriptionId,
            text = result.transcript,
            confidence = result.confidence ?: 0.9f,
        )

        logger.info("Transcription completed in ${processingTimeMs.toLong()}ms")

        // Convert to STTOutput
        val wordTimestamps = result.timestamps?.map { timestamp ->
            WordTimestamp(
                word = timestamp.word,
                startTime = timestamp.startTime,
                endTime = timestamp.endTime,
                confidence = timestamp.confidence ?: 0.9f,
            )
        }

        val alternatives = result.alternatives?.map { alt ->
            TranscriptionAlternative(
                text = alt.transcript,
                confidence = alt.confidence,
            )
        }

        val audioLength = estimateAudioLength(
            dataSize = audioSizeBytes,
            format = effectiveOptions.audioFormat,
            sampleRate = effectiveOptions.sampleRate,
        )

        return STTOutput(
            text = result.transcript,
            confidence = result.confidence ?: 0.9f,
            wordTimestamps = wordTimestamps,
            detectedLanguage = result.language,
            alternatives = alternatives,
            metadata = TranscriptionMetadata(
                modelId = modelId,
                processingTime = processingTime,
                audioLength = audioLength,
            ),
        )
    }

    /**
     * Stream transcription for real-time processing
     *
     * @param audioStream Flow of audio data chunks
     * @param options Transcription options
     * @return Flow of transcription text
     */
    fun streamTranscribe(
        audioStream: Flow<ByteArray>,
        options: STTOptions,
    ): Flow<String> = flow {
        val service = managedLifecycle.requireService()
        val effectiveOptions = mergeOptions(options)

        // Start transcription tracking (streaming mode - audio length unknown upfront)
        val transcriptionId = analyticsService.startTranscription(
            audioLengthMs = 0.0, // Unknown for streaming
            audioSizeBytes = 0, // Unknown for streaming
            language = effectiveOptions.language,
        )

        var lastPartialWordCount = 0

        try {
            val result = service.streamTranscribe(
                audioStream = audioStream,
                options = effectiveOptions,
                onPartial = { partial ->
                    // Track streaming update
                    val wordCount = partial.split(" ").filter { it.isNotEmpty() }.size
                    if (wordCount > lastPartialWordCount) {
                        analyticsService.trackPartialTranscript(text = partial)
                        lastPartialWordCount = wordCount
                    }
                    // Note: Can't yield from callback directly, partials are tracked but final result is emitted
                },
            )

            // Complete transcription tracking
            analyticsService.completeTranscription(
                transcriptionId = transcriptionId,
                text = result.transcript,
                confidence = result.confidence ?: 0.9f,
            )

            // Emit final result
            emit(result.transcript)
        } catch (e: Exception) {
            analyticsService.trackTranscriptionFailed(
                transcriptionId = transcriptionId,
                errorMessage = e.message ?: e.toString(),
            )
            throw e
        }
    }

    // ============================================================================
    // MARK: - Analytics API (iOS STTCapability.getAnalyticsMetrics pattern)
    // ============================================================================

    /**
     * Get current STT analytics metrics.
     * Matches iOS STTCapability.getAnalyticsMetrics().
     *
     * @return STTMetrics with transcription statistics
     */
    fun getAnalyticsMetrics(): STTMetrics = analyticsService.getMetrics()

    // ============================================================================
    // MARK: - Private Methods
    // ============================================================================

    private fun mergeOptions(options: STTOptions): STTOptions {
        val cfg = config ?: return options

        return STTOptions(
            language = options.language.ifEmpty { cfg.language },
            detectLanguage = options.detectLanguage,
            enablePunctuation = options.enablePunctuation,
            enableDiarization = options.enableDiarization,
            maxSpeakers = options.maxSpeakers,
            enableTimestamps = options.enableTimestamps,
            vocabularyFilter = options.vocabularyFilter.ifEmpty { cfg.vocabularyList },
            audioFormat = options.audioFormat,
            sampleRate = if (options.sampleRate != 16000) options.sampleRate else cfg.sampleRate,
            preferredFramework = options.preferredFramework,
        )
    }

    private fun estimateAudioLength(
        dataSize: Int,
        format: AudioFormat,
        sampleRate: Int,
    ): Double {
        // Rough estimation based on format and sample rate
        val bytesPerSample = when (format) {
            AudioFormat.PCM, AudioFormat.WAV -> 2 // 16-bit PCM
            AudioFormat.MP3 -> 1 // Compressed
            else -> 2
        }

        val samples = dataSize / bytesPerSample
        return samples.toDouble() / sampleRate.toDouble()
    }
}

// ============================================================================
// MARK: - ManagedLifecycle Factory
// ============================================================================

/**
 * Factory method to create ManagedLifecycle for STT
 */
internal fun createSTTManagedLifecycle(): ManagedLifecycle<STTService> {
    return ManagedLifecycle(
        lifecycle = createSTTLifecycleManager(),
        resourceType = CapabilityResourceType.STT_MODEL,
        loggerCategory = "STT.Lifecycle",
    )
}

/**
 * Private helper to create ModelLifecycleManager for STT
 */
private fun createSTTLifecycleManager(): ModelLifecycleManager<STTService> {
    val logger = SDKLogger("STT.Loader")

    return ModelLifecycleManager(
        category = "STT.Lifecycle",
        loadResource = { resourceId, config ->
            logger.info("Loading STT model: $resourceId")

            // Get model info from registry
            val modelInfo = ServiceContainer.shared.modelRegistry.getModel(resourceId)
                ?: throw SDKError.ModelNotFound("STT model not found: $resourceId")

            logger.info("Found model: ${modelInfo.name} (id: ${modelInfo.id})")

            // Ensure model is downloaded
            val modelPath = modelInfo.localPath
                ?: throw SDKError.ModelNotDownloaded(
                    "Model not downloaded: $resourceId. Please download the model first."
                )

            logger.info("Using model path: $modelPath")

            // Create configuration
            val sttConfig = (config as? STTConfiguration)?.copy(modelId = resourceId)
                ?: STTConfiguration(modelId = resourceId)

            // Create service using registry
            val service = ModuleRegistry.createSTT(sttConfig)

            logger.info("STT model loaded successfully: $resourceId")
            service
        },
        unloadResource = { service ->
            service.cleanup()
        },
    )
}
