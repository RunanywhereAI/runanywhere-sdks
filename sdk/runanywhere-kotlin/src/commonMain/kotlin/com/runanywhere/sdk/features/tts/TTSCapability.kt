package com.runanywhere.sdk.features.tts

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
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * TTS Capability - Actor-like class for Text-to-Speech operations
 *
 * Aligned EXACTLY with iOS TTSCapability pattern:
 * - Uses ManagedLifecycle<TTSService> directly for voice lifecycle
 * - No intermediate Component layer
 * - Voice lifecycle management (loadVoice, unload, isVoiceLoaded)
 * - Synthesis API (synthesize, synthesizeStream)
 * - Voice listing (availableVoices)
 * - Analytics tracking via TTSAnalyticsService
 */
class TTSCapability internal constructor(
    private val analyticsService: TTSAnalyticsService = TTSAnalyticsService(),
) : ModelLoadableCapability<TTSConfiguration, TTSService> {
    private val logger = SDKLogger("TTSCapability")

    // Managed lifecycle with integrated event tracking (matches iOS)
    private val managedLifecycle: ManagedLifecycle<TTSService> = ManagedLifecycle.forTTS()

    // Current configuration
    private var config: TTSConfiguration? = null

    // ============================================================================
    // MARK: - Configuration (Capability Protocol)
    // ============================================================================

    override fun configure(config: TTSConfiguration) {
        this.config = config
    }

    // ============================================================================
    // MARK: - Voice Lifecycle (ModelLoadableCapability Protocol)
    // ============================================================================

    /**
     * Check if a TTS voice is currently loaded (alias for isModelLoaded)
     */
    val isVoiceLoaded: Boolean
        get() = isModelLoaded

    /**
     * Check if model is loaded (iOS ModelLoadableCapability pattern)
     */
    override val isModelLoaded: Boolean
        get() = runCatching { kotlinx.coroutines.runBlocking { managedLifecycle.isLoaded() } }.getOrElse { false }

    /**
     * Get the currently loaded voice ID
     */
    val currentVoiceId: String?
        get() = currentModelId

    /**
     * Get the currently loaded model/voice ID
     */
    override val currentModelId: String?
        get() = runCatching { kotlinx.coroutines.runBlocking { managedLifecycle.currentResourceId() } }.getOrNull()

    /**
     * Get available TTS voices
     */
    val availableVoices: List<String>
        get() = runCatching {
            kotlinx.coroutines.runBlocking {
                managedLifecycle.currentService()?.availableVoices ?: emptyList()
            }
        }.getOrElse { emptyList() }

    /**
     * Whether currently synthesizing
     */
    val isSynthesizing: Boolean
        get() = runCatching {
            kotlinx.coroutines.runBlocking {
                managedLifecycle.currentService()?.isSynthesizing ?: false
            }
        }.getOrElse { false }

    /**
     * Load a TTS voice by ID
     *
     * @param voiceId The voice identifier
     * @throws SDKError if loading fails
     */
    suspend fun loadVoice(voiceId: String) {
        logger.info("Loading TTS voice: $voiceId")

        try {
            managedLifecycle.load(voiceId)
            logger.info("✅ TTS voice loaded: $voiceId")
        } catch (e: CapabilityError) {
            logger.error("Failed to load TTS voice: $voiceId", e)
            throw SDKError.ModelLoadingFailed("Failed to load TTS voice: ${e.message}")
        } catch (e: Exception) {
            logger.error("Failed to load TTS voice: $voiceId", e)
            throw SDKError.ModelLoadingFailed("Failed to load TTS voice: ${e.message}")
        }
    }

    /**
     * Load model (alias for loadVoice for iOS compatibility)
     */
    override suspend fun loadModel(modelId: String) = loadVoice(modelId)

    /**
     * Unload the currently loaded TTS voice
     */
    override suspend fun unload() {
        logger.info("Unloading TTS voice: $currentVoiceId")
        try {
            managedLifecycle.unload()
            logger.info("✅ TTS voice unloaded")
        } catch (e: Exception) {
            logger.error("Failed to unload TTS voice", e)
            throw e
        }
    }

    /**
     * Cleanup all resources
     */
    override suspend fun cleanup() {
        managedLifecycle.reset()
    }

    // ============================================================================
    // MARK: - Synthesis API
    // ============================================================================

    /**
     * Synthesize text to speech
     *
     * @param text Text to synthesize
     * @param options Synthesis options
     * @return TTSResult with audio data
     */
    suspend fun synthesize(
        text: String,
        options: TTSOptions,
    ): TTSResult {
        val service = managedLifecycle.requireService()
        val voiceId = managedLifecycle.resourceIdOrUnknown()

        logger.info("Synthesizing text with voice: $voiceId")

        // Merge options with config defaults
        val effectiveOptions = mergeOptions(options)

        val startTime = getCurrentTimeMillis()

        // Start synthesis tracking
        val synthesisId = analyticsService.startSynthesis(
            text = text,
            voice = effectiveOptions.voice ?: voiceId,
        )

        // Perform synthesis
        val audioData: ByteArray
        try {
            audioData = service.synthesize(text = text, options = effectiveOptions)
        } catch (e: Exception) {
            logger.error("Synthesis failed: $e")
            analyticsService.trackSynthesisFailed(
                synthesisId = synthesisId,
                errorMessage = e.message ?: e.toString(),
            )
            managedLifecycle.trackOperationError(e, "synthesize")
            throw CapabilityError.OperationFailed("Synthesis", e)
        }

        val processingTimeMs = (getCurrentTimeMillis() - startTime).toDouble()

        // Calculate audio duration
        val duration = estimateAudioDuration(audioData.size, effectiveOptions.sampleRate)
        val audioDurationMs = duration * 1000.0

        // Complete synthesis tracking
        analyticsService.completeSynthesis(
            synthesisId = synthesisId,
            audioDurationMs = audioDurationMs,
            audioSizeBytes = audioData.size,
        )

        logger.info("Synthesis completed in ${processingTimeMs.toLong()}ms, ${audioData.size} bytes")

        return TTSResult(
            audioData = audioData,
            format = effectiveOptions.audioFormat,
            duration = duration,
        )
    }

    /**
     * Stream synthesis for long text
     *
     * @param text Text to synthesize
     * @param options Synthesis options
     * @return Flow of audio data chunks
     */
    fun synthesizeStream(
        text: String,
        options: TTSOptions,
    ): Flow<ByteArray> = flow {
        val service = managedLifecycle.requireService()
        val voiceId = managedLifecycle.resourceIdOrUnknown()
        val effectiveOptions = mergeOptions(options)

        // Start synthesis tracking
        val synthesisId = analyticsService.startSynthesis(
            text = text,
            voice = effectiveOptions.voice ?: voiceId,
        )

        var totalBytes = 0

        try {
            service.synthesizeStream(
                text = text,
                options = effectiveOptions,
                onChunk = { chunk ->
                    totalBytes += chunk.count()
                    analyticsService.trackSynthesisChunk(
                        synthesisId = synthesisId,
                        chunkSize = chunk.count(),
                    )
                },
            )

            // Complete synthesis tracking
            val audioDuration = estimateAudioDuration(totalBytes, effectiveOptions.sampleRate)
            val audioDurationMs = audioDuration * 1000.0
            analyticsService.completeSynthesis(
                synthesisId = synthesisId,
                audioDurationMs = audioDurationMs,
                audioSizeBytes = totalBytes,
            )
        } catch (e: Exception) {
            analyticsService.trackSynthesisFailed(
                synthesisId = synthesisId,
                errorMessage = e.message ?: e.toString(),
            )
            throw e
        }
    }

    /**
     * Stop current synthesis
     */
    fun stop() {
        logger.info("Stopping synthesis")
        runCatching {
            kotlinx.coroutines.runBlocking {
                managedLifecycle.currentService()?.stop()
            }
        }
    }

    // ============================================================================
    // MARK: - Analytics
    // ============================================================================

    /**
     * Get current TTS analytics metrics
     */
    fun getAnalyticsMetrics(): TTSMetrics = analyticsService.getMetrics()

    // ============================================================================
    // MARK: - Private Methods
    // ============================================================================

    private fun mergeOptions(options: TTSOptions): TTSOptions {
        val cfg = config ?: return options

        return TTSOptions(
            voice = options.voice ?: cfg.voice,
            language = options.language,
            rate = options.rate,
            pitch = options.pitch,
            volume = options.volume,
            audioFormat = options.audioFormat,
            sampleRate = options.sampleRate,
            useSSML = options.useSSML,
        )
    }

    private fun estimateAudioDuration(dataSize: Int, sampleRate: Int = 22050): Double {
        val bytesPerSample = 2 // 16-bit PCM
        val samples = dataSize / bytesPerSample
        return samples.toDouble() / sampleRate.toDouble()
    }
}

