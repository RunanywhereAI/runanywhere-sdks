package com.runanywhere.sdk.components.stt

import com.runanywhere.sdk.data.models.generateUUID
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.services.analytics.STTAnalyticsService
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import com.runanywhere.sdk.utils.PlatformUtils
import com.runanywhere.sdk.events.ModularPipelineEvent
import com.runanywhere.sdk.events.SpeakerInfo
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.launch

/**
 * Handles Speech-to-Text processing in the voice pipeline (matches iOS STTHandler exactly)
 *
 * @param voiceAnalytics Voice analytics service (optional)
 * @param sttAnalytics STT analytics service (optional)
 * @param telemetryScope Coroutine scope for telemetry operations. Should be provided by parent
 *                       component for proper lifecycle management. Defaults to a new scope if not provided.
 */
class STTHandler(
    private val voiceAnalytics: Any? = null, // VoiceAnalyticsService - avoiding dependency for now
    private val sttAnalytics: STTAnalyticsService? = null,
    private val telemetryScope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
) {
    private val logger = SDKLogger("STTHandler")

    // Get telemetry service from ServiceContainer (matches iOS pattern)
    private val telemetryService get() = ServiceContainer.shared.telemetryService

    /**
     * Transcribe audio samples to text (matches iOS signature exactly)
     *
     * @param samples Audio samples to transcribe
     * @param service STT service to use for transcription
     * @param options Transcription options
     * @param speakerDiarization Optional speaker diarization service
     * @param continuation Event stream continuation
     * @return Transcription result
     */
    suspend fun transcribeAudio(
        samples: FloatArray,
        service: STTService,
        options: STTOptions,
        speakerDiarization: SpeakerDiarizationService?,
        continuation: MutableSharedFlow<ModularPipelineEvent>
    ): String {

        if (samples.isEmpty()) {
            logger.debug("transcribeAudio called with empty samples, skipping")
            return ""
        }

        logger.debug("Starting transcription with ${samples.size} samples")

        // Generate session ID for telemetry tracking
        val sessionId = generateUUID()

        // Calculate audio length (assuming 16kHz sample rate like iOS)
        val audioLength = samples.size.toDouble() / 16000.0
        val audioDurationMs = audioLength * 1000.0

        // Track transcription start
        sttAnalytics?.trackTranscriptionStarted(audioLength)

        val startTime = getCurrentTimeMillis()
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
                    language = options.language,
                    device = PlatformUtils.getDeviceModel(),
                    osVersion = PlatformUtils.getOSVersion()
                )
            } catch (e: Exception) {
                logger.debug("Failed to track STT transcription started: ${e.message}")
            }
        }

        try {
            // Get transcription result based on service's preferred format
            val result = performTranscription(
                samples = samples,
                service = service,
                options = options
            )

            val endTime = getCurrentTimeMillis()
            val processingTimeMs = (endTime - startTime).toDouble()
            val duration = processingTimeMs / 1000.0

            val transcript = result.text
            logger.info("STT transcription result: '$transcript'")

            if (transcript.isNotEmpty()) {
                // Track successful transcription completion
                val wordCount = transcript.split("\\s+".toRegex()).filter { it.isNotEmpty() }.size
                val characterCount = transcript.length
                val confidence = result.confidence ?: 0.8f // Default confidence if not provided
                val realTimeFactor = if (audioDurationMs > 0) processingTimeMs / audioDurationMs else 0.0

                sttAnalytics?.trackTranscription(
                    text = transcript,
                    confidence = confidence,
                    duration = duration,
                    audioLength = audioLength
                )

                sttAnalytics?.trackFinalTranscript(
                    text = transcript,
                    confidence = confidence
                )

                // Track transcription completion - fire and forget
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
                            osVersion = PlatformUtils.getOSVersion()
                        )
                    } catch (e: Exception) {
                        logger.debug("Failed to track STT transcription completed: ${e.message}")
                    }
                }

                // Handle speaker diarization if available (matching iOS pattern)
                if (speakerDiarization != null && options.enableDiarization) {
                    handleSpeakerDiarization(
                        samples = samples,
                        transcript = transcript,
                        service = speakerDiarization,
                        continuation = continuation
                    )
                } else {
                    // Regular transcript without speaker info (matching iOS)
                    continuation.emit(ModularPipelineEvent.sttFinalTranscript(transcript))
                }
                return transcript
            } else {
                logger.warning("STT returned empty transcript")
                return ""
            }
        } catch (error: Exception) {
            logger.error("STT transcription failed: $error")

            // Track transcription error
            sttAnalytics?.trackError(error, "transcription")

            // Track transcription failure - fire and forget
            val endTime = getCurrentTimeMillis()
            val processingTimeMs = (endTime - startTime).toDouble()
            val failureModelId = service.currentModel
            val errorMsg = error.message ?: error.toString()

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
                        errorMessage = errorMsg,
                        device = PlatformUtils.getDeviceModel(),
                        osVersion = PlatformUtils.getOSVersion()
                    )
                } catch (e: Exception) {
                    logger.debug("Failed to track STT transcription failure: ${e.message}")
                }
            }

            throw error
        }
    }

    // MARK: - Private Methods

    private suspend fun performTranscription(
        samples: FloatArray,
        service: STTService,
        options: STTOptions
    ): STTResult {

        // Convert based on service's preferred format (matching iOS pattern)
        logger.debug("Converting ${samples.size} float samples based on service preference")

        val audioData = when (service.preferredAudioFormat) {
            STTServiceAudioFormat.FLOAT_ARRAY -> convertFloatArrayToBytes(samples) // Service can handle floats internally
            STTServiceAudioFormat.DATA -> convertFloatArrayToBytes(samples)
        }

        logger.debug("Calling STT.transcribe with ${audioData.size} bytes")

        val result = service.transcribe(
            audioData = audioData,
            options = options
        )

        // Convert STTTranscriptionResult to STTResult (matching iOS pattern)
        val segments: List<STTSegment> = result.timestamps?.map { timestamp ->
            STTSegment(
                text = timestamp.word,
                startTime = timestamp.startTime,
                endTime = timestamp.endTime,
                confidence = timestamp.confidence ?: 0.95f
            )
        } ?: emptyList()

        val alternatives: List<STTAlternative> = result.alternatives?.map { alt ->
            STTAlternative(
                text = alt.transcript,
                confidence = alt.confidence
            )
        } ?: emptyList()

        return STTResult(
            text = result.transcript,
            segments = segments,
            language = result.language,
            confidence = result.confidence ?: 0.95f,
            duration = segments.lastOrNull()?.endTime ?: 0.0,
            alternatives = alternatives
        )
    }

    private fun convertFloatArrayToBytes(samples: FloatArray): ByteArray {
        // Convert float samples to byte array (matching iOS conversion pattern)
        val byteArray = ByteArray(samples.size * 4) // 4 bytes per float
        for (i in samples.indices) {
            val bits = samples[i].toBits()
            byteArray[i * 4] = (bits and 0xFF).toByte()
            byteArray[i * 4 + 1] = ((bits shr 8) and 0xFF).toByte()
            byteArray[i * 4 + 2] = ((bits shr 16) and 0xFF).toByte()
            byteArray[i * 4 + 3] = ((bits shr 24) and 0xFF).toByte()
        }
        return byteArray
    }

    private suspend fun handleSpeakerDiarization(
        samples: FloatArray,
        transcript: String,
        service: SpeakerDiarizationService,
        continuation: MutableSharedFlow<ModularPipelineEvent>
    ) {
        // Process audio to identify speaker (matching iOS pattern)
        val speaker = service.processAudio(samples)

        // Track speaker detection
        sttAnalytics?.trackSpeakerDetection(
            speaker = speaker.id,
            confidence = speaker.confidence ?: 0.8f
        )

        // Get all speakers to check if speaker changed (matching iOS logic)
        val allSpeakers = service.getAllSpeakers()
        val previousSpeaker = if (allSpeakers.size > 1) allSpeakers[allSpeakers.size - 2] else null

        if (previousSpeaker?.id != speaker.id) {
            continuation.emit(ModularPipelineEvent.sttSpeakerChanged(from = previousSpeaker, to = speaker))

            // Track speaker change
            sttAnalytics?.trackSpeakerChange(
                from = previousSpeaker?.id,
                to = speaker.id
            )
        }

        // Emit transcript with speaker info (matching iOS pattern)
        continuation.emit(ModularPipelineEvent.sttFinalTranscriptWithSpeaker(transcript, speaker))
        logger.info("Transcript with speaker ${speaker.name ?: speaker.id}: '$transcript'")
    }
}

// MARK: - Supporting Classes (matching iOS patterns)

/**
 * STT Result data class (matches iOS STTResult)
 */
data class STTResult(
    val text: String,
    val segments: List<STTSegment>,
    val language: String?,
    val confidence: Float,
    val duration: Double,
    val alternatives: List<STTAlternative>
)

/**
 * STT Segment data class (matches iOS STTSegment)
 */
data class STTSegment(
    val text: String,
    val startTime: Double,
    val endTime: Double,
    val confidence: Float,
    val speaker: Int? = null
)

/**
 * STT Alternative data class (matches iOS STTAlternative)
 */
data class STTAlternative(
    val text: String,
    val confidence: Float
)

/**
 * Speaker Diarization Service interface (matches iOS pattern)
 */
interface SpeakerDiarizationService {
    /**
     * Process audio samples to identify speaker
     */
    fun processAudio(samples: FloatArray): SpeakerInfo

    /**
     * Get all identified speakers
     */
    fun getAllSpeakers(): List<SpeakerInfo>
}
