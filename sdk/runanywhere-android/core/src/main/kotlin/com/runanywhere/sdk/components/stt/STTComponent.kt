package com.runanywhere.sdk.components.stt

import com.runanywhere.sdk.components.base.BaseComponent
import com.runanywhere.sdk.components.base.ComponentState
import com.runanywhere.sdk.components.base.SDKComponent
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
    private val sttConfiguration: STTConfiguration
) : BaseComponent<STTService>(sttConfiguration) {

    override val componentType: SDKComponent = SDKComponent.STT

    private var currentModel: LoadedModel? = null
    private lateinit var sttService: STTService

    override suspend fun createService(): STTService {
        return WhisperSTTService()
    }

    override suspend fun initializeService() {
        // Create STT service based on configuration
        sttService = createService()

        // Initialize with model if specified
        sttConfiguration.modelId?.let { modelId ->
            val modelPath = getModelPath(modelId)
            sttService.initialize(modelPath)
        }
    }

    suspend fun transcribe(audioData: ByteArray): TranscriptionResult {
        requireReady()

        val result = sttService.transcribe(
            audioData = audioData,
            options = STTOptions(
                language = sttConfiguration.language,
                enableTimestamps = sttConfiguration.enableTimestamps
            )
        )

        // Convert STTTranscriptionResult to TranscriptionResult
        return TranscriptionResult(
            text = result.transcript,
            confidence = result.confidence ?: 0.0f,
            language = result.language,
            timestamps = result.timestamps?.map {
                WordTimestamp(
                    word = it.word,
                    startTime = it.startTime.toDouble(),
                    endTime = it.endTime.toDouble(),
                    confidence = it.confidence ?: 0.0f
                )
            }
        )
    }

    fun transcribeStream(audioStream: Flow<ByteArray>): Flow<TranscriptionEvent> = flow {
        requireReady()

        if (true) { // TODO: Add enableVAD to configuration
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
                emit(TranscriptionEvent.FinalTranscription(result.transcript))
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
        state = ComponentState.NOT_INITIALIZED
    }

    private fun createSTTService(config: STTConfiguration): STTService {
        // Create Whisper STT service
        return WhisperSTTService()
    }

    private suspend fun transcribeBuffer(buffer: List<ByteArray>): String {
        val merged = buffer.reduce { acc, bytes -> acc + bytes }
        val result = sttService.transcribe(merged, STTOptions())
        return result.transcript
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
 * Transcription result
 */
data class TranscriptionResult(
    val text: String,
    val confidence: Float = 0.0f,
    val language: String? = null,
    val timestamps: List<WordTimestamp>? = null
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
