/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Android-only ergonomic helper that builds a [VLMImage] from a
 * [android.graphics.Bitmap]. Mirrors Swift's
 * `RAVLMImage.fromUIImage(_:)` factory.
 *
 * Camera-frame factories (CVPixelBuffer / android.media.Image) are
 * intentionally not provided here — those are app-level concerns that
 * vary per capture pipeline. The `examples/android` app shows how to
 * unpack an `ImageProxy` plane with explicit row / pixel stride before
 * calling [VLMImage.fromRawRGB].
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.VLMImage
import android.graphics.Bitmap
import com.runanywhere.sdk.public.types.RAVLMImage

/**
 * Build a [VLMImage] from a [Bitmap], stripping the alpha channel into a
 * tightly packed RGB byte buffer (3 bytes per pixel, row-major, no padding).
 *
 * Stride handling: [Bitmap.getPixels] returns ARGB ints into a caller-owned
 * array — Android does the row-stride bookkeeping internally, so callers
 * never observe `rowBytes` / `pixelStride` when going through this path.
 * That's how we sidestep the stride bug that bites callers who reach for
 * [Bitmap.copyPixelsToBuffer] without translating `rowBytes` into a packed
 * byte stream (each row may carry trailing padding bytes, especially for
 * non-power-of-two widths).
 */
fun VLMImage.Companion.fromBitmap(bitmap: Bitmap): RAVLMImage {
    val width = bitmap.width
    val height = bitmap.height
    val pixelCount = width * height

    // ARGB ints, packed (no row padding) — Bitmap.getPixels handles stride.
    val pixels = IntArray(pixelCount)
    bitmap.getPixels(pixels, 0, width, 0, 0, width, height)

    // Strip alpha → tightly packed RGB bytes (3 * w * h, no padding).
    val rgb = ByteArray(pixelCount * 3)
    var dst = 0
    for (i in 0 until pixelCount) {
        val argb = pixels[i]
        rgb[dst++] = ((argb shr 16) and 0xFF).toByte() // R
        rgb[dst++] = ((argb shr 8) and 0xFF).toByte() // G
        rgb[dst++] = (argb and 0xFF).toByte() // B
    }

    return RAVLMImage.fromRawRGB(rgb, width, height)
}
