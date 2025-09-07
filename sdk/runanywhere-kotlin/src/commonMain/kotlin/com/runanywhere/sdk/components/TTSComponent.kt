package com.runanywhere.sdk.components

import com.runanywhere.sdk.components.base.BaseComponent
import com.runanywhere.sdk.components.base.ComponentState
import com.runanywhere.sdk.components.base.SDKComponent
import com.runanywhere.sdk.components.base.ComponentConfiguration
import com.runanywhere.sdk.components.base.ComponentInput
import com.runanywhere.sdk.components.base.ComponentOutput
import com.runanywhere.sdk.data.models.ModelInfo
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.core.TTSServiceProvider
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.coroutines.flow.*
import kotlinx.serialization.Serializable

/**
 * TTS Component for text-to-speech synthesis
 * Aligned with iOS TTSComponent.swift architecture - comprehensive multi-layered implementation
 * Features:
 * - Structured I/O models (TTSInput/TTSOutput) with metadata
 * - Progressive streaming with sentence-by-sentence synthesis
 * - Event-driven pipeline integration
 * - Rich voice management with TTSVoice objects
 * - Flow-based streaming using Kotlin coroutines
 * - StateFlow state management for reactive synthesis
 */
class TTSComponent(
    private val ttsConfiguration: TTSConfiguration
) : BaseComponent<TTSService>(ttsConfiguration) {

    override val componentType: SDKComponent = SDKComponent.TTS

    // MARK: - State Management (matching iOS patterns)

    private var currentModel: ModelInfo? = null
    private val _isSynthesizing = MutableStateFlow(false)
    val isSynthesizing: StateFlow<Boolean> = _isSynthesizing.asStateFlow()

    private val _currentOptions = MutableStateFlow<TTSOptions?>(null)
    val currentOptions: StateFlow<TTSOptions?> = _currentOptions.asStateFlow()

    // MARK: - Audio Format Configuration

    private val _audioFormat = MutableStateFlow(ttsConfiguration.outputFormat)
    val audioFormat: StateFlow<TTSOutputFormat> = _audioFormat.asStateFlow()

    // MARK: - Progressive Streaming Support

    private val streamingTTSHandler = StreamingTTSHandler()
    private val ssmlProcessor = DefaultSSMLProcessor()

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
        service?.initialize()

        // Load model if specified
        ttsConfiguration.modelId?.let { modelId ->
            // Model loading will be handled by the service provider
        }
    }

    /**
     * Synthesize text to audio with structured I/O (matching iOS)
     * Returns comprehensive TTSOutput with metadata
     */
    suspend fun synthesize(
        text: String,
        voice: String? = null,
        language: String? = null
    ): TTSOutput {
        return synthesize(TTSInput(text = text, voiceId = voice, language = language))
    }

    /**
     * Main synthesis method with structured input (iOS-style)
     */
    suspend fun synthesize(input: TTSInput): TTSOutput {
        ensureReady()
        input.validate()

        val startTime = getCurrentTimeMillis()
        _isSynthesizing.value = true

        return try {
            // Create synthesis options from input
            val options = createTTSOptions(input)
            _currentOptions.value = options

            // Perform synthesis
            val audioData = service?.synthesize(
                text = input.textToSynthesize,
                voice = options.voice,
                rate = options.rate,
                pitch = options.pitch,
                volume = options.volume
            ) ?: throw SDKError.ComponentFailure("TTS service not initialized")

            // Calculate processing metrics
            val processingTime = getCurrentTimeMillis() - startTime
            val estimatedDuration = estimateAudioDuration(audioData, options.outputFormat)

            // Create comprehensive output with metadata
            TTSOutput(
                audioData = audioData,
                format = options.outputFormat,
                duration = estimatedDuration,
                metadata = SynthesisMetadata(
                    voice = options.voice,
                    language = options.language ?: "en-US",
                    processingTimeMs = processingTime,
                    audioFormat = options.outputFormat,
                    sampleRate = options.outputFormat.sampleRate,
                    originalText = input.text,
                    processedText = input.textToSynthesize,
                    synthesizedAt = getCurrentTimeMillis()
                )
            )
        } finally {
            _isSynthesizing.value = false
            _currentOptions.value = null
        }
    }

    /**
     * Stream synthesis using callback pattern (iOS-style)
     */
    suspend fun synthesizeStream(
        text: String,
        options: TTSOptions,
        onChunk: suspend (ByteArray) -> Unit
    ) {
        ensureReady()

        _isSynthesizing.value = true
        try {
            service?.synthesizeStream(
                text = text,
                voice = options.voice,
                rate = options.rate,
                pitch = options.pitch,
                volume = options.volume
            )?.collect { chunk ->
                onChunk(chunk)
            } ?: throw SDKError.ComponentFailure("TTS service not initialized")
        } finally {
            _isSynthesizing.value = false
        }
    }

    /**
     * Flow-based streaming synthesis (Kotlin-native)
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
                } ?: throw SDKError.ComponentFailure("TTS service not initialized")
            } finally {
                _isSynthesizing.value = false
            }
        }
    }

    /**
     * Synthesize with SSML markup (enhanced processing)
     */
    suspend fun synthesizeSSML(
        ssml: String,
        options: TTSOptions = TTSOptions()
    ): TTSOutput {
        ensureReady()

        if (!ttsConfiguration.enableSSML) {
            throw SDKError.ConfigurationError("SSML is not enabled in configuration")
        }

        // Parse and validate SSML
        val parsedSSML = ssmlProcessor.parse(ssml)
        val validationResult = ssmlProcessor.validate(ssml)

        if (!validationResult.isValid) {
            throw SDKError.InvalidInput("Invalid SSML: ${validationResult.errors.joinToString(", ")}")
        }

        // Create input with processed text
        val input = TTSInput(
            text = ssml,
            textToSynthesize = parsedSSML.plainText,
            isSSML = true,
            voiceId = options.voice.id,
            language = options.language
        )

        return synthesize(input)
    }

    /**
     * Get available voices (iOS-style with comprehensive voice info)
     */
    fun getAvailableVoices(): List<TTSVoice> {
        return service?.getAvailableVoices() ?: listOf(TTSVoice.DEFAULT)
    }

    /**
     * Get available voice identifiers (iOS compatibility)
     */
    val availableVoiceIds: List<String>
        get() = getAvailableVoices().map { it.id }

    /**
     * Current synthesis state (iOS-style)
     */
    val isSynthesizingState: Boolean
        get() = _isSynthesizing.value

    /**
     * Load a specific model with enhanced error handling
     */
    suspend fun loadModel(modelInfo: ModelInfo) {
        transitionTo(ComponentState.INITIALIZING)

        try {
            currentModel = modelInfo
            service?.loadModel(modelInfo)
            transitionTo(ComponentState.READY)
        } catch (e: Exception) {
            transitionTo(ComponentState.FAILED)
            throw SDKError.ModelLoadingFailed("Failed to load TTS model: ${modelInfo.id}")
        }
    }

    /**
     * Stop current synthesis (iOS-style)
     */
    fun stop() {
        _isSynthesizing.value = false
        service?.stop()
    }

    /**
     * Cancel current synthesis (compatibility)
     */
    fun cancelSynthesis() = stop()

    /**
     * Progressive TTS for streaming text generation (iOS StreamingTTSHandler equivalent)
     */
    fun processIncrementalText(token: String): Flow<ByteArray> {
        return streamingTTSHandler.processToken(token, TTSOptions())
    }

    /**
     * Flush remaining buffered text
     */
    fun flushRemainingText(): Flow<ByteArray> {
        return streamingTTSHandler.flushRemaining(TTSOptions())
    }

    // MARK: - Private Helper Methods

    /**
     * Create TTSOptions from TTSInput (iOS-style options creation)
     */
    private fun createTTSOptions(input: TTSInput): TTSOptions {
        val voice = if (input.voiceId != null) {
            getAvailableVoices().find { it.id == input.voiceId } ?: TTSVoice.DEFAULT
        } else {
            ttsConfiguration.defaultVoice
        }

        return TTSOptions(
            voice = voice,
            rate = ttsConfiguration.defaultRate,
            pitch = ttsConfiguration.defaultPitch,
            volume = ttsConfiguration.defaultVolume,
            language = input.language,
            outputFormat = ttsConfiguration.outputFormat
        )
    }

    /**
     * Estimate audio duration from byte array
     */
    private fun estimateAudioDuration(audioData: ByteArray, format: TTSOutputFormat): Double {
        return when (format) {
            TTSOutputFormat.PCM_16KHZ -> audioData.size.toDouble() / (16000 * 2) // 16-bit samples
            TTSOutputFormat.PCM_8KHZ -> audioData.size.toDouble() / (8000 * 2)
            TTSOutputFormat.PCM_24KHZ -> audioData.size.toDouble() / (24000 * 2)
            TTSOutputFormat.PCM_48KHZ -> audioData.size.toDouble() / (48000 * 2)
            else -> audioData.size.toDouble() / (16000 * 2) // Default estimation
        }
    }
}

