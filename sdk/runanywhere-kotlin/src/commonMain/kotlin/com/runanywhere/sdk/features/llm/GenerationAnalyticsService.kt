package com.runanywhere.sdk.features.llm

import com.runanywhere.sdk.events.EventPublisher
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.currentTimeMillis
import com.runanywhere.sdk.models.enums.InferenceFramework
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

/**
 * LLM generation analytics service for tracking generation operations.
 * Mirrors iOS GenerationAnalyticsService exactly.
 *
 * Tracks:
 * - Non-streaming generations (single operation)
 * - Streaming generations (token-by-token with TTFT)
 * - Metrics calculation and aggregation
 *
 * NOTE: Token estimation uses ~4 chars/token approximation (not exact tokenizer count).
 * For precise token counts, use the model's actual tokenizer.
 */
class GenerationAnalyticsService {

    private val logger = SDKLogger("GenerationAnalytics")

    // Active generations
    private val activeGenerations = mutableMapOf<String, GenerationTracker>()

    // Metrics - separated by mode
    private var totalGenerations = 0
    private var streamingGenerations = 0
    private var nonStreamingGenerations = 0
    private var totalTimeToFirstToken = 0.0  // Only for streaming with TTFT recorded
    private var streamingTTFTCount = 0       // Only count TTFT for streaming generations that recorded it
    private var totalTokensPerSecond = 0.0
    private var totalInputTokens = 0
    private var totalOutputTokens = 0
    private val startTime = currentTimeMillis()
    private var lastEventTime: Long? = null

    // MARK: - Types

    private data class GenerationTracker(
        val startTime: Long,
        val modelId: String,
        val isStreaming: Boolean,
        val framework: InferenceFramework,
        var firstTokenTime: Long? = null
    )

    // MARK: - Generation Tracking

    /**
     * Start tracking a non-streaming generation.
     * @param modelId The model being used
     * @param framework The inference framework being used
     * @return A unique generation ID for tracking
     */
    @OptIn(ExperimentalUuidApi::class)
    fun startGeneration(
        modelId: String,
        framework: InferenceFramework = InferenceFramework.LLAMA_CPP
    ): String {
        val id = Uuid.random().toString()

        synchronized(activeGenerations) {
            activeGenerations[id] = GenerationTracker(
                startTime = currentTimeMillis(),
                modelId = modelId,
                isStreaming = false,
                framework = framework
            )
        }

        EventPublisher.track(
            LLMEvent.GenerationStarted(
                generationId = id,
                modelId = modelId,
                prompt = null,  // Privacy: don't log prompts by default
                isStreaming = false,
                framework = framework
            )
        )

        logger.debug("Non-streaming generation started: $id")
        return id
    }

    /**
     * Start tracking a streaming generation.
     * @param modelId The model being used
     * @param framework The inference framework being used
     * @return A unique generation ID for tracking
     */
    @OptIn(ExperimentalUuidApi::class)
    fun startStreamingGeneration(
        modelId: String,
        framework: InferenceFramework = InferenceFramework.LLAMA_CPP
    ): String {
        val id = Uuid.random().toString()

        synchronized(activeGenerations) {
            activeGenerations[id] = GenerationTracker(
                startTime = currentTimeMillis(),
                modelId = modelId,
                isStreaming = true,
                framework = framework
            )
        }

        EventPublisher.track(
            LLMEvent.GenerationStarted(
                generationId = id,
                modelId = modelId,
                prompt = null,  // Privacy: don't log prompts by default
                isStreaming = true,
                framework = framework
            )
        )

        logger.debug("Streaming generation started: $id")
        return id
    }

    /**
     * Track first token (for streaming generations).
     * Only applicable for streaming generations.
     * @param generationId The generation ID from startStreamingGeneration
     */
    fun trackFirstToken(generationId: String) {
        val tracker = synchronized(activeGenerations) {
            activeGenerations[generationId]
        } ?: return

        // Only track for streaming generations
        if (!tracker.isStreaming) {
            logger.warn("trackFirstToken called on non-streaming generation: $generationId")
            return
        }

        // Only track once
        if (tracker.firstTokenTime != null) {
            return
        }

        val now = currentTimeMillis()
        synchronized(activeGenerations) {
            activeGenerations[generationId] = tracker.copy(firstTokenTime = now)
        }

        val latencyMs = (now - tracker.startTime).toDouble()

        EventPublisher.track(
            LLMEvent.FirstToken(
                generationId = generationId,
                latencyMs = latencyMs
            )
        )

        logger.debug("First token: $generationId, latency: ${String.format("%.1f", latencyMs)}ms")
    }

    /**
     * Track streaming update (analytics only, for streaming generations).
     * @param generationId The generation ID from startStreamingGeneration
     * @param tokensGenerated Number of tokens generated so far
     */
    fun trackStreamingUpdate(generationId: String, tokensGenerated: Int) {
        val tracker = synchronized(activeGenerations) {
            activeGenerations[generationId]
        } ?: return

        // Only track for streaming generations
        if (!tracker.isStreaming) {
            return
        }

        EventPublisher.track(
            LLMEvent.StreamingUpdate(
                generationId = generationId,
                tokensGenerated = tokensGenerated
            )
        )
    }

