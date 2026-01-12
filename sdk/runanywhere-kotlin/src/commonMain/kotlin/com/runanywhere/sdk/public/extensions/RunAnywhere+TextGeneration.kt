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
import com.runanywhere.sdk.public.extensions.LLM.LLMGenerationOptions
import com.runanywhere.sdk.public.extensions.LLM.LLMGenerationResult
import com.runanywhere.sdk.public.extensions.LLM.LLMStreamingResult
import kotlinx.coroutines.flow.Flow

// MARK: - Text Generation

/**
 * Simple text generation with automatic event publishing.
 *
 * @param prompt The text prompt
 * @return Generated response (text only)
 */
expect suspend fun RunAnywhere.chat(prompt: String): String

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
    options: LLMGenerationOptions? = null,
): LLMGenerationResult

/**
 * Streaming text generation.
 *
 * Returns a Flow of tokens for real-time display.
 *
 * Example usage:
 * ```kotlin
 * RunAnywhere.generateStream("Tell me a story")
 *     .collect { token -> print(token) }
 * ```
 *
 * @param prompt The text prompt
 * @param options Generation options (optional)
 * @return Flow of tokens as they are generated
 */
expect fun RunAnywhere.generateStream(
    prompt: String,
    options: LLMGenerationOptions? = null,
): Flow<String>

/**
 * Streaming text generation with metrics.
 *
 * Returns both a token stream for real-time display and a deferred result
 * that resolves to complete metrics.
 *
 * Example usage:
 * ```kotlin
 * val result = RunAnywhere.generateStreamWithMetrics("Tell me a story")
 *
 * // Display tokens in real-time
 * result.stream.collect { token -> print(token) }
 *
 * // Get complete analytics after streaming finishes
 * val metrics = result.result.await()
 * println("Speed: ${metrics.tokensPerSecond} tok/s")
 * ```
 *
 * @param prompt The text prompt
 * @param options Generation options (optional)
 * @return LLMStreamingResult containing both the token stream and final metrics deferred
 */
expect suspend fun RunAnywhere.generateStreamWithMetrics(
    prompt: String,
    options: LLMGenerationOptions? = null,
): LLMStreamingResult

// MARK: - Generation Control

/**
 * Cancel any ongoing text generation.
 *
 * This will interrupt the current generation and stop producing tokens.
 * Safe to call even if no generation is in progress.
 */
expect fun RunAnywhere.cancelGeneration()
