package com.runanywhere.sdk.voice.handlers

import com.runanywhere.sdk.components.vad.VADComponent
import com.runanywhere.sdk.components.vad.VADConfiguration
import com.runanywhere.sdk.components.vad.VADInput
import com.runanywhere.sdk.components.vad.VADOutput
import com.runanywhere.sdk.components.vad.VADMetadata
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.voice.vad.SimpleEnergyVAD
import com.runanywhere.sdk.voice.vad.SpeechActivityEvent
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * Handler for Voice Activity Detection operations
 * Manages VAD processing and speech detection
 */
class VADHandler(
    private val vadComponent: VADComponent? = null,
    private val simpleVAD: SimpleEnergyVAD? = null
) {

    private val logger = SDKLogger("VADHandler")

    // Speech detection state
    private var speechStartTime: Long? = null
    private var speechEndTime: Long? = null
    private var currentSpeechDuration: Long = 0

    // Configuration
    private var minSpeechDuration: Long = 200 // milliseconds
    private var maxSilenceDuration: Long = 1000 // milliseconds

    // Callbacks
    var onSpeechStart: (() -> Unit)? = null
    var onSpeechEnd: ((duration: Long) -> Unit)? = null

    init {
        // Setup SimpleVAD callbacks if available
        simpleVAD?.onSpeechActivity = { event ->
            handleSpeechActivityEvent(event)
        }
    }

    /**
     * Detect speech in audio data
     */
    suspend fun detectSpeech(audioData: ByteArray): VADOutput {
        // Use component if available
        if (vadComponent != null) {
            // Convert byte array to float array for VADInput
            val floatArray = byteArrayToFloatArray(audioData)
            val input = VADInput(audioSamples = floatArray)
            return vadComponent.process(input) as? VADOutput
                ?: VADOutput(
                    isSpeech = false,
                    confidence = 0.0f,
                    energyLevel = 0.0f,
                    speechProbability = 0.0f,
                    metadata = VADMetadata(
                        frameDuration = 100,
                        sampleRate = 16000,
                        aggressiveness = 2,
                        processingTime = 0.0
                    )
                )
        }

        // Fallback to SimpleVAD
        if (simpleVAD != null) {
            val isSpeech = simpleVAD.processAudioBuffer(audioData)
            return VADOutput(
                isSpeech = isSpeech,
                confidence = if (isSpeech) 0.9f else 0.1f,
                energyLevel = 0.5f, // TODO: Get actual energy from SimpleVAD
                speechProbability = if (isSpeech) 0.9f else 0.1f,
                metadata = VADMetadata(
                    frameDuration = 100,
                    sampleRate = 16000,
                    aggressiveness = 2,
                    processingTime = 0.0
                )
            )
        }

        // No VAD available, assume speech
        logger.warning("No VAD available, assuming speech")
        return VADOutput(
            isSpeech = true,
            confidence = 0.5f,
            energyLevel = 0.5f,
            speechProbability = 0.5f,
            metadata = VADMetadata(
                frameDuration = 100,
                sampleRate = 16000,
                aggressiveness = 2,
                processingTime = 0.0
            )
        )
    }

    /**
     * Stream VAD processing
     */
    fun streamVAD(audioStream: Flow<ByteArray>): Flow<VADOutput> = flow {
        audioStream.collect { chunk ->
            val vadOutput = detectSpeech(chunk)
            emit(vadOutput)
        }
    }

    /**
     * Process continuous audio stream with speech segmentation
     */
    fun segmentSpeech(audioStream: Flow<ByteArray>): Flow<SpeechSegment> = flow {
        val audioBuffer = mutableListOf<ByteArray>()
        var isInSpeech = false
        var silenceDuration = 0L
        val chunkDuration = 100L // Assume 100ms chunks

        audioStream.collect { chunk ->
            val vadOutput = detectSpeech(chunk)

            if (vadOutput.isSpeech) {
                if (!isInSpeech) {
                    // Speech started
                    isInSpeech = true
                    speechStartTime = System.currentTimeMillis()
                    audioBuffer.clear()
                    onSpeechStart?.invoke()
                    logger.debug("Speech segment started")
                }

                audioBuffer.add(chunk)
                silenceDuration = 0

            } else {
                if (isInSpeech) {
                    audioBuffer.add(chunk)
                    silenceDuration += chunkDuration

                    // Check if silence exceeds threshold
                    if (silenceDuration >= maxSilenceDuration) {
                        // Speech ended
                        isInSpeech = false
                        speechEndTime = System.currentTimeMillis()
                        val duration = speechEndTime!! - speechStartTime!!

                        if (duration >= minSpeechDuration) {
                            // Emit speech segment
                            val segment = SpeechSegment(
                                audio = combineAudioBuffers(audioBuffer),
                                startTime = speechStartTime!!,
                                endTime = speechEndTime!!,
                                duration = duration
                            )
                            emit(segment)
                            onSpeechEnd?.invoke(duration)
                            logger.debug("Speech segment ended: ${duration}ms")
                        } else {
                            logger.debug("Speech segment too short: ${duration}ms")
                        }

                        audioBuffer.clear()
                    }
                }
            }
        }

        // Emit final segment if in speech
        if (isInSpeech && audioBuffer.isNotEmpty()) {
            speechEndTime = System.currentTimeMillis()
            val duration = speechEndTime!! - speechStartTime!!

            if (duration >= minSpeechDuration) {
                val segment = SpeechSegment(
                    audio = combineAudioBuffers(audioBuffer),
                    startTime = speechStartTime!!,
                    endTime = speechEndTime!!,
                    duration = duration,
                    isFinal = true
                )
                emit(segment)
                onSpeechEnd?.invoke(duration)
            }
        }
    }

    /**
     * Configure VAD handler
     */
    fun configure(
        minSpeechDuration: Long? = null,
        maxSilenceDuration: Long? = null,
        energyThreshold: Float? = null
    ) {
        minSpeechDuration?.let { this.minSpeechDuration = it }
        maxSilenceDuration?.let { this.maxSilenceDuration = it }
        energyThreshold?.let { simpleVAD?.setEnergyThreshold(it) }

        logger.info("VAD configured - minSpeech: ${this.minSpeechDuration}ms, maxSilence: ${this.maxSilenceDuration}ms")
    }

    /**
     * Initialize the handler
     */
    suspend fun initialize() {
        vadComponent?.initialize()
        simpleVAD?.initialize(VADConfiguration())
        logger.info("VAD handler initialized")
    }

    /**
     * Cleanup resources
     */
    suspend fun cleanup() {
        vadComponent?.cleanup()
        simpleVAD?.stop()
        logger.info("VAD handler cleaned up")
    }

    /**
     * Reset VAD state
     */
    fun reset() {
        speechStartTime = null
        speechEndTime = null
        currentSpeechDuration = 0
        simpleVAD?.reset()
        logger.debug("VAD state reset")
    }

    // Private helpers

    private fun handleSpeechActivityEvent(event: SpeechActivityEvent) {
        when (event) {
            is SpeechActivityEvent.SpeechStart -> {
                speechStartTime = System.currentTimeMillis()
                onSpeechStart?.invoke()
            }
            is SpeechActivityEvent.SpeechEnd -> {
                speechEndTime = System.currentTimeMillis()
                val duration = speechEndTime!! - (speechStartTime ?: speechEndTime!!)
                onSpeechEnd?.invoke(duration)
            }
            is SpeechActivityEvent.EnergyUpdate -> {
                // Log energy updates if needed
            }
        }
    }

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

    private fun byteArrayToFloatArray(bytes: ByteArray): FloatArray {
        val floats = FloatArray(bytes.size / 2)

        for (i in floats.indices) {
            val sample = (bytes[i * 2 + 1].toInt() shl 8) or (bytes[i * 2].toInt() and 0xFF)
            floats[i] = sample / 32768.0f
        }

        return floats
    }
}

/**
 * Speech segment detected by VAD
 */
data class SpeechSegment(
    val audio: ByteArray,
    val startTime: Long,
    val endTime: Long,
    val duration: Long,
    val isFinal: Boolean = false
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is SpeechSegment) return false
        return audio.contentEquals(other.audio) &&
                startTime == other.startTime &&
                endTime == other.endTime &&
                duration == other.duration &&
                isFinal == other.isFinal
    }

    override fun hashCode(): Int {
        var result = audio.contentHashCode()
        result = 31 * result + startTime.hashCode()
        result = 31 * result + endTime.hashCode()
        result = 31 * result + duration.hashCode()
        result = 31 * result + isFinal.hashCode()
        return result
    }
}
