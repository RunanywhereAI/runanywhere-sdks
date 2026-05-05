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

import ai.runanywhere.proto.v1.SDKEvent
import ai.runanywhere.proto.v1.VLMGenerationOptions
import ai.runanywhere.proto.v1.VLMImage
import ai.runanywhere.proto.v1.VLMResult
import com.runanywhere.sdk.public.RunAnywhere
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

/**
 * Ask a specific question about an image.
 *
 * Per canonical §7: `askAboutImage(question, image) → String`.
 *
 * @param question The question to ask about the image
 * @param image The image to analyze
 * @return Answer text
 */
expect suspend fun RunAnywhere.askAboutImage(
    question: String,
    image: VLMImage,
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
 * Returns generated proto events emitted by the C++ VLM stream ABI.
 *
 * Example usage:
 * ```kotlin
 * RunAnywhere.processImageStream(image, "Describe this")
 *     .collect { event -> print(event.generation?.token.orEmpty()) }
 * ```
 *
 * @param image The image to process
 * @param prompt The text prompt
 * @param options Generation options (optional)
 * @return Flow of generated SDK events as they are emitted
 */
expect fun RunAnywhere.processImageStream(
    image: VLMImage,
    prompt: String,
    options: VLMGenerationOptions? = null,
): Flow<SDKEvent>

// MARK: - Model Management

/**
 * Load a VLM model by ID using the generated model lifecycle.
 *
 * The native lifecycle returns concrete primary and vision-projector artifacts
 * in `ModelLoadResult.resolved_artifacts`; Kotlin consumes those generated
 * role-tagged artifacts directly.
 *
 * @param modelId Model identifier (must be registered in the global model registry)
 */
expect suspend fun RunAnywhere.loadVLMModel(modelId: String)

/**
 * Unload the current VLM model.
 */
expect suspend fun RunAnywhere.unloadVLMModel()

/**
 * Check if a VLM model is currently loaded.
 */
expect val RunAnywhere.isVLMModelLoaded: Boolean

/**
 * Get the currently loaded VLM model ID.
 *
 * This is a synchronous property that returns the ID of the currently loaded VLM model,
 * or null if no model is loaded. Matches iOS pattern and other component properties
 * (currentLLMModelId, currentSTTModelId, currentTTSVoiceId).
 */
expect val RunAnywhere.currentVLMModelId: String?

// MARK: - Generation Control

/**
 * Cancel any ongoing VLM generation.
 *
 * This will interrupt the current generation and stop producing tokens.
 * Safe to call even if no generation is in progress.
 */
expect fun RunAnywhere.cancelVLMGeneration()
