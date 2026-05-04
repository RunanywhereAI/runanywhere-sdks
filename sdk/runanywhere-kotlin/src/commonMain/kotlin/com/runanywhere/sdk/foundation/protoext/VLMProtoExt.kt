/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Extension helpers for the proto-canonical VLM types
 * (ai.runanywhere.proto.v1.{VLMImage, VLMConfiguration, VLMGenerationOptions,
 *  VLMResult, VLMImageFormat, VLMErrorCode}).
 *
 * Wire generates VLMImage with a `oneof source` (file_path / encoded /
 * raw_rgb / base64). The legacy hand-rolled type used a discriminated union
 * with helper factories. These extensions restore those factories.
 */

package com.runanywhere.sdk.foundation.protoext

import ai.runanywhere.proto.v1.VLMConfiguration
import ai.runanywhere.proto.v1.VLMImage
import ai.runanywhere.proto.v1.VLMImageFormat
import okio.ByteString.Companion.toByteString

/**
 * Create a VLMImage from a file path.
 */
fun vlmImageFromFilePath(path: String): VLMImage =
    VLMImage(
        file_path = path,
        format = VLMImageFormat.VLM_IMAGE_FORMAT_FILE_PATH,
    )

/**
 * Create a VLMImage from raw RGB pixel data.
 */
fun vlmImageFromRgbPixels(data: ByteArray, width: Int, height: Int): VLMImage =
    VLMImage(
        raw_rgb = data.toByteString(),
        width = width,
        height = height,
        format = VLMImageFormat.VLM_IMAGE_FORMAT_RAW_RGB,
    )

/**
 * Create a VLMImage from encoded image bytes (JPEG/PNG/WEBP).
 */
fun vlmImageFromEncoded(data: ByteArray, format: VLMImageFormat = VLMImageFormat.VLM_IMAGE_FORMAT_UNSPECIFIED): VLMImage =
    VLMImage(
        encoded = data.toByteString(),
        format = format,
    )

/**
 * Create a VLMImage from a base64-encoded string.
 */
fun vlmImageFromBase64(data: String): VLMImage =
    VLMImage(
        base64 = data,
        format = VLMImageFormat.VLM_IMAGE_FORMAT_BASE64,
    )

/**
 * Validate this VLMConfiguration. Mirrors legacy validate() ranges where
 * applicable to the proto-canonical fields.
 */
fun VLMConfiguration.validate() {
    require(max_image_size_px >= 0) {
        "max_image_size_px must be non-negative (got $max_image_size_px)"
    }
    require(max_tokens >= 0) {
        "max_tokens must be non-negative (got $max_tokens)"
    }
}

/** Whether a model id has been configured (non-blank). */
val VLMConfiguration.hasModelId: Boolean
    get() = model_id.isNotBlank()
