package com.runanywhere.sdk.components

import com.runanywhere.sdk.components.base.BaseComponent
import com.runanywhere.sdk.components.base.ComponentState
import com.runanywhere.sdk.components.base.SDKComponent
import com.runanywhere.sdk.components.base.ComponentConfiguration
import com.runanywhere.sdk.data.models.ModelInfo
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat
import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.core.TTSServiceProvider
import kotlinx.coroutines.flow.*
import kotlinx.serialization.Serializable

/**
 * TTS Component for text-to-speech synthesis
 * One-to-one mapping from iOS TTSComponent.swift
 */
class TTSComponent(
    private val ttsConfiguration: TTSConfiguration
) : BaseComponent<TTSService>(ttsConfiguration) {

    override val componentType: SDKComponent = SDKComponent.TTS

    private var currentModel: ModelInfo? = null
    private val _isSynthesizing = MutableStateFlow(false)
    val isSynthesizing: StateFlow<Boolean> = _isSynthesizing.asStateFlow()

    private val _currentSpeechRate = MutableStateFlow(1.0f)
    val currentSpeechRate: StateFlow<Float> = _currentSpeechRate.asStateFlow()

    override suspend fun createService(): TTSService {
        // Create service from registry or default implementation
        val provider = ModuleRegistry.ttsProvider(ttsConfiguration.modelId)
        return if (provider != null) {
            TTSServiceAdapter(provider)
        } else {
            DefaultTTSService()
        }
    }

    override suspend fun initializeService() {
        // Initialize service
        service = createService()

        // Load model if specified
        ttsConfiguration.modelId?.let { modelId ->
            // Model loading will be handled by the service provider
        }
    }

    /**
     * Synthesize text to audio
     */
    suspend fun synthesize(
        text: String,
        options: TTSOptions = TTSOptions()
    ): ByteArray {
        ensureReady()

        _isSynthesizing.value = true
        return try {
            service?.synthesize(
                text = text,
                voice = options.voice,
                rate = options.rate,
                pitch = options.pitch,
                volume = options.volume
            ) ?: throw IllegalStateException("TTS service not initialized")
        } finally {
            _isSynthesizing.value = false
        }
    }

    /**
     * Synthesize text to audio stream
     */
    fun synthesizeStream(
        text: String,
        options: TTSOptions = TTSOptions()
    ): Flow<ByteArray> {
        ensureReady()

        return flow {
            _isSynthesizing.value = true
            try {
                service?.synthesizeStream(
                    text = text,
                    voice = options.voice,
                    rate = options.rate,
                    pitch = options.pitch,
                    volume = options.volume
                )?.collect { audioChunk ->
                    emit(audioChunk)
                } ?: throw IllegalStateException("TTS service not initialized")
            } finally {
                _isSynthesizing.value = false
            }
        }
    }

    /**
     * Synthesize with SSML markup
     */
    suspend fun synthesizeSSML(
        ssml: String,
        options: TTSOptions = TTSOptions()
    ): ByteArray {
        ensureReady()

        // Parse SSML and synthesize
        val parsedText = parseSSML(ssml)
        return synthesize(parsedText, options)
    }

    /**
     * Get available voices
     */
    fun getAvailableVoices(): List<TTSVoice> {
        return service?.getAvailableVoices() ?: emptyList()
    }

    /**
     * Set speech rate
     */
    fun setSpeechRate(rate: Float) {
        _currentSpeechRate.value = rate.coerceIn(0.5f, 2.0f)
    }

    /**
     * Load a specific model
     */
    suspend fun loadModel(modelInfo: ModelInfo) {
        transitionTo(ComponentState.INITIALIZING)

        try {
            // Load model (implementation would depend on the model format)
            currentModel = modelInfo
            service?.loadModel(modelInfo)
            transitionTo(ComponentState.READY)
        } catch (e: Exception) {
            transitionTo(ComponentState.FAILED)
            throw e
        }
    }

    /**
     * Cancel current synthesis
     */
    fun cancelSynthesis() {
        _isSynthesizing.value = false
        service?.cancelCurrent()
    }

    /**
     * Parse SSML markup
     */
    private fun parseSSML(ssml: String): String {
        // Simple SSML parsing - real implementation would be more complex
        return ssml
            .replace(Regex("<[^>]*>"), "") // Remove tags
            .trim()
    }
}

/**
 * TTS Options
 */
@Serializable
data class TTSOptions(
    val voice: TTSVoice = TTSVoice.DEFAULT,
    val rate: Float = 1.0f,
    val pitch: Float = 1.0f,
    val volume: Float = 1.0f,
    val language: String? = null,
    val outputFormat: TTSOutputFormat = TTSOutputFormat.PCM_16KHZ
)

