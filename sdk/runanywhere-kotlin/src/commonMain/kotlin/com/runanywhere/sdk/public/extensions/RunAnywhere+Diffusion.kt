/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for diffusion image generation operations.
 * Calls C++ directly via CppBridge.Diffusion for all operations.
 *
 * Mirrors Swift RunAnywhere+Diffusion.swift exactly.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionConfiguration
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionGenerationOptions
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionInfo
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionProgress
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionResult
import kotlinx.coroutines.flow.Flow

// MARK: - Image Generation

/**
 * Generate an image from a text prompt.
 *
 * @param prompt The text prompt describing the desired image.
 * @param options Generation options (resolution, steps, guidance, etc.).
 * @return DiffusionResult containing the generated RGBA image data and metadata.
 */
expect suspend fun RunAnywhere.generateImage(
    prompt: String,
    options: DiffusionGenerationOptions? = null,
): DiffusionResult

/**
 * Generate an image with progress streaming.
 *
 * Returns a Flow of DiffusionProgress updates during generation.
 * The final progress update contains the result image data.
 *
 * Example usage:
 * ```kotlin
 * RunAnywhere.generateImageStream("A sunset over mountains")
 *     .collect { progress ->
 *         println("Step ${progress.currentStep}/${progress.totalSteps}")
 *     }
 * ```
 *
 * @param prompt The text prompt.
 * @param options Generation options.
 * @return Flow of DiffusionProgress updates.
 */
expect fun RunAnywhere.generateImageStream(
    prompt: String,
    options: DiffusionGenerationOptions? = null,
): Flow<DiffusionProgress>

// MARK: - Generation Control

/**
 * Cancel any ongoing image generation.
 * Safe to call even if no generation is in progress.
 */
expect fun RunAnywhere.cancelImageGeneration()

// MARK: - Model Management

/**
 * Load a diffusion model by ID.
 *
 * Resolves the model path, framework, and configuration from the model registry.
 * This is the recommended API — matches [RunAnywhere.loadLLMModel] pattern.
 *
 * @param modelId Model identifier (must be registered and downloaded).
 */
expect suspend fun RunAnywhere.loadDiffusionModel(modelId: String)

/**
 * Load a diffusion model for image generation with explicit path and configuration.
 *
 * Use [loadDiffusionModel(modelId)] for simpler usage when the model is registered.
 *
 * @param modelPath Path to the model file (.safetensors, .gguf, .ckpt, or CoreML directory).
 * @param modelId Model identifier for the registry.
 * @param modelName Optional display name.
 * @param configuration Optional diffusion configuration.
 */
expect suspend fun RunAnywhere.loadDiffusionModel(
    modelPath: String,
    modelId: String,
    modelName: String? = null,
    configuration: DiffusionConfiguration? = null,
)

/**
 * Unload the currently loaded diffusion model and free resources.
 */
expect suspend fun RunAnywhere.unloadDiffusionModel()

/**
 * Check if a diffusion model is currently loaded and ready.
 */
expect val RunAnywhere.isDiffusionModelLoaded: Boolean

// MARK: - Info

/**
 * Get information about the loaded diffusion service.
 *
 * @return DiffusionInfo with capabilities and current state.
 */
expect suspend fun RunAnywhere.getDiffusionInfo(): DiffusionInfo

/**
 * Get the capability flags for the loaded diffusion backend.
 *
 * @return Bitmask of DiffusionCapabilities flags.
 */
expect fun RunAnywhere.getDiffusionCapabilities(): Int
