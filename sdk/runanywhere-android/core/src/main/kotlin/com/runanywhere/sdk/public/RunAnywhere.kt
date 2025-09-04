package com.runanywhere.sdk.public

import com.runanywhere.sdk.analytics.AnalyticsTracker
import com.runanywhere.sdk.components.base.*
import com.runanywhere.sdk.components.stt.*
import com.runanywhere.sdk.components.vad.*
import com.runanywhere.sdk.events.*
import com.runanywhere.sdk.models.ModelManager
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * Main SDK configuration
 */
data class STTSDKConfig(
    val modelId: String = "whisper-base",
    val enableVAD: Boolean = true,
    val vadConfig: VADConfiguration = VADConfiguration(),
    val language: String = "en",
    val enableAnalytics: Boolean = true
)

/**
 * Main public API for RunAnywhere STT SDK
 * This is a convenience wrapper around the component architecture
 */
object RunAnywhere {
    private var vadComponent: VADComponent? = null
    private var sttComponent: STTComponent? = null
    private val modelManager = ModelManager()
    private val analytics = AnalyticsTracker()
    private var isInitialized = false
    private var config: STTSDKConfig? = null

    init {
        // Register default service providers
        WhisperServiceProvider.register()
        WebRTCVADServiceProvider.register()
    }

    /**
     * Initialize the SDK
     */
    suspend fun initialize(sdkConfig: STTSDKConfig = STTSDKConfig()) {
        config = sdkConfig

        // Initialize VAD if enabled
        if (sdkConfig.enableVAD) {
            vadComponent = VADComponent(sdkConfig.vadConfig)
            vadComponent?.initialize()
        }

        // Initialize STT
        val sttConfig = STTConfiguration(
            modelId = sdkConfig.modelId,
            language = sdkConfig.language
        )
        sttComponent = STTComponent(sttConfig)
        sttComponent?.initialize()

        // Track initialization
        if (sdkConfig.enableAnalytics) {
            analytics.track(
                "stt_initialized", mapOf(
                    "model" to sdkConfig.modelId,
                    "vad_enabled" to sdkConfig.enableVAD,
                    "language" to sdkConfig.language
                )
            )
        }

        isInitialized = true
        EventBus.emit(STTEvent.Initialized)
    }

    /**
     * Simple transcription of audio data
     */
    suspend fun transcribe(audioData: ByteArray): String {
        requireInitialized()
        val startTime = System.currentTimeMillis()

        val result = sttComponent!!.transcribe(audioData)

        config?.let { cfg ->
            if (cfg.enableAnalytics) {
                analytics.track(
                    "transcription_completed", mapOf(
                        "duration_ms" to (System.currentTimeMillis() - startTime),
                        "audio_length_s" to (audioData.size / 32000.0),
                        "text_length" to result.text.length
                    )
                )
            }
        }

        EventBus.emit(
            STTEvent.TranscriptionCompleted(
                text = result.text,
                duration = System.currentTimeMillis() - startTime
            )
        )

        return result.text
    }

    /**
     * Stream transcription with VAD
     */
    fun transcribeStream(audioStream: Flow<ByteArray>): Flow<TranscriptionEvent> = flow {
        requireInitialized()

        if (vadComponent == null) {
            // If VAD is not enabled, just transcribe directly
            audioStream.collect { chunk ->
                val result = sttComponent!!.transcribe(chunk)
                emit(TranscriptionEvent.FinalTranscription(result.text))
            }
        } else {
            // Use VAD for speech detection
            var isInSpeech = false
            val audioBuffer = mutableListOf<ByteArray>()

            audioStream.collect { chunk ->
                // Convert to float array for VAD
                val floatAudio = chunk.toFloatArray()
                val vadResult = vadComponent!!.processAudioChunk(floatAudio)

                when {
                    vadResult.isSpeech && !isInSpeech -> {
                        isInSpeech = true
                        audioBuffer.clear()
                        audioBuffer.add(chunk)
                        emit(TranscriptionEvent.SpeechStart)
                    }

                    vadResult.isSpeech && isInSpeech -> {
                        audioBuffer.add(chunk)
                        // Emit partial transcription if buffer is large enough
                        if (audioBuffer.size > 5) {
                            val partialAudio = audioBuffer.toByteArray()
                            val partial = sttComponent!!.transcribe(partialAudio)
                            emit(TranscriptionEvent.PartialTranscription(partial.text))
                        }
                    }

                    !vadResult.isSpeech && isInSpeech -> {
                        isInSpeech = false
                        if (audioBuffer.isNotEmpty()) {
                            val finalAudio = audioBuffer.toByteArray()
                            val result = sttComponent!!.transcribe(finalAudio)
                            emit(TranscriptionEvent.FinalTranscription(result.text))
                            emit(TranscriptionEvent.SpeechEnd)
                        }
                    }
                }
            }
        }
    }

