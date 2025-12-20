package com.runanywhere.sdk.features.tts

import com.runanywhere.sdk.core.AudioFormat
import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/**
 * TTS Capability - Public API wrapper for Text-to-Speech operations
 *
 * Aligned with iOS TTSCapability pattern:
 * - Voice lifecycle management (loadVoice, unload, isVoiceLoaded)
 * - Synthesis API (synthesize, synthesizeStream)
 * - Voice listing (availableVoices)
 * - Event tracking (handled automatically by underlying component)
 *
 * This capability wraps TTSComponent and provides the interface expected by
 * the public RunAnywhere+TTS.kt extension functions.
 */
class TTSCapability internal constructor(
    private val getComponent: () -> TTSComponent
) {
    private val logger = SDKLogger("TTSCapability")

    private var _isVoiceLoaded: Boolean = false
    private var _currentVoiceId: String? = null

    /**
     * Check if a TTS voice is currently loaded (alias for isModelLoaded)
     */
    val isVoiceLoaded: Boolean
        get() = _isVoiceLoaded && getComponent().state == com.runanywhere.sdk.core.capabilities.ComponentState.READY

    /**
     * Check if model is loaded (iOS ModelLoadableCapability pattern)
     */
    val isModelLoaded: Boolean
        get() = isVoiceLoaded

    /**
     * Get the currently loaded voice ID
     */
    val currentVoiceId: String?
        get() = _currentVoiceId

    /**
     * Get available TTS voices
     */
    val availableVoices: List<String>
        get() = try {
            getComponent().getAllVoices().map { it.id }
        } catch (e: Exception) {
            emptyList()
        }

    // ============================================================================
    // MARK: - Voice Lifecycle (iOS ModelLoadableCapability pattern)
    // ============================================================================

    /**
     * Load a TTS voice by ID
     *
     * @param voiceId The voice identifier
     * @throws SDKError if loading fails
     */
    suspend fun loadVoice(voiceId: String) {
        logger.info("Loading TTS voice: $voiceId")

        try {
            val component = getComponent()
            component.initialize()

            _currentVoiceId = voiceId
            _isVoiceLoaded = true

            logger.info("✅ TTS voice loaded: $voiceId")
        } catch (e: Exception) {
            logger.error("Failed to load TTS voice: $voiceId", e)
            _isVoiceLoaded = false
            _currentVoiceId = null
            throw SDKError.ModelLoadingFailed("Failed to load TTS voice: ${e.message}")
        }
    }

    /**
     * Load model (alias for loadVoice for iOS compatibility)
     */
    suspend fun loadModel(modelId: String) = loadVoice(modelId)

    /**
     * Unload the currently loaded TTS voice
     */
    suspend fun unload() {
        logger.info("Unloading TTS voice: $_currentVoiceId")

        try {
            getComponent().cleanup()
            _isVoiceLoaded = false
            _currentVoiceId = null
            logger.info("✅ TTS voice unloaded")
        } catch (e: Exception) {
            logger.error("Failed to unload TTS voice", e)
            throw e
        }
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
    suspend fun synthesize(text: String, options: TTSOptions): TTSResult {
        ensureVoiceLoaded()

        val component = getComponent()

        val output = component.synthesize(
            text = text,
            voice = options.voice,
            language = options.language
        )

        return TTSResult(
            audioData = output.audioData,
            format = output.format,
            duration = output.duration
        )
    }

    /**
     * Stream synthesis for long text
     *
     * @param text Text to synthesize
     * @param options Synthesis options
     * @return Flow of audio data chunks
     */
    fun synthesizeStream(text: String, options: TTSOptions): Flow<ByteArray> {
        ensureVoiceLoaded()

        val component = getComponent()

        return component.synthesizeStream(text, options)
    }

    /**
     * Stop current synthesis
     */
    fun stop() {
        try {
            getComponent().stop()
        } catch (e: Exception) {
            logger.debug("Stop called but no synthesis in progress")
        }
    }

    // ============================================================================
    // MARK: - Private Helpers
    // ============================================================================

    private fun ensureVoiceLoaded() {
        if (!isVoiceLoaded) {
            throw SDKError.ComponentNotReady("TTS voice not loaded. Call loadTTSVoice() first.")
        }
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
    val duration: Double
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

// Note: TTSOptions is defined in TTSComponent.kt and should be imported from there
// AudioFormat is defined in core/AudioTypes.kt and imported above
