/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Ergonomic helpers for canonical VLM proto types.
 *
 * Mirrors Swift RAVLMImage+Helpers.swift. This SDK is an Android library, so
 * the Android Bitmap factory lives alongside the platform-agnostic factories.
 *
 * RAVLMConfiguration and RAVLMGenerationOptions were both deleted outright
 * (idl/vlm_options.proto): VLMConfiguration had no commons adapter at all,
 * and VLMGenerationOptions's 11 sampling fields were name-for-name copies of
 * LLMGenerationOptions with drifted defaults. Sampling now lives on
 * VLMGenerationRequest.options (LLMGenerationOptions, shared with the text
 * path); the four genuinely vision-specific knobs survive on
 * VLMVisionOptions.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.VLMImage
import android.graphics.Bitmap
import com.runanywhere.sdk.public.types.RAVLMImage
import okio.ByteString.Companion.toByteString

// MARK: - VLMImage factories (platform-agnostic)

/**
 * Create a [VLMImage] from an encoded JPEG / PNG / WebP byte buffer.
 *
 * `img.format`/`.encoded` were deleted along with `VLMImageFormat`
 * (idl/vlm_options.proto): the oneof case name (`data`) now carries the same
 * discrimination the old `format` enum did, and [mediaType] (a plain MIME
 * string) replaces the closed format enum entirely so a new container type
 * is not a proto change.
 */
fun VLMImage.Companion.fromEncoded(
    data: ByteArray,
    mediaType: String,
): RAVLMImage =
    RAVLMImage(
        data_ = data.toByteString(),
        media_type = mediaType,
    )

/**
 * Create a [VLMImage] from an on-disk file path.
 */
fun VLMImage.Companion.fromFilePath(path: String): RAVLMImage =
    RAVLMImage(file_path = path)

/**
 * Create a [VLMImage] from a base64-encoded string.
 */
fun VLMImage.Companion.fromBase64(
    base64: String,
    mediaType: String,
): RAVLMImage =
    RAVLMImage(
        base64 = base64,
        media_type = mediaType,
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
    )

/**
 * Create a [VLMImage] from raw RGBA bytes (4 bytes per pixel, no padding).
 *
 * `raw_rgba` is now its own oneof arm (idl/vlm_options.proto field 12), not a
 * shared `raw_rgb` slot distinguished by a format flag.
 */
fun VLMImage.Companion.fromRawRGBA(
    data: ByteArray,
    width: Int,
    height: Int,
): RAVLMImage =
    RAVLMImage(
        raw_rgba = data.toByteString(),
        width = width,
        height = height,
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
