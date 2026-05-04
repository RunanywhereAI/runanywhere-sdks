/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Extension helpers for proto-canonical LLM types.
 * Provides camelCase aliases and ergonomic factory functions over the
 * Wire-generated ai.runanywhere.proto.v1.{LLMGenerationOptions,
 * LLMGenerationResult, LLMConfiguration, ThinkingTagPattern} types.
 */

package com.runanywhere.sdk.foundation.protoext

import ai.runanywhere.proto.v1.LLMConfiguration
import ai.runanywhere.proto.v1.LLMGenerationOptions
import ai.runanywhere.proto.v1.LLMGenerationResult

// ============================================================================
// LLMGenerationOptions — camelCase ergonomics
// ============================================================================

/** Sentinel default options instance (all proto3 zero-defaults). */
val LLMGenerationOptionsDefault: LLMGenerationOptions = LLMGenerationOptions()

val LLMGenerationOptions.maxTokens: Int get() = max_tokens
val LLMGenerationOptions.topP: Float get() = top_p
val LLMGenerationOptions.topK: Int get() = top_k
val LLMGenerationOptions.streamingEnabled: Boolean get() = streaming_enabled
val LLMGenerationOptions.preferredFramework get() = preferred_framework
val LLMGenerationOptions.systemPrompt: String? get() = system_prompt
val LLMGenerationOptions.jsonSchema: String? get() = json_schema
val LLMGenerationOptions.thinkingPattern get() = thinking_pattern
val LLMGenerationOptions.executionTarget get() = execution_target
val LLMGenerationOptions.structuredOutput get() = structured_output
val LLMGenerationOptions.stopSequences: List<String> get() = stop_sequences

// ============================================================================
// LLMGenerationResult — camelCase ergonomics
// ============================================================================

val LLMGenerationResult.thinkingContent: String? get() = thinking_content
val LLMGenerationResult.inputTokens: Int get() = input_tokens
val LLMGenerationResult.tokensUsed: Int get() = tokens_generated
val LLMGenerationResult.modelUsed: String get() = model_used
val LLMGenerationResult.latencyMs: Double get() = generation_time_ms
val LLMGenerationResult.tokensPerSecond: Double get() = tokens_per_second
val LLMGenerationResult.timeToFirstTokenMs: Double? get() = ttft_ms
val LLMGenerationResult.thinkingTokens: Int get() = thinking_tokens
val LLMGenerationResult.responseTokens: Int get() = response_tokens
val LLMGenerationResult.finishReason: String get() = finish_reason
val LLMGenerationResult.jsonOutput: String? get() = json_output

// ============================================================================
// LLMConfiguration — validate + Builder ergonomics
// ============================================================================

/** Validate this LLMConfiguration. Throws [IllegalArgumentException] on failure. */
fun LLMConfiguration.validate() {
    require(context_length == 0 || context_length in 1..32768) {
        "Context length must be between 1 and 32768 (got $context_length)"
    }
    require(temperature == 0f || temperature in 0f..2f) {
        "Temperature must be between 0 and 2.0 (got $temperature)"
    }
    require(max_tokens == 0 || max_tokens in 1..(if (context_length > 0) context_length else Int.MAX_VALUE)) {
        "Max tokens must be between 1 and context length (got $max_tokens)"
    }
}

val LLMConfiguration.contextLength: Int get() = context_length
val LLMConfiguration.maxTokens: Int get() = max_tokens
val LLMConfiguration.systemPrompt: String? get() = system_prompt
val LLMConfiguration.streamingEnabled: Boolean get() = streaming
