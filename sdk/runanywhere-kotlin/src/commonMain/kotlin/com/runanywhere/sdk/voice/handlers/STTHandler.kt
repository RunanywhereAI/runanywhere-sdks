package com.runanywhere.sdk.voice.handlers

import com.runanywhere.sdk.components.stt.STTComponent
import com.runanywhere.sdk.components.stt.STTInput
import com.runanywhere.sdk.components.stt.STTOutput
import com.runanywhere.sdk.components.stt.STTOptions
import com.runanywhere.sdk.components.stt.TranscriptionMetadata
import com.runanywhere.sdk.components.vad.VADOutput
import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * Handler for Speech-to-Text operations
 * Coordinates between VAD and STT components for optimal transcription
 */
class STTHandler(
    private val sttComponent: STTComponent,
    private val vadHandler: VADHandler? = null
) {

    private val logger = SDKLogger("STTHandler")

    // Processing configuration
    private var bufferDuration: Float = 1.0f // seconds
    private var enableVAD: Boolean = true
    private var enablePartialResults: Boolean = true

    /**
     * Process audio for transcription with optional VAD
     */
    suspend fun processAudio(
        audioData: ByteArray,
        options: STTOptions? = null
    ): TranscriptionResult {
        logger.debug("Processing audio: ${audioData.size} bytes")

        // Process with VAD if enabled and available
        val vadOutput = if (enableVAD && vadHandler != null) {
            vadHandler.detectSpeech(audioData)
        } else {
            null
        }

        // Skip if no speech detected
        if (vadOutput != null && !vadOutput.isSpeech) {
            logger.debug("No speech detected, skipping transcription")
            return TranscriptionResult(
                text = "",
                confidence = 0.0f,
                isFinal = false,
                vadOutput = vadOutput
            )
        }

        // Prepare STT input
        val sttInput = STTInput(
            audioData = audioData,
            vadOutput = vadOutput,
            options = options
        )

        // Process with STT
        // Note: STTComponent doesn't have a generic process method,
        // we need to use the transcribe method instead
        val result = sttComponent.transcribe(audioData)
        val sttOutput = STTOutput(
            text = result.text,
            confidence = result.confidence,
            wordTimestamps = null,
            detectedLanguage = null,
            alternatives = null,
            metadata = com.runanywhere.sdk.components.stt.TranscriptionMetadata(
                modelId = "default",
                processingTime = 0.0,
                audioLength = audioData.size.toDouble() / 32000.0, // Assume 16kHz stereo
                realTimeFactor = 0.0
            )
        )

        return TranscriptionResult(
            text = sttOutput.text,
            confidence = sttOutput.confidence,
            isFinal = true,
            vadOutput = vadOutput,
            wordTimestamps = sttOutput.wordTimestamps,
            detectedLanguage = sttOutput.detectedLanguage
        )
    }

    /**
     * Stream audio processing with continuous transcription
     */
    fun streamAudio(
        audioStream: Flow<ByteArray>,
        options: STTOptions? = null
    ): Flow<TranscriptionResult> = flow {

        val audioBuffer = mutableListOf<ByteArray>()
        var bufferSize = 0
        val maxBufferSize = (16000 * bufferDuration).toInt() * 2 // 16kHz * duration * 2 bytes per sample

        audioStream.collect { chunk ->
            // Add to buffer
            audioBuffer.add(chunk)
            bufferSize += chunk.size

            // Process when buffer is full
            if (bufferSize >= maxBufferSize) {
                val combinedAudio = combineAudioBuffers(audioBuffer)
                val result = processAudio(combinedAudio, options)

                if (result.text.isNotEmpty() || enablePartialResults) {
                    emit(result)
                }

                // Clear buffer
                audioBuffer.clear()
                bufferSize = 0
            }
        }

        // Process remaining buffer
        if (audioBuffer.isNotEmpty()) {
            val combinedAudio = combineAudioBuffers(audioBuffer)
            val result = processAudio(combinedAudio, options)

            if (result.text.isNotEmpty()) {
                emit(result.copy(isFinal = true))
            }
        }
    }

    /**
     * Configure the handler
     */
    fun configure(
        bufferDuration: Float? = null,
        enableVAD: Boolean? = null,
        enablePartialResults: Boolean? = null
    ) {
        bufferDuration?.let { this.bufferDuration = it }
        enableVAD?.let { this.enableVAD = it }
        enablePartialResults?.let { this.enablePartialResults = it }

        logger.info("Handler configured - bufferDuration: ${this.bufferDuration}s, VAD: ${this.enableVAD}, partials: ${this.enablePartialResults}")
    }

    /**
     * Initialize the handler
     */
    suspend fun initialize() {
        sttComponent.initialize()
        vadHandler?.initialize()
        logger.info("STT handler initialized")
    }

    /**
     * Cleanup resources
     */
    suspend fun cleanup() {
        sttComponent.cleanup()
        vadHandler?.cleanup()
        logger.info("STT handler cleaned up")
    }

    // Private helpers

    private fun combineAudioBuffers(buffers: List<ByteArray>): ByteArray {
        val totalSize = buffers.sumOf { it.size }
        val combined = ByteArray(totalSize)
        var offset = 0

        for (buffer in buffers) {
            buffer.copyInto(combined, offset)
            offset += buffer.size
        }

        return combined
    }
}

/**
 * Transcription result from STT handler
 */
data class TranscriptionResult(
    val text: String,
    val confidence: Float,
    val isFinal: Boolean,
    val vadOutput: VADOutput? = null,
    val wordTimestamps: List<com.runanywhere.sdk.components.stt.WordTimestamp>? = null,
    val detectedLanguage: String? = null
)
