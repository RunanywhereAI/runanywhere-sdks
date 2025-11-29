package com.runanywhere.sdk.public.models

import com.runanywhere.sdk.models.ExecutionTarget
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.services.analytics.PerformanceMetrics
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.flow.Flow

/**
 * Hardware acceleration type used during generation.
 * Matches iOS HardwareAcceleration enum.
 */
enum class HardwareAcceleration(val value: String) {
    CPU("cpu"),
    GPU("gpu"),
    NEURAL_ENGINE("neural_engine"),
    ANE("ane"),  // Apple Neural Engine alias
    NPU("npu"),  // Android Neural Processing Unit
    HYBRID("hybrid");

    companion object {
        fun fromValue(value: String): HardwareAcceleration {
            return values().find { it.value == value } ?: CPU
        }
    }
}

/**
 * Structured output validation result.
 * Matches iOS StructuredOutputValidation.
 */
data class StructuredOutputValidation(
    val isValid: Boolean,
    val errors: List<String> = emptyList(),
    val warnings: List<String> = emptyList()
)

/**
 * Result of a text generation request.
 * Matches iOS GenerationResult struct exactly.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Models/GenerationResult.swift
 */
data class GenerationResult(
    /** Generated text (with thinking content removed if extracted) */
    val text: String,

    /** Thinking/reasoning content extracted from the response */
    val thinkingContent: String? = null,

    /** Number of tokens used */
    val tokensUsed: Int,

    /** Model used for generation */
    val modelUsed: String,

    /** Latency in milliseconds */
    val latencyMs: Double,

    /** Execution target (device/cloud/hybrid) */
    val executionTarget: ExecutionTarget,

    /** Amount saved by using on-device execution */
    val savedAmount: Double = 0.0,

    /** Framework used for generation (if on-device) */
    val framework: LLMFramework? = null,

    /** Hardware acceleration used */
    val hardwareUsed: HardwareAcceleration = HardwareAcceleration.CPU,

    /** Memory used during generation (in bytes) */
    val memoryUsed: Long = 0,

    /** Detailed performance metrics */
    val performanceMetrics: PerformanceMetrics,

    /** Structured output validation result (if structured output was requested) */
    val structuredOutputValidation: StructuredOutputValidation? = null,

    /** Number of tokens used for thinking/reasoning (if model supports thinking mode) */
    val thinkingTokens: Int? = null,

    /** Number of tokens in the actual response content (excluding thinking) */
    val responseTokens: Int? = null
) {
    /**
     * Check if generation was successful
     */
    val isSuccessful: Boolean
        get() = text.isNotEmpty()

    /**
     * Check if thinking mode was used
     */
    val usedThinkingMode: Boolean
        get() = thinkingContent != null || thinkingTokens != null

    /**
     * Get effective tokens per second
     */
    val effectiveTokensPerSecond: Double
        get() = performanceMetrics.tokensPerSecond.takeIf { it > 0 }
            ?: if (latencyMs > 0) tokensUsed.toDouble() / (latencyMs / 1000.0) else 0.0

    companion object {
        /**
         * Create a simple result with minimal required fields.
         * Used for quick testing or simple use cases.
         */
        fun simple(
            text: String,
            tokensUsed: Int = text.length / 4,
            modelUsed: String = "unknown",
            latencyMs: Double = 0.0
        ): GenerationResult {
            return GenerationResult(
                text = text,
                tokensUsed = tokensUsed,
                modelUsed = modelUsed,
                latencyMs = latencyMs,
                executionTarget = ExecutionTarget.ON_DEVICE,
                performanceMetrics = PerformanceMetrics(
                    tokensPerSecond = if (latencyMs > 0) tokensUsed / (latencyMs / 1000.0) else 0.0
                )
            )
        }
    }
}

/**
 * Container for streaming generation with metrics.
 * Provides both the token stream and a deferred result that resolves to final metrics.
 * Matches iOS StreamingResult struct.
 *
 * Example usage:
 * ```kotlin
 * val result = RunAnywhere.generateStream(prompt)
 *
 * // Display tokens in real-time
 * result.stream.collect { token ->
 *     print(token)
 * }
 *
 * // Get complete analytics after streaming finishes
 * val metrics = result.result.await()
 * println("Speed: ${metrics.performanceMetrics.tokensPerSecond} tok/s")
 * println("Tokens: ${metrics.tokensUsed}")
 * println("Time: ${metrics.latencyMs}ms")
 * ```
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Models/GenerationResult.swift
 */
data class StreamingResult(
    /** Stream of tokens as they are generated */
    val stream: Flow<String>,

    /** Deferred that completes with final generation result including metrics.
     *  Resolves after streaming is complete.
     */
    val result: Deferred<GenerationResult>
) {
    /**
     * Collect all tokens into a single string.
     * This suspends until streaming is complete.
     */
    suspend fun collectText(): String {
        val builder = StringBuilder()
        stream.collect { token ->
            builder.append(token)
        }
        return builder.toString()
    }
}
