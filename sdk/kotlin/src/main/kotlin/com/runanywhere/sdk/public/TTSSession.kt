// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

package com.runanywhere.sdk.`public`

/**
 * Text-to-speech session. Synchronous `synthesize()` returns raw PCM
 * samples + sample rate.
 */
class TTSSession(
    modelId: String,
    modelPath: String,
    format: ModelFormat = ModelFormat.ONNX,
) {
    data class AudioResult(val pcm: FloatArray, val sampleRateHz: Int)

    private val handle: Long

    init {
        require(NativeLibrary.isLoaded) { "racommons_core not loaded" }
        handle = nativeCreate(modelId, modelPath, format.raw)
        if (handle == 0L) throw RunAnywhereException(
            RunAnywhereException.BACKEND_UNAVAILABLE, "ra_tts_create returned null")
    }

    fun synthesize(text: String): AudioResult {
        val sr = IntArray(1)
        val pcm = nativeSynthesize(handle, text, sr)
            ?: throw RunAnywhereException(-1, "ra_tts_synthesize failed")
        return AudioResult(pcm, sr[0])
    }

    fun cancel(): Int = nativeCancel(handle)

    fun close() { if (handle != 0L) nativeDestroy(handle) }

    private external fun nativeCreate(modelId: String, modelPath: String,
                                        format: Int): Long
    private external fun nativeSynthesize(handle: Long, text: String,
                                            outSr: IntArray): FloatArray?
    private external fun nativeCancel(handle: Long): Int
    private external fun nativeDestroy(handle: Long)
}