    /**
     * Get available models
     */
    fun getAvailableModels() = modelManager.getAvailableModels()

    /**
     * Check if a model is available locally
     */
    fun isModelAvailable(modelId: String) = modelManager.isModelAvailable(modelId)

    /**
     * Download a model
     */
    suspend fun downloadModel(modelId: String) {
        modelManager.ensureModel(modelId)
    }

    /**
     * Cleanup and release resources
     */
    suspend fun cleanup() {
        vadComponent?.cleanup()
        sttComponent?.cleanup()
        vadComponent = null
        sttComponent = null
        isInitialized = false
    }

    /**
     * Check if SDK is initialized
     */
    fun isInitialized() = isInitialized

    private fun requireInitialized() {
        if (!isInitialized) {
            throw IllegalStateException("SDK not initialized. Call RunAnywhere.initialize() first")
        }
    }

    // MARK: - Model Management

    /**
     * Load a model by ID
     */
    suspend fun loadModel(modelId: String) {
        events.publish(SDKModelEvent.LoadStarted(modelId))

        try {
            requireInitialized()

            val loadedModel = serviceContainer.modelLoadingService.loadModel(modelId)

            // Set the loaded model in appropriate service
            when (loadedModel.model.category) {
                ModelCategory.SPEECH_RECOGNITION -> {
                    serviceContainer.sttComponent.setCurrentModel(loadedModel)
                }

                ModelCategory.LANGUAGE -> {
                    // For future LLM component
                }

                else -> {
                    // Other model types
                }
            }

            events.publish(SDKModelEvent.LoadCompleted(modelId))
        } catch (e: Exception) {
            events.publish(SDKModelEvent.LoadFailed(modelId, e))
            throw e
        }
    }

    /**
     * Get available models
     */
    suspend fun availableModels(): List<ModelInfo> {
        requireInitialized()
        return serviceContainer.modelRegistry.discoverModels()
    }

    /**
     * Get currently loaded model for STT
     */
    val currentSTTModel: ModelInfo?
        get() = if (_isInitialized) {
            serviceContainer.sttComponent.getCurrentModel()?.model
        } else null

    // MARK: - STT Operations

    /**
     * Simple transcription
     */
    suspend fun transcribe(audioData: ByteArray): String {
        events.publish(SDKVoiceEvent.TranscriptionStarted)

        try {
            requireInitialized()

            val sttComponent = serviceContainer.sttComponent

            // Ensure STT is initialized
            if (!sttComponent.isInitialized()) {
                sttComponent.initialize()
            }

            val result = sttComponent.transcribe(audioData)

            events.publish(SDKVoiceEvent.TranscriptionFinal(result.text))
            return result.text

        } catch (e: Exception) {
            events.publish(SDKVoiceEvent.PipelineError(e))
            throw e
        }
    }

    /**
     * Streaming transcription with VAD
     */
    fun transcribeStream(audioStream: Flow<ByteArray>): Flow<TranscriptionEvent> {
        requireInitialized()
        return serviceContainer.sttComponent.transcribeStream(audioStream)
    }

    // MARK: - Configuration

    val isInitialized: Boolean
        get() = _isInitialized

    val currentEnvironment: SDKEnvironment
        get() = _currentEnvironment

    // MARK: - Private Helpers

    private fun requireInitialized() {
        if (!_isInitialized) {
            throw SDKError.NotInitialized
        }
    }

    private fun setLogLevel(level: LogLevel) {
        SDKLogger.setLevel(level)
    }

    private fun getMockModels(): List<ModelInfo> {
        // Return mock models matching Swift SDK's MockNetworkService
        return listOf(
            ModelInfo(
                id = "whisper-tiny",
                name = "Whisper Tiny",
                category = ModelCategory.SPEECH_RECOGNITION,
                format = ModelFormat.GGML,
                downloadURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin",
                downloadSize = 39_000_000L,
                memoryRequired = 39_000_000L,
                contextLength = 0,
                supportsThinking = false
            ),
            ModelInfo(
                id = "whisper-base",
                name = "Whisper Base",
                category = ModelCategory.SPEECH_RECOGNITION,
                format = ModelFormat.GGML,
                downloadURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin",
                downloadSize = 74_000_000L,
                memoryRequired = 74_000_000L,
                contextLength = 0,
                supportsThinking = false
            ),
            ModelInfo(
                id = "whisper-small",
                name = "Whisper Small",
                category = ModelCategory.SPEECH_RECOGNITION,
                format = ModelFormat.GGML,
                downloadURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin",
                downloadSize = 244_000_000L,
                memoryRequired = 244_000_000L,
                contextLength = 0,
                supportsThinking = false
            )
        )
    }
}
