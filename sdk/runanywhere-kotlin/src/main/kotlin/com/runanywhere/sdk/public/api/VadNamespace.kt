/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public v4 surface: `RunAnywhere.vad`.
 *
 * Endpointing (min-speech / min-silence / prefix padding) is owned by commons
 * `rac_vad_stream_*`. This namespace only captures/feeds PCM and maps
 * SPEECH_ACTIVITY onset/offset events — no local isSpeech edge machine.
 */

package com.runanywhere.sdk.public.api

import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVAD
import com.runanywhere.sdk.foundation.errors.SDKException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

private val vadStreamScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

/**
 * Live VAD push stream backed by commons `rac_vad_stream_*`.
 * Commons emits SPEECH_ACTIVITY onset/offset; FRAME events surface as
 * [VadEvent.Activity].
 */
private class CommonsVadStream(
    private val format: AudioFormatSpec,
    private val options: VadOptions,
) : VadStream {
    private val inbox = Channel<AudioFrame>(Channel.UNLIMITED)
    private val outbox = Channel<VadEvent>(Channel.UNLIMITED)
    private val closed = AtomicBoolean(false)
    private val finished = AtomicBoolean(false)
    private val sessionId = AtomicLong(0L)

    override val events: Flow<VadEvent> = outbox.receiveAsFlow()

    init {
        vadStreamScope.launch {
            try {
                CppBridgeVAD.setStreamCallback { raw ->
                    if (closed.get()) return@setStreamCallback
                    for (event in decodeVadStreamEvent(raw)) {
                        if (event is VadEvent.Failed) {
                            finished.set(true)
                        }
                        outbox.trySend(event)
                    }
                }
                val started = CppBridgeVAD.streamStart(options.toProto(format.sampleRate))
                sessionId.set(started)
                for (frame in inbox) {
                    if (closed.get() || finished.get()) break
                    CppBridgeVAD.streamFeed(started, frameToPcm16(frame, format))
                }
                if (!closed.get() && !finished.get()) {
                    finished.set(true)
                    CppBridgeVAD.streamStop(started)
                    sessionId.set(0L)
                    outbox.trySend(VadEvent.Completed)
                }
            } catch (error: SDKException) {
                finished.set(true)
                outbox.trySend(VadEvent.Failed(error))
            } catch (error: Exception) {
                finished.set(true)
                outbox.trySend(VadEvent.Failed(SDKException.from(error)))
            } finally {
                val open = sessionId.getAndSet(0L)
                if (open > 0L && !finished.get()) {
                    runCatching { CppBridgeVAD.streamCancel(open) }
                }
                runCatching { CppBridgeVAD.unsetStreamCallback() }
                outbox.close()
            }
        }
    }

    override fun pushFrame(frame: AudioFrame) {
        if (closed.get() || finished.get()) return
        inbox.trySend(frame)
    }

    override fun flush() {
        // Commons processes each feed as it arrives.
    }

    override fun finish() {
        inbox.close()
    }

    override suspend fun close() {
        if (!closed.compareAndSet(false, true)) return
        inbox.close()
        val open = sessionId.getAndSet(0L)
        if (open > 0L) {
            finished.set(true)
            runCatching { CppBridgeVAD.streamCancel(open) }
        }
        // Worker `finally` unsets the stream callback and closes [outbox].
    }
}

private fun frameToPcm16(frame: AudioFrame, format: AudioFormatSpec): ByteArray =
    when (format.encoding) {
        AudioEncoding.PCM16 -> frame.samples
        AudioEncoding.FLOAT32, AudioEncoding.CONTAINER ->
            AudioInput(frame.samples, format).pcm16Bytes()
    }

/**
 * Voice-activity detection over raw audio.
 *
 * ```kotlin
 * val verdict = RunAnywhere.vad.detect(AudioInput.pcm16(frame))
 * if (verdict.isSpeech) startTurn()
 * ```
 */
public class VadNamespace internal constructor() {
    /**
     * Find the speech segments in a piece of audio.
     *
     * Endpointing is applied by commons `rac_vad_stream_*`; this method only
     * feeds PCM and maps SPEECH_ACTIVITY onset/offset into [VadResult.segments].
     *
     * @throws SDKException when the buffer is empty or the SDK is not initialized.
     */
    public suspend fun detect(audio: AudioInput, options: VadOptions? = null): VadResult {
        val opts = options.orDefault()
        val pcm16 = audio.pcm16Bytes()
        val accumulator = VadSegmentAccumulator()
        CppBridgeVAD.setStreamCallback { raw ->
            for (event in decodeVadStreamEvent(raw)) {
                accumulator.onEvent(event)
            }
        }
        var sessionId = 0L
        try {
            sessionId = CppBridgeVAD.streamStart(opts.toProto(audio.format.sampleRate))
            if (pcm16.isNotEmpty()) {
                CppBridgeVAD.streamFeed(sessionId, pcm16)
            }
            CppBridgeVAD.streamStop(sessionId)
            sessionId = 0L
        } finally {
            if (sessionId > 0L) {
                runCatching { CppBridgeVAD.streamCancel(sessionId) }
            }
            runCatching { CppBridgeVAD.unsetStreamCallback() }
        }
        return accumulator.toResult()
    }

    /**
     * Open a live voice-activity stream with one audio format established up front.
     *
     * @throws SDKException when [format] uses a container encoding — live
     *   streams take raw PCM only; use [detect] for containers.
     */
    public fun openStream(format: AudioFormatSpec, options: VadOptions? = null): VadStream {
        if (format.encoding == AudioEncoding.CONTAINER) {
            throw SDKException.invalidConfiguration(
                "vad.openStream needs raw PCM audio; container formats are batch-only — use vad.detect.",
            )
        }
        return CommonsVadStream(format, options.orDefault())
    }

    /**
     * @deprecated Use [openStream]. Track speech across a live [audio]
     *   stream, emitting a transition when it starts or ends. Forwards into
     *   a [VadStream] when every chunk shares one format; mixed formats throw.
     * @throws SDKException when the SDK is not initialized, or chunks carry mixed formats.
     */
    @Deprecated("Use vad.openStream(format, options).", ReplaceWith("openStream(format, options)"))
    public fun detectStream(
        audio: Flow<AudioInput>,
        options: VadOptions? = null,
    ): Flow<VadEvent> =
        channelFlow {
            var stream: VadStream? = null
            var format: AudioFormatSpec? = null
            var forwarder: Job? = null
            try {
                audio.collect { chunk ->
                    if (stream == null) {
                        val opened = openStream(chunk.format, options)
                        format = chunk.format
                        stream = opened
                        forwarder = launch { opened.events.collect { send(it) } }
                    } else if (chunk.format != format) {
                        throw SDKException.invalidConfiguration(
                            "vad.detectStream requires every chunk to share one audio format.",
                        )
                    }
                    stream?.pushFrame(AudioFrame(chunk.bytes, chunk.bytes.size))
                }
                stream?.finish()
                forwarder?.join()
            } finally {
                withContext(NonCancellable) { stream?.close() }
            }
        }
}
