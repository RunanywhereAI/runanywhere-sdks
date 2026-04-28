/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for diffusion (image generation) operations.
 * Routes through the C++ component layer for architectural consistency
 * with LLM/STT/TTS, when the platform exposes the diffusion ABI.
 *
 * Mirrors Swift sdk/runanywhere-swift/.../Diffusion/RunAnywhere+Diffusion.swift.
 *
 * NOTE: As of v3.x the Kotlin/Android `librunanywhere_jni` does not yet
 * export `rac_diffusion_*` thunks. The functions below are wired through
 * `expect`/`actual` so each platform can provide its own bridge — the
 * default JVM/Android actual currently throws
 * `SDKError.unsupportedOperation` until the C++ commons surface lands.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionCapabilities
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionConfiguration
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionGenerationOptions
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionProgress
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionResult
import kotlinx.coroutines.flow.Flow

// MARK: - Image Generation

/**
 * Generate an image from a text prompt.
 *
 * @param prompt Text description of the desired image.
 * @param options Generation options (optional, uses defaults if not provided).
 * @return DiffusionResult containing the generated image.
 */
expect suspend fun RunAnywhere.generateImage(
    prompt: String,
    options: DiffusionGenerationOptions? = null,
): DiffusionResult

/**
 * Generate an image with a progress callback.
 *
 * @param prompt Text description of the desired image.
 * @param options Generation options.
 * @param onProgress Callback for progress updates; return false to cancel.
 * @return DiffusionResult containing the generated image.
 */
expect suspend fun RunAnywhere.generateImage(
    prompt: String,
    options: DiffusionGenerationOptions?,
    onProgress: (DiffusionProgress) -> Boolean,
): DiffusionResult

/**
 * Generate an image with progress reporting via Flow.
 *
 * @param prompt Text description of the desired image.
 * @param options Generation options.
 * @return Flow emitting DiffusionProgress updates; the terminal value is
 *         the final progress event with progress = 1.0.
 */
expect fun RunAnywhere.generateImageStream(
    prompt: String,
    options: DiffusionGenerationOptions? = null,
): Flow<DiffusionProgress>

/** Cancel ongoing image generation. */
expect suspend fun RunAnywhere.cancelImageGeneration()

// MARK: - Model Lifecycle

/**
 * Load a diffusion model.
 *
 * @param modelPath Path to the model directory (e.g. CoreML .mlmodelc bundle on Apple).
 * @param modelId Model identifier.
 * @param modelName Human-readable model name.
 * @param configuration Optional configuration for the model.
 */
expect suspend fun RunAnywhere.loadDiffusionModel(
    modelPath: String,
    modelId: String,
    modelName: String,
    configuration: DiffusionConfiguration? = null,
)

/** Unload the current diffusion model. */
expect suspend fun RunAnywhere.unloadDiffusionModel()

/** Whether a diffusion model is currently loaded. */
expect suspend fun RunAnywhere.isDiffusionModelLoaded(): Boolean

/** The currently loaded diffusion model ID, if any. */
expect suspend fun RunAnywhere.currentDiffusionModelId(): String?

/** The currently loaded diffusion framework, if any. */
expect suspend fun RunAnywhere.currentDiffusionFramework(): InferenceFramework?

/** Get diffusion service capabilities (text-to-image, inpainting, etc.). */
expect suspend fun RunAnywhere.getDiffusionCapabilities(): DiffusionCapabilities
