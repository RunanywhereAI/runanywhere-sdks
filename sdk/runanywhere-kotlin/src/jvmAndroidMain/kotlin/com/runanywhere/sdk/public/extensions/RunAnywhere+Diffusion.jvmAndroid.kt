/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for diffusion image generation operations.
 * Routes all calls through CppBridgeDiffusion to the C++ rac_diffusion_component.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeDiffusion
import com.runanywhere.sdk.foundation.errors.SDKError
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionConfiguration
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionGenerationOptions
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionInfo
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionModelVariant
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionProgress
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.withContext

private val diffusionLogger = SDKLogger("Diffusion")

// MARK: - Image Generation

actual suspend fun RunAnywhere.generateImage(
    prompt: String,
    options: DiffusionGenerationOptions?,
): DiffusionResult {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    ensureServicesReady()

    val opts = options ?: DiffusionGenerationOptions(prompt = prompt)
    val effectiveOptions = if (opts.prompt != prompt) opts.copy(prompt = prompt) else opts

    diffusionLogger.info("Generating image for prompt: ${prompt.take(50)}${if (prompt.length > 50) "..." else ""}")

    return withContext(Dispatchers.IO) {
        val result = CppBridgeDiffusion.generate(effectiveOptions)
            ?: throw SDKError.general("Image generation failed")

        diffusionLogger.info(
            "Image generated: ${result.width}x${result.height} in ${result.generationTimeMs}ms",
        )
        result
    }
}

actual fun RunAnywhere.generateImageStream(
    prompt: String,
    options: DiffusionGenerationOptions?,
): Flow<DiffusionProgress> = flow {
    // For streaming, we emit progress updates during generation
    // Currently bridges to the non-streaming generate with synthetic progress
    val opts = options ?: DiffusionGenerationOptions(prompt = prompt)
    val effectiveOptions = if (opts.prompt != prompt) opts.copy(prompt = prompt) else opts

    // Emit starting progress
    emit(
        DiffusionProgress(
            progress = 0.0f,
            currentStep = 0,
            totalSteps = effectiveOptions.steps ?: 28,
            stage = "Starting",
        ),
    )

    // Generate (this blocks until complete)
    val result = CppBridgeDiffusion.generate(effectiveOptions)

    if (result != null) {
        // Emit completion progress with result data
        emit(
            DiffusionProgress(
                progress = 1.0f,
                currentStep = effectiveOptions.steps ?: 28,
                totalSteps = effectiveOptions.steps ?: 28,
                stage = "Complete",
                intermediateImage = result.imageData,
                intermediateImageWidth = result.width,
                intermediateImageHeight = result.height,
            ),
        )
    }
}.flowOn(Dispatchers.IO)

// MARK: - Generation Control

actual fun RunAnywhere.cancelImageGeneration() {
    CppBridgeDiffusion.cancel()
}

// MARK: - Model Management

actual suspend fun RunAnywhere.loadDiffusionModel(
    modelPath: String,
    modelId: String,
    modelName: String?,
    configuration: DiffusionConfiguration?,
) {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    ensureServicesReady()

    withContext(Dispatchers.IO) {
        // Configure if provided
        if (configuration != null) {
            if (!CppBridgeDiffusion.configure(configuration)) {
                throw SDKError.general("Failed to configure diffusion component")
            }
        }

        // Load model
        if (!CppBridgeDiffusion.loadModel(modelPath, modelId, modelName)) {
            throw SDKError.general("Failed to load diffusion model: $modelId")
        }

        diffusionLogger.info("Diffusion model loaded: $modelId")
    }
}

actual suspend fun RunAnywhere.unloadDiffusionModel() {
    withContext(Dispatchers.IO) {
        CppBridgeDiffusion.unload()
    }
}

actual val RunAnywhere.isDiffusionModelLoaded: Boolean
    get() = CppBridgeDiffusion.isLoaded

// MARK: - Info

actual suspend fun RunAnywhere.getDiffusionInfo(): DiffusionInfo {
    return withContext(Dispatchers.IO) {
        CppBridgeDiffusion.getInfo() ?: DiffusionInfo(
            isReady = false,
            modelVariant = DiffusionModelVariant.SD_1_5,
            supportsTextToImage = false,
            supportsImageToImage = false,
            supportsInpainting = false,
            safetyCheckerEnabled = false,
            maxWidth = 0,
            maxHeight = 0,
        )
    }
}

actual fun RunAnywhere.getDiffusionCapabilities(): Int {
    return CppBridgeDiffusion.getCapabilities()
}
