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

    // Extension functions
    private fun ByteArray.toFloatArray(): FloatArray {
        val floatArray = FloatArray(this.size / 2)
        for (i in floatArray.indices) {
            val sample = (this[i * 2].toInt() and 0xFF) or (this[i * 2 + 1].toInt() shl 8)
            floatArray[i] = sample / 32768.0f
        }
        return floatArray
    }

    private fun List<ByteArray>.toByteArray(): ByteArray {
        val totalSize = sumOf { it.size }
        val result = ByteArray(totalSize)
        var offset = 0
        forEach { chunk ->
            chunk.copyInto(result, offset)
            offset += chunk.size
        }
        return result
    }
}
