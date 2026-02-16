/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for VLM (Vision Language Model) operations.
 * Calls C++ directly via CppBridge.VLM for all operations.
 * Events are emitted by C++ layer via CppEventBridge.
 *
 * Mirrors Swift RunAnywhere+VisionLanguage.swift exactly.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.VLM.VLMGenerationOptions
import com.runanywhere.sdk.public.extensions.VLM.VLMImage
import com.runanywhere.sdk.public.extensions.VLM.VLMResult
import com.runanywhere.sdk.public.extensions.VLM.VLMStreamingResult
import kotlinx.coroutines.flow.Flow

// MARK: - Simple API

/**
 * Simple image description with default prompt.
 *
 * @param image The image to describe
 * @param prompt The text prompt (defaults to "What's in this image?")
 * @return Generated description text
 */
expect suspend fun RunAnywhere.describeImage(
    image: VLMImage,
    prompt: String = "What's in this image?",
): String

// MARK: - Full API

/**
 * Process an image with a text prompt and return full result with metrics.
 *
 * @param image The image to process
 * @param prompt The text prompt
 * @param options Generation options (optional)
 * @return VLMResult with generated text and detailed metrics
 */
expect suspend fun RunAnywhere.processImage(
    image: VLMImage,
    prompt: String,
    options: VLMGenerationOptions? = null,
): VLMResult

/**
 * Process an image with streaming output.
 *
 * Returns a Flow of tokens for real-time display.
 *
 * Example usage:
 * ```kotlin
 * RunAnywhere.processImageStream(image, "Describe this")
 *     .collect { token -> print(token) }
 * ```
 *
 * @param image The image to process
 * @param prompt The text prompt
 * @param options Generation options (optional)
 * @return Flow of tokens as they are generated
 */
expect fun RunAnywhere.processImageStream(
    image: VLMImage,
    prompt: String,
    options: VLMGenerationOptions? = null,
): Flow<String>

/**
 * Process an image with streaming output and metrics.
 *
 * Returns both a token stream for real-time display and a deferred result
 * that resolves to complete metrics.
 *
 * Example usage:
 * ```kotlin
 * val result = RunAnywhere.processImageStreamWithMetrics(image, "Describe this")
 *
 * // Display tokens in real-time
 * result.stream.collect { token -> print(token) }
 *
 * // Get complete analytics after streaming finishes
 * val metrics = result.result.await()
 * println("Speed: ${metrics.tokensPerSecond} tok/s")
 * ```
 *
 * @param image The image to process
 * @param prompt The text prompt
 * @param options Generation options (optional)
 * @return VLMStreamingResult containing both the token stream and final metrics deferred
 */
expect suspend fun RunAnywhere.processImageStreamWithMetrics(
    image: VLMImage,
    prompt: String,
    options: VLMGenerationOptions? = null,
): VLMStreamingResult

// MARK: - Model Management

/**
 * Load a VLM model by ID using the global model registry.
 *
 * The C++ layer resolves the model folder, finds the main .gguf and mmproj .gguf
 * files automatically. This is the preferred API for loading VLM models.
 *
 * @param modelId Model identifier (must be registered in the global model registry)
 */
expect suspend fun RunAnywhere.loadVLMModel(modelId: String)

/**
 * Load a VLM model with explicit paths.
 *
 * @param modelPath Path to the main model file (LLM weights)
 * @param mmprojPath Path to the vision projector file (optional, required for llama.cpp)
 * @param modelId Model identifier for telemetry
 * @param modelName Human-readable model name
 */
expect suspend fun RunAnywhere.loadVLMModel(
    modelPath: String,
    mmprojPath: String?,
    modelId: String,
    modelName: String,
)

/**
 * Unload the current VLM model.
 */
expect suspend fun RunAnywhere.unloadVLMModel()

/**
 * Check if a VLM model is currently loaded.
 */
expect val RunAnywhere.isVLMModelLoaded: Boolean

// MARK: - Generation Control

/**
 * Cancel any ongoing VLM generation.
 *
 * This will interrupt the current generation and stop producing tokens.
 * Safe to call even if no generation is in progress.
 */
expect fun RunAnywhere.cancelVLMGeneration()
