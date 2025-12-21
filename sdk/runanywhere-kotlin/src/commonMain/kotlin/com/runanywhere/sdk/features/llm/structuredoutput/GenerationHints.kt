package com.runanywhere.sdk.features.llm.structuredoutput

import com.runanywhere.sdk.models.Generatable

/**
 * Hints for customizing structured output generation
 * Matches iOS GenerationHints
 */
data class GenerationHints(
    /** Preferred temperature for this type */
    val temperature: Float? = null,
    /** Maximum tokens for this type */
    val maxTokens: Int? = null,
    /** Custom system role for this type */
    val systemRole: String? = null,
) {
    companion object {
        /**
         * Default hints for JSON objects
         */
        val DEFAULT = GenerationHints()

        /**
         * Hints optimized for code generation
         */
        val CODE =
            GenerationHints(
                temperature = 0.2f,
                maxTokens = 2000,
                systemRole = "You are a code generator that outputs valid code in JSON format.",
            )

        /**
         * Hints optimized for analysis/factual content
         */
        val ANALYTICAL =
            GenerationHints(
                temperature = 0.3f,
                maxTokens = 1500,
                systemRole = "You are an analytical assistant that provides structured analysis in JSON format.",
            )

        /**
         * Hints optimized for creative content
         */
        val CREATIVE =
            GenerationHints(
                temperature = 0.8f,
                maxTokens = 2500,
                systemRole = "You are a creative assistant that generates structured creative content in JSON format.",
            )

        /**
         * Hints optimized for short responses
         */
        val CONCISE =
            GenerationHints(
                temperature = 0.5f,
                maxTokens = 500,
            )
    }
}

/**
 * Extension property to provide type-specific generation hints
 * Default implementation returns null (use default hints)
 *
 * Override this in your Generatable implementation to customize generation:
 * ```kotlin
 * data class MyType(...) : Generatable {
 *     companion object {
 *         val hints = GenerationHints(temperature = 0.5f, maxTokens = 1000)
 *     }
 * }
 * ```
 */
val Generatable.generationHints: GenerationHints?
    get() = null
