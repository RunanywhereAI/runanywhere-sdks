package com.runanywhere.sdk.features.vad

import com.runanywhere.sdk.events.BaseSDKEvent
import com.runanywhere.sdk.events.EventCategory
import com.runanywhere.sdk.events.EventDestination
import com.runanywhere.sdk.models.enums.InferenceFramework

/**
 * All VAD (Voice Activity Detection) related events.
 * Mirrors iOS VADEvent enum exactly.
 *
 * Usage:
 * ```kotlin
 * EventPublisher.track(VADEvent.Initialized(...))
 * ```
 *
 * NOTE: iOS uses InferenceFrameworkType while KMP uses InferenceFramework.
 * This is a documented naming drift that will be resolved in a future iteration.
 */
sealed class VADEvent : BaseSDKEvent(EventCategory.VOICE) {
    // MARK: - Service Lifecycle

    /** VAD initialized (no model load for simple VAD, uses built-in algorithms) */
    data class Initialized(
        val framework: InferenceFramework = InferenceFramework.BUILT_IN,
    ) : VADEvent() {
        override val type: String = "vad_initialized"
        override val properties: Map<String, String>
            get() = mapOf("framework" to framework.value)
    }

    /** VAD initialization failed */
    data class InitializationFailed(
        val error: String,
        val framework: InferenceFramework = InferenceFramework.BUILT_IN,
    ) : VADEvent() {
        override val type: String = "vad_initialization_failed"
        override val properties: Map<String, String>
            get() =
                mapOf(
                    "error" to error,
                    "framework" to framework.value,
                )
    }

    /** VAD cleaned up */
    data object CleanedUp : VADEvent() {
        override val type: String = "vad_cleaned_up"
        override val properties: Map<String, String>
            get() = emptyMap()
    }

    // MARK: - Model Lifecycle (for model-based VAD like Silero VAD)

    /** Model loading started (for model-based VAD) */
    data class ModelLoadStarted(
        val modelId: String,
        val modelSizeBytes: Long = 0,
        val framework: InferenceFramework = InferenceFramework.UNKNOWN,
    ) : VADEvent() {
        override val type: String = "vad_model_load_started"
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

    /** Model loading completed */
    data class ModelLoadCompleted(
        val modelId: String,
        val durationMs: Double,
        val modelSizeBytes: Long = 0,
        val framework: InferenceFramework = InferenceFramework.UNKNOWN,
    ) : VADEvent() {
        override val type: String = "vad_model_load_completed"
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

    /** Model loading failed */
    data class ModelLoadFailed(
        val modelId: String,
        val error: String,
        val framework: InferenceFramework = InferenceFramework.UNKNOWN,
    ) : VADEvent() {
        override val type: String = "vad_model_load_failed"
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
    ) : VADEvent() {
        override val type: String = "vad_model_unloaded"
        override val properties: Map<String, String>
            get() = mapOf("model_id" to modelId)
    }

    // MARK: - Detection

    /** VAD started processing */
    data object Started : VADEvent() {
        override val type: String = "vad_started"
        override val properties: Map<String, String>
            get() = emptyMap()
    }

    /** VAD stopped processing */
    data object Stopped : VADEvent() {
        override val type: String = "vad_stopped"
        override val properties: Map<String, String>
            get() = emptyMap()
    }

    /**
     * Speech started (voice activity detected).
     * This event is analytics-only (too chatty for public API).
     */
    data object SpeechStarted : VADEvent() {
        override val type: String = "vad_speech_started"
        override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
        override val properties: Map<String, String>
            get() = emptyMap()
    }

    /**
     * Speech ended with duration.
     * This event is analytics-only (too chatty for public API).
     * @param durationMs Duration of the speech segment in milliseconds
     */
    data class SpeechEnded(
        val durationMs: Double,
    ) : VADEvent() {
        override val type: String = "vad_speech_ended"
        override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
        override val properties: Map<String, String>
            get() = mapOf("duration_ms" to String.format("%.1f", durationMs))
    }

    /** VAD processing paused */
    data object Paused : VADEvent() {
        override val type: String = "vad_paused"
        override val properties: Map<String, String>
            get() = emptyMap()
    }

    /** VAD processing resumed */
    data object Resumed : VADEvent() {
        override val type: String = "vad_resumed"
        override val properties: Map<String, String>
            get() = emptyMap()
    }
}

// MARK: - VAD Metrics

/**
 * VAD analytics metrics.
 * Mirrors iOS VADMetrics struct.
 */
data class VADMetrics(
    /** Total number of speech segments detected */
    val totalEvents: Int = 0,
    /** When tracking started (epoch millis) */
    val startTime: Long = System.currentTimeMillis(),
    /** When the last event occurred (epoch millis, null if no events yet) */
    val lastEventTime: Long? = null,
    /** Total number of speech segments */
    val totalSpeechSegments: Int = 0,
    /** Total duration of all speech segments in milliseconds */
    val totalSpeechDurationMs: Double = 0.0,
    /** Average duration of speech segments in milliseconds (-1 if N/A) */
    val averageSpeechDurationMs: Double = -1.0,
    /** The inference framework being used */
    val framework: InferenceFramework = InferenceFramework.BUILT_IN,
)