/**
 * TTS Voice configuration
 */
@Serializable
data class TTSVoice(
    val id: String,
    val name: String,
    val language: String,
    val gender: TTSGender,
    val style: TTSStyle = TTSStyle.NEUTRAL
) {
    companion object {
        val DEFAULT = TTSVoice(
            id = "default",
            name = "Default Voice",
            language = "en-US",
            gender = TTSGender.NEUTRAL,
            style = TTSStyle.NEUTRAL
        )
    }
}

/**
 * TTS Gender types
 */
@Serializable
enum class TTSGender {
    MALE,
    FEMALE,
    NEUTRAL
}

/**
 * TTS Style types
 */
@Serializable
enum class TTSStyle {
    NEUTRAL,
    CHEERFUL,
    SAD,
    ANGRY,
    FEARFUL,
    FRIENDLY,
    HOPEFUL,
    SHOUTING,
    WHISPERING,
    NEWSCAST,
    CUSTOMER_SERVICE
}

/**
 * TTS Output format
 */
@Serializable
enum class TTSOutputFormat {
    PCM_8KHZ,
    PCM_16KHZ,
    PCM_24KHZ,
    PCM_48KHZ,
    MP3,
    OGG_VORBIS,
    OPUS;

    val sampleRate: Int
        get() = when (this) {
            PCM_8KHZ -> 8000
            PCM_16KHZ -> 16000
            PCM_24KHZ -> 24000
            PCM_48KHZ -> 48000
            else -> 16000 // Default for compressed formats
        }
}

/**
 * TTS Configuration
 */
data class TTSConfiguration(
    val modelId: String? = null,
    val defaultVoice: TTSVoice = TTSVoice.DEFAULT,
    val defaultRate: Float = 1.0f,
    val defaultPitch: Float = 1.0f,
    val defaultVolume: Float = 1.0f,
    val outputFormat: TTSOutputFormat = TTSOutputFormat.PCM_16KHZ,
    val enableSSML: Boolean = true
) : ComponentConfiguration {
    override fun validate() {
        require(defaultRate > 0f && defaultRate <= 3f) { "Rate must be between 0 and 3" }
        require(defaultPitch > 0f && defaultPitch <= 2f) { "Pitch must be between 0 and 2" }
        require(defaultVolume >= 0f && defaultVolume <= 1f) { "Volume must be between 0 and 1" }
    }
}

/**
 * TTS Service interface
 */
interface TTSService {
    suspend fun synthesize(
        text: String,
        voice: TTSVoice,
        rate: Float,
        pitch: Float,
        volume: Float
    ): ByteArray

    fun synthesizeStream(
        text: String,
        voice: TTSVoice,
        rate: Float,
        pitch: Float,
        volume: Float
    ): Flow<ByteArray>

    fun getAvailableVoices(): List<TTSVoice>
    suspend fun loadModel(modelInfo: ModelInfo)
    fun cancelCurrent()
}

/**
 * Adapter for ModuleRegistry providers
 */
class TTSServiceAdapter(
    private val provider: TTSServiceProvider
) : TTSService {
    override suspend fun synthesize(
        text: String,
        voice: TTSVoice,
        rate: Float,
        pitch: Float,
        volume: Float
    ): ByteArray {
        return provider.synthesize(text, TTSOptions(voice, rate, pitch, volume))
    }

    override fun synthesizeStream(
        text: String,
        voice: TTSVoice,
        rate: Float,
        pitch: Float,
        volume: Float
    ): Flow<ByteArray> {
        return provider.synthesizeStream(text, TTSOptions(voice, rate, pitch, volume))
    }

    override fun getAvailableVoices(): List<TTSVoice> = listOf(TTSVoice.DEFAULT)

    override suspend fun loadModel(modelInfo: ModelInfo) {
        // Provider handles model loading
    }

    override fun cancelCurrent() {
        // Provider handles cancellation
    }
}

/**
 * Default TTS service implementation
 */
class DefaultTTSService : TTSService {
    override suspend fun synthesize(
        text: String,
        voice: TTSVoice,
        rate: Float,
        pitch: Float,
        volume: Float
    ): ByteArray {
        // Default implementation - could use platform-specific TTS
        return ByteArray(0)
    }

    override fun synthesizeStream(
        text: String,
        voice: TTSVoice,
        rate: Float,
        pitch: Float,
        volume: Float
    ): Flow<ByteArray> {
        return flow {
            emit(synthesize(text, voice, rate, pitch, volume))
        }
    }

    override fun getAvailableVoices(): List<TTSVoice> = listOf(TTSVoice.DEFAULT)

    override suspend fun loadModel(modelInfo: ModelInfo) {
        // Load model implementation
    }

    override fun cancelCurrent() {
        // Cancel implementation
    }
}
