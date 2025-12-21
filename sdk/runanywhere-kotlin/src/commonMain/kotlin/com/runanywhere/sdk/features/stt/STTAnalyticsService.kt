package com.runanywhere.sdk.features.stt

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.currentTimeMillis
import com.runanywhere.sdk.infrastructure.events.EventPublisher
import com.runanywhere.sdk.models.enums.InferenceFramework
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

/**
 * STT analytics service for tracking transcription operations.
 * Mirrors iOS STTAnalyticsService exactly.
 *
 * Model lifecycle events (load/unload) are handled separately by ManagedLifecycle.
 *
 * NOTE: Audio length estimation assumes 16-bit PCM @ 16kHz (standard for STT).
 * Formula: audioLengthMs = (bytes / 2) / 16000 * 1000
 *
 * NOTE: Real-Time Factor (RTF) will be 0 or undefined for streaming transcription
 * since audioLengthMs = 0 when audio is processed in chunks of unknown total length.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Features/STT/Analytics/STTAnalyticsService.swift
 */
class STTAnalyticsService {
    private val logger = SDKLogger("STTAnalytics")

    // Active transcription operations
    private val activeTranscriptions = mutableMapOf<String, TranscriptionTracker>()

    // Metrics
    private var transcriptionCount = 0
    private var totalConfidence = 0f
    private var totalLatency = 0.0
    private var totalAudioProcessed = 0.0 // Total audio length in ms
    private var totalRealTimeFactor = 0.0
    private val startTime = currentTimeMillis()
    private var lastEventTime: Long? = null

    // MARK: - TypesGo

    private data class TranscriptionTracker(
        val startTime: Long,
        val audioLengthMs: Double,
        val audioSizeBytes: Int,
        val language: String,
        val framework: InferenceFramework,
    )

    // MARK: - Transcription Tracking

    /**
     * Start tracking a transcription.
     * @param audioLengthMs Duration of audio in milliseconds
     * @param audioSizeBytes Size of audio data in bytes
     * @param language Language code for transcription
     * @param framework The inference framework being used
     * @return A unique transcription ID for tracking
     */
    @OptIn(ExperimentalUuidApi::class)
    fun startTranscription(
        audioLengthMs: Double,
        audioSizeBytes: Int,
        language: String,
        framework: InferenceFramework = InferenceFramework.WHISPER_CPP,
    ): String {
        val id = Uuid.random().toString()

        synchronized(activeTranscriptions) {
            activeTranscriptions[id] =
                TranscriptionTracker(
                    startTime = currentTimeMillis(),
                    audioLengthMs = audioLengthMs,
                    audioSizeBytes = audioSizeBytes,
                    language = language,
                    framework = framework,
                )
        }

        EventPublisher.track(
            STTEvent.TranscriptionStarted(
                transcriptionId = id,
                audioLengthMs = audioLengthMs,
                audioSizeBytes = audioSizeBytes,
                language = language,
                framework = framework,
            ),
        )

        logger.debug("Transcription started: $id, audio: ${String.format("%.1f", audioLengthMs)}ms, $audioSizeBytes bytes")
        return id
    }

    /**
     * Track partial transcript (for streaming transcription).
     */
    fun trackPartialTranscript(text: String) {
        val wordCount = text.split(" ").filter { it.isNotBlank() }.size

        EventPublisher.track(
            STTEvent.PartialTranscript(
                text = text,
                wordCount = wordCount,
            ),
        )

        logger.debug("Partial transcript: $wordCount words")
    }

    /**
     * Track final transcript (for streaming transcription).
     */
    fun trackFinalTranscript(text: String, confidence: Float) {
        EventPublisher.track(
            STTEvent.FinalTranscript(
                text = text,
                confidence = confidence,
            ),
        )

        logger.debug("Final transcript: ${text.length} chars, confidence: ${String.format("%.3f", confidence)}")
    }

