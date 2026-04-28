/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * LLM public types. Proto-canonical types are typealiased here so all
 * existing imports from this package continue to compile unchanged.
 * Kotlin-specific wrappers (Builder, companion constants) remain here.
 *
 * Wave 3: LLMGenerationOptions and LLMGenerationResult deleted as
 * hand-rolled duplicates — replaced by typealiases to proto generated types.
 * Ergonomic camelCase extensions live in LLMProtoExt.kt.
 */

package com.runanywhere.sdk.public.extensions.LLM

import com.runanywhere.sdk.core.types.ComponentConfiguration
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.core.types.SDKComponent
import kotlinx.serialization.Serializable

// ---------------------------------------------------------------------------
// LLM Configuration  (Kotlin-specific: Builder pattern + validate())
// ---------------------------------------------------------------------------

@Serializable
data class LLMConfiguration(
    override val modelId: String? = null,
    val contextLength: Int = 2048,
    val temperature: Double = 0.7,
    val maxTokens: Int = 100,
    val systemPrompt: String? = null,
    val streamingEnabled: Boolean = true,
    override val preferredFramework: InferenceFramework? = null,
) : ComponentConfiguration {
    val componentType: SDKComponent get() = SDKComponent.LLM

    fun validate() {
        require(contextLength in 1..32768) { "Context length must be between 1 and 32768" }
        require(temperature in 0.0..2.0) { "Temperature must be between 0 and 2.0" }
        require(maxTokens in 1..contextLength) { "Max tokens must be between 1 and context length" }
    }

    class Builder(
        private var modelId: String? = null,
    ) {
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

        fun build() =
            LLMConfiguration(
                modelId = modelId,
                contextLength = contextLength,
                temperature = temperature,
                maxTokens = maxTokens,
                systemPrompt = systemPrompt,
                streamingEnabled = streamingEnabled,
                preferredFramework = preferredFramework,
            )
    }

    companion object {
        fun builder(modelId: String? = null) = Builder(modelId)
    }
}

// ---------------------------------------------------------------------------
// ThinkingTagPattern  (Kotlin-specific: companion constants + factory)
// ---------------------------------------------------------------------------

@Serializable
data class ThinkingTagPattern(
    val openingTag: String,
    val closingTag: String,
) {
    companion object {
        val DEFAULT = ThinkingTagPattern("<think>", "</think>")
        val THINKING = ThinkingTagPattern("<thinking>", "</thinking>")

        fun custom(opening: String, closing: String) = ThinkingTagPattern(opening, closing)
    }
}
