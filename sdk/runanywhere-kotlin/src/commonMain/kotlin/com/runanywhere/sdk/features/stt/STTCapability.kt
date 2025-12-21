package com.runanywhere.sdk.features.stt

import com.runanywhere.sdk.core.AudioFormat
import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.core.capabilities.ComponentState
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.flow.Flow

/**
 * STT Capability - Public API wrapper for Speech-to-Text operations
 *
 * Aligned with iOS STTCapability pattern:
 * - Model lifecycle management (loadModel, unload, isModelLoaded, cleanup)
 * - Transcription API (transcribe, streamTranscribe)
 * - Analytics API (getAnalyticsMetrics)
 * - Streaming support detection (supportsStreaming)
 * - Event tracking (handled automatically by underlying component)
 *
 * This capability wraps STTComponent and provides the interface expected by
 * the public RunAnywhere+STT.kt extension functions.
 */
class STTCapability internal constructor(
    private val getComponent: () -> STTComponent,
) {
    private val logger = SDKLogger("STTCapability")

    private var _isModelLoaded: Boolean = false
    private var _currentModelId: String? = null

    /**
     * Check if an STT model is currently loaded
     */
    val isModelLoaded: Boolean
        get() = _isModelLoaded && getComponent().state == ComponentState.READY

    /**
     * Get the currently loaded model ID
     */
    val currentModelId: String?
        get() = _currentModelId

    /**
     * Whether the underlying STT service supports live/streaming transcription.
     * Matches iOS STTCapability.supportsStreaming property.
     */
    val supportsStreaming: Boolean
        get() = try {
            getComponent().supportsStreaming
        } catch (_: Exception) {
            false
        }

    // ============================================================================
    // MARK: - Model Lifecycle (iOS ModelLoadableCapability pattern)
    // ============================================================================

    /**
     * Load an STT model by ID
     *
     * @param modelId The model identifier (e.g., "whisper-base", "whisper-small")
     * @throws SDKError if loading fails or no provider is available
     */
    suspend fun loadModel(modelId: String) {
        logger.info("Loading STT model: $modelId")

        // Check if provider is available
        if (!ModuleRegistry.hasSTT) {
            throw SDKError.ComponentNotInitialized(
                "No STT service provider registered. Add WhisperKit or another STT module as a dependency.",
            )
        }

        try {
            // Initialize the component (which handles model loading internally)
            val component = getComponent()
            component.initialize()

            _currentModelId = modelId
            _isModelLoaded = true

            logger.info("✅ STT model loaded: $modelId")
        } catch (e: Exception) {
            logger.error("Failed to load STT model: $modelId", e)
            _isModelLoaded = false
            _currentModelId = null
            throw SDKError.ModelLoadingFailed("Failed to load STT model: ${e.message}")
        }
    }

    /**
     * Unload the currently loaded STT model
     */
    suspend fun unload() {
        logger.info("Unloading STT model: $_currentModelId")

        try {
            getComponent().cleanup()
            _isModelLoaded = false
            _currentModelId = null
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
    suspend fun cleanup() {
        logger.info("Cleaning up STT capability")
        try {
            getComponent().cleanup()
            _isModelLoaded = false
            _currentModelId = null
            logger.info("✅ STT capability cleaned up")
        } catch (e: Exception) {
            logger.error("Failed to cleanup STT capability", e)
            // Don't throw - cleanup should be best-effort
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
    fun getAnalyticsMetrics(): STTMetrics {
        return try {
            getComponent().getAnalyticsMetrics()
        } catch (_: Exception) {
            STTMetrics()
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
        ensureModelLoaded()

        val component = getComponent()
        return component.transcribe(audioData, AudioFormat.WAV, null)
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
        ensureModelLoaded()

        val component = getComponent()

        // Use process method with full options
        val input =
            STTInput(
                audioData = audioData,
                format = options.audioFormat,
                language = options.language,
                options = options,
            )

        return component.process(input)
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
    ): Flow<String> {
        ensureModelLoaded()

        val component = getComponent()
        return component.streamTranscribe(audioStream, options.language)
    }

    // ============================================================================
    // MARK: - Private Helpers
    // ============================================================================

    private fun ensureModelLoaded() {
        if (!isModelLoaded) {
            throw SDKError.ComponentNotReady("STT model not loaded. Call loadSTTModel() first.")
        }
    }
}

// All STT types (STTOptions, STTResult, STTOutput, etc.) are defined in STTModels.kt
// to avoid duplicate type definitions
