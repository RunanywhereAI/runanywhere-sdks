package com.runanywhere.sdk.public.api

import ai.runanywhere.proto.v1.SpeechActivityEvent
import ai.runanywhere.proto.v1.SpeechActivityKind
import ai.runanywhere.proto.v1.VADResult
import ai.runanywhere.proto.v1.VADStreamEvent
import ai.runanywhere.proto.v1.VADStreamEventKind
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue

/**
 * Focused coverage for commons `rac_vad_stream_*` SPEECH_ACTIVITY mapping —
 * onset/offset timestamps become public events and segment pairs. No local
 * isSpeech edge machine.
 */
class VadStreamMappingTest {
    @Test
    fun `SPEECH_ACTIVITY started maps audio_start_ms`() {
        val raw =
            VADStreamEvent(
                kind = VADStreamEventKind.VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY,
                activity =
                    SpeechActivityEvent(
                        event_type = SpeechActivityKind.SPEECH_ACTIVITY_KIND_SPEECH_STARTED,
                        audio_start_ms = 120L,
                        segment_id = "seg-1",
                    ),
            ).encode()

        val events = decodeVadStreamEvent(raw)
        assertEquals(1, events.size)
        val started = assertIs<VadEvent.SpeechStarted>(events.single())
        assertEquals(120L, started.timestampMs)
    }

    @Test
    fun `SPEECH_ACTIVITY ended maps audio_end_ms`() {
        val raw =
            VADStreamEvent(
                kind = VADStreamEventKind.VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY,
                activity =
                    SpeechActivityEvent(
                        event_type = SpeechActivityKind.SPEECH_ACTIVITY_KIND_SPEECH_ENDED,
                        audio_start_ms = 120L,
                        audio_end_ms = 980L,
                        segment_id = "seg-1",
                    ),
            ).encode()

        val events = decodeVadStreamEvent(raw)
        val ended = assertIs<VadEvent.SpeechEnded>(events.single())
        assertEquals(980L, ended.timestampMs)
    }

    @Test
    fun `accumulator builds segments from onset and offset`() {
        val accumulator = VadSegmentAccumulator()
        accumulator.onEvent(VadEvent.SpeechStarted(timestampMs = 40L))
        accumulator.onEvent(VadEvent.Activity(isSpeech = true, probability = 0.9f, timestampMs = 20L))
        accumulator.onEvent(VadEvent.SpeechEnded(timestampMs = 640L))

        val result = accumulator.toResult()
        assertTrue(result.isSpeech)
        assertEquals(0.9f, result.probability)
        assertEquals(listOf(Segment(startMs = 40L, endMs = 640L)), result.segments)
    }

    @Test
    fun `FRAME events never synthesize speech edges`() {
        val raw =
            VADStreamEvent(
                kind = VADStreamEventKind.VAD_STREAM_EVENT_KIND_FRAME,
                result = VADResult(is_speech = true, probability = 0.8f, duration_ms = 30),
            ).encode()

        val events = decodeVadStreamEvent(raw)
        assertEquals(1, events.size)
        assertIs<VadEvent.Activity>(events.single())
    }

    @Test
    fun `ONGOING activity is ignored`() {
        val raw =
            VADStreamEvent(
                kind = VADStreamEventKind.VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY,
                activity =
                    SpeechActivityEvent(
                        event_type = SpeechActivityKind.SPEECH_ACTIVITY_KIND_ONGOING,
                        audio_start_ms = 10L,
                    ),
            ).encode()

        assertTrue(decodeVadStreamEvent(raw).isEmpty())
    }
}
