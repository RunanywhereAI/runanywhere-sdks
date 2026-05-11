/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for text generation (LLM) operations.
 * Calls C++ directly via CppBridge.LLM for all operations.
 * Events are emitted by C++ layer via CppEventBridge.
 *
 * Mirrors Swift RunAnywhere+TextGeneration.swift exactly.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
import com.runanywhere.sdk.public.types.RALLMGenerationResult
import com.runanywhere.sdk.public.types.RALLMStreamEvent
import kotlinx.coroutines.flow.Flow

// MARK: - Text Generation

/**
 * Generate text with full metrics and analytics.
 *
 * @param prompt The text prompt
 * @param options Generation options (optional)
 * @return GenerationResult with full metrics including thinking tokens, timing, performance, etc.
 * @note Events are automatically dispatched via C++ layer
 */
expect suspend fun RunAnywhere.generate(
    prompt: String,
    options: RALLMGenerationOptions? = null,
): RALLMGenerationResult

/**
 * Streaming text generation.
 *
 * v2 close-out Phase G-2: returns `Flow<LLMStreamEvent>` sourced from the
 * Phase G-2 [`LLMStreamAdapter`]. One event per generated token plus a
 * terminal event (`isFinal == true`) carrying `finishReason` and any
 * `errorMessage`. The prior `Flow<String>` shape + `generateStreamWithMetrics`
 * variant were DELETED; callers derive metrics from the event sequence
 * (e.g. track `firstTokenTime` on the first non-empty `event.token_`).
 *
 * Example:
 * ```kotlin
 * RunAnywhere.generateStream("Tell me a story").collect { event ->
 *     if (event.isFinal) return@collect
 *     print(event.token_)
 * }
 * ```
 *
 * @param prompt The text prompt
 * @param options Generation options (optional)
 * @return Flow of proto-decoded events as they are generated.
 */
expect fun RunAnywhere.generateStream(
    prompt: String,
    options: RALLMGenerationOptions? = null,
): Flow<RALLMStreamEvent>

// MARK: - Generation Control

/**
 * Cancel any ongoing text generation.
 *
 * This will interrupt the current generation and stop producing tokens.
 * Safe to call even if no generation is in progress.
 */
expect fun RunAnywhere.cancelGeneration()
