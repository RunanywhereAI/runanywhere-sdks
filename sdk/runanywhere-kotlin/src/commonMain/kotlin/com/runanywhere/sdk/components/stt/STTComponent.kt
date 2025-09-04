package com.runanywhere.sdk.components.stt

import com.runanywhere.sdk.components.base.BaseComponent
import com.runanywhere.sdk.components.base.ComponentState
import com.runanywhere.sdk.components.base.SDKComponent
import com.runanywhere.sdk.data.models.LoadedModel
import com.runanywhere.sdk.components.vad.VADComponent
import com.runanywhere.sdk.components.vad.VADConfiguration
import com.runanywhere.sdk.data.models.ModelInfo
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.files.FileManager
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant

/**
 * Speech-to-Text component matching Swift SDK architecture
 */
class STTComponent(
    private val sttConfiguration: STTConfiguration
) : BaseComponent<STTService>(sttConfiguration) {

    override val componentType: SDKComponent = SDKComponent.STT

    private val logger = com.runanywhere.sdk.foundation.SDKLogger("STTComponent")
    private var currentModel: LoadedModel? = null
    private lateinit var sttService: STTService
    private var analyticsCallback: ((String, Map<String, Any>) -> Unit)? = null

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

        val startTime = Clock.System.now().toEpochMilliseconds()

        // Send analytics event for transcription start
        analyticsCallback?.invoke("transcription_started", mapOf(
            "audio_size_bytes" to audioData.size,
            "model_id" to (currentModel?.model?.id ?: "unknown"),
            "session_id" to generateSessionId(),
            "timestamp" to startTime
        ))

        val result = sttService.transcribe(
            audioData = audioData,
            options = STTOptions(
                language = sttConfiguration.language,
                enableTimestamps = sttConfiguration.enableTimestamps
            )
        )

        val endTime = Clock.System.now().toEpochMilliseconds()
        val duration = endTime - startTime

        // Send analytics event for transcription completed
        analyticsCallback?.invoke("transcription_completed", mapOf(
            "duration" to duration,
            "text_length" to result.transcript.length,
            "confidence" to (result.confidence ?: 0.0f),
            "language" to (result.language ?: "unknown"),
            "model_id" to (currentModel?.model?.id ?: "unknown"),
            "session_id" to generateSessionId(),
            "timestamp" to endTime,
            "audio_duration_ms" to estimateAudioDuration(audioData.size),
            "has_timestamps" to (result.timestamps?.isNotEmpty() == true)
        ))

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

        val sessionId = generateSessionId()
        val streamStartTime = Clock.System.now().toEpochMilliseconds()

        // Send analytics event for stream start
        analyticsCallback?.invoke("stream_transcription_started", mapOf(
            "session_id" to sessionId,
            "timestamp" to streamStartTime,
            "model_id" to (currentModel?.model?.id ?: "unknown"),
            "vad_enabled" to true
        ))

        if (true) { // TODO: Add enableVAD to configuration
            // Use VAD for speech detection
            val vadComponent = VADComponent(VADConfiguration())
            vadComponent.initialize()

            var isInSpeech = false
            val audioBuffer = mutableListOf<ByteArray>()
            var speechSegmentStartTime: Long? = null
            var totalChunksProcessed = 0

            audioStream.collect { chunk ->
                totalChunksProcessed++
                val floatAudio = chunk.toFloatArray()
                val vadResult = vadComponent.processAudioChunk(floatAudio)

                when {
                    vadResult.isSpeech && !isInSpeech -> {
                        isInSpeech = true
                        speechSegmentStartTime = Clock.System.now().toEpochMilliseconds()
                        audioBuffer.clear()
                        audioBuffer.add(chunk)
                        emit(TranscriptionEvent.SpeechStart)

                        // Send analytics for speech start
                        analyticsCallback?.invoke("speech_segment_started", mapOf(
                            "session_id" to sessionId,
                            "timestamp" to speechSegmentStartTime!!,
                            "chunk_number" to totalChunksProcessed
                        ))
                    }

                    vadResult.isSpeech && isInSpeech -> {
                        audioBuffer.add(chunk)
                        // Emit partial if buffer is large enough
                        if (audioBuffer.size > 5) {
                            val partial = transcribeBuffer(audioBuffer)
                            emit(TranscriptionEvent.PartialTranscription(partial))

                            // Send analytics for partial transcription
                            analyticsCallback?.invoke("partial_transcription", mapOf(
                                "session_id" to sessionId,
                                "timestamp" to Clock.System.now().toEpochMilliseconds(),
                                "text_length" to partial.length,
                                "buffer_size" to audioBuffer.size
                            ))
                        }
                    }

                    !vadResult.isSpeech && isInSpeech -> {
                        isInSpeech = false
                        val speechEndTime = Clock.System.now().toEpochMilliseconds()
                        val speechDuration = speechSegmentStartTime?.let { speechEndTime - it }

                        if (audioBuffer.isNotEmpty()) {
                            val final = transcribeBuffer(audioBuffer)
                            emit(TranscriptionEvent.FinalTranscription(final))
                            emit(TranscriptionEvent.SpeechEnd)

                            // Send analytics for speech segment completion
                            analyticsCallback?.invoke("speech_segment_completed", mapOf<String, Any>(
                                "session_id" to sessionId,
                                "timestamp" to speechEndTime,
                                "speech_duration" to (speechDuration ?: 0L),
                                "final_text_length" to final.length,
                                "buffer_chunks" to audioBuffer.size,
                                "estimated_audio_duration" to estimateAudioDuration(audioBuffer.sumOf { it.size })
                            ))
                        }
                    }
                }
            }

            // Send stream completion analytics
            analyticsCallback?.invoke("stream_transcription_completed", mapOf(
                "session_id" to sessionId,
                "timestamp" to Clock.System.now().toEpochMilliseconds(),
                "total_duration" to (Clock.System.now().toEpochMilliseconds() - streamStartTime),
                "total_chunks_processed" to totalChunksProcessed
            ))

        } else {
            // Direct transcription without VAD
            var chunkCount = 0
            audioStream.collect { chunk ->
                chunkCount++
                val result = sttService.transcribe(chunk, STTOptions())
                emit(TranscriptionEvent.FinalTranscription(result.transcript))

                // Send analytics for direct transcription
                analyticsCallback?.invoke("direct_transcription", mapOf(
                    "session_id" to sessionId,
                    "timestamp" to Clock.System.now().toEpochMilliseconds(),
                    "chunk_number" to chunkCount,
                    "text_length" to result.transcript.length
                ))
            }
        }
    }

    fun setCurrentModel(model: LoadedModel) {
        currentModel = model
    }

    fun getCurrentModel(): LoadedModel? = currentModel

    fun isInitialized(): Boolean = state == ComponentState.READY

    /**
     * Load a model into the STT service
     */
    suspend fun loadModel(modelPath: String) {
        requireReady()
        sttService.initialize(modelPath)
        logger.info("Loaded STT model from $modelPath")
    }

    /**
     * Set analytics callback for STT events
     */
    fun setAnalyticsCallback(callback: (String, Map<String, Any>) -> Unit) {
        analyticsCallback = callback
    }

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

    private fun generateSessionId(): String {
        return "stt-session-${Clock.System.now().toEpochMilliseconds()}"
    }

    private fun estimateAudioDuration(audioDataSize: Int, sampleRate: Int = 16000, channels: Int = 1, bytesPerSample: Int = 2): Long {
        // Estimate duration in milliseconds based on audio data size
        val samplesCount = audioDataSize / (channels * bytesPerSample)
        return (samplesCount * 1000L) / sampleRate
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
