/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for Voice Activity Detection operations.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.VADOptions
import ai.runanywhere.proto.v1.VADStreamEvent
import ai.runanywhere.proto.v1.VADStreamEventKind
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVAD
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.NativeProtoProgressListener
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RAVADOptions
import com.runanywhere.sdk.public.types.RAVADResult
import kotlinx.coroutines.channels.trySendBlocking
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.flow.collect

private val vadLogger = SDKLogger.vad

actual suspend fun RunAnywhere.detectVoiceActivity(audioData: ByteArray): RAVADResult =
    detectVoiceActivity(audioData, RAVADOptions())

actual suspend fun RunAnywhere.detectVoiceActivity(
    audioData: ByteArray,
    options: RAVADOptions,
): RAVADResult {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    vadLogger.debug("Processing VAD frame: ${audioData.size} bytes")

    val result = CppBridgeVAD.process(audioData.toFloatArray(), options)

    if (result.is_speech) {
        vadLogger.debug("Speech detected (confidence: ${String.format("%.2f", result.confidence)})")
    }

    return result
}

actual fun RunAnywhere.streamVAD(
    audioSamples: Flow<FloatArray>,
    options: RAVADOptions,
): Flow<RAVADResult> =
    channelFlow {
        if (!isInitialized) {
            throw SDKException.notInitialized("SDK not initialized")
        }

        // Ensure the native VAD component exists; the stream callback is
        // registered per-handle and C++ drives the event envelope (seq,
        // timestamp_us, request_id, kind) via dispatch_vad_stream_event.
        // We surface only the per-frame VADResult to match Swift
        // `streamVAD(audio:)` which yields one RAVADResult per chunk.
        val handle = CppBridgeVAD.getHandle()

        val listener =
            NativeProtoProgressListener { bytes ->
                val event =
                    try {
                        VADStreamEvent.ADAPTER.decode(bytes)
                    } catch (t: Throwable) {
                        close(t)
                        return@NativeProtoProgressListener false
                    }
                // Only forward FRAME envelopes that carry a VADResult;
                // STARTED/STOPPED/STATISTICS/ERROR transitions are
                // internal stream lifecycle and not surfaced through the
                // RAVADResult contract.
                if (event.kind == VADStreamEventKind.VAD_STREAM_EVENT_KIND_FRAME) {
                    event.result?.let { trySendBlocking(it) }
                }
                true
            }

        val registerRc = RunAnywhereBridge.racVadSetStreamProtoCallback(handle, listener)
        if (registerRc != RunAnywhereBridge.RAC_SUCCESS) {
            throw SDKException.operation(
                "racVadSetStreamProtoCallback failed with rc=$registerRc",
            )
        }

        val sessionId =
            RunAnywhereBridge.racVadStreamStartProto(
                handle,
                VADOptions.ADAPTER.encode(options),
            )
        if (sessionId == 0L) {
            RunAnywhereBridge.racVadSetStreamProtoCallback(handle, null)
            throw SDKException.operation("racVadStreamStartProto returned 0")
        }

        try {
            audioSamples.collect { samples ->
                val pcmBytes = samples.toPcm16LeBytes()
                val feedRc =
                    RunAnywhereBridge.racVadStreamFeedAudioProto(sessionId, pcmBytes)
                if (feedRc != RunAnywhereBridge.RAC_SUCCESS) {
                    throw SDKException.operation(
                        "racVadStreamFeedAudioProto failed with rc=$feedRc",
                    )
                }
            }
            RunAnywhereBridge.racVadStreamStopProto(sessionId)
        } finally {
            // Ensure the session and listener are always torn down, whether
            // the upstream flow completes normally, errors, or is cancelled.
            RunAnywhereBridge.racVadStreamCancelProto(sessionId)
            RunAnywhereBridge.racVadSetStreamProtoCallback(handle, null)
        }
    }

actual suspend fun RunAnywhere.resetVAD() {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    CppBridgeVAD.reset()
}

private fun ByteArray.toFloatArray(): FloatArray {
    val samples = FloatArray(size / 2)
    var byteIndex = 0
    for (i in samples.indices) {
        val lo = this[byteIndex].toInt() and 0xFF
        val hi = this[byteIndex + 1].toInt()
        val pcm = (hi shl 8) or lo
        samples[i] = (pcm.toShort().toFloat() / Short.MAX_VALUE.toFloat()).coerceIn(-1f, 1f)
        byteIndex += 2
    }
    return samples
}

/**
 * Convert normalized Float PCM samples in `[-1.0, 1.0]` to little-endian
 * int16 PCM bytes for `rac_vad_stream_feed_audio_proto`, which expects the
 * raw byte encoding used throughout the C ABI (`RAC_STT_BYTES_PER_SAMPLE`).
 */
private fun FloatArray.toPcm16LeBytes(): ByteArray {
    val bytes = ByteArray(size * 2)
    var byteIndex = 0
    for (sample in this) {
        val clamped = sample.coerceIn(-1f, 1f)
        val pcm = (clamped * Short.MAX_VALUE.toFloat()).toInt()
        bytes[byteIndex] = (pcm and 0xFF).toByte()
        bytes[byteIndex + 1] = ((pcm shr 8) and 0xFF).toByte()
        byteIndex += 2
    }
    return bytes
}
