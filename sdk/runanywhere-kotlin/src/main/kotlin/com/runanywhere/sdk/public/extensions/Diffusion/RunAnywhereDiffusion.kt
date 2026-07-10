/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.DiffusionGenerationOptions
import ai.runanywhere.proto.v1.DiffusionMode
import ai.runanywhere.proto.v1.ModelCategory
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeDiffusion
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RADiffusionGenerationOptions
import com.runanywhere.sdk.public.types.RADiffusionResult
import okio.ByteString.Companion.toByteString

/** Generate an image with the lifecycle-loaded image-generation model. */
suspend fun RunAnywhere.generateImage(
    options: RADiffusionGenerationOptions,
    modelId: String? = null,
): RADiffusionResult {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK")
    }
    ensureServicesReady()
    val loaded =
        currentModel(
            CurrentModelRequest(
                category = ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION,
            ),
        )
    if (!loaded.found) {
        throw SDKException.modelNotLoaded(modelId)
    }
    if (!modelId.isNullOrBlank() && loaded.model_id != modelId) {
        throw SDKException.invalidArgument(
            "Loaded image-generation model '${loaded.model_id}' does not match '$modelId'",
        )
    }
    return CppBridgeDiffusion.generate(options, modelId)
}

/**
 * Inpaint an encoded PNG/JPEG using an encoded mask where white pixels mark
 * the region to replace. The result advertises its raw RGBA media type.
 */
suspend fun RunAnywhere.inpaint(
    inputImage: ByteArray,
    maskImage: ByteArray,
    prompt: String = "Remove the masked region.",
    width: Int = 512,
    height: Int = 512,
    modelId: String? = null,
): RADiffusionResult {
    if (inputImage.isEmpty()) {
        throw SDKException.invalidArgument("inputImage must not be empty")
    }
    if (maskImage.isEmpty()) {
        throw SDKException.invalidArgument("maskImage must not be empty")
    }
    if (prompt.isBlank()) {
        throw SDKException.invalidArgument("prompt must not be blank")
    }
    if (width <= 0 || height <= 0) {
        throw SDKException.invalidArgument("width and height must be positive")
    }
    val inputMediaType =
        inputImage.encodedImageMediaType()
            ?: throw SDKException.invalidArgument("inputImage must be encoded PNG or JPEG data")
    val maskMediaType =
        maskImage.encodedImageMediaType()
            ?: throw SDKException.invalidArgument("maskImage must be encoded PNG or JPEG data")
    return generateImage(
        options =
            DiffusionGenerationOptions(
                prompt = prompt,
                width = width,
                height = height,
                mode = DiffusionMode.DIFFUSION_MODE_INPAINTING,
                input_image = inputImage.toByteString(),
                mask_image = maskImage.toByteString(),
                input_image_media_type = inputMediaType,
                mask_image_media_type = maskMediaType,
            ),
        modelId = modelId,
    )
}

private fun ByteArray.encodedImageMediaType(): String? =
    when {
        size >= 8 &&
            this[0] == 0x89.toByte() &&
            this[1] == 'P'.code.toByte() &&
            this[2] == 'N'.code.toByte() &&
            this[3] == 'G'.code.toByte() -> "image/png"
        size >= 3 &&
            this[0] == 0xff.toByte() &&
            this[1] == 0xd8.toByte() &&
            this[2] == 0xff.toByte() -> "image/jpeg"
        else -> null
    }
