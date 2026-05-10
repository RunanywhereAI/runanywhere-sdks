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
import com.runanywhere.sdk.public.types.RASDKEvent
import com.runanywhere.sdk.public.types.RAVLMGenerationOptions
import com.runanywhere.sdk.public.types.RAVLMImage
import com.runanywhere.sdk.public.types.RAVLMResult
import kotlinx.coroutines.flow.Flow

// MARK: - Inference

/**
 * Process an image and return full result with metrics.
 *
 * Mirrors Swift's `processImage(_:options:)` — the prompt is part of [options].
 *
 * @param image The image to process
 * @param options Generation options (prompt is set on options.prompt)
 * @return VLMResult with generated text and detailed metrics
 */
expect suspend fun RunAnywhere.processImage(
    image: RAVLMImage,
    options: RAVLMGenerationOptions = RAVLMGenerationOptions(),
): RAVLMResult

/**
 * Process an image with streaming output.
 *
 * Mirrors Swift's `processImageStream(_:options:)` — the prompt is part of [options].
 *
 * Example usage:
 * ```kotlin
 * RunAnywhere.processImageStream(image, VLMGenerationOptions(prompt = "Describe this"))
 *     .collect { event -> print(event.generation?.token.orEmpty()) }
 * ```
 *
 * @param image The image to process
 * @param options Generation options (prompt is set on options.prompt)
 * @return Flow of generated SDK events as they are emitted
 */
expect fun RunAnywhere.processImageStream(
    image: RAVLMImage,
    options: RAVLMGenerationOptions = RAVLMGenerationOptions(),
): Flow<RASDKEvent>

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

// MARK: - Generation Control

/**
 * Cancel any ongoing VLM generation.
 *
 * This will interrupt the current generation and stop producing tokens.
 * Safe to call even if no generation is in progress.
 */
expect fun RunAnywhere.cancelVLMGeneration()
