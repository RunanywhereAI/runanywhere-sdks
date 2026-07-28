/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Ergonomic helpers for canonical VLM proto types.
 *
 * Mirrors Swift RAVLMImage+Helpers.swift. This SDK is an Android library, so
 * the Android Bitmap factory lives alongside the platform-agnostic factories.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.VLMConfiguration
import ai.runanywhere.proto.v1.VLMGenerationOptions
import ai.runanywhere.proto.v1.VLMImage
import ai.runanywhere.proto.v1.VLMImageFormat
import android.graphics.Bitmap
import com.runanywhere.sdk.public.types.RAVLMGenerationOptions
import com.runanywhere.sdk.public.types.RAVLMImage
import okio.ByteString.Companion.toByteString
import com.runanywhere.sdk.generated.convenience.defaults as generatedDefaults

// MARK: - VLMConfiguration

/**
 * Default VLM component configuration mirroring Swift `RAVLMConfiguration.defaults`.
 *
 * Only load-bearing identification + limits cross the IDL boundary
 * (model_id, max_image_size_px, max_tokens). Per-request sampling
 * parameters live on [VLMGenerationOptions].
 */
fun VLMConfiguration.Companion.defaults(modelId: String = ""): VLMConfiguration =
    VLMConfiguration(
        model_id = modelId,
        max_image_size_px = 1_024,
        max_tokens = 0,
    )

// MARK: - VLMGenerationOptions

/**
 * [VLMGenerationOptions.defaults] with a prompt filled in.
 *
 * Sampling values come from generated/convenience/RAConvenience.kt, emitted from
 * the rac_default annotations in idl/vlm_options.proto. The table this replaced
 * capped max_tokens at 256 against the C layer's 2048 and set top_k=40 where the
 * C layer disables it.
 */
fun VLMGenerationOptions.Companion.defaults(prompt: String = ""): RAVLMGenerationOptions =
    generatedDefaults().copy(prompt = prompt)

// MARK: - VLMImage factories (platform-agnostic)

/**
 * Create a [VLMImage] from an encoded JPEG / PNG / WebP byte buffer.
 */
fun VLMImage.Companion.fromEncoded(
    data: ByteArray,
    format: VLMImageFormat,
): RAVLMImage =
    RAVLMImage(
        encoded = data.toByteString(),
        format = format,
    )

/**
 * Create a [VLMImage] from an on-disk file path.
 */
fun VLMImage.Companion.fromFilePath(path: String): RAVLMImage =
    RAVLMImage(
        file_path = path,
        format = VLMImageFormat.VLM_IMAGE_FORMAT_FILE_PATH,
    )

/**
 * Create a [VLMImage] from a base64-encoded string.
 */
fun VLMImage.Companion.fromBase64(base64: String): RAVLMImage =
    RAVLMImage(
        base64 = base64,
        format = VLMImageFormat.VLM_IMAGE_FORMAT_BASE64,
    )

/**
 * Create a [VLMImage] from raw RGB bytes (3 bytes per pixel, no padding).
 */
fun VLMImage.Companion.fromRawRGB(
    data: ByteArray,
    width: Int,
    height: Int,
): RAVLMImage =
    RAVLMImage(
        raw_rgb = data.toByteString(),
        width = width,
        height = height,
        format = VLMImageFormat.VLM_IMAGE_FORMAT_RAW_RGB,
    )

/**
 * Create a [VLMImage] from raw RGBA bytes (4 bytes per pixel, no padding).
 *
 * Stored in the same `raw_rgb` oneof slot as RGB; [format] disambiguates.
 */
fun VLMImage.Companion.fromRawRGBA(
    data: ByteArray,
    width: Int,
    height: Int,
): RAVLMImage =
    RAVLMImage(
        raw_rgb = data.toByteString(),
        width = width,
        height = height,
        format = VLMImageFormat.VLM_IMAGE_FORMAT_RAW_RGBA,
    )

/**
 * Create a [VLMImage] from an Android [Bitmap], encoded as tightly-packed RGBA
 * bytes to match Swift's UIKit/AppKit image helpers.
 */
fun VLMImage.Companion.fromBitmap(bitmap: Bitmap): RAVLMImage {
    val width = bitmap.width
    val height = bitmap.height
    val pixels = IntArray(width * height)
    bitmap.getPixels(pixels, 0, width, 0, 0, width, height)

    val rgba = ByteArray(pixels.size * 4)
    pixels.forEachIndexed { index, pixel ->
        val offset = index * 4
        rgba[offset] = ((pixel shr 16) and 0xFF).toByte()
        rgba[offset + 1] = ((pixel shr 8) and 0xFF).toByte()
        rgba[offset + 2] = (pixel and 0xFF).toByte()
        rgba[offset + 3] = ((pixel shr 24) and 0xFF).toByte()
    }
    return fromRawRGBA(rgba, width, height)
}
