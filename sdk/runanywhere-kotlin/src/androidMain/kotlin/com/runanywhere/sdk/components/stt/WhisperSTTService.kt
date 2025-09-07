package com.runanywhere.sdk.components.stt

import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.withContext
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Android implementation of Whisper STT Service
 * Uses the Whisper JNI library for speech-to-text transcription
 */
actual class WhisperSTTService : STTService {
    private val logger = SDKLogger("WhisperSTTService")
    private var modelPath: String? = null
    private val whisperService = WhisperService()

    actual override suspend fun initialize(modelPath: String?) {
        this.modelPath = modelPath
        if (modelPath != null) {
            logger.info("Initializing Whisper with model: $modelPath")

            val success = whisperService.initialize(modelPath)
            if (success) {
                logger.info("Whisper STT Service initialized successfully")

                // Log model information
                val modelInfo = whisperService.getModelInfo()
                modelInfo?.let {
                    logger.debug("Model: ${it.name}, Type: ${it.type}, Multilingual: ${it.isMultilingual}")
                }
            } else {
                logger.error("Failed to initialize Whisper STT Service")
                throw IllegalStateException("Failed to initialize Whisper with model: $modelPath")
            }
        } else {
            logger.error("No model path provided for Whisper initialization")
            throw IllegalArgumentException("Model path is required for Whisper STT Service")
        }
    }

    actual override suspend fun transcribe(
        audioData: ByteArray,
        options: STTOptions
    ): STTTranscriptionResult = withContext(Dispatchers.Default) {
        if (!whisperService.isReady()) {
            logger.error("WhisperSTTService not initialized or not ready")
            return@withContext STTTranscriptionResult(
                transcript = "",
                confidence = 0.0f,
                language = options.language,
                error = "Service not initialized"
            )
        }

        try {
            logger.debug("Transcribing ${audioData.size} bytes of audio")

            // Convert PCM audio data to float array for whisper processing
            val floatAudio = convertPcmToFloat(audioData)

            // Create whisper parameters from STT options
            val whisperParams = WhisperParams(
                language = options.language,
                enableTimestamps = options.enableTimestamps,
                enableTranslate = options.translateToEnglish,
                temperature = options.temperature ?: 0.0f,
                beamSize = options.beamSize ?: 1,
                suppressBlank = true,
                suppressNonSpeech = true,
                prompt = options.prompt
            )

            // Perform transcription
            val result = whisperService.transcribeWithParams(floatAudio, whisperParams)

            // Convert WhisperResult to STTTranscriptionResult
            val timestamps = if (options.enableTimestamps && result.segments.isNotEmpty()) {
                result.segments.map { segment ->
                    STTTranscriptionResult.TimestampInfo(
                        text = segment.text,
                        startTime = segment.startTime,
                        endTime = segment.endTime,
                        confidence = segment.confidence
                    )
                }
            } else null

            val confidence = if (result.segments.isNotEmpty()) {
                result.segments.map { it.confidence }.average().toFloat()
            } else 1.0f

            logger.debug("Transcription completed: '${result.text}' (confidence: $confidence)")

            STTTranscriptionResult(
                transcript = result.text,
                confidence = confidence,
                language = result.language,
                timestamps = timestamps,
                processingTimeMs = result.processingTimeMs
            )

        } catch (e: Exception) {
            logger.error("Error during transcription", e)
            STTTranscriptionResult(
                transcript = "",
                confidence = 0.0f,
                language = options.language ?: "unknown",
                error = e.message
            )
        }
    }

    actual override suspend fun <T> streamTranscribe(
        audioStream: Flow<ByteArray>,
        options: STTOptions,
        onPartial: (String) -> Unit
    ): STTTranscriptionResult {
        if (!whisperService.isReady()) {
            logger.error("WhisperSTTService not ready for streaming")
            return STTTranscriptionResult(
                transcript = "",
                confidence = 0.0f,
                language = options.language,
                error = "Service not ready"
            )
        }

        val audioChunks = mutableListOf<ByteArray>()
        var accumulatedText = ""

        audioStream.collect { chunk ->
            audioChunks.add(chunk)

            // For streaming, we can process chunks individually for partial results
            if (audioChunks.size % 5 == 0) { // Process every 5 chunks for partial
                try {
                    val combinedChunks = audioChunks.takeLast(10) // Use last 10 chunks for context
                    val combinedAudio = combinedChunks.reduce { acc, bytes -> acc + bytes }
                    val floatAudio = convertPcmToFloat(combinedAudio)

                    val partialResult = whisperService.transcribe(
                        audioData = floatAudio,
                        language = options.language,
                        enableTimestamps = false,
                        enableTranslate = options.translateToEnglish
                    )

                    if (partialResult.text.isNotEmpty() && partialResult.text != accumulatedText) {
                        accumulatedText = partialResult.text
                        onPartial(partialResult.text)
                    }
                } catch (e: Exception) {
                    logger.debug("Error in partial transcription", e)
                    // Continue processing, don't fail the stream
                }
            }
        }

        // Final transcription with all collected audio
        val combinedAudio = audioChunks.reduce { acc, bytes -> acc + bytes }
        return transcribe(combinedAudio, options)
    }

    actual override val isReady: Boolean
        get() = whisperService.isReady()

    actual override val currentModel: String?
        get() = modelPath

    override suspend fun cleanup() {
        logger.info("Cleaning up WhisperSTTService")
        whisperService.cleanup()
        modelPath = null
    }

    /**
     * Convert PCM byte array to float array for whisper processing
     * Assumes 16-bit PCM mono audio
     */
    private fun convertPcmToFloat(pcmData: ByteArray): FloatArray {
        // If JNI conversion is available, use it for optimal performance
        if (WhisperJNI.isLoaded()) {
            return WhisperJNI.convertPcmToFloat(pcmData, 16000, 16000)
        }

        // Fallback: manual conversion
        val buffer = ByteBuffer.wrap(pcmData).order(ByteOrder.LITTLE_ENDIAN)
        val floatArray = FloatArray(pcmData.size / 2) // 16-bit = 2 bytes per sample

        for (i in floatArray.indices) {
            val sample = buffer.short.toInt()
            floatArray[i] = sample / 32768.0f // Convert to -1.0 to 1.0 range
        }

        return floatArray
    }

    /**
     * Get detected language probabilities from last transcription
     */
    fun getLanguageProbabilities(): Array<WhisperLanguageProb> {
        return if (whisperService.isReady()) {
            whisperService.getLanguageProbabilities()
        } else {
            emptyArray()
        }
    }

    /**
     * Get current model information
     */
    fun getModelInfo(): WhisperModelInfo? {
        return whisperService.getModelInfo()
    }
}
