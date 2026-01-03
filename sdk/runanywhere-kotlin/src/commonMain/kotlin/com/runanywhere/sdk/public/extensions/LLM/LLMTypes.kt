/*
 * Copyright 2024 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public types for LLM text generation.
 * These are thin wrappers over C++ types in rac_llm_types.h
 *
 * Mirrors Swift LLMTypes.swift exactly.
 */

package com.runanywhere.sdk.public.extensions.LLM

import com.runanywhere.sdk.core.types.ComponentConfiguration
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.core.types.SDKComponent
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.flow.Flow
import kotlinx.serialization.Serializable

// MARK: - LLM Configuration

/**
 * Configuration for LLM component.
 * Mirrors Swift LLMConfiguration exactly.
 */
@Serializable
data class LLMConfiguration(
    override val modelId: String? = null,
    val contextLength: Int = 2048,
    val temperature: Double = 0.7,
    val maxTokens: Int = 100,
    val systemPrompt: String? = null,
    val streamingEnabled: Boolean = true,
    override val preferredFramework: InferenceFramework? = null
) : ComponentConfiguration {

    val componentType: SDKComponent get() = SDKComponent.LLM

    /**
     * Validate the configuration.
     * @throws IllegalArgumentException if validation fails
     */
    fun validate() {
        require(contextLength in 1..32768) {
            "Context length must be between 1 and 32768"
        }
        require(temperature in 0.0..2.0) {
            "Temperature must be between 0 and 2.0"
        }
        require(maxTokens in 1..contextLength) {
            "Max tokens must be between 1 and context length"
        }
    }

    /**
     * Builder pattern for LLMConfiguration.
     */
    class Builder(private var modelId: String? = null) {
        private var contextLength: Int = 2048
        private var temperature: Double = 0.7
        private var maxTokens: Int = 100
        private var systemPrompt: String? = null
        private var streamingEnabled: Boolean = true
        private var preferredFramework: InferenceFramework? = null

        fun contextLength(length: Int) = apply { contextLength = length }
        fun temperature(temp: Double) = apply { temperature = temp }
        fun maxTokens(tokens: Int) = apply { maxTokens = tokens }
        fun systemPrompt(prompt: String?) = apply { systemPrompt = prompt }
        fun streamingEnabled(enabled: Boolean) = apply { streamingEnabled = enabled }
        fun preferredFramework(framework: InferenceFramework?) = apply { preferredFramework = framework }

        fun build() = LLMConfiguration(
            modelId = modelId,
            contextLength = contextLength,
            temperature = temperature,
            maxTokens = maxTokens,
            systemPrompt = systemPrompt,
            streamingEnabled = streamingEnabled,
            preferredFramework = preferredFramework
        )
    }

    companion object {
        /**
         * Create configuration with builder pattern.
         */
        fun builder(modelId: String? = null) = Builder(modelId)
    }
}

// MARK: - LLM Generation Options

/**
 * Options for text generation.
 * Mirrors Swift LLMGenerationOptions exactly.
 */
@Serializable
data class LLMGenerationOptions(
    val maxTokens: Int = 100,
    val temperature: Float = 0.8f,
    val topP: Float = 1.0f,
    val stopSequences: List<String> = emptyList(),
    val streamingEnabled: Boolean = false,
    val preferredFramework: InferenceFramework? = null,
    val structuredOutput: StructuredOutputConfig? = null,
    val systemPrompt: String? = null
) {
    companion object {
        val DEFAULT = LLMGenerationOptions()
    }
}

// MARK: - LLM Generation Result

/**
 * Result of a text generation request.
 * Mirrors Swift LLMGenerationResult exactly.
 */
@Serializable
data class LLMGenerationResult(
    /** Generated text (with thinking content removed if extracted) */
    val text: String,

    /** Thinking/reasoning content extracted from the response */
    val thinkingContent: String? = null,

    /** Number of input/prompt tokens (from tokenizer) */
    val inputTokens: Int = 0,

    /** Number of tokens used (output tokens) */
    val tokensUsed: Int,

    /** Model used for generation */
    val modelUsed: String,

    /** Total latency in milliseconds */
    val latencyMs: Double,

    /** Framework used for generation */
    val framework: String? = null,

    /** Tokens generated per second */
    val tokensPerSecond: Double = 0.0,

    /** Time to first token in milliseconds (only for streaming) */
    val timeToFirstTokenMs: Double? = null,

    /** Structured output validation result */
    val structuredOutputValidation: StructuredOutputValidation? = null,

    /** Number of tokens used for thinking/reasoning */
    val thinkingTokens: Int? = null,

    /** Number of tokens in the actual response content */
    val responseTokens: Int = tokensUsed
)

// MARK: - LLM Streaming Result

/**
 * Container for streaming generation with metrics.
 * Mirrors Swift LLMStreamingResult.
 *
 * In Kotlin, we use Flow instead of AsyncThrowingStream.
 */
data class LLMStreamingResult(
    /** Flow of tokens as they are generated */
    val stream: Flow<String>,

    /** Deferred result that completes with final generation result including metrics */
    val result: Deferred<LLMGenerationResult>
)

// MARK: - Thinking Tag Pattern

/**
 * Pattern for extracting thinking/reasoning content from model output.
 * Mirrors Swift ThinkingTagPattern exactly.
 */
@Serializable
data class ThinkingTagPattern(
    val openingTag: String,
    val closingTag: String
) {
    companion object {
        /** Default pattern used by models like DeepSeek and Hermes */
        val DEFAULT = ThinkingTagPattern("<think>", "</think>")

        /** Alternative pattern with full "thinking" word */
        val THINKING = ThinkingTagPattern("<thinking>", "</thinking>")

        /** Custom pattern for models that use different tags */
        fun custom(opening: String, closing: String) = ThinkingTagPattern(opening, closing)
    }
}

// MARK: - Structured Output Types

/**
 * Interface for types that can be generated as structured output from LLMs.
 * Mirrors Swift Generatable protocol.
 */
interface Generatable {
    companion object {
        /** Default JSON schema */
        val DEFAULT_JSON_SCHEMA = """
            {
              "type": "object",
              "additionalProperties": false
            }
        """.trimIndent()
    }
}

/**
 * Structured output configuration.
 * Note: In Kotlin, we use KClass instead of Type.
 */
@Serializable
data class StructuredOutputConfig(
    /** The type name to generate */
    val typeName: String,

    /** Whether to include schema in prompt */
    val includeSchemaInPrompt: Boolean = true,

    /** JSON schema for the type */
    val jsonSchema: String = Generatable.DEFAULT_JSON_SCHEMA
)

/**
 * Hints for customizing structured output generation.
 * Mirrors Swift GenerationHints exactly.
 */
@Serializable
data class GenerationHints(
    val temperature: Float? = null,
    val maxTokens: Int? = null,
    val systemRole: String? = null
)

/**
 * Token emitted during streaming.
 * Mirrors Swift StreamToken exactly.
 */
@Serializable
data class StreamToken(
    val text: String,
    val timestamp: Long = System.currentTimeMillis(),
    val tokenIndex: Int
)

/**
 * Structured output validation result.
 * Mirrors Swift StructuredOutputValidation exactly.
 */
@Serializable
data class StructuredOutputValidation(
    val isValid: Boolean,
    val containsJSON: Boolean,
    val error: String?
)
