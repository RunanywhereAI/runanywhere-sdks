// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

package com.runanywhere.sdk.`public`

/** Text embedding session — maps a string to a fixed-dimension vector. */
class EmbedSession(
    modelId: String,
    modelPath: String,
    format: ModelFormat = ModelFormat.GGUF,
) {
    private val handle: Long
    val dims: Int

    init {
        require(NativeLibrary.isLoaded) { "racommons_core not loaded" }
        handle = nativeCreate(modelId, modelPath, format.raw)
        if (handle == 0L) throw RunAnywhereException(
            RunAnywhereException.BACKEND_UNAVAILABLE, "ra_embed_create returned null")
        dims = nativeDims(handle)
    }

    fun embed(text: String): FloatArray {
        return nativeEmbed(handle, text)
            ?: throw RunAnywhereException(-1, "ra_embed_text failed")
    }

    fun close() { if (handle != 0L) nativeDestroy(handle) }

    private external fun nativeCreate(modelId: String, modelPath: String,
                                        format: Int): Long
    private external fun nativeDims(handle: Long): Int
    private external fun nativeEmbed(handle: Long, text: String): FloatArray?
    private external fun nativeDestroy(handle: Long)
}
