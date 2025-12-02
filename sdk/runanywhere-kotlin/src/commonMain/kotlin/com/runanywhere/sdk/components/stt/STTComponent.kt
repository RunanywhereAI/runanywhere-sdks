package com.runanywhere.sdk.components.stt

import com.runanywhere.sdk.components.base.BaseComponent
import com.runanywhere.sdk.components.base.ComponentState
import com.runanywhere.sdk.components.base.SDKComponent
import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import com.runanywhere.sdk.events.ModularPipelineEvent
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.launch

/**
 * Speech-to-Text component matching iOS STTComponent architecture exactly
 */
class STTComponent(
    private val sttConfiguration: STTConfiguration
) : BaseComponent<STTServiceWrapper>(sttConfiguration) {

    override val componentType: SDKComponent = SDKComponent.STT

    private val logger = com.runanywhere.sdk.foundation.SDKLogger("STTComponent")
    private var isModelLoaded = false
    private var modelPath: String? = null

    // iOS parity - STT Handler for voice pipeline integration
    private val sttHandler by lazy {
        STTHandler(
            voiceAnalytics = null, // Will be injected later
            sttAnalytics = null // Will be injected later
        )
    }

    override suspend fun createService(): STTServiceWrapper {
        // Try to get a registered STT provider from central registry
        val provider = ModuleRegistry.sttProvider(sttConfiguration.modelId)
            ?: throw SDKError.ComponentNotInitialized(
                "No STT service provider registered. Please register an STT service provider."
            )

        // Check if model needs downloading
        sttConfiguration.modelId?.let { modelId ->
            modelPath = modelId
            // Provider should handle model management
        }

        // Create service through provider
        val sttService = provider.createSTTService(sttConfiguration)

        // Wrap the service
        val wrapper = STTServiceWrapper(sttService)

        // Service is already initialized by the provider
        isModelLoaded = true

        return wrapper
    }

    override suspend fun initializeService() {
        // Service creation already handles initialization
        logger.info("STT component initialized with model: ${sttConfiguration.modelId}")
    }

    override suspend fun cleanup() {
        service?.wrappedService?.cleanup()
        isModelLoaded = false
        modelPath = null
        state = ComponentState.NOT_INITIALIZED
        logger.info("STT component cleaned up")
    }

    // MARK: - Public API (matches iOS STTComponent)

    /**
     * Transcribe audio data
     */
    suspend fun transcribe(
        audioData: ByteArray,
        format: AudioFormat = AudioFormat.WAV,
        language: String? = null
    ): STTOutput {
        requireReady()

        val input = STTInput(
            audioData = audioData,
            format = format,
            language = language
        )
        return process(input)
    }

    /**
     * Transcribe audio buffer (FloatArray)
     */
    suspend fun transcribe(
        audioBuffer: FloatArray,
        language: String? = null
    ): STTOutput {
        requireReady()

        val input = STTInput(
            audioData = byteArrayOf(), // Empty, use buffer
            audioBuffer = audioBuffer,
            format = AudioFormat.PCM,
            language = language
        )
        return process(input)
    }

    /**
     * Transcribe with VAD context
     */
    suspend fun transcribeWithVAD(
        audioData: ByteArray,
        format: AudioFormat = AudioFormat.WAV,
        vadOutput: com.runanywhere.sdk.components.vad.VADOutput
    ): STTOutput {
        requireReady()

        val input = STTInput(
            audioData = audioData,
            format = format,
            vadOutput = vadOutput
        )
        return process(input)
    }

    /**
     * Process STT input (matches iOS architecture)
     */
    suspend fun process(input: STTInput): STTOutput {
        requireReady()

        val service = service?.wrappedService
            ?: throw SDKError.ComponentNotReady("STT service not available")

        // Validate input
        input.validate()

        // Create options from input or use defaults
        val options = input.options ?: STTOptions(
            language = input.language ?: sttConfiguration.language,
            detectLanguage = input.language == null,
            enablePunctuation = sttConfiguration.enablePunctuation,
            enableDiarization = sttConfiguration.enableDiarization,
            maxSpeakers = null,
            enableTimestamps = sttConfiguration.enableTimestamps,
            vocabularyFilter = sttConfiguration.vocabularyList,
            audioFormat = input.format
        )

        // Get audio data
        val audioData: ByteArray = when {
            input.audioData.isNotEmpty() -> input.audioData
            input.audioBuffer != null -> convertFloatArrayToBytes(input.audioBuffer)
            else -> throw SDKError.ValidationFailed("No audio data provided")
        }

        // Track processing time
        val startTime = getCurrentTimeMillis()

        // Perform transcription
        val result = service.transcribe(audioData = audioData, options = options)

        val processingTime = (getCurrentTimeMillis() - startTime) / 1000.0 // Convert to seconds

        // Convert to strongly typed output
        val wordTimestamps = result.timestamps?.map { timestamp ->
            WordTimestamp(
                word = timestamp.word,
                startTime = timestamp.startTime,
                endTime = timestamp.endTime,
                confidence = timestamp.confidence ?: 0.9f
            )
        }

        val alternatives = result.alternatives?.map { alt ->
            TranscriptionAlternative(
                text = alt.transcript,
                confidence = alt.confidence
            )
        }

        // Calculate audio length (estimate based on data size and format)
        val audioLength = estimateAudioLength(
            dataSize = audioData.size,
            format = input.format,
            sampleRate = sttConfiguration.sampleRate
        )

        val metadata = TranscriptionMetadata(
            modelId = service.currentModel ?: "unknown",
            processingTime = processingTime,
            audioLength = audioLength
        )

        return STTOutput(
            text = result.transcript,
            confidence = result.confidence ?: 0.9f,
            wordTimestamps = wordTimestamps,
            detectedLanguage = result.language,
            alternatives = alternatives,
            metadata = metadata
        )
    }

    /**
     * Enhanced stream transcription with Speaker Diarization support (matches iOS architecture)
     * Uses callbackFlow for thread-safe emissions from any coroutine context
     */
    fun streamTranscribe(
        audioStream: Flow<ByteArray>,
        language: String? = null,
        enableSpeakerDiarization: Boolean = sttConfiguration.enableDiarization
    ): Flow<STTStreamEvent> = callbackFlow {
        requireReady()

        val service = service?.wrappedService
            ?: throw SDKError.ComponentNotReady("STT service not available")

        val streamingOptions = STTStreamingOptions(
            language = language ?: sttConfiguration.language,
            detectLanguage = language == null,
            enablePartialResults = true,
            enableSpeakerDiarization = enableSpeakerDiarization,
            enableAudioLevelMonitoring = true
        )

        // Launch transcription in a coroutine
        val transcriptionJob = launch {
        try {
            // Use enhanced streaming if available, otherwise fall back to basic streaming
            if (service.supportsStreaming) {
                service.transcribeStream(audioStream, streamingOptions).collect { event ->
                        trySend(event)
                }
            } else {
                // Fallback to basic streaming
                    trySend(STTStreamEvent.SpeechStarted)

                val basicOptions = STTOptions(
                    language = streamingOptions.language ?: "en",
                    detectLanguage = streamingOptions.detectLanguage,
                    enablePunctuation = sttConfiguration.enablePunctuation,
                    enableDiarization = streamingOptions.enableSpeakerDiarization,
                    enableTimestamps = false,
                    vocabularyFilter = sttConfiguration.vocabularyList,
                    audioFormat = AudioFormat.PCM
                )

                val result = service.streamTranscribe(
                    audioStream = audioStream,
                    options = basicOptions
                ) { partial ->
                        trySend(STTStreamEvent.PartialTranscription(partial))
                }

                // Emit final result
                    trySend(STTStreamEvent.FinalTranscription(result))
                    trySend(STTStreamEvent.SpeechEnded)
            }
        } catch (error: Exception) {
            val sttError = when (error) {
                is STTError -> error
                else -> STTError.transcriptionFailed(error)
            }
                trySend(STTStreamEvent.Error(sttError))
            }
        }

        // Wait for flow to be closed
        awaitClose {
            transcriptionJob.cancel()
        }
    }

    /**
     * Detect language from audio sample (matches iOS architecture)
     */
    suspend fun detectLanguage(audioData: ByteArray): Map<String, Float> {
        requireReady()

        val service = service?.wrappedService
            ?: throw SDKError.ComponentNotReady("STT service not available")

        return if (service.supportsLanguageDetection) {
            service.detectLanguage(audioData)
        } else {
            // Fallback: use transcription with language detection
            val options = STTOptions(
                language = "auto",
                detectLanguage = true,
                enablePunctuation = false,
                enableTimestamps = false
            )

            val result = service.transcribe(audioData, options)
            result.language?.let { detectedLang ->
                mapOf(detectedLang to 1.0f)
            } ?: emptyMap()
        }
    }

    /**
     * Get supported languages for current service
     */
    fun getSupportedLanguages(): List<String> {
        return service?.wrappedService?.supportedLanguages ?: emptyList()
    }

    /**
     * Check if specific language is supported
     */
    fun supportsLanguage(languageCode: String): Boolean {
        return service?.wrappedService?.supportsLanguage(languageCode) ?: false
    }

    /**
     * Transcribe with automatic language switching based on confidence
     */
    suspend fun transcribeWithAutoLanguage(
        audioData: ByteArray,
        candidateLanguages: List<String> = emptyList(),
        confidenceThreshold: Float = 0.7f
    ): STTOutput {
        requireReady()

        // Step 1: Detect language if not specified
        val detectedLanguages = detectLanguage(audioData)
        val bestLanguage = detectedLanguages.maxByOrNull { it.value }

        val targetLanguage = if (bestLanguage != null && bestLanguage.value >= confidenceThreshold) {
            // Use detected language if confidence is high enough
            bestLanguage.key
        } else if (candidateLanguages.isNotEmpty()) {
            // Try candidate languages
            candidateLanguages.firstOrNull { supportsLanguage(it) }
        } else {
            // Fall back to configuration default
            sttConfiguration.language
        }

        // Step 2: Transcribe with selected language
        return transcribe(
            audioData = audioData,
            language = targetLanguage
        )
    }

    /**
     * Transcribe audio using the voice pipeline handler (matches iOS STTHandler integration)
     */
    suspend fun transcribeAudioWithHandler(
        samples: FloatArray,
        options: STTOptions? = null,
        speakerDiarization: SpeakerDiarizationService? = null,
        continuation: kotlinx.coroutines.flow.MutableSharedFlow<ModularPipelineEvent>
    ): String {
        requireReady()

        val service = service?.wrappedService
            ?: throw SDKError.ComponentNotReady("STT service not available")

        val transcriptionOptions = options ?: STTOptions(
            language = sttConfiguration.language,
            detectLanguage = false,
            enablePunctuation = sttConfiguration.enablePunctuation,
            enableDiarization = sttConfiguration.enableDiarization,
            enableTimestamps = sttConfiguration.enableTimestamps,
            vocabularyFilter = sttConfiguration.vocabularyList
        )

        return sttHandler.transcribeAudio(
            samples = samples,
            service = service,
            options = transcriptionOptions,
            speakerDiarization = speakerDiarization,
            continuation = continuation
        )
    }

    /**
     * Get service for compatibility (matches iOS)
     */
    fun getService(): STTService? {
        return service?.wrappedService
    }

    // MARK: - Capabilities (matches iOS)

    /**
     * Whether the underlying service supports live/streaming transcription
     * If false, `streamTranscribe` will internally fall back to batch processing
     */
    val supportsStreaming: Boolean
        get() = service?.wrappedService?.supportsStreaming ?: false

    /**
     * Get the recommended transcription mode based on service capabilities
     */
    val recommendedMode: STTMode
        get() = if (supportsStreaming) STTMode.LIVE else STTMode.BATCH

    // MARK: - Private Helpers

    private fun requireReady() {
        if (state != ComponentState.READY) {
            throw SDKError.NotInitialized
        }
    }

    private fun convertFloatArrayToBytes(floatArray: FloatArray): ByteArray {
        val byteArray = ByteArray(floatArray.size * 2) // 2 bytes per float (16-bit PCM)
        for (i in floatArray.indices) {
            val sample = (floatArray[i] * 32767).toInt().coerceIn(-32768, 32767)
            byteArray[i * 2] = (sample and 0xFF).toByte()
            byteArray[i * 2 + 1] = ((sample shr 8) and 0xFF).toByte()
        }
        return byteArray
    }

    private fun estimateAudioLength(dataSize: Int, format: AudioFormat, sampleRate: Int): Double {
        // Rough estimation based on format and sample rate
        val bytesPerSample: Int = when (format) {
            AudioFormat.PCM, AudioFormat.WAV -> 2 // 16-bit PCM
            AudioFormat.MP3 -> 1 // Compressed
            else -> 2
        }

        val samples = dataSize / bytesPerSample
        return samples.toDouble() / sampleRate.toDouble()
    }
}
