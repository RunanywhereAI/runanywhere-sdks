/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Map commons `VADStreamEvent` payloads (rac_vad_stream_*) onto the public
 * `VadEvent` surface. Endpointing lives in commons; this file only decodes
 * SPEECH_ACTIVITY onset/offset + FRAME/ERROR envelopes.
 */

package com.runanywhere.sdk.public.api

import ai.runanywhere.proto.v1.SpeechActivityKind
import ai.runanywhere.proto.v1.VADStreamEvent
import ai.runanywhere.proto.v1.VADStreamEventKind
import com.runanywhere.sdk.foundation.errors.SDKException

/** Decode one commons `VADStreamEvent` into zero or more public events. */
internal fun decodeVadStreamEvent(raw: ByteArray): List<VadEvent> {
    val event = VADStreamEvent.ADAPTER.decode(raw)
    return when (event.kind) {
        VADStreamEventKind.VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY -> {
            val activity = event.activity ?: return emptyList()
            when (activity.event_type) {
                SpeechActivityKind.SPEECH_ACTIVITY_KIND_SPEECH_STARTED ->
                    listOf(VadEvent.SpeechStarted(timestampMs = activity.audio_start_ms))
                SpeechActivityKind.SPEECH_ACTIVITY_KIND_SPEECH_ENDED ->
                    listOf(VadEvent.SpeechEnded(timestampMs = activity.audio_end_ms))
                else -> emptyList()
            }
        }
        VADStreamEventKind.VAD_STREAM_EVENT_KIND_FRAME -> {
            val result = event.result ?: return emptyList()
            val isSpeech = result.is_speech
            listOf(
                VadEvent.Activity(
                    isSpeech = isSpeech,
                    probability =
                        when {
                            result.probability != 0f -> result.probability
                            isSpeech -> 1f
                            else -> 0f
                        },
                    timestampMs = result.timestamp_ms,
                ),
            )
        }
        VADStreamEventKind.VAD_STREAM_EVENT_KIND_ERROR ->
            listOf(
                VadEvent.Failed(
                    error =
                        event.error?.let { SDKException(it) }
                            ?: SDKException.operation("vad stream error"),
                ),
            )
        else -> emptyList()
    }
}

/**
 * Collects SPEECH_ACTIVITY onset/offset pairs into [Segment]s and tracks the
 * peak FRAME probability. Used by one-buffer `vad.detect`.
 */
internal class VadSegmentAccumulator {
    private val segments = mutableListOf<Segment>()
    private var openStartMs: Long? = null
    var maxProbability: Float = 0f
        private set

    fun onEvent(event: VadEvent) {
        when (event) {
            is VadEvent.SpeechStarted -> openStartMs = event.timestampMs ?: 0L
            is VadEvent.SpeechEnded -> {
                val start = openStartMs ?: return
                val end = maxOf(event.timestampMs ?: start, start)
                segments.add(Segment(startMs = start, endMs = end))
                openStartMs = null
            }
            is VadEvent.Activity -> maxProbability = maxOf(maxProbability, event.probability)
            is VadEvent.Failed -> throw event.error
            VadEvent.Completed -> Unit
        }
    }

    fun toResult(): VadResult {
        val speech = segments.isNotEmpty()
        return VadResult(
            isSpeech = speech,
            probability =
                when {
                    speech && maxProbability <= 0f -> 1f
                    else -> maxProbability
                },
            segments = segments.toList(),
        )
    }
}
