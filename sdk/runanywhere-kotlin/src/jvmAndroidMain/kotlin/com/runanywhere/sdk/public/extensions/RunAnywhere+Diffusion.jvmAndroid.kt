/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for Diffusion image generation operations.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeDiffusion
import com.runanywhere.sdk.foundation.errors.SDKError
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionConfiguration
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionGenerationOptions
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionModelVariant
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionProgress
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionResult
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

private val diffusionLogger = SDKLogger.diffusion

// MARK: - Configuration

actual suspend fun RunAnywhere.configureDiffusion(config: DiffusionConfiguration) {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }
    val result = CppBridgeDiffusion.configure(config)
    if (result != 0) {
        throw SDKError.diffusion("Failed to configure diffusion component: $result")
    }
    diffusionLogger.info("Diffusion configured with variant: ${config.modelVariant}")
}

// MARK: - Model Loading

actual suspend fun RunAnywhere.loadDiffusionModel(
    modelPath: String,
    modelId: String,
    modelName: String?,
) {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }
    diffusionLogger.info("Loading diffusion model: $modelId from $modelPath")
    val result = CppBridgeDiffusion.loadModel(modelPath, modelId, modelName)
    if (result != 0) {
        throw SDKError.diffusion("Failed to load diffusion model: $result")
    }
    diffusionLogger.info("Diffusion model loaded: $modelId")
}

actual suspend fun RunAnywhere.unloadDiffusionModel() {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }
    CppBridgeDiffusion.unload()
    diffusionLogger.info("Diffusion model unloaded")
}

actual suspend fun RunAnywhere.isDiffusionModelLoaded(): Boolean {
    return CppBridgeDiffusion.isLoaded
}

actual val RunAnywhere.currentDiffusionModelId: String?
    get() = CppBridgeDiffusion.getLoadedModelId()

actual val RunAnywhere.isDiffusionModelLoadedSync: Boolean
    get() = CppBridgeDiffusion.isLoaded

// MARK: - Image Generation

actual suspend fun RunAnywhere.generateImage(prompt: String): DiffusionResult {
    return generateImageWithOptions(DiffusionGenerationOptions.textToImage(prompt))
}

actual suspend fun RunAnywhere.generateImageWithOptions(
    options: DiffusionGenerationOptions,
): DiffusionResult {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    diffusionLogger.debug("Generating image: ${options.prompt.take(50)}...")
    val result = CppBridgeDiffusion.generate(options)
    diffusionLogger.info("Image generated: ${result.width}x${result.height}, ${result.generationTimeMs}ms")
    return result
}

actual fun RunAnywhere.generateImageWithProgress(
    options: DiffusionGenerationOptions,
): Flow<DiffusionProgress> = callbackFlow {
    if (!isInitialized) {
        close(SDKError.notInitialized("SDK not initialized"))
        return@callbackFlow
    }

    diffusionLogger.debug("Generating image with progress: ${options.prompt.take(50)}...")

    val callback = CppBridgeDiffusion.ProgressCallback { progress ->
        val sendResult = trySend(progress)
        sendResult.isSuccess
    }

    try {
        // This will block until generation is complete
        CppBridgeDiffusion.generate(options, callback)
    } catch (e: Exception) {
        close(e)
    }

    awaitClose {
        // Cancel generation if the flow is closed
        CppBridgeDiffusion.cancel()
    }
}

actual suspend fun RunAnywhere.cancelDiffusionGeneration() {
    CppBridgeDiffusion.cancel()
    diffusionLogger.info("Diffusion generation cancelled")
}

// MARK: - Convenience Methods

actual suspend fun RunAnywhere.textToImage(
    prompt: String,
    negativePrompt: String,
    width: Int?,
    height: Int?,
    steps: Int?,
    seed: Long,
): DiffusionResult {
    // Get defaults from current config or model variant default
    val variant = DiffusionModelVariant.SD15 // Default variant
    val (defaultWidth, defaultHeight) = variant.defaultResolution
    val defaultSteps = variant.defaultSteps

    val options = DiffusionGenerationOptions.textToImage(
        prompt = prompt,
        negativePrompt = negativePrompt,
        width = width ?: defaultWidth,
        height = height ?: defaultHeight,
        steps = steps ?: defaultSteps,
        seed = seed,
    )
    return generateImageWithOptions(options)
}

actual suspend fun RunAnywhere.imageToImage(
    prompt: String,
    inputImage: ByteArray,
    denoiseStrength: Float,
    negativePrompt: String,
    seed: Long,
): DiffusionResult {
    val options = DiffusionGenerationOptions.imageToImage(
        prompt = prompt,
        inputImage = inputImage,
        negativePrompt = negativePrompt,
        denoiseStrength = denoiseStrength,
        seed = seed,
    )
    return generateImageWithOptions(options)
}

actual suspend fun RunAnywhere.inpaint(
    prompt: String,
    inputImage: ByteArray,
    maskImage: ByteArray,
    negativePrompt: String,
    seed: Long,
): DiffusionResult {
    val options = DiffusionGenerationOptions.inpainting(
        prompt = prompt,
        inputImage = inputImage,
        maskImage = maskImage,
        negativePrompt = negativePrompt,
        seed = seed,
    )
    return generateImageWithOptions(options)
}
