/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public v4 surface: `RunAnywhere.stt`.
 */

package com.runanywhere.sdk.public.api

import ai.runanywhere.proto.v1.STTOutput
import com.runanywhere.sdk.foundation.errors.SDKException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.consumeAsFlow
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.launch
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

private val sttStreamScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

/**
 * Live STT push stream backing `stt.openStream`.
 *
 * The native ABI exports no incremental push contract: frames are buffered
 * as they are pushed, and the native streaming pass runs once against the
 * buffered audio when [finish] is called. Partial/final events on [events]
 * come from that native pass; the stream never fabricates a `completed` it
 * did not see the backend report.
 */
private class KotlinSttStream(
    private val requestId: String,
    private val format: AudioFormatSpec,
    options: SttOptions?,
) : SttStream {
    private val frames = Channel<ByteArray>(Channel.UNLIMITED)
    private val outbox = Channel<TranscriptionEvent>(Channel.UNLIMITED)
    private val startedEmitted = AtomicBoolean(false)
    private val finished = AtomicBoolean(false)
    private val closed = AtomicBoolean(false)
    private var sequence = 0L

    override val events: Flow<TranscriptionEvent> = outbox.receiveAsFlow()

    init {
        sttStreamScope.launch {
            try {
                legacyTranscribeStream(frames.consumeAsFlow(), options.orDefault().toProto()).collect { partial ->
                    announceStarted()
                    if (partial.is_final) {
                        // `STTPartialResult` collapsed to `text`/`is_final`/`language`
                        // (idl/stt_options.proto): `final_output`/`confidence`/
                        // `audio_start_ms`/`audio_end_ms` no longer exist on it, so
                        // this synthesizes a terminal STTOutput from just `text`/
                        // `language`, mirroring Swift's `transcription(from:)`.
                        val synthesized =
                            STTOutput(
                                text = partial.text,
                                language = partial.language?.takeIf { it.isNotEmpty() },
                            )
                        outbox.trySend(
                            TranscriptionEvent.TranscriptFinal(requestId, sequence++, synthesized.toTranscription()),
                        )
                        outbox.trySend(TranscriptionEvent.Completed(requestId))
                    } else if (partial.text.isNotEmpty()) {
                        outbox.trySend(
                            TranscriptionEvent.Partial(
                                requestId = requestId,
                                sequence = sequence,
                                segmentId = "0",
                                revision = (sequence++).toInt(),
                                alternatives = listOf(TranscriptAlternative(partial.text)),
                            ),
                        )
                    }
                }
                // The native pass ended without a final/error envelope. Stop
                // silently rather than fabricating a successful `completed`.
            } catch (error: SDKException) {
                announceStarted()
                outbox.trySend(TranscriptionEvent.Failed(requestId, error))
            } finally {
                outbox.close()
            }
        }
    }

    private fun announceStarted() {
        if (startedEmitted.compareAndSet(false, true)) {
            outbox.trySend(TranscriptionEvent.Started(requestId))
        }
    }

    override fun pushFrame(frame: AudioFrame) {
        if (closed.get() || finished.get()) return
        val normalized =
            when (format.encoding) {
                AudioEncoding.PCM16 -> AudioInput.pcm16(frame.samples, format.sampleRate, format.channels).normalizedBytes()
                AudioEncoding.FLOAT32, AudioEncoding.CONTAINER -> frame.samples
            }
        frames.trySend(normalized)
    }

    override fun flush() {
        // No incremental partial ABI: nothing buffered client-side to flush.
    }

    override fun finish() {
        if (!finished.compareAndSet(false, true)) return
        frames.close()
    }

    override suspend fun close() {
        if (!closed.compareAndSet(false, true)) return
        frames.close()
        outbox.close()
    }
}

/**
 * Speech-to-text transcription.
 *
 * ```kotlin
 * val text = RunAnywhere.stt.transcribe(AudioInput.wav(recording)).text
 * println(text)
 * ```
 */
public class SttNamespace internal constructor() {
    /**
     * Transcribe a complete [audio] buffer.
     *
     * @throws SDKException when no speech-recognition model is loaded.
     */
    public suspend fun transcribe(audio: AudioInput, options: SttOptions? = null): Transcription =
        legacyTranscribe(audio.pcm16Bytes(), options.orDefault().toProto()).toTranscription()

    /**
     * Open a live transcription stream with one audio format established up front.
     *
     * @throws SDKException when [format] uses a container encoding — live
     *   streams take raw PCM only; use [transcribe] for containers.
     */
    public fun openStream(format: AudioFormatSpec, options: SttOptions? = null): SttStream {
        if (format.encoding == AudioEncoding.CONTAINER) {
            throw SDKException.invalidConfiguration(
                "stt.openStream needs raw PCM audio; container formats are batch-only — use stt.transcribe.",
            )
        }
        return KotlinSttStream(UUID.randomUUID().toString(), format, options)
    }

    /**
     * @deprecated Use [openStream]. Transcribe a live [audio] stream, emitting
     *   `started`, `partial`, and `transcriptFinal`/`completed`. Forwards into
     *   an [SttStream] when every chunk shares one format; mixed formats throw.
     * @throws SDKException when no speech-recognition model is loaded, or chunks
     *   carry mixed formats.
     */
    @Deprecated("Use stt.openStream(format, options).", ReplaceWith("openStream(format, options)"))
    public fun transcribeStream(
        audio: Flow<AudioInput>,
        options: SttOptions? = null,
    ): Flow<TranscriptionEvent> =
        flow {
            var stream: SttStream? = null
            var format: AudioFormatSpec? = null
            audio.collect { chunk ->
                if (format == null) {
                    format = chunk.format
                    if (format?.encoding == AudioEncoding.CONTAINER) {
                        throw SDKException.invalidConfiguration(
                            "stt.transcribeStream needs raw PCM chunks; decode container audio before streaming it.",
                        )
                    }
                    stream = openStream(chunk.format, options)
                } else if (chunk.format != format) {
                    throw SDKException.invalidConfiguration(
                        "stt.transcribeStream requires every chunk to share one audio format.",
                    )
                }
                stream?.pushFrame(AudioFrame(chunk.bytes, chunk.bytes.size))
            }
            val live = stream ?: return@flow
            live.finish()
            emitAll(live.events)
        }

    /** Readiness, model, and language coverage of the speech-recognition component. */
    public suspend fun state(): SttState = legacySttState().toSttState()
}
