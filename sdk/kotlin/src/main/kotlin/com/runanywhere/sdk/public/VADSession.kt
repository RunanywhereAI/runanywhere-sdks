// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

package com.runanywhere.sdk.`public`

import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.consumeAsFlow

/**
 * Voice activity detection session. Feed PCM via feedAudio, collect
 * voice_start / voice_end / barge_in / silence events via `events`.
 */
class VADSession(
    modelId: String,
    modelPath: String,
    format: ModelFormat = ModelFormat.ONNX,
) {
    data class Event(val kind: Kind, val frameOffsetUs: Long, val energy: Float)
    enum class Kind { UNKNOWN, VOICE_START, VOICE_END, BARGE_IN, SILENCE }

    private val emitter = Emitter()
    private val handle: Long

    init {
        require(NativeLibrary.isLoaded) { "racommons_core not loaded" }
        handle = nativeCreate(emitter, modelId, modelPath, format.raw)
        if (handle == 0L) throw RunAnywhereException(
            RunAnywhereException.BACKEND_UNAVAILABLE, "ra_vad_create returned null")
    }

    val events: Flow<Event> = emitter.channel.consumeAsFlow()

    fun feedAudio(samples: FloatArray, sampleRateHz: Int): Int =
        nativeFeedAudio(handle, samples, sampleRateHz)

    fun close() { if (handle != 0L) nativeDestroy(handle); emitter.channel.close() }

    @Suppress("unused")
    internal class Emitter {
        val channel: Channel<Event> = Channel(Channel.BUFFERED)
        fun onEvent(kind: Int, frameOffsetUs: Long, energy: Float) {
            val k = when (kind) {
                1 -> Kind.VOICE_START
                2 -> Kind.VOICE_END
                3 -> Kind.BARGE_IN
                4 -> Kind.SILENCE
                else -> Kind.UNKNOWN
            }
            channel.trySend(Event(k, frameOffsetUs, energy))
        }
    }

    private external fun nativeCreate(emitter: Emitter, modelId: String,
                                        modelPath: String, format: Int): Long
    private external fun nativeFeedAudio(handle: Long, samples: FloatArray,
                                           sampleRateHz: Int): Int
    private external fun nativeDestroy(handle: Long)
}
