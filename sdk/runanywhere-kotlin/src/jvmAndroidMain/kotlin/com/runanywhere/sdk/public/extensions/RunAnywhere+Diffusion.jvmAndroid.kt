/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for diffusion (image generation).
 *
 * Stub-only for now: the C++ commons does not yet ship `rac_diffusion_*`
 * thunks for non-Apple platforms (the Swift SDK uses Apple's
 * `StableDiffusion` framework directly through CoreML). Each function
 * raises `SDKException.unsupportedOperation` so the API surface is parity-
 * consistent with Swift while making the platform gap obvious to callers.
 *
 * When the Kotlin side gains diffusion support (e.g. via ONNX Runtime +
 * stable-diffusion ONNX models), this file will be replaced with a
 * `CppBridgeDiffusion`-routed implementation.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.DiffusionCapabilities
import ai.runanywhere.proto.v1.DiffusionConfiguration
import ai.runanywhere.proto.v1.DiffusionGenerationOptions
import ai.runanywhere.proto.v1.DiffusionProgress
import ai.runanywhere.proto.v1.DiffusionResult
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

private fun unsupported(opName: String): SDKException =
    SDKException.operation(
        message =
            "Diffusion is not yet supported on JVM/Android. Operation '$opName' is unavailable; " +
                "the C++ commons does not yet export rac_diffusion_* thunks for this platform.",
    )

actual suspend fun RunAnywhere.generateImage(
    prompt: String,
    options: DiffusionGenerationOptions?,
): DiffusionResult = throw unsupported("generateImage")

actual suspend fun RunAnywhere.generateImage(
    prompt: String,
    options: DiffusionGenerationOptions?,
    onProgress: (DiffusionProgress) -> Boolean,
): DiffusionResult = throw unsupported("generateImage(onProgress)")

actual fun RunAnywhere.generateImageStream(
    prompt: String,
    options: DiffusionGenerationOptions?,
): Flow<DiffusionProgress> =
    flow {
        throw unsupported("generateImageStream")
    }

actual suspend fun RunAnywhere.cancelImageGeneration() {
    throw unsupported("cancelImageGeneration")
}

actual suspend fun RunAnywhere.loadDiffusionModel(
    modelPath: String,
    modelId: String,
    modelName: String,
    configuration: DiffusionConfiguration?,
) {
    throw unsupported("loadDiffusionModel")
}

actual suspend fun RunAnywhere.unloadDiffusionModel() {
    throw unsupported("unloadDiffusionModel")
}

actual suspend fun RunAnywhere.isDiffusionModelLoaded(): Boolean = false

actual suspend fun RunAnywhere.currentDiffusionModelId(): String? = null

actual suspend fun RunAnywhere.currentDiffusionFramework(): InferenceFramework? = null

actual suspend fun RunAnywhere.getDiffusionCapabilities(): DiffusionCapabilities =
    DiffusionCapabilities()
