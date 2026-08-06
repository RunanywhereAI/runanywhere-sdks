/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Internal bridge from the v3 input envelopes onto the generated proto image
 * and audio carriers.
 */

package com.runanywhere.sdk.public.api

import ai.runanywhere.proto.v1.SegmentationImage
import ai.runanywhere.proto.v1.SegmentationPixelFormat
import ai.runanywhere.proto.v1.VLMImage
import com.runanywhere.sdk.foundation.errors.SDKException
import okio.ByteString
import okio.ByteString.Companion.toByteString
import java.io.File

private const val PNG_HEADER_BYTES = 8
private const val JPEG_HEADER_BYTES = 3

/**
 * `VLMImageFormat` and `VLMImage.encoded` are deleted (idl/vlm_options.proto):
 * `VLMImage` is now a plain oneof (`file_path` / `data` / `raw_rgb` / `base64`
 * / `raw_rgba`) plus a `media_type` string required alongside `data`/`base64`
 * — no format enum to select. `raw_rgb` and `raw_rgba` are two distinct oneof
 * arms now (not one field disambiguated by a format flag).
 */
internal fun ImageInput.toVlmImage(): VLMImage =
    when {
        filePath != null -> VLMImage(file_path = filePath)
        encoded != null ->
            VLMImage(
                data_ = encoded.toByteString(),
                media_type = sniffMediaType(encoded) ?: "image/jpeg",
            )
        raw != null ->
            if (layout == ImagePixelLayout.RGBA8) {
                VLMImage(raw_rgba = raw.toByteString(), width = width, height = height)
            } else {
                VLMImage(raw_rgb = raw.toByteString(), width = width, height = height)
            }
        else -> throw SDKException.invalidArgument("ImageInput carries no pixels")
    }

internal fun ImageInput.toSegmentationImage(): SegmentationImage {
    val pixels =
        raw ?: throw SDKException.invalidArgument(
            "Segmentation needs raw pixels; build the input with ImageInput.rawRgb/rawRgba/bitmap",
        )
    return SegmentationImage(
        data_ = pixels.toByteString(),
        width = width,
        height = height,
        pixel_format =
            if (layout == ImagePixelLayout.RGBA8) {
                SegmentationPixelFormat.SEGMENTATION_PIXEL_FORMAT_RGBA8
            } else {
                SegmentationPixelFormat.SEGMENTATION_PIXEL_FORMAT_RGB8
            },
    )
}

/** Encoded container bytes, reading from disk when the input is a file reference. */
internal fun ImageInput.encodedBytes(): ByteString? {
    encoded?.let { return it.toByteString() }
    val path = filePath ?: return null
    val handle = File(path)
    if (!handle.isFile) throw SDKException.invalidArgument("No image file at $path")
    return runCatching { handle.readBytes().toByteString() }.getOrElse { error ->
        throw SDKException.invalidArgument("Could not read image file at $path", error)
    }
}

internal fun ImageInput.encodedMediaType(): String? =
    encodedBytes()?.toByteArray()?.let(::sniffMediaType)

private fun sniffMediaType(data: ByteArray): String? =
    when {
        data.size >= PNG_HEADER_BYTES &&
            data[0] == 0x89.toByte() &&
            data[1] == 'P'.code.toByte() &&
            data[2] == 'N'.code.toByte() &&
            data[3] == 'G'.code.toByte() -> "image/png"
        data.size >= JPEG_HEADER_BYTES &&
            data[0] == 0xFF.toByte() &&
            data[1] == 0xD8.toByte() &&
            data[2] == 0xFF.toByte() -> "image/jpeg"
        data.size >= 12 &&
            data[8] == 'W'.code.toByte() &&
            data[9] == 'E'.code.toByte() &&
            data[10] == 'B'.code.toByte() &&
            data[11] == 'P'.code.toByte() -> "image/webp"
        else -> null
    }