// MARK: - Structured I/O Models (iOS-style)

/**
 * TTS Input model matching iOS TTSInput
 */
@Serializable
data class TTSInput(
    val text: String,
    val textToSynthesize: String = text,
    val isSSML: Boolean = false,
    val voiceId: String? = null,
    val language: String? = null
) : ComponentInput {
    override fun validate() {
        require(text.isNotBlank()) { "Text cannot be blank" }
        require(textToSynthesize.isNotBlank()) { "Text to synthesize cannot be blank" }
    }
}

/**
 * TTS Output model matching iOS TTSOutput with comprehensive metadata
 */
@Serializable
data class TTSOutput(
    val audioData: ByteArray,
    val format: TTSOutputFormat,
    val duration: Double,
    val metadata: SynthesisMetadata,
    override val timestamp: Long = getCurrentTimeMillis()
) : ComponentOutput {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other == null || this::class != other::class) return false

        other as TTSOutput

        if (!audioData.contentEquals(other.audioData)) return false
        if (format != other.format) return false
        if (duration != other.duration) return false
        if (metadata != other.metadata) return false
        if (timestamp != other.timestamp) return false

        return true
    }

    override fun hashCode(): Int {
        var result = audioData.contentHashCode()
        result = 31 * result + format.hashCode()
        result = 31 * result + duration.hashCode()
        result = 31 * result + metadata.hashCode()
        result = 31 * result + timestamp.hashCode()
        return result
    }
}