// ============================================================================
// MARK: - TTSResult (Capability-level output type)
// ============================================================================

/**
 * TTS result with audio data - capability-level wrapper
 * Uses AudioFormat from core package (com.runanywhere.sdk.core.AudioFormat)
 */
data class TTSResult(
    /** Synthesized audio data */
    val audioData: ByteArray,
    /** Audio format (from core package) */
    val format: AudioFormat,
    /** Duration in seconds */
    val duration: Double,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other == null || this::class != other::class) return false
        other as TTSResult
        return audioData.contentEquals(other.audioData) && format == other.format && duration == other.duration
    }

    override fun hashCode(): Int {
        var result = audioData.contentHashCode()
        result = 31 * result + format.hashCode()
        result = 31 * result + duration.hashCode()
        return result
    }
}

// ============================================================================
// MARK: - ManagedLifecycle Factory Extension
// ============================================================================

/**
 * Factory method to create ManagedLifecycle for TTS
 */
fun ManagedLifecycle.Companion.forTTS(): ManagedLifecycle<TTSService> {
    return ManagedLifecycle(
        lifecycle = ModelLifecycleManager.forTTS(),
        resourceType = CapabilityResourceType.TTS_VOICE,
        loggerCategory = "TTS.Lifecycle",
    )
}

/**
 * Factory method to create ModelLifecycleManager for TTS
 */
fun ModelLifecycleManager.Companion.forTTS(): ModelLifecycleManager<TTSService> {
    val logger = SDKLogger("TTS.Loader")

    return ModelLifecycleManager(
        category = "TTS.Lifecycle",
        loadResource = { resourceId, config ->
            logger.info("Loading TTS voice: $resourceId")

            // Get provider from registry
            val provider = ModuleRegistry.ttsProvider(resourceId)

            val service: TTSService = if (provider != null) {
                TTSServiceAdapter(provider)
            } else {
                // Fall back to default TTS service
                DefaultTTSService()
            }

            // Initialize the service
            service.initialize()

            logger.info("TTS voice loaded successfully: $resourceId")
            service
        },
        unloadResource = { service ->
            service.cleanup()
        },
    )
}
