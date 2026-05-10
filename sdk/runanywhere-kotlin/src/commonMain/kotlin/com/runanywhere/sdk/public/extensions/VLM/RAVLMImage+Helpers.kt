/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Ergonomic helpers for canonical VLM proto types.
 *
 * Mirrors Swift RAVLMImage+Helpers.swift. Only the platform-agnostic
 * factories live here; Apple-only (UIImage / CVPixelBuffer) and
 * Android-only (Bitmap) factories live in their respective platform
 * source sets — see `androidMain/.../VLM/VLMImage+Bitmap.kt`.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.VLMConfiguration
import ai.runanywhere.proto.v1.VLMGenerationOptions
import ai.runanywhere.proto.v1.VLMImage
import ai.runanywhere.proto.v1.VLMImageFormat
import com.runanywhere.sdk.public.types.RAVLMGenerationOptions
import com.runanywhere.sdk.public.types.RAVLMImage
import okio.ByteString.Companion.toByteString

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
 * Default VLM generation options mirroring Swift `RAVLMGenerationOptions.defaults`.
 */
fun VLMGenerationOptions.Companion.defaults(prompt: String = ""): RAVLMGenerationOptions =
    RAVLMGenerationOptions(
        prompt = prompt,
        max_tokens = 256,
        temperature = 0.7f,
        top_p = 0.9f,
        top_k = 40,
    )

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