    /**
     * Complete a transcription.
     * @param transcriptionId The transcription ID from startTranscription
     * @param text The transcribed text
     * @param confidence Confidence score (0.0 to 1.0)
     */
    fun completeTranscription(
        transcriptionId: String,
        text: String,
        confidence: Float,
    ) {
        val tracker =
            synchronized(activeTranscriptions) {
                activeTranscriptions.remove(transcriptionId)
            } ?: return

        val endTime = currentTimeMillis()
        val processingTimeMs = (endTime - tracker.startTime).toDouble()
        val wordCount = text.split(" ").filter { it.isNotBlank() }.size

        // Calculate real-time factor (RTF): processing time / audio length
        // RTF < 1.0 means faster than real-time
        val realTimeFactor =
            if (tracker.audioLengthMs > 0) {
                processingTimeMs / tracker.audioLengthMs
            } else {
                0.0
            }

        // Update metrics
        synchronized(this) {
            transcriptionCount++
            totalConfidence += confidence
            totalLatency += processingTimeMs / 1000.0
            totalAudioProcessed += tracker.audioLengthMs
            totalRealTimeFactor += realTimeFactor
            lastEventTime = endTime
        }

        EventPublisher.track(
            STTEvent.TranscriptionCompleted(
                transcriptionId = transcriptionId,
                text = text,
                confidence = confidence,
                durationMs = processingTimeMs,
                audioLengthMs = tracker.audioLengthMs,
                audioSizeBytes = tracker.audioSizeBytes,
                wordCount = wordCount,
                realTimeFactor = realTimeFactor,
                framework = tracker.framework,
            ),
        )

        logger.debug("Transcription completed: $transcriptionId, RTF: ${String.format("%.3f", realTimeFactor)}")
    }

    /**
     * Track transcription failure.
     */
    fun trackTranscriptionFailed(
        transcriptionId: String,
        errorMessage: String,
    ) {
        synchronized(activeTranscriptions) {
            activeTranscriptions.remove(transcriptionId)
        }
        lastEventTime = currentTimeMillis()

        EventPublisher.track(
            STTEvent.TranscriptionFailed(
                transcriptionId = transcriptionId,
                error = errorMessage,
            ),
        )

        logger.error("Transcription failed: $transcriptionId - $errorMessage")
    }

    /**
     * Track language detection (analytics only).
     */
    fun trackLanguageDetection(language: String, confidence: Float) {
        EventPublisher.track(
            STTEvent.LanguageDetected(
                language = language,
                confidence = confidence,
            ),
        )

        logger.debug("Language detected: $language with confidence ${String.format("%.3f", confidence)}")
    }

    /**
     * Track an error during operations.
     */
    fun trackError(error: Throwable, operation: String) {
        lastEventTime = currentTimeMillis()
        logger.error("STT error during $operation: ${error.message}")
    }

    // MARK: - Metrics

    /**
     * Get current STT metrics.
     * Matches iOS STTAnalyticsService.getMetrics()
     */
    fun getMetrics(): STTMetrics =
        synchronized(this) {
            // Average RTF only if we have transcriptions
            val avgRTF =
                if (transcriptionCount > 0) {
                    totalRealTimeFactor / transcriptionCount
                } else {
                    0.0
                }

            STTMetrics(
                totalEvents = transcriptionCount,
                startTime = startTime,
                lastEventTime = lastEventTime,
                totalTranscriptions = transcriptionCount,
                averageConfidence =
                    if (transcriptionCount > 0) {
                        totalConfidence / transcriptionCount
                    } else {
                        0f
                    },
                averageLatency =
                    if (transcriptionCount > 0) {
                        totalLatency / transcriptionCount
                    } else {
                        0.0
                    },
                averageRealTimeFactor = avgRTF,
                totalAudioProcessedMs = totalAudioProcessed,
            )
        }
}

// MARK: - STT Metrics

/**
 * Metrics for STT operations.
 * Mirrors iOS STTMetrics struct exactly.
 */
data class STTMetrics(
    /** Total number of transcription events */
    val totalEvents: Int = 0,
    /** When tracking started (epoch millis) */
    val startTime: Long = currentTimeMillis(),
    /** When the last event occurred (epoch millis) */
    val lastEventTime: Long? = null,
    /** Total number of transcriptions completed */
    val totalTranscriptions: Int = 0,
    /** Average confidence score across all transcriptions (0.0 to 1.0) */
    val averageConfidence: Float = 0f,
    /** Average processing latency in seconds */
    val averageLatency: Double = 0.0,
    /**
     * Average real-time factor (processing time / audio length)
     * Values < 1.0 indicate faster-than-real-time processing
     */
    val averageRealTimeFactor: Double = 0.0,
    /** Total audio processed in milliseconds */
    val totalAudioProcessedMs: Double = 0.0,
)
