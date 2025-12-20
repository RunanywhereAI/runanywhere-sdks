package com.runanywhere.sdk.features.llm

import com.runanywhere.sdk.infrastructure.events.BaseSDKEvent
import com.runanywhere.sdk.infrastructure.events.EventCategory
import com.runanywhere.sdk.infrastructure.events.EventDestination
import com.runanywhere.sdk.models.enums.InferenceFramework

/**
 * All LLM (Large Language Model) related events.
 * Mirrors iOS LLMEvent enum exactly.
 *
 * Usage:
 * ```kotlin
 * EventPublisher.track(LLMEvent.GenerationCompleted(...))
 * ```
 *
 * NOTE: iOS uses InferenceFrameworkType while KMP uses InferenceFramework.
 * This is a documented naming drift that will be resolved in a future iteration.
 */
sealed class LLMEvent : BaseSDKEvent(EventCategory.LLM) {
    // MARK: - Model Lifecycle

    /** Model load started */
    data class ModelLoadStarted(
        val modelId: String,
        val modelSizeBytes: Long = 0,
        val framework: InferenceFramework = InferenceFramework.LLAMA_CPP,
    ) : LLMEvent() {
        override val type: String = "llm_model_load_started"
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
        val framework: InferenceFramework = InferenceFramework.LLAMA_CPP,
    ) : LLMEvent() {
        override val type: String = "llm_model_load_completed"
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
        val framework: InferenceFramework = InferenceFramework.LLAMA_CPP,
    ) : LLMEvent() {
        override val type: String = "llm_model_load_failed"
        override val properties: Map<String, String>
            get() =
                mapOf(
                    "model_id" to modelId,
                    "error" to error,
                    "framework" to framework.value,
                )
    }

    /** Model unload started */
    data class ModelUnloadStarted(
        val modelId: String,
    ) : LLMEvent() {
        override val type: String = "llm_model_unload_started"
        override val properties: Map<String, String>
            get() = mapOf("model_id" to modelId)
    }

    /** Model unloaded */
    data class ModelUnloaded(
        val modelId: String,
    ) : LLMEvent() {
        override val type: String = "llm_model_unloaded"
        override val properties: Map<String, String>
            get() = mapOf("model_id" to modelId)
    }

    // MARK: - Generation

    /**
     * Generation started event
     * @param generationId Unique identifier for this generation operation
     * @param modelId The model being used
     * @param prompt The prompt (optional, may be omitted for privacy)
     * @param isStreaming Whether this is a streaming generation
     * @param framework The inference framework being used
     */
    data class GenerationStarted(
        val generationId: String,
        val modelId: String,
        val prompt: String? = null,
        val isStreaming: Boolean = false,
        val framework: InferenceFramework = InferenceFramework.LLAMA_CPP,
    ) : LLMEvent() {
        override val type: String = "llm_generation_started"
        override val properties: Map<String, String>
            get() =
                buildMap {
                    put("generation_id", generationId)
                    put("model_id", modelId)
                    prompt?.let { put("prompt", it) }
                    put("is_streaming", isStreaming.toString())
                    put("framework", framework.value)
                }
    }

    /**
     * First token generated event (for streaming).
     * Used to calculate Time To First Token (TTFT).
     * @param generationId Unique identifier for this generation operation
     * @param latencyMs Time in milliseconds from generation start to first token
     */
    data class FirstToken(
        val generationId: String,
        val latencyMs: Double,
    ) : LLMEvent() {
        override val type: String = "llm_first_token"
        override val properties: Map<String, String>
            get() =
                mapOf(
                    "generation_id" to generationId,
                    "latency_ms" to String.format("%.1f", latencyMs),
                )
    }

    /**
     * Streaming update event.
     * This event is analytics-only (too chatty for public API).
     * @param generationId Unique identifier for this generation operation
     * @param tokensGenerated Number of tokens generated so far
     */
    data class StreamingUpdate(
        val generationId: String,
        val tokensGenerated: Int,
    ) : LLMEvent() {
        override val type: String = "llm_streaming_update"
        override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
        override val properties: Map<String, String>
            get() =
                mapOf(
                    "generation_id" to generationId,
                    "tokens_generated" to tokensGenerated.toString(),
                )
    }

    /**
     * Generation completed event
     * @param generationId Unique identifier for this generation operation
     * @param modelId The model that was used
     * @param inputTokens Number of input (prompt) tokens
     * @param outputTokens Number of output (completion) tokens
     * @param durationMs Total generation time in milliseconds
     * @param tokensPerSecond Generation speed (tokens per second)
     * @param isStreaming Whether this was a streaming generation
     * @param timeToFirstTokenMs Time to first token (for streaming, null otherwise)
     * @param framework The inference framework that was used
     */
    data class GenerationCompleted(
        val generationId: String,
        val modelId: String,
        val inputTokens: Int,
        val outputTokens: Int,
        val durationMs: Double,
        val tokensPerSecond: Double,
        val isStreaming: Boolean = false,
        val timeToFirstTokenMs: Double? = null,
        val framework: InferenceFramework = InferenceFramework.LLAMA_CPP,
    ) : LLMEvent() {
        override val type: String = "llm_generation_completed"
        override val properties: Map<String, String>
            get() =
                buildMap {
                    put("generation_id", generationId)
                    put("model_id", modelId)
                    put("input_tokens", inputTokens.toString())
                    put("output_tokens", outputTokens.toString())
                    put("duration_ms", String.format("%.1f", durationMs))
                    put("tokens_per_second", String.format("%.2f", tokensPerSecond))
                    put("is_streaming", isStreaming.toString())
                    timeToFirstTokenMs?.let { put("ttft_ms", String.format("%.1f", it)) }
                    put("framework", framework.value)
                }
    }

    /** Generation failed */
    data class GenerationFailed(
        val generationId: String,
        val error: String,
    ) : LLMEvent() {
        override val type: String = "llm_generation_failed"
        override val properties: Map<String, String>
            get() =
                mapOf(
                    "generation_id" to generationId,
                    "error" to error,
                )
    }
}
