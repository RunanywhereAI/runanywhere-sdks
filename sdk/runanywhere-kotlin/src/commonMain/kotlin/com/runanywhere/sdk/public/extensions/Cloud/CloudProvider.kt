/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Interface for cloud AI providers (OpenAI-compatible APIs).
 * Mirrors Swift CloudProvider.swift exactly.
 */

package com.runanywhere.sdk.public.extensions.Cloud

import kotlinx.coroutines.flow.Flow

// MARK: - Cloud Provider Interface

/**
 * Interface for cloud AI inference providers.
 *
 * Implement this interface to add a custom cloud provider for hybrid routing.
 * The SDK ships with [OpenAICompatibleProvider][com.runanywhere.sdk.features.cloud.OpenAICompatibleProvider]
 * which works with any OpenAI-compatible API (OpenAI, Groq, Together, Ollama, etc.).
 *
 * Example:
 * ```kotlin
 * val provider = OpenAICompatibleProvider(
 *     apiKey = "sk-...",
 *     model = "gpt-4o-mini"
 * )
 * RunAnywhere.registerCloudProvider(provider)
 * ```
 *
 * Mirrors Swift CloudProvider protocol exactly.
 */
interface CloudProvider {

    /** Unique identifier for this provider */
    val providerId: String

    /** Human-readable display name */
    val displayName: String

    /**
     * Generate text (non-streaming).
     *
     * @param prompt The text prompt
     * @param options Cloud generation options
     * @return Cloud generation result
     */
    suspend fun generate(
        prompt: String,
        options: CloudGenerationOptions,
    ): CloudGenerationResult

    /**
     * Generate text with streaming.
     *
     * @param prompt The text prompt
     * @param options Cloud generation options
     * @return Flow of token strings as they are generated
     */
    fun generateStream(
        prompt: String,
        options: CloudGenerationOptions,
    ): Flow<String>

    /**
     * Check if the provider is available and configured.
     *
     * @return true if the provider is available
     */
    suspend fun isAvailable(): Boolean
}