/**
 * Synthesis metadata (iOS-style comprehensive tracking)
 */
@Serializable
data class SynthesisMetadata(
    val voice: TTSVoice,
    val language: String,
    val processingTimeMs: Long,
    val audioFormat: TTSOutputFormat,
    val sampleRate: Int,
    val originalText: String,
    val processedText: String,
    val synthesizedAt: Long,
    val phonemeTimestamps: List<PhonemeTimestamp>? = null
)

/**
 * Phoneme timestamp for advanced TTS features
 */
@Serializable
data class PhonemeTimestamp(
    val phoneme: String,
    val startTime: Double,
    val duration: Double
)

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
 * TTS Service interface - Enhanced to match iOS TTSService protocol
 */
interface TTSService {
    suspend fun initialize() // iOS-style initialization

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
    fun stop() // iOS-style stop method

    val isSynthesizing: Boolean // iOS-style state property
    val availableVoiceIds: List<String> // iOS compatibility

    suspend fun cleanup() // iOS-style cleanup
}

/**
 * Adapter for ModuleRegistry providers - Enhanced with iOS-style interface
 */
class TTSServiceAdapter(
    private val provider: TTSServiceProvider
) : TTSService {
    private var _isSynthesizing = false

    override suspend fun initialize() {
        // Provider-specific initialization if needed
    }

    override suspend fun synthesize(
        text: String,
        voice: TTSVoice,
        rate: Float,
        pitch: Float,
        volume: Float
    ): ByteArray {
        _isSynthesizing = true
        return try {
            provider.synthesize(text, TTSOptions(voice, rate, pitch, volume))
        } finally {
            _isSynthesizing = false
        }
    }

    override fun synthesizeStream(
        text: String,
        voice: TTSVoice,
        rate: Float,
        pitch: Float,
        volume: Float
    ): Flow<ByteArray> {
        return flow {
            _isSynthesizing = true
            try {
                provider.synthesizeStream(text, TTSOptions(voice, rate, pitch, volume)).collect { chunk ->
                    emit(chunk)
                }
            } finally {
                _isSynthesizing = false
            }
        }
    }

    override fun getAvailableVoices(): List<TTSVoice> = listOf(TTSVoice.DEFAULT)

    override val availableVoiceIds: List<String>
        get() = getAvailableVoices().map { it.id }

    override val isSynthesizing: Boolean
        get() = _isSynthesizing

    override suspend fun loadModel(modelInfo: ModelInfo) {
        // Provider handles model loading
    }

    override fun cancelCurrent() {
        _isSynthesizing = false
    }

    override fun stop() = cancelCurrent()

    override suspend fun cleanup() {
        _isSynthesizing = false
    }
}

/**
 * Default TTS service implementation - Enhanced with iOS-style patterns
 */
class DefaultTTSService : TTSService {
    private var _isSynthesizing = false

    override suspend fun initialize() {
        // Platform-specific initialization will be in actual implementations
    }

