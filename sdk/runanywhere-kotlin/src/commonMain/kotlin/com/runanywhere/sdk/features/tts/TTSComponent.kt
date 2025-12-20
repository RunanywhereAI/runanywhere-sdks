package com.runanywhere.sdk.features.tts

import com.runanywhere.sdk.core.AudioFormat
import com.runanywhere.sdk.core.capabilities.BaseComponent
import com.runanywhere.sdk.core.capabilities.ComponentState
import com.runanywhere.sdk.core.capabilities.SDKComponent
import com.runanywhere.sdk.core.capabilities.ComponentConfiguration
import com.runanywhere.sdk.core.capabilities.ComponentInput
import com.runanywhere.sdk.core.capabilities.ComponentOutput
import com.runanywhere.sdk.data.models.ModelInfo
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.core.TTSServiceProvider
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.flow.*
import kotlinx.serialization.Serializable

/**
 * TTS Component for text-to-speech synthesis
 * Aligned with iOS TTSComponent.swift architecture - comprehensive multi-layered implementation
 * Features:
 * - Structured I/O models (TTSInput/TTSOutput) with metadata
 * - Progressive streaming with sentence-by-sentence synthesis
 * - Event-driven pipeline integration with analytics tracking
 * - Rich voice management with TTSVoice objects
 * - Flow-based streaming using Kotlin coroutines
 * - StateFlow state management for reactive synthesis
 */
