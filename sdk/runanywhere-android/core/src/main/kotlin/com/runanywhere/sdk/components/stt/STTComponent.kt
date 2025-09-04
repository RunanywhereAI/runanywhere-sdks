package com.runanywhere.sdk.components.stt

import com.runanywhere.sdk.components.base.BaseComponent
import com.runanywhere.sdk.components.base.ComponentState
import com.runanywhere.sdk.components.vad.VADComponent
import com.runanywhere.sdk.components.vad.VADConfiguration
import com.runanywhere.sdk.data.models.LoadedModel
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.files.FileManager
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * Speech-to-Text component matching Swift SDK architecture
 */
class STTComponent(
    private val configuration: STTConfiguration
) : BaseComponent<STTService>() {

    private var currentModel: LoadedModel? = null
    private lateinit var sttService: STTService

    override suspend fun initialize() {
        state = ComponentState.INITIALIZING

        try {
            // Create STT service based on configuration
            sttService = createSTTService(configuration)

            // Initialize with model if specified
            configuration.modelId?.let { modelId ->
                val modelPath = getModelPath(modelId)
                sttService.initialize(modelPath)
            }

            state = ComponentState.READY
        } catch (e: Exception) {
            state = ComponentState.FAILED
            throw e
        }
    }

    suspend fun transcribe(audioData: ByteArray): TranscriptionResult {
        requireReady()

        return sttService.transcribe(
            audioData = audioData,
            options = STTOptions(
                language = configuration.language,
                enableTimestamps = configuration.enableTimestamps
            )
        )
    }

    fun transcribeStream(audioStream: Flow<ByteArray>): Flow<TranscriptionEvent> = flow {
        requireReady()

        if (configuration.enableVAD) {
            // Use VAD for speech detection
            val vadComponent = VADComponent(VADConfiguration())
            vadComponent.initialize()

            var isInSpeech = false
            val audioBuffer = mutableListOf<ByteArray>()

            audioStream.collect { chunk ->
                val floatAudio = chunk.toFloatArray()
                val vadResult = vadComponent.processAudioChunk(floatAudio)

                when {
                    vadResult.isSpeech && !isInSpeech -> {
                        isInSpeech = true
                        audioBuffer.clear()
                        audioBuffer.add(chunk)
                        emit(TranscriptionEvent.SpeechStart)
                    }

                    vadResult.isSpeech && isInSpeech -> {
                        audioBuffer.add(chunk)
                        // Emit partial if buffer is large enough
                        if (audioBuffer.size > 5) {
                            val partial = transcribeBuffer(audioBuffer)
                            emit(TranscriptionEvent.PartialTranscription(partial))
                        }
                    }

                    !vadResult.isSpeech && isInSpeech -> {
                        isInSpeech = false
                        if (audioBuffer.isNotEmpty()) {
                            val final = transcribeBuffer(audioBuffer)
                            emit(TranscriptionEvent.FinalTranscription(final))
                            emit(TranscriptionEvent.SpeechEnd)
                        }
                    }
                }
            }
        } else {
            // Direct transcription without VAD
            audioStream.collect { chunk ->
                val result = sttService.transcribe(chunk, STTOptions())
                emit(TranscriptionEvent.FinalTranscription(result.text))
            }
        }
    }

    fun setCurrentModel(model: LoadedModel) {
        currentModel = model
    }

    fun getCurrentModel(): LoadedModel? = currentModel

    fun isInitialized(): Boolean = state == ComponentState.READY

    override suspend fun cleanup() {
        sttService.cleanup()
        state = ComponentState.TERMINATED
    }

    private fun createSTTService(config: STTConfiguration): STTService {
        // Create Whisper STT service
        return WhisperSTTService()
    }

    private suspend fun transcribeBuffer(buffer: List<ByteArray>): String {
        val merged = buffer.reduce { acc, bytes -> acc + bytes }
        val result = sttService.transcribe(merged, STTOptions())
        return result.text
    }

    private fun getModelPath(modelId: String): String {
        return "${FileManager.modelsDirectory}/$modelId.bin"
    }

    private fun requireReady() {
        if (state != ComponentState.READY) {
            throw SDKError.NotInitialized
        }
    }
}

/**
 * Extension function to convert ByteArray to FloatArray for VAD
 */
private fun ByteArray.toFloatArray(): FloatArray {
    val floatArray = FloatArray(this.size / 2)
    for (i in floatArray.indices) {
        val sample = (this[i * 2].toInt() and 0xFF) or (this[i * 2 + 1].toInt() shl 8)
        floatArray[i] = sample / 32768.0f
    }
    return floatArray
}

/**
 * STT Configuration
 */
data class STTConfiguration(
    val modelId: String? = "whisper-base",
    val language: String = "en",
    val sampleRate: Int = 16000,
    val enablePunctuation: Boolean = true,
    val enableTimestamps: Boolean = false,
    val enableVAD: Boolean = true,
    val maxAlternatives: Int = 1
)

/**
 * STT Options for transcription
 */
data class STTOptions(
    val language: String = "en",
    val enableTimestamps: Boolean = false
)

/**
 * Transcription result
 */
data class TranscriptionResult(
    val text: String,
    val confidence: Float = 0.0f,
    val language: String? = null,
    val timestamps: List<WordTimestamp>? = null
)

/**
 * Word timestamp information
 */
data class WordTimestamp(
    val word: String,
    val startTime: Float,
    val endTime: Float
)

/**
 * Transcription events for streaming
 */
sealed class TranscriptionEvent {
    object SpeechStart : TranscriptionEvent()
    object SpeechEnd : TranscriptionEvent()
    data class PartialTranscription(val text: String) : TranscriptionEvent()
    data class FinalTranscription(val text: String) : TranscriptionEvent()
    data class Error(val error: Throwable) : TranscriptionEvent()
}
