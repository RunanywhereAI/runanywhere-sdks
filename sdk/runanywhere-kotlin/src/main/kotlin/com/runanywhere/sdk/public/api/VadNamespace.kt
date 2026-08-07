/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public v4 surface: `RunAnywhere.vad`.
 */

package com.runanywhere.sdk.public.api

import com.runanywhere.sdk.foundation.errors.SDKException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicBoolean

private val vadStreamScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

/**
 * Live VAD push stream backing `vad.openStream`. Each pushed frame is
 * processed immediately against one persistent detector, so speech
 * transitions are reported as they happen rather than buffered.
 */
private class KotlinVadStream(
    private val format: AudioFormatSpec,
    options: VadOptions?,
) : VadStream {
    private val inbox = Channel<AudioFrame>(Channel.UNLIMITED)
    private val outbox = Channel<VadEvent>(Channel.UNLIMITED)
    private val closed = AtomicBoolean(false)
    private var speaking = false

    override val events: Flow<VadEvent> = outbox.receiveAsFlow()

    init {
        vadStreamScope.launch {
            try {
                for (frame in inbox) {
                    val bytes =
                        when (format.encoding) {
                            AudioEncoding.PCM16 ->
                                AudioInput.pcm16(frame.samples, format.sampleRate, format.channels).normalizedBytes()
                            AudioEncoding.FLOAT32, AudioEncoding.CONTAINER -> frame.samples
                        }
                    val verdict = legacyDetectVoiceActivity(bytes, options.orDefault().toProto()).toVadResult()
                    when {
                        verdict.isSpeech && !speaking -> {
                            speaking = true
                            outbox.trySend(VadEvent.SpeechStarted(frame.timestampMs))
                        }
                        !verdict.isSpeech && speaking -> {
                            speaking = false
                            outbox.trySend(VadEvent.SpeechEnded(frame.timestampMs))
                        }
                    }
                    outbox.trySend(VadEvent.Activity(verdict.isSpeech, verdict.probability, frame.timestampMs))
                }
                outbox.trySend(VadEvent.Completed)
            } catch (error: SDKException) {
                outbox.trySend(VadEvent.Failed(error))
            } finally {
                outbox.close()
            }
        }
    }

    override fun pushFrame(frame: AudioFrame) {
        if (closed.get()) return
        inbox.trySend(frame)
    }

    override fun flush() {
        // Every pushed frame is already processed as it arrives; nothing buffered to flush.
    }

    override fun finish() {
        inbox.close()
    }

    override suspend fun close() {
        if (!closed.compareAndSet(false, true)) return
        inbox.close()
        outbox.close()
    }
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
     * Decide whether [audio] contains speech.
     *
     * @throws SDKException when the buffer is empty or the SDK is not initialized.
     */
    public suspend fun detect(audio: AudioInput, options: VadOptions? = null): VadResult =
        legacyDetectVoiceActivity(audio.normalizedBytes(), options.orDefault().toProto()).toVadResult()

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
        return KotlinVadStream(format, options)
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
        flow {
            var stream: VadStream? = null
            var format: AudioFormatSpec? = null
            audio.collect { chunk ->
                if (format == null) {
                    format = chunk.format
                    stream = openStream(chunk.format, options)
                } else if (chunk.format != format) {
                    throw SDKException.invalidConfiguration(
                        "vad.detectStream requires every chunk to share one audio format.",
                    )
                }
                stream?.pushFrame(AudioFrame(chunk.bytes, chunk.bytes.size))
            }
            val live = stream ?: return@flow
            live.finish()
            emitAll(live.events)
        }
}