    /**
     * Complete a generation.
     * Works for both streaming and non-streaming generations.
     * @param generationId The generation ID from startGeneration or startStreamingGeneration
     * @param inputTokens Number of input (prompt) tokens
     * @param outputTokens Number of output (completion) tokens
     * @param modelId The model that was used
     */
    fun completeGeneration(
        generationId: String,
        inputTokens: Int,
        outputTokens: Int,
        modelId: String
    ) {
        val tracker = synchronized(activeGenerations) {
            activeGenerations.remove(generationId)
        } ?: return

        val endTime = currentTimeMillis()
        val totalTimeMs = (endTime - tracker.startTime).toDouble()
        val totalTimeSeconds = totalTimeMs / 1000.0

        // Calculate tokens per second
        val tokensPerSecond = if (totalTimeSeconds > 0) {
            outputTokens.toDouble() / totalTimeSeconds
        } else {
            0.0
        }

        // Calculate TTFT for streaming only
        val timeToFirstTokenMs: Double? = if (tracker.isStreaming && tracker.firstTokenTime != null) {
            (tracker.firstTokenTime!! - tracker.startTime).toDouble()
        } else {
            null
        }

        // Update metrics
        synchronized(this) {
            totalGenerations++
            if (tracker.isStreaming) {
                streamingGenerations++
                // Only count TTFT if it was actually recorded
                if (timeToFirstTokenMs != null) {
                    totalTimeToFirstToken += timeToFirstTokenMs
                    streamingTTFTCount++
                }
            } else {
                nonStreamingGenerations++
            }
            totalTokensPerSecond += tokensPerSecond
            totalInputTokens += inputTokens
            totalOutputTokens += outputTokens
            lastEventTime = endTime
        }

        EventPublisher.track(
            LLMEvent.GenerationCompleted(
                generationId = generationId,
                modelId = modelId,
                inputTokens = inputTokens,
                outputTokens = outputTokens,
                durationMs = totalTimeMs,
                tokensPerSecond = tokensPerSecond,
                isStreaming = tracker.isStreaming,
                timeToFirstTokenMs = timeToFirstTokenMs,
                framework = tracker.framework
            )
        )

        logger.debug(
            "Generation completed: $generationId, " +
            "in: $inputTokens, out: $outputTokens, " +
            "time: ${String.format("%.1f", totalTimeMs)}ms, " +
            "speed: ${String.format("%.2f", tokensPerSecond)} tok/s"
        )
    }

    /**
     * Track generation failure.
     * @param generationId The generation ID
     * @param error The error that occurred
     */
    fun trackGenerationFailed(generationId: String, error: Throwable) {
        synchronized(activeGenerations) {
            activeGenerations.remove(generationId)
        }
        lastEventTime = currentTimeMillis()

        EventPublisher.track(
            LLMEvent.GenerationFailed(
                generationId = generationId,
                error = error.message ?: "Unknown error"
            )
        )

        logger.error("Generation failed: $generationId, error: ${error.message}")
    }

    /**
     * Track generation failure with error message.
     * @param generationId The generation ID
     * @param errorMessage The error message
     */
    fun trackGenerationFailed(generationId: String, errorMessage: String) {
        synchronized(activeGenerations) {
            activeGenerations.remove(generationId)
        }
        lastEventTime = currentTimeMillis()

        EventPublisher.track(
            LLMEvent.GenerationFailed(
                generationId = generationId,
                error = errorMessage
            )
        )

        logger.error("Generation failed: $generationId, error: $errorMessage")
    }

    /**
     * Track an error during operations.
     * @param error The error that occurred
     * @param operation Description of the operation that failed
     */
    fun trackError(error: Throwable, operation: String) {
        lastEventTime = currentTimeMillis()
        logger.error("LLM error during $operation: ${error.message}")
        // Error events can be added via a generic ErrorEvent if needed
    }

    // MARK: - Metrics

    /**
     * Get current generation metrics.
     */
    fun getMetrics(): GenerationMetrics {
        return synchronized(this) {
            GenerationMetrics(
                totalEvents = totalGenerations,
                startTime = startTime,
                lastEventTime = lastEventTime,
                totalGenerations = totalGenerations,
                streamingGenerations = streamingGenerations,
                nonStreamingGenerations = nonStreamingGenerations,
                averageTimeToFirstToken = if (streamingTTFTCount > 0) {
                    totalTimeToFirstToken / streamingTTFTCount
                } else {
                    0.0
                },
                averageTokensPerSecond = if (totalGenerations > 0) {
                    totalTokensPerSecond / totalGenerations
                } else {
                    0.0
                },
                totalInputTokens = totalInputTokens,
                totalOutputTokens = totalOutputTokens
            )
        }
    }
}

// MARK: - Generation Metrics

/**
 * Metrics for LLM generation operations.
 * Mirrors iOS GenerationMetrics struct.
 */
data class GenerationMetrics(
    /** Total number of generation events */
    val totalEvents: Int = 0,
    /** When tracking started (epoch millis) */
    val startTime: Long = currentTimeMillis(),
    /** When the last event occurred (epoch millis) */
    val lastEventTime: Long? = null,
    /** Total number of generations completed (streaming + non-streaming) */
    val totalGenerations: Int = 0,
    /** Number of streaming generations */
    val streamingGenerations: Int = 0,
    /** Number of non-streaming generations */
    val nonStreamingGenerations: Int = 0,
    /** Average time to first token in milliseconds (only for streaming generations with TTFT recorded) */
    val averageTimeToFirstToken: Double = 0.0,
    /** Average tokens per second across all generations */
    val averageTokensPerSecond: Double = 0.0,
    /** Total input tokens processed across all generations */
    val totalInputTokens: Int = 0,
    /** Total output tokens generated across all generations */
    val totalOutputTokens: Int = 0
)
