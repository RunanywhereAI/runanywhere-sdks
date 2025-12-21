package com.runanywhere.sdk.features.stt

import com.runanywhere.sdk.core.AudioFormat
import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.core.capabilities.BaseComponent
import com.runanywhere.sdk.core.capabilities.ComponentState
import com.runanywhere.sdk.core.capabilities.SDKComponent
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.data.models.generateUUID
import com.runanywhere.sdk.features.speakerdiarization.SpeakerDiarizationService
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.infrastructure.events.ModularPipelineEvent
import com.runanywhere.sdk.utils.PlatformUtils
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.launch

/**
 * Speech-to-Text component matching iOS STTComponent architecture exactly
 */
class STTComponent(
    private val sttConfiguration: STTConfiguration,
) : BaseComponent<STTServiceWrapper>(sttConfiguration) {
    override val componentType: SDKComponent = SDKComponent.STT

    private val logger =
        com.runanywhere.sdk.foundation
            .SDKLogger("STTComponent")
    private var isModelLoaded = false
    private var modelPath: String? = null

    // Coroutine scope for fire-and-forget telemetry operations (avoids GlobalScope)
    private val telemetryScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // Get telemetry service from ServiceContainer (matches iOS pattern)
    private val telemetryService get() = ServiceContainer.shared.telemetryService

    // iOS parity - STT Handler for voice pipeline integration
    // Pass telemetryScope to handler for proper lifecycle management
    private val sttHandler by lazy {
        STTHandler(
            telemetryScope = telemetryScope,
        )
    }

    override suspend fun createService(): STTServiceWrapper {
        // Try to get a registered STT provider from central registry
        val provider =
            ModuleRegistry.sttProvider(sttConfiguration.modelId)
                ?: throw SDKError.ComponentNotInitialized(
                    "No STT service provider registered. Please register an STT service provider.",
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
        // Cancel any pending telemetry operations to prevent memory leaks
        telemetryScope.cancel()
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
        language: String? = null,
    ): STTOutput {
        requireReady()

        val input =
            STTInput(
                audioData = audioData,
                format = format,
                language = language,
            )
        return process(input)
    }

    /**
     * Transcribe audio buffer (FloatArray)
     */
    suspend fun transcribe(
        audioBuffer: FloatArray,
        language: String? = null,
    ): STTOutput {
        requireReady()

        val input =
            STTInput(
                audioData = byteArrayOf(), // Empty, use buffer
                audioBuffer = audioBuffer,
                format = AudioFormat.PCM,
                language = language,
            )
        return process(input)
    }

    /**
     * Transcribe with VAD context
     */
    suspend fun transcribeWithVAD(
        audioData: ByteArray,
        format: AudioFormat = AudioFormat.WAV,
        vadOutput: com.runanywhere.sdk.features.vad.VADOutput,
    ): STTOutput {
        requireReady()

        val input =
            STTInput(
                audioData = audioData,
                format = format,
                vadOutput = vadOutput,
            )
        return process(input)
    }

    /**
     * Process STT input (matches iOS architecture)
     */
    suspend fun process(input: STTInput): STTOutput {
        requireReady()

        val service =
            service?.wrappedService
                ?: throw SDKError.ComponentNotReady("STT service not available")

        // Validate input
        input.validate()

        // Create options from input or use defaults
        val options =
            input.options ?: STTOptions(
                language = input.language ?: sttConfiguration.language,
                detectLanguage = input.language == null,
                enablePunctuation = sttConfiguration.enablePunctuation,
                enableDiarization = sttConfiguration.enableDiarization,
                maxSpeakers = null,
                enableTimestamps = sttConfiguration.enableTimestamps,
                vocabularyFilter = sttConfiguration.vocabularyList,
                audioFormat = input.format,
            )

        // Get audio data
        val audioData: ByteArray =
            when {
                input.audioData.isNotEmpty() -> input.audioData
                input.audioBuffer != null -> convertFloatArrayToBytes(input.audioBuffer)
                else -> throw SDKError.ValidationFailed("No audio data provided")
            }

        // Generate session ID for telemetry tracking
        val sessionId = generateUUID()

        // Calculate audio length for telemetry
        val estimatedAudioLength =
            estimateAudioLength(
                dataSize = audioData.size,
                format = input.format,
                sampleRate = sttConfiguration.sampleRate,
            )
        val audioDurationMs = estimatedAudioLength * 1000.0

        // Track processing time - start before telemetry to avoid blocking
        val startTime = getCurrentTimeMillis()

        // Get current model ID for telemetry
        val currentModelId = service.currentModel
        logger.info("Starting STT transcription with model: $currentModelId")

        // Track transcription started - fire and forget to avoid blocking transcription
        telemetryScope.launch {
            try {
                telemetryService?.trackSTTTranscriptionStarted(
                    sessionId = sessionId,
                    modelId = currentModelId ?: "unknown",
                    modelName = currentModelId ?: "Unknown STT Model",
                    framework = "ONNX Runtime",
                    language = options.language ?: "en",
                    device = PlatformUtils.getDeviceModel(),
                    osVersion = PlatformUtils.getOSVersion(),
                )
            } catch (e: Exception) {
                logger.debug("Failed to track STT transcription started: ${e.message}")
            }
        }

        // Perform transcription
        val result =
            try {
                service.transcribe(audioData = audioData, options = options)
            } catch (error: Exception) {
                // Track transcription failure - fire and forget
                val endTime = getCurrentTimeMillis()
                val processingTimeMs = (endTime - startTime).toDouble()
                val failureModelId = service.currentModel

                telemetryScope.launch {
                    try {
                        telemetryService?.trackSTTTranscriptionFailed(
                            sessionId = sessionId,
                            modelId = failureModelId ?: "unknown",
                            modelName = failureModelId ?: "Unknown STT Model",
                            framework = "ONNX Runtime",
                            language = options.language ?: "en",
                            audioDurationMs = audioDurationMs,
                            processingTimeMs = processingTimeMs,
                            errorMessage = error.message ?: error.toString(),
                            device = PlatformUtils.getDeviceModel(),
                            osVersion = PlatformUtils.getOSVersion(),
                        )
                    } catch (e: Exception) {
                        logger.debug("Failed to track STT transcription failure: ${e.message}")
                    }
                }

                throw error
            }

        val processingTime = (getCurrentTimeMillis() - startTime) / 1000.0 // Convert to seconds
        val processingTimeMs = (getCurrentTimeMillis() - startTime).toDouble()

        // Convert to strongly typed output
        val wordTimestamps =
            result.timestamps?.map { timestamp ->
                WordTimestamp(
                    word = timestamp.word,
                    startTime = timestamp.startTime,
                    endTime = timestamp.endTime,
                    confidence = timestamp.confidence ?: 0.9f,
                )
            }

        val alternatives =
            result.alternatives?.map { alt ->
                TranscriptionAlternative(
                    text = alt.transcript,
                    confidence = alt.confidence,
                )
            }

        // Calculate audio length (estimate based on data size and format)
        val audioLength =
            estimateAudioLength(
                dataSize = audioData.size,
                format = input.format,
                sampleRate = sttConfiguration.sampleRate,
            )

        val metadata =
            TranscriptionMetadata(
                modelId = service.currentModel ?: "unknown",
                processingTime = processingTime,
                audioLength = audioLength,
            )

        // Track successful transcription completion - fire and forget
        val transcript = result.transcript
        if (transcript.isNotEmpty()) {
            val wordCount = transcript.split("\\s+".toRegex()).filter { it.isNotEmpty() }.size
            val characterCount = transcript.length
            // Use default confidence of 0.9 if null or 0 (native ONNX may not provide confidence)
            val confidence = result.confidence?.takeIf { it > 0.0f } ?: 0.9f
            val realTimeFactor = if (audioDurationMs > 0) processingTimeMs / audioDurationMs else 0.0
            val completionModelId = service.currentModel
            val completionLanguage = options.language ?: result.language ?: "en"

            telemetryScope.launch {
                try {
                    telemetryService?.trackSTTTranscriptionCompleted(
                        sessionId = sessionId,
                        modelId = completionModelId ?: "unknown",
                        modelName = completionModelId ?: "Unknown STT Model",
                        framework = "ONNX Runtime",
                        language = completionLanguage,
                        audioDurationMs = audioDurationMs,
                        processingTimeMs = processingTimeMs,
                        realTimeFactor = realTimeFactor,
                        wordCount = wordCount,
                        characterCount = characterCount,
                        confidence = confidence,
                        device = PlatformUtils.getDeviceModel(),
                        osVersion = PlatformUtils.getOSVersion(),
                    )
                } catch (e: Exception) {
                    logger.debug("Failed to track STT transcription completed: ${e.message}")
                }
            }
        }

        return STTOutput(
            text = result.transcript,
            confidence = result.confidence ?: 0.9f,
            wordTimestamps = wordTimestamps,
            detectedLanguage = result.language,
            alternatives = alternatives,
            metadata = metadata,
        )
    }

    /**
     * Live transcription with real-time partial results (matches iOS liveTranscribe)
     * - Parameters:
     *   - audioStream: Flow of audio data chunks
     *   - options: Transcription options
     * - Returns: Flow of transcription text (partial and final results)
     * - Note: If the service doesn't support streaming, this will collect all audio
     *         and return a single result when the stream completes
     */
    fun liveTranscribe(
        audioStream: Flow<ByteArray>,
        options: STTOptions = STTOptions.default(),
    ): Flow<String> = streamTranscribe(audioStream, options.language)

    /**
     * Stream transcription (matches iOS streamTranscribe)
     * Returns Flow<String> equivalent to iOS AsyncThrowingStream<String, Error>
     */
    fun streamTranscribe(
        audioStream: Flow<ByteArray>,
        language: String? = null,
    ): Flow<String> =
        callbackFlow {
            requireReady()

            val service =
                service?.wrappedService
                    ?: throw SDKError.ComponentNotReady("STT service not available")

            val options =
                STTOptions(
                    language = language ?: sttConfiguration.language,
                    detectLanguage = language == null,
                    enablePunctuation = sttConfiguration.enablePunctuation,
                    enableDiarization = sttConfiguration.enableDiarization,
                    enableTimestamps = false,
                    vocabularyFilter = sttConfiguration.vocabularyList,
                    audioFormat = AudioFormat.PCM,
                )

            // Launch transcription in a coroutine
            val transcriptionJob =
                launch {
                    try {
                        val result =
                            service.streamTranscribe(
                                audioStream = audioStream,
                                options = options,
                            ) { partial ->
                                // Yield partial result
                                trySend(partial)
                            }

                        // Yield final result
                        trySend(result.transcript)
                    } catch (error: Exception) {
                        logger.error("STT streaming error: ${error.message}", error)
                        throw error
                    }
                }

            // Wait for flow to be closed
            awaitClose {
                transcriptionJob.cancel()
                logger.debug("STT streaming flow closed")
            }
        }

    /**
     * Transcribe audio using the voice pipeline handler (matches iOS STTHandler integration)
     */
    suspend fun transcribeAudioWithHandler(
        samples: FloatArray,
        options: STTOptions? = null,
        speakerDiarization: SpeakerDiarizationService? = null,
        continuation: kotlinx.coroutines.flow.MutableSharedFlow<ModularPipelineEvent>,
    ): String {
        requireReady()

        val service =
            service?.wrappedService
                ?: throw SDKError.ComponentNotReady("STT service not available")

        val transcriptionOptions =
            options ?: STTOptions(
                language = sttConfiguration.language,
                detectLanguage = false,
                enablePunctuation = sttConfiguration.enablePunctuation,
                enableDiarization = sttConfiguration.enableDiarization,
                enableTimestamps = sttConfiguration.enableTimestamps,
                vocabularyFilter = sttConfiguration.vocabularyList,
            )

        return sttHandler.transcribeAudio(
            samples = samples,
            service = service,
            options = transcriptionOptions,
            speakerDiarization = speakerDiarization,
            continuation = continuation,
        )
    }

    /**
     * Get service for compatibility (matches iOS)
     */
    fun getService(): STTService? = service?.wrappedService

    // MARK: - Analytics (matches iOS STTCapability.getAnalyticsMetrics())

    // Internal analytics service for tracking transcription operations
    private val analyticsService = STTAnalyticsService()

    /**
     * Get current STT analytics metrics
     * Matches iOS STTCapability.getAnalyticsMetrics()
     */
    fun getAnalyticsMetrics(): STTMetrics = analyticsService.getMetrics()

    /**
     * Track a transcription for analytics
     * Called internally when transcription completes
     */
    internal fun trackTranscription(
        audioLengthMs: Double,
        audioSizeBytes: Int,
        language: String,
        text: String,
        confidence: Float,
    ) {
        val transcriptionId = analyticsService.startTranscription(
            audioLengthMs = audioLengthMs,
            audioSizeBytes = audioSizeBytes,
            language = language,
        )
        analyticsService.completeTranscription(
            transcriptionId = transcriptionId,
            text = text,
            confidence = confidence,
        )
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

    private fun estimateAudioLength(
        dataSize: Int,
        format: AudioFormat,
        sampleRate: Int,
    ): Double {
        // Rough estimation based on format and sample rate
        val bytesPerSample: Int =
            when (format) {
                AudioFormat.PCM, AudioFormat.WAV -> 2 // 16-bit PCM
                AudioFormat.MP3 -> 1 // Compressed
                else -> 2
            }

        val samples = dataSize / bytesPerSample
        return samples.toDouble() / sampleRate.toDouble()
    }
}