class TTSComponent(
    private val ttsConfiguration: TTSConfiguration,
    private val analyticsService: TTSAnalyticsService = TTSAnalyticsService()
) : BaseComponent<TTSService>(ttsConfiguration) {

    private val logger = SDKLogger("TTSComponent")

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
     * Main synthesis method with structured input - aligned with iOS process() method
     */
    suspend fun synthesize(input: TTSInput): TTSOutput {
        ensureReady()
        input.validate()

        _isSynthesizing.value = true

        // Get text to synthesize - SSML takes priority (iOS pattern)
        val textToSynthesize = input.ssml ?: input.text

        // Create options from input or use defaults (iOS pattern)
        val options = input.options ?: TTSOptions(
            voice = input.voiceId ?: ttsConfiguration.voice,
            language = input.language ?: ttsConfiguration.language,
            rate = ttsConfiguration.speakingRate,
            pitch = ttsConfiguration.pitch,
            volume = ttsConfiguration.volume,
            audioFormat = ttsConfiguration.audioFormat,
            sampleRate = if (ttsConfiguration.audioFormat == AudioFormat.PCM) 16000 else 44100,
            useSSML = input.ssml != null
        )
        _currentOptions.value = options

        // Start analytics tracking (iOS pattern)
        val synthesisId = analyticsService.startSynthesis(
            text = textToSynthesize,
            voice = options.voice ?: ttsConfiguration.voice
        )

        return try {
            // Perform synthesis
            val audioData = service?.synthesize(
                text = textToSynthesize,
                options = options
            ) ?: throw SDKError.ComponentFailure("TTS service not initialized")

            // Estimate audio duration
            val duration = estimateAudioDuration(audioData, ttsConfiguration.audioFormat)
            val audioDurationMs = duration * 1000.0

            // Complete analytics tracking (iOS pattern)
            analyticsService.completeSynthesis(
                synthesisId = synthesisId,
                audioDurationMs = audioDurationMs,
                audioSizeBytes = audioData.size
            )

            // Create metadata (iOS pattern)
            val metadata = SynthesisMetadata(
                voice = options.voice ?: ttsConfiguration.voice,
                language = options.language,
                processingTime = duration, // Using duration as proxy for now
                characterCount = textToSynthesize.length
            )

            // Create output (iOS pattern)
            TTSOutput(
                audioData = audioData,
                format = ttsConfiguration.audioFormat,
                duration = duration,
                phonemeTimestamps = null,  // Would be extracted from service if available
                metadata = metadata
            )
        } catch (e: Exception) {
            // Track failure
            analyticsService.trackSynthesisFailed(
                synthesisId = synthesisId,
                errorMessage = e.message ?: "Unknown error"
            )
            throw e
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
     * Synthesize with SSML markup - aligned with iOS synthesizeSSML()
     */
    suspend fun synthesizeSSML(
        ssml: String,
        voice: String? = null,
        language: String? = null
    ): TTSOutput {
        ensureReady()

        // Create input with SSML - iOS pattern: text is empty, ssml contains markup
        val input = TTSInput(
            text = "",
            ssml = ssml,
            voiceId = voice,
            language = language
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

    // MARK: - Analytics (iOS pattern)

    /**
     * Get analytics metrics for this component (iOS getAnalyticsMetrics())
     */
    fun getAnalyticsMetrics(): TTSMetrics {
        return analyticsService.getMetrics()
    }

    // MARK: - Private Helper Methods

    /**
     * Estimate audio duration from byte array - aligned with iOS estimateAudioDuration()
     */
    private fun estimateAudioDuration(audioData: ByteArray, format: AudioFormat): Double {
        // iOS pattern: rough estimation based on format and typical bitrates
        val bytesPerSecond = when (format) {
            AudioFormat.PCM, AudioFormat.WAV -> 32000  // 16-bit PCM at 16kHz
            AudioFormat.MP3 -> 16000                   // 128kbps MP3
            else -> 32000
        }
        return audioData.size.toDouble() / bytesPerSecond
    }
}

// MARK: - Structured I/O Models (iOS-style)

/**
 * TTS Input model - aligned with iOS TTSInput
 * iOS has: text, ssml, voiceId, language, options
 */
@Serializable
data class TTSInput(
    val text: String,                      // iOS: text
    val ssml: String? = null,              // iOS: ssml (optional SSML markup, overrides text)
    val voiceId: String? = null,           // iOS: voiceId
    val language: String? = null,          // iOS: language
    val options: TTSOptions? = null        // iOS: options (custom options override)
) : ComponentInput {
    override fun validate() {
        // iOS: if text.isEmpty && ssml == nil, throw error
        require(text.isNotEmpty() || ssml != null) { "TTSInput must contain either text or SSML" }
    }

    /**
     * Get the text to synthesize - SSML takes priority over text (iOS pattern)
     */
    val textToSynthesize: String
        get() = ssml ?: text
}

/**
 * TTS Output model - aligned with iOS TTSOutput
 * iOS has: audioData, format, duration, phonemeTimestamps, metadata, timestamp
 */
@Serializable
data class TTSOutput(
    val audioData: ByteArray,                           // iOS: audioData as Data
    val format: AudioFormat,                            // iOS: format as AudioFormat
    val duration: Double,                               // iOS: duration as TimeInterval (seconds)
    val phonemeTimestamps: List<PhonemeTimestamp>? = null, // iOS: phonemeTimestamps
    val metadata: SynthesisMetadata,                    // iOS: metadata
    override val timestamp: Long = getCurrentTimeMillis() // iOS: timestamp as Date
) : ComponentOutput {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other == null || this::class != other::class) return false

        other as TTSOutput

        if (!audioData.contentEquals(other.audioData)) return false
        if (format != other.format) return false
        if (duration != other.duration) return false
        if (phonemeTimestamps != other.phonemeTimestamps) return false
        if (metadata != other.metadata) return false
        if (timestamp != other.timestamp) return false

        return true
    }

    override fun hashCode(): Int {
        var result = audioData.contentHashCode()
        result = 31 * result + format.hashCode()
        result = 31 * result + duration.hashCode()
        result = 31 * result + (phonemeTimestamps?.hashCode() ?: 0)
        result = 31 * result + metadata.hashCode()
        result = 31 * result + timestamp.hashCode()
        return result
    }
}

/**
 * Synthesis metadata - aligned with iOS SynthesisMetadata
 * iOS has: voice (String), language, processingTime, characterCount, charactersPerSecond (computed)
 */
@Serializable
data class SynthesisMetadata(
    val voice: String,                    // iOS: voice as String identifier
    val language: String,
    val processingTime: Double,           // iOS: processingTime as TimeInterval (seconds)
    val characterCount: Int               // iOS: characterCount
) {
    /**
     * Characters per second - computed from characterCount / processingTime (iOS pattern)
     */
    val charactersPerSecond: Double
        get() = if (processingTime > 0) characterCount.toDouble() / processingTime else 0.0
}

/**
 * Phoneme timestamp information - aligned with iOS PhonemeTimestamp
 * iOS has: phoneme, startTime, endTime
 */
@Serializable
data class PhonemeTimestamp(
    val phoneme: String,
    val startTime: Double,    // iOS: startTime as TimeInterval
    val endTime: Double       // iOS: endTime as TimeInterval
)

/**
 * TTS Options - aligned exactly with iOS TTSOptions
 * iOS has: voice, language, rate, pitch, volume, audioFormat, sampleRate, useSSML
 */
@Serializable
data class TTSOptions(
    val voice: String? = null,             // iOS: voice (optional voice identifier)
    val language: String = "en-US",        // iOS: language
    val rate: Float = 1.0f,                // iOS: rate (0.0 to 2.0, 1.0 is normal)
    val pitch: Float = 1.0f,               // iOS: pitch (0.0 to 2.0, 1.0 is normal)
    val volume: Float = 1.0f,              // iOS: volume (0.0 to 1.0)
    val audioFormat: AudioFormat = AudioFormat.PCM,  // iOS: audioFormat
    val sampleRate: Int = 16000,           // iOS: sampleRate
    val useSSML: Boolean = false           // iOS: useSSML
)

/**
 * TTS Voice configuration - KMP extension for rich voice information
 * Note: iOS only uses simple string voice identifiers, this is a KMP enhancement
 */
@Serializable
data class TTSVoice(
    val id: String,
    val name: String,
    val language: String,
    val gender: TTSGender = TTSGender.NEUTRAL
) {
    companion object {
        val DEFAULT = TTSVoice(
            id = "default",
            name = "Default Voice",
            language = "en-US",
            gender = TTSGender.NEUTRAL
        )
    }
}

/**
 * TTS Gender types - KMP extension for voice metadata
 */
@Serializable
enum class TTSGender {
    MALE,
    FEMALE,
    NEUTRAL
}

// AudioFormat is imported from core package (core/AudioTypes.kt)
// The shared AudioFormat enum has: PCM, WAV, MP3, OPUS, AAC, FLAC, OGG, PCM_16BIT

/**
 * TTS Configuration - aligned with iOS TTSConfiguration
 * iOS has: voice, language, speakingRate, pitch, volume, audioFormat, useNeuralVoice, enableSSML
 */
data class TTSConfiguration(
    val modelId: String? = null,                                    // Model path for ONNX models
    val voice: String = "default",                                  // iOS: voice identifier string
    val language: String = "en-US",                                 // iOS: language
    val speakingRate: Float = 1.0f,                                 // iOS: speakingRate (0.5 to 2.0)
    val pitch: Float = 1.0f,                                        // iOS: pitch (0.5 to 2.0)
    val volume: Float = 1.0f,                                       // iOS: volume (0.0 to 1.0)
    val audioFormat: AudioFormat = AudioFormat.PCM,                 // iOS: audioFormat
    val useNeuralVoice: Boolean = true,                             // iOS: useNeuralVoice
    val enableSSML: Boolean = false                                 // iOS: enableSSML (default false in iOS)
) : ComponentConfiguration {
    override fun validate() {
        require(speakingRate >= 0.5f && speakingRate <= 2.0f) { "Speaking rate must be between 0.5 and 2.0" }
        require(pitch >= 0.5f && pitch <= 2.0f) { "Pitch must be between 0.5 and 2.0" }
        require(volume >= 0f && volume <= 1f) { "Volume must be between 0.0 and 1.0" }
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
    private val logger = SDKLogger("StreamingTTSHandler")

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
            voice = config?.voice,
            language = config?.language ?: "en-US",
            rate = config?.speakingRate ?: 1.0f,
            pitch = config?.pitch ?: 1.0f,
            volume = config?.volume ?: 1.0f
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
            logger.error("TTS failed for sentence", e)
        }
    }
}

// Note: SSML processing is handled by the underlying TTS service
// iOS simply passes SSML markup to the service via useSSML flag in TTSOptions
