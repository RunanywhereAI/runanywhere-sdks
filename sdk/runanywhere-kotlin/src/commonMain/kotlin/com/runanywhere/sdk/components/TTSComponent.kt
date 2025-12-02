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

    private val _audioFormat = MutableStateFlow(ttsConfiguration.audioFormat)
    val audioFormat: StateFlow<AudioFormat> = _audioFormat.asStateFlow()

    // MARK: - Progressive Streaming Support

    private var streamingTTSHandler: StreamingTTSHandler? = null
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

        // Initialize streaming handler with service
        service?.let { ttsService ->
            streamingTTSHandler = StreamingTTSHandler(ttsService)
        }

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

            // Perform synthesis using iOS-compatible interface
            val audioData = service?.synthesize(
                text = input.textToSynthesize,
                options = options
            ) ?: throw SDKError.ComponentFailure("TTS service not initialized")

            // Calculate processing metrics
            val processingTime = getCurrentTimeMillis() - startTime
            val estimatedDuration = estimateAudioDuration(audioData, options.audioFormat)

            // Create comprehensive output with metadata (iOS compatible with AudioFormat)
            TTSOutput(
                audioData = audioData,
                format = options.audioFormat, // iOS-compatible AudioFormat
                duration = estimatedDuration,
                metadata = SynthesisMetadata(
                    voice = options.effectiveVoice,
                    language = options.language,
                    processingTimeMs = processingTime,
                    audioFormat = options.audioFormat, // iOS-compatible AudioFormat
                    sampleRate = options.sampleRate,
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
                options = options,
                onChunk = onChunk
            ) ?: throw SDKError.ComponentFailure("TTS service not initialized")
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
                    options = options
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
    fun getAllVoices(): List<TTSVoice> {
        return service?.getAllVoices() ?: listOf(TTSVoice.DEFAULT)
    }


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
     * Returns true if TTS was triggered for complete sentences
     */
    suspend fun processIncrementalText(token: String, options: TTSOptions? = null): Boolean {
        return streamingTTSHandler?.processToken(token, options) ?: false
    }

    /**
     * Flow-based progressive TTS (Kotlin-native pattern)
     */
    fun processIncrementalTextFlow(token: String, options: TTSOptions = TTSOptions()): Flow<ByteArray> {
        return streamingTTSHandler?.processTokenFlow(token, options) ?: emptyFlow()
    }

    /**
     * Flush remaining buffered text (iOS equivalent)
     */
    suspend fun flushRemainingText(options: TTSOptions? = null) {
        streamingTTSHandler?.flushRemaining(options)
    }

    /**
     * Flow-based flush (Kotlin-native pattern)
     */
    fun flushRemainingTextFlow(options: TTSOptions = TTSOptions()): Flow<ByteArray> {
        return streamingTTSHandler?.flushRemainingFlow(options) ?: emptyFlow()
    }

    /**
     * Reset streaming handler for new session (iOS equivalent)
     */
    fun resetStreamingSession() {
        streamingTTSHandler?.reset()
    }

    // MARK: - Private Helper Methods

    /**
     * Create TTSOptions from TTSInput (iOS-style options creation)
     * Note: The voiceId is set to the model path (ttsConfiguration.modelId) for ONNX models,
     * similar to iOS where the voice field in TTSConfiguration contains the model path.
     */
    private fun createTTSOptions(input: TTSInput): TTSOptions {
        val voice = if (input.voiceId != null) {
            getAllVoices().find { it.id == input.voiceId } ?: TTSVoice.DEFAULT
        } else {
            ttsConfiguration.defaultVoice
        }

        // Use model ID from configuration as the voice ID for ONNX model path resolution
        // This matches iOS behavior where configuration.voice contains the model path
        val effectiveVoiceId = ttsConfiguration.modelId ?: input.voiceId

        return TTSOptions(
            voiceId = effectiveVoiceId,
            voice = voice,
            language = input.language ?: voice.language,
            rate = ttsConfiguration.defaultRate,
            pitch = ttsConfiguration.defaultPitch,
            volume = ttsConfiguration.defaultVolume,
            audioFormat = ttsConfiguration.audioFormat, // iOS-compatible AudioFormat
            sampleRate = ttsConfiguration.sampleRate,
            useSSML = input.isSSML
        )
    }

    /**
     * Estimate audio duration from byte array - iOS-compatible using AudioFormat
     */
    private fun estimateAudioDuration(audioData: ByteArray, format: AudioFormat): Double {
        return when (format) {
            AudioFormat.PCM, AudioFormat.WAV -> audioData.size.toDouble() / (16000 * 2) // 16-bit samples
            AudioFormat.MP3, AudioFormat.AAC -> audioData.size.toDouble() / (16000 * 2) // Estimate for compressed
            AudioFormat.FLAC, AudioFormat.OPUS -> audioData.size.toDouble() / (16000 * 2)
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
    val format: AudioFormat, // iOS-compatible AudioFormat
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
    val audioFormat: AudioFormat, // iOS-compatible AudioFormat
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
 * TTS Options matching iOS TTSOptions structure for full parity
 * Supports both string-based voice selection (iOS style) and rich TTSVoice objects (KMP style)
 */
@Serializable
data class TTSOptions(
    // iOS-compatible voice selection - can be voice identifier string
    val voiceId: String? = null,

    // Rich voice object for KMP-style usage
    val voice: TTSVoice = TTSVoice.DEFAULT,

    // Core parameters matching iOS exactly
    val language: String = "en-US",
    val rate: Float = 1.0f,     // Speech rate (0.0 to 2.0, 1.0 is normal) - iOS compatible
    val pitch: Float = 1.0f,    // Speech pitch (0.0 to 2.0, 1.0 is normal) - iOS compatible
    val volume: Float = 1.0f,   // Speech volume (0.0 to 1.0) - iOS compatible

    // Audio format - iOS compatible
    val audioFormat: AudioFormat = AudioFormat.PCM,
    val sampleRate: Int = 16000,

    // SSML support - iOS compatible
    val useSSML: Boolean = false
) {
    /**
     * Get effective voice - prioritizes voiceId (iOS style) over voice object
     */
    val effectiveVoice: TTSVoice
        get() = if (voiceId != null) {
            TTSVoice(
                id = voiceId,
                name = voiceId,
                language = language,
                gender = TTSGender.NEUTRAL
            )
        } else {
            voice
        }

    /**
     * iOS-style constructor for string-based voice selection
     */
    constructor(
        voice: String? = null,
        language: String = "en-US",
        rate: Float = 1.0f,
        pitch: Float = 1.0f,
        volume: Float = 1.0f,
        audioFormat: AudioFormat = AudioFormat.PCM,
        sampleRate: Int = 16000,
        useSSML: Boolean = false
    ) : this(
        voiceId = voice,
        voice = TTSVoice.DEFAULT,
        language = language,
        rate = rate,
        pitch = pitch,
        volume = volume,
        audioFormat = audioFormat,
        sampleRate = sampleRate,
        useSSML = useSSML
    )
}

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
 * Audio format enum matching iOS AudioFormat pattern
 * Aligned with iOS TTSOptions.audioFormat for cross-platform consistency
 */
@Serializable
enum class AudioFormat {
    PCM,
    WAV,
    MP3,
    AAC,
    FLAC,
    OPUS;

    val sampleRate: Int
        get() = when (this) {
            PCM, WAV -> 16000
            MP3, AAC -> 16000
            FLAC, OPUS -> 16000
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
    val audioFormat: AudioFormat = AudioFormat.PCM, // iOS-compatible AudioFormat
    val sampleRate: Int = 16000, // Sample rate (iOS typically uses this)
    val enableSSML: Boolean = true
) : ComponentConfiguration {
    override fun validate() {
        require(defaultRate > 0f && defaultRate <= 3f) { "Rate must be between 0 and 3" }
        require(defaultPitch > 0f && defaultPitch <= 2f) { "Pitch must be between 0 and 2" }
        require(defaultVolume >= 0f && defaultVolume <= 1f) { "Volume must be between 0 and 1" }
        require(sampleRate > 0) { "Sample rate must be positive" }
    }
}

/**
 * TTS Service interface - Enhanced to exactly match iOS TTSService protocol
 * Provides both iOS-style string-based API and KMP-style rich object API for full parity
 */
interface TTSService {
    /**
     * Initialize the TTS service (iOS TTSService.initialize())
     */
    suspend fun initialize()

    /**
     * iOS-style synthesize method with options object
     * Matches: func synthesize(text: String, options: TTSOptions) async throws -> Data
     */
    suspend fun synthesize(text: String, options: TTSOptions): ByteArray

    /**
     * iOS-style stream synthesis with callback
     * Matches: func synthesizeStream(text: String, options: TTSOptions, onChunk: @escaping (Data) -> Void)
     */
    suspend fun synthesizeStream(
        text: String,
        options: TTSOptions,
        onChunk: suspend (ByteArray) -> Unit
    )

    /**
     * KMP Flow-based streaming (Kotlin-native pattern)
     */
    fun synthesizeStream(text: String, options: TTSOptions): Flow<ByteArray>

    /**
     * Stop current synthesis (iOS TTSService.stop())
     */
    fun stop()

    /**
     * Check if currently synthesizing (iOS TTSService.isSynthesizing)
     */
    val isSynthesizing: Boolean

    /**
     * Get available voices (iOS TTSService.availableVoices)
     * Returns string identifiers for iOS compatibility
     */
    val availableVoices: List<String>

    /**
     * Get rich voice objects (KMP enhancement)
     */
    fun getAllVoices(): List<TTSVoice>

    /**
     * Cleanup resources (iOS TTSService.cleanup())
     */
    suspend fun cleanup()

    // KMP-specific extensions
    suspend fun loadModel(modelInfo: ModelInfo)
    fun cancelCurrent()
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

    // iOS-style synthesize method
    override suspend fun synthesize(text: String, options: TTSOptions): ByteArray {
        _isSynthesizing = true
        return try {
            provider.synthesize(text, options)
        } finally {
            _isSynthesizing = false
        }
    }

    // iOS-style callback streaming
    override suspend fun synthesizeStream(
        text: String,
        options: TTSOptions,
        onChunk: suspend (ByteArray) -> Unit
    ) {
        _isSynthesizing = true
        try {
            provider.synthesizeStream(text, options).collect { chunk ->
                onChunk(chunk)
            }
        } finally {
            _isSynthesizing = false
        }
    }

    // KMP-style Flow streaming
    override fun synthesizeStream(text: String, options: TTSOptions): Flow<ByteArray> {
        return flow {
            _isSynthesizing = true
            try {
                provider.synthesizeStream(text, options).collect { chunk ->
                    emit(chunk)
                }
            } finally {
                _isSynthesizing = false
            }
        }
    }

    override fun getAllVoices(): List<TTSVoice> = listOf(TTSVoice.DEFAULT)

    override val availableVoices: List<String>
        get() = getAllVoices().map { it.id }


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

    // iOS-style synthesize method
    override suspend fun synthesize(text: String, options: TTSOptions): ByteArray {
        _isSynthesizing = true
        try {
            // Default implementation - platform-specific implementations will override
            return ByteArray(0)
        } finally {
            _isSynthesizing = false
        }
    }

    // iOS-style callback streaming
    override suspend fun synthesizeStream(
        text: String,
        options: TTSOptions,
        onChunk: suspend (ByteArray) -> Unit
    ) {
        _isSynthesizing = true
        try {
            val audioData = synthesize(text, options)
            if (audioData.isNotEmpty()) {
                onChunk(audioData)
            }
        } finally {
            _isSynthesizing = false
        }
    }

    // KMP-style Flow streaming
    override fun synthesizeStream(text: String, options: TTSOptions): Flow<ByteArray> {
        return flow {
            val audioData = synthesize(text, options)
            if (audioData.isNotEmpty()) {
                emit(audioData)
            }
        }
    }

    override fun getAllVoices(): List<TTSVoice> = listOf(TTSVoice.DEFAULT)

    override val availableVoices: List<String>
        get() = getAllVoices().map { it.id }


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
 * Enhanced to exactly match iOS StreamingTTSHandler functionality and patterns
 */
class StreamingTTSHandler(private val ttsService: TTSService) {
    // State tracking matching iOS implementation
    private var spokenText = ""
    private var pendingBuffer = ""

    // Configuration matching iOS
    private val sentenceDelimiters = setOf('.', '!', '?')
    private val minSentenceLength = 3 // Minimum characters for a valid sentence

    /**
     * Reset the handler for a new streaming session (iOS equivalent)
     */
    fun reset() {
        spokenText = ""
        pendingBuffer = ""
    }

    /**
     * Process a new token from the streaming response (iOS equivalent)
     * Returns true if TTS was triggered
     */
    suspend fun processToken(
        token: String,
        options: TTSOptions? = null
    ): Boolean {
        // Add token to pending buffer
        pendingBuffer += token

        // Check for complete sentences
        val sentences = extractCompleteSentences()

        return if (sentences.isNotEmpty()) {
            // Speak the complete sentences
            for (sentence in sentences) {
                speakSentence(sentence, options ?: TTSOptions())
            }
            true
        } else {
            false
        }
    }

    /**
     * Flow-based token processing for Kotlin-native usage
     */
    fun processTokenFlow(token: String, options: TTSOptions): Flow<ByteArray> = flow {
        pendingBuffer += token
        val sentences = extractCompleteSentences()

        for (sentence in sentences) {
            if (sentence.length >= minSentenceLength) {
                val audioData = ttsService.synthesize(sentence, options)
                if (audioData.isNotEmpty()) {
                    emit(audioData)
                }
                spokenText += sentence
            }
        }
    }

    /**
     * Speak any remaining text in the buffer (iOS equivalent: flushRemaining)
     */
    suspend fun flushRemaining(options: TTSOptions? = null) {
        val remainingText = pendingBuffer.trim()
        pendingBuffer = ""

        if (remainingText.isNotEmpty() && !spokenText.contains(remainingText)) {
            speakSentence(remainingText, options ?: TTSOptions())
        }
    }

    /**
     * Flow-based flush for Kotlin-native usage
     */
    fun flushRemainingFlow(options: TTSOptions): Flow<ByteArray> = flow {
        if (pendingBuffer.isNotBlank()) {
            val remainingText = pendingBuffer.trim()
            pendingBuffer = ""

            if (remainingText.isNotEmpty() && !spokenText.contains(remainingText)) {
                val audioData = ttsService.synthesize(remainingText, options)
                if (audioData.isNotEmpty()) {
                    emit(audioData)
                }
                spokenText += remainingText
            }
        }
    }

    /**
     * Process streaming text with default TTS options from config (iOS equivalent)
     */
    suspend fun processStreamingText(
        text: String,
        config: TTSConfiguration?
    ): Boolean {
        val options = TTSOptions(
            voiceId = config?.defaultVoice?.id,
            language = config?.defaultVoice?.language ?: "en-US",
            rate = config?.defaultRate ?: 1.0f,
            pitch = config?.defaultPitch ?: 1.0f,
            volume = config?.defaultVolume ?: 1.0f
        )

        return processToken(text, options)
    }

    /**
     * Extract complete sentences from the pending buffer (iOS equivalent logic)
     */
    private fun extractCompleteSentences(): List<String> {
        val completeSentences = mutableListOf<String>()
        var currentIndex = 0

        while (currentIndex < pendingBuffer.length) {
            // Find next delimiter
            val delimiterIndex = pendingBuffer.indexOfAny(sentenceDelimiters.toCharArray(), currentIndex)

            if (delimiterIndex != -1) {
                val sentenceEndIndex = delimiterIndex + 1
                val sentence = pendingBuffer.substring(currentIndex, sentenceEndIndex)

                // Check if this sentence is new (not already spoken) and meets minimum length
                val fullTextSoFar = spokenText + sentence
                if (!spokenText.endsWith(sentence) && sentence.length >= minSentenceLength) {
                    completeSentences.add(sentence.trim())
                    spokenText = fullTextSoFar
                }

                currentIndex = sentenceEndIndex
            } else {
                // No more delimiters found
                break
            }
        }

        // Update pending buffer to only contain unprocessed text
        pendingBuffer = if (currentIndex < pendingBuffer.length) {
            pendingBuffer.substring(currentIndex)
        } else {
            ""
        }

        return completeSentences
    }

    /**
     * Speak a single sentence (iOS equivalent: speakSentence)
     */
    private suspend fun speakSentence(sentence: String, options: TTSOptions) {
        if (sentence.isEmpty()) return

        try {
            ttsService.synthesize(sentence, options)
        } catch (e: Exception) {
            // Log error but continue with other sentences
            println("TTS failed for sentence: $e")
        }
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
