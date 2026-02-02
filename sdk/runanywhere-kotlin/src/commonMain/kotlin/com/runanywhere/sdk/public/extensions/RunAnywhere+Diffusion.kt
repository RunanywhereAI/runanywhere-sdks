/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for Diffusion image generation operations.
 * Calls C++ directly via CppBridge.Diffusion for all operations.
 * Events are emitted by C++ layer via CppEventBridge.
 *
 * Mirrors Swift RunAnywhere+Diffusion.swift exactly.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionConfiguration
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionGenerationOptions
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionProgress
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionResult
import kotlinx.coroutines.flow.Flow

// MARK: - Configuration

/**
 * Configure the diffusion component.
 *
 * @param config Diffusion configuration
 */
expect suspend fun RunAnywhere.configureDiffusion(config: DiffusionConfiguration)

// MARK: - Model Loading

/**
 * Load a diffusion model.
 *
 * @param modelPath Path to the model directory
 * @param modelId Unique identifier for the model
 * @param modelName Human-readable model name (optional)
 */
expect suspend fun RunAnywhere.loadDiffusionModel(
    modelPath: String,
    modelId: String,
    modelName: String? = null,
)

/**
 * Unload the currently loaded diffusion model.
 */
expect suspend fun RunAnywhere.unloadDiffusionModel()

/**
 * Check if a diffusion model is loaded.
 */
expect suspend fun RunAnywhere.isDiffusionModelLoaded(): Boolean

/**
 * Get the currently loaded diffusion model ID.
 *
 * This is a synchronous property that returns the ID of the currently loaded diffusion model,
 * or null if no model is loaded.
 */
expect val RunAnywhere.currentDiffusionModelId: String?

/**
 * Check if a diffusion model is loaded (non-suspend version for quick checks).
 *
 * This accesses cached state and doesn't require suspension.
 */
expect val RunAnywhere.isDiffusionModelLoadedSync: Boolean

// MARK: - Image Generation

/**
 * Generate an image from a text prompt.
 *
 * Simple API that uses default configuration.
 *
 * @param prompt Text description of the desired image
 * @return Generated image result
 */
expect suspend fun RunAnywhere.generateImage(prompt: String): DiffusionResult

/**
 * Generate an image with detailed options.
 *
 * @param options Generation options (prompt, dimensions, steps, etc.)
 * @return Generated image result
 */
expect suspend fun RunAnywhere.generateImageWithOptions(
    options: DiffusionGenerationOptions,
): DiffusionResult

/**
 * Generate an image with progress updates.
 *
 * @param options Generation options
 * @return Flow of progress updates, completing with the final result
 */
expect fun RunAnywhere.generateImageWithProgress(
    options: DiffusionGenerationOptions,
): Flow<DiffusionProgress>

/**
 * Cancel ongoing image generation.
 */
expect suspend fun RunAnywhere.cancelDiffusionGeneration()

// MARK: - Convenience Methods

/**
 * Generate an image using text-to-image mode.
 *
 * @param prompt Text description
 * @param negativePrompt Things to avoid (optional)
 * @param width Output width (default: model default)
 * @param height Output height (default: model default)
 * @param steps Number of denoising steps (default: model default)
 * @param seed Random seed (-1 for random)
 * @return Generated image result
 */
expect suspend fun RunAnywhere.textToImage(
    prompt: String,
    negativePrompt: String = "",
    width: Int? = null,
    height: Int? = null,
    steps: Int? = null,
    seed: Long = -1L,
): DiffusionResult

/**
 * Transform an image using image-to-image mode.
 *
 * @param prompt Text description of the transformation
 * @param inputImage Input image data (PNG/JPEG)
 * @param denoiseStrength Transformation strength (0.0-1.0)
 * @param negativePrompt Things to avoid (optional)
 * @param seed Random seed (-1 for random)
 * @return Transformed image result
 */
expect suspend fun RunAnywhere.imageToImage(
    prompt: String,
    inputImage: ByteArray,
    denoiseStrength: Float = 0.75f,
    negativePrompt: String = "",
    seed: Long = -1L,
): DiffusionResult

/**
 * Inpaint a region of an image.
 *
 * @param prompt Text description of what to paint
 * @param inputImage Input image data (PNG/JPEG)
 * @param maskImage Mask image data (grayscale PNG, white = paint)
 * @param negativePrompt Things to avoid (optional)
 * @param seed Random seed (-1 for random)
 * @return Inpainted image result
 */
expect suspend fun RunAnywhere.inpaint(
    prompt: String,
    inputImage: ByteArray,
    maskImage: ByteArray,
    negativePrompt: String = "",
    seed: Long = -1L,
): DiffusionResult
