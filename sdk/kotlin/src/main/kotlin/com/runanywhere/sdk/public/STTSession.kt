// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

package com.runanywhere.sdk.`public`

import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.consumeAsFlow

/**
 * Streaming speech-to-text session. Feed PCM via feedAudio, collect
 * transcript chunks from the `transcripts` flow. Call flush() on end
 * of utterance to force final chunks.
 */
class STTSession(
    modelId: String,
    modelPath: String,
    format: ModelFormat = ModelFormat.WHISPERKIT,
) {
    data class Chunk(
        val text: String,
        val isPartial: Boolean,
        val confidence: Float,
        val audioStartUs: Long,
        val audioEndUs: Long,
    )

    private val emitter = Emitter()
    private val handle: Long

    init {
        require(NativeLibrary.isLoaded) { "racommons_core not loaded" }
        handle = nativeCreate(emitter, modelId, modelPath, format.raw)
        if (handle == 0L) throw RunAnywhereException(
            RunAnywhereException.BACKEND_UNAVAILABLE, "ra_stt_create returned null")
    }

    val transcripts: Flow<Chunk> = emitter.channel.consumeAsFlow()

    fun feedAudio(samples: FloatArray, sampleRateHz: Int): Int =
        nativeFeedAudio(handle, samples, sampleRateHz)

    fun flush(): Int = nativeFlush(handle)

    fun close() { if (handle != 0L) nativeDestroy(handle); emitter.channel.close() }

    @Suppress("unused")
    internal class Emitter {
        val channel: Channel<Chunk> = Channel(Channel.BUFFERED)
        fun onChunk(text: String, isPartial: Boolean, confidence: Float,
                    startUs: Long, endUs: Long) {
            channel.trySend(Chunk(text, isPartial, confidence, startUs, endUs))
        }
    }

    private external fun nativeCreate(emitter: Emitter, modelId: String,
                                        modelPath: String, format: Int): Long
    private external fun nativeFeedAudio(handle: Long, samples: FloatArray,
                                           sampleRateHz: Int): Int
    private external fun nativeFlush(handle: Long): Int
    private external fun nativeDestroy(handle: Long)
}
