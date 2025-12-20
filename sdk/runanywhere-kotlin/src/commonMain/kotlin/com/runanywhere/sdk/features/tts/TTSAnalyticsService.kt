package com.runanywhere.sdk.features.tts

import com.runanywhere.sdk.events.EventPublisher
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.currentTimeMillis
import com.runanywhere.sdk.models.enums.InferenceFramework
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

/**
 * TTS analytics service for tracking synthesis operations.
 * Mirrors iOS TTSAnalyticsService exactly.
 *
 * Model lifecycle events (load/unload) are handled separately by ManagedLifecycle.
 *
 * NOTE: Audio duration estimation assumes 16-bit PCM @ 22050Hz (standard for TTS).
 * Formula: audioDurationMs = (bytes / 2) / 22050 * 1000
 * Actual sample rates may vary depending on the TTS model/voice configuration.
 */
class TTSAnalyticsService {
    private val logger = SDKLogger("TTSAnalytics")

    // Active synthesis operations
    private val activeSyntheses = mutableMapOf<String, SynthesisTracker>()

    // Metrics
    private var synthesisCount = 0
    private var totalCharacters = 0
    private var totalProcessingTimeMs = 0.0
    private var totalAudioDurationMs = 0.0
    private var totalAudioSizeBytes = 0L
    private var totalCharactersPerSecond = 0.0
    private val startTime = currentTimeMillis()
    private var lastEventTime: Long? = null

    // MARK: - Types

    private data class SynthesisTracker(
        val startTime: Long,
        val voiceId: String,
        val characterCount: Int,
        val framework: InferenceFramework,
    )

    // MARK: - Synthesis Tracking

    /**
     * Start tracking a synthesis.
     * @param text The text to synthesize
     * @param voice The voice ID being used
     * @param framework The inference framework being used
     * @return A unique synthesis ID for tracking
     */
    @OptIn(ExperimentalUuidApi::class)
    fun startSynthesis(
        text: String,
        voice: String,
        framework: InferenceFramework = InferenceFramework.SYSTEM_TTS,
    ): String {
        val id = Uuid.random().toString()
        val characterCount = text.length

        synchronized(activeSyntheses) {
            activeSyntheses[id] =
                SynthesisTracker(
                    startTime = currentTimeMillis(),
                    voiceId = voice,
                    characterCount = characterCount,
                    framework = framework,
                )
        }

        EventPublisher.track(
            TTSEvent.SynthesisStarted(
                synthesisId = id,
                voiceId = voice,
                characterCount = characterCount,
                framework = framework,
            ),
        )

        logger.debug("Synthesis started: $id, $characterCount characters")
        return id
    }

    /**
     * Track synthesis chunk (analytics only, for streaming synthesis).
     */
    fun trackSynthesisChunk(
        synthesisId: String,
        chunkSize: Int,
    ) {
        EventPublisher.track(
            TTSEvent.SynthesisChunk(
                synthesisId = synthesisId,
                chunkSize = chunkSize,
            ),
        )
    }

    /**
     * Complete a synthesis.
     * @param synthesisId The synthesis ID from startSynthesis
     * @param audioDurationMs Duration of the generated audio in milliseconds
     * @param audioSizeBytes Size of the generated audio in bytes
     */
    fun completeSynthesis(
        synthesisId: String,
        audioDurationMs: Double,
        audioSizeBytes: Int,
    ) {
        val tracker =
            synchronized(activeSyntheses) {
                activeSyntheses.remove(synthesisId)
            } ?: return

        val endTime = currentTimeMillis()
        val processingTimeMs = (endTime - tracker.startTime).toDouble()
        val characterCount = tracker.characterCount

        // Calculate characters per second (synthesis speed)
        val charsPerSecond =
            if (processingTimeMs > 0) {
                characterCount.toDouble() / (processingTimeMs / 1000.0)
            } else {
                0.0
            }

        // Update metrics
        synchronized(this) {
            synthesisCount++
            totalCharacters += characterCount
            totalProcessingTimeMs += processingTimeMs
            totalAudioDurationMs += audioDurationMs
            totalAudioSizeBytes += audioSizeBytes.toLong()
            totalCharactersPerSecond += charsPerSecond
            lastEventTime = endTime
        }

        EventPublisher.track(
            TTSEvent.SynthesisCompleted(
                synthesisId = synthesisId,
                voiceId = tracker.voiceId,
                characterCount = characterCount,
                audioDurationMs = audioDurationMs,
                audioSizeBytes = audioSizeBytes,
                processingDurationMs = processingTimeMs,
                charactersPerSecond = charsPerSecond,
                framework = tracker.framework,
            ),
        )

        logger.debug("Synthesis completed: $synthesisId, audio: ${String.format("%.1f", audioDurationMs)}ms, $audioSizeBytes bytes")
    }

    /**
     * Track synthesis failure.
     */
    fun trackSynthesisFailed(
        synthesisId: String,
        errorMessage: String,
    ) {
        synchronized(activeSyntheses) {
            activeSyntheses.remove(synthesisId)
        }
        lastEventTime = currentTimeMillis()

        EventPublisher.track(
            TTSEvent.SynthesisFailed(
                synthesisId = synthesisId,
                error = errorMessage,
            ),
        )
    }

    /**
     * Track an error during operations.
     */
    fun trackError(
        error: Throwable,
        operation: String,
    ) {
        lastEventTime = currentTimeMillis()
        logger.error("TTS error during $operation: ${error.message}")
        // Error events can be added via a generic ErrorEvent if needed
    }

    // MARK: - Metrics

    /**
     * Get current TTS metrics.
     */
    fun getMetrics(): TTSMetrics =
        synchronized(this) {
            TTSMetrics(
                totalEvents = synthesisCount,
                startTime = startTime,
                lastEventTime = lastEventTime,
                totalSyntheses = synthesisCount,
                averageCharactersPerSecond =
                    if (synthesisCount > 0) {
                        totalCharactersPerSecond / synthesisCount
                    } else {
                        0.0
                    },
                averageProcessingTimeMs =
                    if (synthesisCount > 0) {
                        totalProcessingTimeMs / synthesisCount
                    } else {
                        0.0
                    },
                averageAudioDurationMs =
                    if (synthesisCount > 0) {
                        totalAudioDurationMs / synthesisCount
                    } else {
                        0.0
                    },
                totalCharactersProcessed = totalCharacters,
                totalAudioSizeBytes = totalAudioSizeBytes,
            )
        }
}

// MARK: - TTS Metrics

/**
 * Metrics for TTS operations.
 * Mirrors iOS TTSMetrics struct.
 */
data class TTSMetrics(
    /** Total number of synthesis events */
    val totalEvents: Int = 0,
    /** When tracking started (epoch millis) */
    val startTime: Long = currentTimeMillis(),
    /** When the last event occurred (epoch millis) */
    val lastEventTime: Long? = null,
    /** Total number of syntheses completed */
    val totalSyntheses: Int = 0,
    /** Average synthesis speed (characters processed per second) */
    val averageCharactersPerSecond: Double = 0.0,
    /** Average processing time in milliseconds */
    val averageProcessingTimeMs: Double = 0.0,
    /** Average audio duration in milliseconds */
    val averageAudioDurationMs: Double = 0.0,
    /** Total characters processed across all syntheses */
    val totalCharactersProcessed: Int = 0,
    /** Total audio size generated in bytes */
    val totalAudioSizeBytes: Long = 0,
)
