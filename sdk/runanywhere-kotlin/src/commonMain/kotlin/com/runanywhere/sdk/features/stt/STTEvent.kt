package com.runanywhere.sdk.features.stt

import com.runanywhere.sdk.infrastructure.events.BaseSDKEvent
import com.runanywhere.sdk.infrastructure.events.EventCategory
import com.runanywhere.sdk.infrastructure.events.EventDestination
import com.runanywhere.sdk.models.enums.InferenceFramework

/**
 * All STT (Speech-to-Text) related events.
 * Mirrors iOS STTEvent enum exactly.
 *
 * Usage:
 * ```kotlin
 * EventPublisher.track(STTEvent.TranscriptionCompleted(...))
 * ```
 *
 * NOTE: iOS uses InferenceFrameworkType while KMP uses InferenceFramework.
 * This is a documented naming drift that will be resolved in a future iteration.
 */
sealed class STTEvent : BaseSDKEvent(EventCategory.STT) {
    // MARK: - Model Lifecycle

    /** Model load started */
    data class ModelLoadStarted(
        val modelId: String,
        val modelSizeBytes: Long = 0,
        val framework: InferenceFramework = InferenceFramework.UNKNOWN,
    ) : STTEvent() {
        override val type: String = "stt_model_load_started"
        override val properties: Map<String, String>
            get() =
                buildMap {
                    put("model_id", modelId)
                    put("framework", framework.value)
                    if (modelSizeBytes > 0) {
                        put("model_size_bytes", modelSizeBytes.toString())
                    }
                }
    }

    /** Model load completed */
    data class ModelLoadCompleted(
        val modelId: String,
        val durationMs: Double,
        val modelSizeBytes: Long = 0,
        val framework: InferenceFramework = InferenceFramework.UNKNOWN,
    ) : STTEvent() {
        override val type: String = "stt_model_load_completed"
        override val properties: Map<String, String>
            get() =
                buildMap {
                    put("model_id", modelId)
                    put("duration_ms", String.format("%.1f", durationMs))
                    put("framework", framework.value)
                    if (modelSizeBytes > 0) {
                        put("model_size_bytes", modelSizeBytes.toString())
                    }
                }
    }

    /** Model load failed */
    data class ModelLoadFailed(
        val modelId: String,
        val error: String,
        val framework: InferenceFramework = InferenceFramework.UNKNOWN,
    ) : STTEvent() {
        override val type: String = "stt_model_load_failed"
        override val properties: Map<String, String>
            get() =
                mapOf(
                    "model_id" to modelId,
                    "error" to error,
                    "framework" to framework.value,
                )
    }

    /** Model unloaded */
    data class ModelUnloaded(
        val modelId: String,
    ) : STTEvent() {
        override val type: String = "stt_model_unloaded"
        override val properties: Map<String, String>
            get() = mapOf("model_id" to modelId)
    }

    // MARK: - Transcription

    /**
     * Transcription started event
     * @param transcriptionId Unique identifier for this transcription operation
     * @param audioLengthMs Duration of audio in milliseconds
     * @param audioSizeBytes Size of audio data in bytes
     * @param language Language code for transcription
     * @param framework The inference framework being used
     */
    data class TranscriptionStarted(
        val transcriptionId: String,
        val audioLengthMs: Double,
        val audioSizeBytes: Int,
        val language: String,
        val framework: InferenceFramework = InferenceFramework.UNKNOWN,
    ) : STTEvent() {
        override val type: String = "stt_transcription_started"
        override val properties: Map<String, String>
            get() =
                mapOf(
                    "transcription_id" to transcriptionId,
                    "audio_length_ms" to String.format("%.1f", audioLengthMs),
                    "audio_size_bytes" to audioSizeBytes.toString(),
                    "language" to language,
                    "framework" to framework.value,
                )
    }

    /**
     * Partial transcript received (for streaming transcription).
     * @param text The partial transcription text
     * @param wordCount Number of words in the partial transcript
     */
    data class PartialTranscript(
        val text: String,
        val wordCount: Int,
    ) : STTEvent() {
        override val type: String = "stt_partial_transcript"
        override val properties: Map<String, String>
            get() =
                mapOf(
                    "text_length" to text.length.toString(),
                    "word_count" to wordCount.toString(),
                )
    }

    /**
     * Final transcript received (for streaming transcription).
     * @param text The final transcription text
     * @param confidence Confidence score (0.0 to 1.0)
     */
    data class FinalTranscript(
        val text: String,
        val confidence: Float,
    ) : STTEvent() {
        override val type: String = "stt_final_transcript"
        override val properties: Map<String, String>
            get() =
                mapOf(
                    "text_length" to text.length.toString(),
                    "confidence" to String.format("%.3f", confidence),
                )
    }

    /**
     * Transcription completed event
     * @param transcriptionId Unique identifier for this transcription operation
     * @param text The transcribed text
     * @param confidence Confidence score (0.0 to 1.0)
     * @param durationMs Processing time in milliseconds
     * @param audioLengthMs Duration of audio in milliseconds
     * @param audioSizeBytes Size of audio data in bytes
     * @param wordCount Number of words in the transcription
     * @param realTimeFactor Processing time / audio length (< 1.0 means faster than real-time)
     * @param framework The inference framework that was used
     */
    data class TranscriptionCompleted(
        val transcriptionId: String,
        val text: String,
        val confidence: Float,
        val durationMs: Double,
        val audioLengthMs: Double,
        val audioSizeBytes: Int,
        val wordCount: Int,
        val realTimeFactor: Double,
        val framework: InferenceFramework = InferenceFramework.UNKNOWN,
    ) : STTEvent() {
        override val type: String = "stt_transcription_completed"
        override val properties: Map<String, String>
            get() =
                mapOf(
                    "transcription_id" to transcriptionId,
                    "text_length" to text.length.toString(),
                    "confidence" to String.format("%.3f", confidence),
                    "duration_ms" to String.format("%.1f", durationMs),
                    "audio_length_ms" to String.format("%.1f", audioLengthMs),
                    "audio_size_bytes" to audioSizeBytes.toString(),
                    "word_count" to wordCount.toString(),
                    "real_time_factor" to String.format("%.3f", realTimeFactor),
                    "framework" to framework.value,
                )
    }

    /** Transcription failed */
    data class TranscriptionFailed(
        val transcriptionId: String,
        val error: String,
    ) : STTEvent() {
        override val type: String = "stt_transcription_failed"
        override val properties: Map<String, String>
            get() =
                mapOf(
                    "transcription_id" to transcriptionId,
                    "error" to error,
                )
    }

    // MARK: - Detection (Analytics Only)

    /**
     * Language detected during transcription.
     * This event is analytics-only.
     * @param language Detected language code
     * @param confidence Confidence score (0.0 to 1.0)
     */
    data class LanguageDetected(
        val language: String,
        val confidence: Float,
    ) : STTEvent() {
        override val type: String = "stt_language_detected"
        override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
        override val properties: Map<String, String>
            get() =
                mapOf(
                    "language" to language,
                    "confidence" to String.format("%.3f", confidence),
                )
    }
}