    override suspend fun synthesize(
        text: String,
        voice: TTSVoice,
        rate: Float,
        pitch: Float,
        volume: Float
    ): ByteArray {
        _isSynthesizing = true
        try {
            // Default implementation - platform-specific implementations will override
            return ByteArray(0)
        } finally {
            _isSynthesizing = false
        }
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

    override val availableVoiceIds: List<String>
        get() = getAvailableVoices().map { it.id }

    override val isSynthesizing: Boolean
        get() = _isSynthesizing

    override suspend fun loadModel(modelInfo: ModelInfo) {
        // Model loading implementation
    }

    override fun cancelCurrent() {
        _isSynthesizing = false
    }

    override fun stop() = cancelCurrent()

    override suspend fun cleanup() {
        _isSynthesizing = false
    }
}

// MARK: - Progressive Streaming Handler (iOS StreamingTTSHandler equivalent)

/**
 * Progressive sentence-based TTS for streaming text generation
 * Matches iOS StreamingTTSHandler functionality
 */
class StreamingTTSHandler {
    private var spokenText = ""
    private var pendingBuffer = ""
    private val sentenceDelimiters = setOf('.', '!', '?')

    /**
     * Process incremental text token and return audio if complete sentences are found
     */
    fun processToken(token: String, options: TTSOptions): Flow<ByteArray> = flow {
        pendingBuffer += token
        val sentences = extractCompleteSentences()

        for (sentence in sentences) {
            // This would need to be connected to the actual TTS service
            // For now, emit empty data as placeholder
            emit(ByteArray(0))
            spokenText += sentence
        }
    }

    /**
     * Flush any remaining text in the buffer
     */
    fun flushRemaining(options: TTSOptions): Flow<ByteArray> = flow {
        if (pendingBuffer.isNotBlank()) {
            emit(ByteArray(0)) // Placeholder implementation
            spokenText += pendingBuffer
            pendingBuffer = ""
        }
    }

    private fun extractCompleteSentences(): List<String> {
        val sentences = mutableListOf<String>()
        var currentSentence = ""

        for (char in pendingBuffer) {
            currentSentence += char
            if (char in sentenceDelimiters) {
                sentences.add(currentSentence.trim())
                currentSentence = ""
            }
        }

        // Update pending buffer to remaining incomplete sentence
        pendingBuffer = currentSentence
        return sentences
    }

    fun reset() {
        spokenText = ""
        pendingBuffer = ""
    }
}

// MARK: - SSML Processing (Enhanced from basic regex)

/**
 * SSML Processor interface - comprehensive SSML support
 */
interface SSMLProcessor {
    fun parse(ssml: String): ParsedSSML
    fun validate(ssml: String): ValidationResult
    fun extractPlainText(ssml: String): String
}

/**
 * Default SSML processor implementation
 */
class DefaultSSMLProcessor : SSMLProcessor {
    override fun parse(ssml: String): ParsedSSML {
        // Enhanced SSML parsing - for now, basic implementation
        val plainText = extractPlainText(ssml)
        return ParsedSSML(
            plainText = plainText,
            prosodyTags = extractProsodyTags(ssml),
            voiceTags = extractVoiceTags(ssml)
        )
    }

    override fun validate(ssml: String): ValidationResult {
        val errors = mutableListOf<String>()

        // Basic validation - check for balanced tags
        if (!areTagsBalanced(ssml)) {
            errors.add("Unbalanced SSML tags")
        }

        return ValidationResult(
            isValid = errors.isEmpty(),
            errors = errors
        )
    }

    override fun extractPlainText(ssml: String): String {
        return ssml.replace(Regex("<[^>]*>"), "").trim()
    }

    private fun extractProsodyTags(ssml: String): List<ProsodyTag> {
        // Implementation for extracting prosody information
        return emptyList()
    }

    private fun extractVoiceTags(ssml: String): List<VoiceTag> {
        // Implementation for extracting voice information
        return emptyList()
    }

    private fun areTagsBalanced(ssml: String): Boolean {
        // Basic implementation - count opening and closing tags
        val openTags = Regex("<[^/][^>]*>").findAll(ssml).count()
        val closeTags = Regex("</[^>]*>").findAll(ssml).count()
        return openTags == closeTags
    }
}

/**
 * Parsed SSML structure
 */
@Serializable
data class ParsedSSML(
    val plainText: String,
    val prosodyTags: List<ProsodyTag>,
    val voiceTags: List<VoiceTag>
)

/**
 * SSML Validation result
 */
data class ValidationResult(
    val isValid: Boolean,
    val errors: List<String>
)

/**
 * SSML Prosody tag information
 */
@Serializable
data class ProsodyTag(
    val rate: String?,
    val pitch: String?,
    val volume: String?
)

/**
 * SSML Voice tag information
 */
@Serializable
data class VoiceTag(
    val name: String?,
    val gender: String?,
    val age: String?
)
