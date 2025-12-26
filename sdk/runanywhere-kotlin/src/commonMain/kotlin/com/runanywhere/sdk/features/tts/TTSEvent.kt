package com.runanywhere.sdk.features.tts

import com.runanywhere.sdk.infrastructure.events.BaseSDKEvent
import com.runanywhere.sdk.infrastructure.events.EventCategory
import com.runanywhere.sdk.infrastructure.events.EventDestination
import com.runanywhere.sdk.models.enums.InferenceFramework

/**
 * All TTS (Text-to-Speech) related events.
 * Mirrors iOS TTSEvent enum exactly.
 *
 * Usage:
 * ```kotlin
 * EventPublisher.track(TTSEvent.SynthesisCompleted(...))
 * ```
 *
 * NOTE: iOS uses InferenceFrameworkType while KMP uses InferenceFramework.
 * This is a documented naming drift that will be resolved in a future iteration.
 */
sealed class TTSEvent : BaseSDKEvent(EventCategory.TTS) {
    // MARK: - Model Lifecycle

    /** Model load started */
    data class ModelLoadStarted(
        val modelId: String,
        val modelSizeBytes: Long = 0,
        val framework: InferenceFramework = InferenceFramework.SYSTEM_TTS,
    ) : TTSEvent() {
        override val type: String = "tts_model_load_started"
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
        val framework: InferenceFramework = InferenceFramework.SYSTEM_TTS,
    ) : TTSEvent() {
        override val type: String = "tts_model_load_completed"
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
        val framework: InferenceFramework = InferenceFramework.SYSTEM_TTS,
    ) : TTSEvent() {
        override val type: String = "tts_model_load_failed"
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
    ) : TTSEvent() {
        override val type: String = "tts_model_unloaded"
        override val properties: Map<String, String>
            get() = mapOf("model_id" to modelId)
    }

    // MARK: - Synthesis

    /**
     * Synthesis started event
     * @param synthesisId Unique identifier for this synthesis operation
     * @param modelId The model being used
     * @param characterCount Number of characters in the text to synthesize
     * @param framework The inference framework being used
     */
    data class SynthesisStarted(
        val synthesisId: String,
        val modelId: String,
        val characterCount: Int,
        val framework: InferenceFramework = InferenceFramework.SYSTEM_TTS,
    ) : TTSEvent() {
        override val type: String = "tts_synthesis_started"
        override val properties: Map<String, String>
            get() =
                mapOf(
                    "synthesis_id" to synthesisId,
                    "model_id" to modelId,
                    "character_count" to characterCount.toString(),
                    "framework" to framework.value,
                )
    }

    /**
     * Streaming synthesis chunk generated.
     * This event is analytics-only (too chatty for public API).
     */
    data class SynthesisChunk(
        val synthesisId: String,
        val chunkSize: Int,
    ) : TTSEvent() {
        override val type: String = "tts_synthesis_chunk"
        override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
        override val properties: Map<String, String>
            get() =
                mapOf(
                    "synthesis_id" to synthesisId,
                    "chunk_size" to chunkSize.toString(),
                )
    }

    /**
     * Synthesis completed event
     * @param synthesisId Unique identifier for this synthesis operation
     * @param modelId The model that was used
     * @param characterCount Number of characters that were synthesized
     * @param audioDurationMs Duration of generated audio in milliseconds
     * @param audioSizeBytes Size of generated audio in bytes
     * @param processingDurationMs Time taken to synthesize (processing time)
     * @param charactersPerSecond Synthesis speed (characters processed per second)
     * @param framework The inference framework that was used
     */
    data class SynthesisCompleted(
        val synthesisId: String,
        val modelId: String,
        val characterCount: Int,
        val audioDurationMs: Double,
        val audioSizeBytes: Int,
        val processingDurationMs: Double,
        val charactersPerSecond: Double,
        val framework: InferenceFramework = InferenceFramework.SYSTEM_TTS,
    ) : TTSEvent() {
        override val type: String = "tts_synthesis_completed"
        override val properties: Map<String, String>
            get() =
                mapOf(
                    "synthesis_id" to synthesisId,
                    "model_id" to modelId,
                    "character_count" to characterCount.toString(),
                    "audio_duration_ms" to String.format("%.1f", audioDurationMs),
                    "audio_size_bytes" to audioSizeBytes.toString(),
                    "processing_duration_ms" to String.format("%.1f", processingDurationMs),
                    "chars_per_second" to String.format("%.2f", charactersPerSecond),
                    "framework" to framework.value,
                )
    }

    /** Synthesis failed */
    data class SynthesisFailed(
        val synthesisId: String,
        val error: String,
    ) : TTSEvent() {
        override val type: String = "tts_synthesis_failed"
        override val properties: Map<String, String>
            get() =
                mapOf(
                    "synthesis_id" to synthesisId,
                    "error" to error,
                )
    }
}
