package com.runanywhere.sdk.capabilities.stt

import com.runanywhere.sdk.components.stt.STTComponent
import com.runanywhere.sdk.components.stt.STTConfiguration
import com.runanywhere.sdk.components.stt.STTOutput as ComponentSTTOutput
import com.runanywhere.sdk.components.stt.STTOptions as ComponentSTTOptions
import com.runanywhere.sdk.components.stt.AudioFormat
import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/**
 * STT Capability - Public API wrapper for Speech-to-Text operations
 *
 * Aligned with iOS STTCapability pattern:
 * - Model lifecycle management (loadModel, unload, isModelLoaded)
 * - Transcription API (transcribe, streamTranscribe)
 * - Event tracking (handled automatically by underlying component)
 *
 * This capability wraps STTComponent and provides the interface expected by
 * the public RunAnywhere+STT.kt extension functions.
 */
class STTCapability internal constructor(
    private val getComponent: () -> STTComponent
) {
    private val logger = SDKLogger("STTCapability")

    private var _isModelLoaded: Boolean = false
    private var _currentModelId: String? = null

    /**
     * Check if an STT model is currently loaded
     */
    val isModelLoaded: Boolean
        get() = _isModelLoaded && getComponent().state == com.runanywhere.sdk.components.base.ComponentState.READY

    /**
     * Get the currently loaded model ID
     */
    val currentModelId: String?
        get() = _currentModelId

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
                "No STT service provider registered. Add WhisperKit or another STT module as a dependency."
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

    // ============================================================================
    // MARK: - Transcription API
    // ============================================================================

    /**
     * Simple transcription with default options
     *
     * @param audioData Raw audio data (WAV, PCM, etc.)
     * @return STTResult with transcribed text and metadata
     */
    suspend fun transcribe(audioData: ByteArray): STTResult {
        ensureModelLoaded()

        val component = getComponent()
        val output = component.transcribe(audioData, AudioFormat.WAV, null)

        return output.toSTTResult()
    }

    /**
     * Transcription with custom options
     *
     * @param audioData Raw audio data
     * @param options Transcription options
     * @return STTResult with transcribed text and metadata
     */
    suspend fun transcribe(audioData: ByteArray, options: STTOptions): STTResult {
        ensureModelLoaded()

        val component = getComponent()
        val componentOptions = options.toComponentOptions()

        // Use process method with full options
        val input = com.runanywhere.sdk.components.stt.STTInput(
            audioData = audioData,
            format = AudioFormat.WAV,
            language = options.language,
            options = componentOptions
        )

        val output = component.process(input)
        return output.toSTTResult()
    }

    /**
     * Stream transcription for real-time processing
     *
     * @param audioStream Flow of audio data chunks
     * @param options Transcription options
     * @return Flow of transcription text
     */
    fun streamTranscribe(audioStream: Flow<ByteArray>, options: STTOptions): Flow<String> {
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

    private fun ComponentSTTOutput.toSTTResult(): STTResult {
        return STTResult(
            text = this.text,
            language = this.detectedLanguage,
            confidence = this.confidence,
            timings = this.wordTimestamps?.map {
                STTTimingInfo(
                    start = it.startTime,
                    end = it.endTime,
                    word = it.word
                )
            }
        )
    }

    private fun STTOptions.toComponentOptions(): ComponentSTTOptions {
        return ComponentSTTOptions(
            language = this.language ?: "en",
            detectLanguage = this.language == null,
            enablePunctuation = true,
            enableDiarization = false,
            enableTimestamps = this.enableTimestamps,
            vocabularyFilter = emptyList(),
            audioFormat = AudioFormat.WAV
        )
    }
}

// ============================================================================
// MARK: - Internal Types (Used by Capability, mapped from public types)
// ============================================================================

/**
 * Internal STT options used by the capability layer
 */
data class STTOptions(
    /** Language hint (e.g., "en", "es", "fr") - null for auto-detect */
    val language: String? = null,
    /** Enable voice activity detection */
    val enableVAD: Boolean = false,
    /** Enable word timestamps */
    val enableTimestamps: Boolean = false
)

/**
 * Internal STT result with metadata
 */
data class STTResult(
    /** Transcribed text */
    val text: String,
    /** Detected language code */
    val language: String?,
    /** Confidence score (0.0 - 1.0) */
    val confidence: Float?,
    /** Word-level timings (if enabled) */
    val timings: List<STTTimingInfo>?
)

/**
 * Word timing information
 */
data class STTTimingInfo(
    /** Start time in seconds */
    val start: Double,
    /** End time in seconds */
    val end: Double,
    /** Word text */
    val word: String
)
