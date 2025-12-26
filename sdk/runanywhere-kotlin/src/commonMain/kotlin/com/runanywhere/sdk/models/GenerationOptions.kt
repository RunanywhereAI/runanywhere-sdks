package com.runanywhere.sdk.models

import kotlinx.serialization.Serializable

/**
 * Options for text generation - exact match with iOS LLMGenerationOptions
 * Significantly enhanced from the simple GenerationOptions in generation package
 */
@Serializable
data class LLMGenerationOptions(
    /** Maximum number of tokens to generate */
    val maxTokens: Int = 100,
    /** Temperature for sampling (0.0 - 1.0) */
    val temperature: Float = 0.7f,
    /** Top-p sampling parameter */
    val topP: Float = 1.0f,
    /** Enable real-time tracking for cost dashboard */
    val enableRealTimeTracking: Boolean = true,
    /** Stop sequences */
    val stopSequences: List<String> = emptyList(),
    /** Enable streaming mode */
    val streamingEnabled: Boolean = false,
    /** Preferred execution target */
    val preferredExecutionTarget: ExecutionTarget? = null,
    /** Structured output configuration (optional) */
    val structuredOutput: StructuredOutputConfig? = null,
    /** System prompt to define AI behavior and formatting rules */
    val systemPrompt: String? = null,
    /** Top-K sampling parameter */
    val topK: Int? = null,
    /** Repetition penalty */
    val repetitionPenalty: Float? = null,
    /** Frequency penalty */
    val frequencyPenalty: Float? = null,
    /** Presence penalty */
    val presencePenalty: Float? = null,
    /** Random seed for reproducible generation */
    val seed: Int? = null,
    /** Context window size */
    val contextLength: Int? = null,
    /** Enable thinking mode for reasoning models */
    val enableThinking: Boolean = false,
    /** Maximum thinking tokens (for reasoning models) */
    val maxThinkingTokens: Int? = null,
) {
    /**
     * Validate generation options
     */
    fun validate() {
        require(maxTokens > 0) { "Max tokens must be positive" }
        require(temperature >= 0f && temperature <= 2f) { "Temperature must be between 0 and 2" }
        require(topP >= 0f && topP <= 1f) { "Top-p must be between 0 and 1" }
        topK?.let { require(it > 0) { "Top-K must be positive" } }
        repetitionPenalty?.let { require(it > 0f) { "Repetition penalty must be positive" } }
        frequencyPenalty?.let { require(it >= -2f && it <= 2f) { "Frequency penalty must be between -2 and 2" } }
        presencePenalty?.let { require(it >= -2f && it <= 2f) { "Presence penalty must be between -2 and 2" } }
        contextLength?.let { require(it > 0) { "Context length must be positive" } }
    }

    /**
     * Create a copy with different streaming setting
     */
    fun withStreaming(enabled: Boolean): LLMGenerationOptions = copy(streamingEnabled = enabled)

    /**
     * Create a copy with different system prompt
     */
    fun withSystemPrompt(prompt: String?): LLMGenerationOptions = copy(systemPrompt = prompt)

    /**
     * Create a copy with different execution target
     */
    fun withExecutionTarget(target: ExecutionTarget?): LLMGenerationOptions = copy(preferredExecutionTarget = target)

    /**
     * Create a copy with structured output configuration
     */
    fun withStructuredOutput(config: StructuredOutputConfig?): LLMGenerationOptions = copy(structuredOutput = config)

    companion object {
        /**
         * Default options for quick text generation
         */
        val DEFAULT = LLMGenerationOptions()

        /**
         * Options optimized for streaming
         */
        val STREAMING =
            LLMGenerationOptions(
                streamingEnabled = true,
                maxTokens = 1000,
            )

        /**
         * Options for creative writing (higher temperature)
         */
        val CREATIVE =
            LLMGenerationOptions(
                temperature = 1.0f,
                maxTokens = 2000,
                topP = 0.9f,
            )

        /**
         * Options for factual/analytical responses (lower temperature)
         */
        val FACTUAL =
            LLMGenerationOptions(
                temperature = 0.1f,
                maxTokens = 500,
                topP = 0.95f,
            )

        /**
         * Options for code generation
         */
        val CODE =
            LLMGenerationOptions(
                temperature = 0.2f,
                maxTokens = 1500,
                stopSequences = listOf("```", "\n\n\n"),
            )
    }
}

// Note: RunAnywhereGenerationOptions typealias was removed in iteration 17.
// All code should use LLMGenerationOptions directly.
