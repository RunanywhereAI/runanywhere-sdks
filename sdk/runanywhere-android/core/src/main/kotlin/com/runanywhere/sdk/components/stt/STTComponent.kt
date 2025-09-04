package com.runanywhere.sdk.components.stt

import com.runanywhere.sdk.components.base.*
import com.runanywhere.sdk.components.vad.VADOutput
import kotlinx.coroutines.flow.*
import java.util.Date
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds

// MARK: - STT Component

/**
 * Speech-to-Text component following the clean architecture
 */
class STTComponent(configuration: STTConfiguration) :
    BaseComponent<STTServiceWrapper>(configuration) {

    // MARK: - Properties

    override val componentType: SDKComponent = SDKComponent.STT

    private val sttConfiguration: STTConfiguration = configuration
    private var isModelLoaded = false
    private var modelPath: String? = null

    // MARK: - Service Creation

    override suspend fun createService(): STTServiceWrapper {
        // Try to get a registered STT provider from central registry
        val provider = ModuleRegistry.sttProvider(sttConfiguration.modelId)
            ?: throw SDKError.ComponentNotInitialized(
                "No STT service provider registered. Please register WhisperServiceProvider.register()"
            )

        // Check if model needs downloading
        modelPath = sttConfiguration.modelId
        // Provider should handle model management

        // Create service through provider
        val sttService = provider.createSTTService(sttConfiguration)

        // Wrap the service
        val wrapper = STTServiceWrapper(sttService)

        // Service is already initialized by the provider
        isModelLoaded = true

        return wrapper
    }

    override suspend fun performCleanup() {
        service?.wrappedService?.cleanup()
        isModelLoaded = false
        modelPath = null
    }

    // MARK: - Model Management

    private suspend fun downloadModel(modelId: String) {
        // Emit download started event
        eventBus.emit(
            ComponentInitializationEvent.ComponentDownloadStarted(
                component = componentType,
                modelId = modelId
            )
        )

        // Simulate download with progress
        for (progress in 0..10) {
            eventBus.emit(
                ComponentInitializationEvent.ComponentDownloadProgress(
                    component = componentType,
                    modelId = modelId,
                    progress = progress / 10f
                )
            )
            kotlinx.coroutines.delay(50.milliseconds)
        }

        // Emit download completed event
        eventBus.emit(
            ComponentInitializationEvent.ComponentDownloadCompleted(
                component = componentType,
                modelId = modelId
            )
        )
    }

    // MARK: - Helper Methods

    private val sttService: STTService?
        get() = service?.wrappedService

    // MARK: - Public API

    /**
     * Transcribe audio data
     */
    suspend fun transcribe(
        audioData: ByteArray,
        format: AudioFormat = AudioFormat.WAV,
        language: String? = null
    ): STTOutput {
        ensureReady()

        val input = STTInput(
            audioData = audioData,
            format = format,
            language = language
        )
        return process(input)
    }

    /**
     * Transcribe audio buffer
     */
    suspend fun transcribe(
        audioBuffer: FloatArray,
        language: String? = null
    ): STTOutput {
        ensureReady()

        // Convert float array to byte array
        val audioData = convertFloatArrayToByteArray(audioBuffer)

        val input = STTInput(
            audioData = audioData,
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
        vadOutput: VADOutput
    ): STTOutput {
        ensureReady()

        val input = STTInput(
            audioData = audioData,
            format = format,
            vadOutput = vadOutput
        )
        return process(input)
    }

    /**
     * Process STT input
     */
    suspend fun process(input: STTInput): STTOutput {
        ensureReady()

        val service = sttService ?: throw SDKError.ComponentNotReady("STT service not available")

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
        val audioData = if (input.audioData.isNotEmpty()) {
            input.audioData
        } else if (input.audioBuffer != null) {
            convertFloatArrayToByteArray(input.audioBuffer)
        } else {
            throw SDKError.ValidationFailed("No audio data provided")
        }

        // Track processing time
        val startTime = System.currentTimeMillis()

        // Perform transcription
        val result = service.transcribe(audioData, options)

        val processingTime = (System.currentTimeMillis() - startTime) / 1000.0

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
        val audioLength =
            estimateAudioLength(audioData.size, input.format, sttConfiguration.sampleRate)

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
     * Stream transcription
     */
    fun streamTranscribe(
        audioStream: Flow<ByteArray>,
        language: String? = null
    ): Flow<String> = flow {
        ensureReady()

        val service = sttService ?: throw SDKError.ComponentNotReady("STT service not available")

        val options = STTOptions(
            language = language ?: sttConfiguration.language,
            detectLanguage = language == null,
            enablePunctuation = sttConfiguration.enablePunctuation,
            enableDiarization = sttConfiguration.enableDiarization,
            enableTimestamps = false,
            vocabularyFilter = sttConfiguration.vocabularyList,
            audioFormat = AudioFormat.PCM
        )

        val partialResults = mutableListOf<String>()

        val result = service.streamTranscribe(
            audioStream = audioStream,
            options = options
        ) { partial ->
            partialResults.add(partial)
        }

        // Emit partial results
        partialResults.forEach { emit(it) }

        // Emit final result
        emit(result.transcript)
    }.catch { error ->
        throw STTError.TranscriptionFailed(error)
    }

    /**
     * Get service for compatibility
     */
    fun getService(): STTService? {
        return sttService
    }

    // MARK: - Private Helpers

    private fun convertFloatArrayToByteArray(floatArray: FloatArray): ByteArray {
        val byteArray = ByteArray(floatArray.size * 2)
        for (i in floatArray.indices) {
            val sample = (floatArray[i] * 32767).toInt().coerceIn(-32768, 32767)
            byteArray[i * 2] = (sample and 0xFF).toByte()
            byteArray[i * 2 + 1] = (sample shr 8 and 0xFF).toByte()
        }
        return byteArray
    }

    private fun estimateAudioLength(dataSize: Int, format: AudioFormat, sampleRate: Int): Double {
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
