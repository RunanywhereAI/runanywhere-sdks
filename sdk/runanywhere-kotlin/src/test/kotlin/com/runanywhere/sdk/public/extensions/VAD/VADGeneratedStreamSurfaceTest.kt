package com.runanywhere.sdk.public.extensions.VAD

import ai.runanywhere.proto.v1.SpeechActivityEvent
import ai.runanywhere.proto.v1.SpeechActivityKind
import ai.runanywhere.proto.v1.VADStreamEvent
import ai.runanywhere.proto.v1.VADStreamEventKind
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.api.VadEvent
import com.runanywhere.sdk.public.api.decodeVadStreamEvent
import com.runanywhere.sdk.public.extensions.streamVAD
import com.runanywhere.sdk.public.types.RAVADResult
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs

class VADGeneratedStreamSurfaceTest {
    @Test
    fun `streamVAD surfaces per-chunk RAVADResult to match Swift`() {
        // `confidence` renamed `probability` (idl/vad_options.proto).
        val result =
            RAVADResult(
                is_speech = true,
                probability = 0.95f,
            )

        assertEquals(true, result.is_speech)
        assertEquals(0.95f, result.probability)
    }

    @Test
    fun `commons SPEECH_ACTIVITY onset and offset carry segment timestamps`() {
        val started =
            decodeVadStreamEvent(
                VADStreamEvent(
                    kind = VADStreamEventKind.VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY,
                    activity =
                        SpeechActivityEvent(
                            event_type = SpeechActivityKind.SPEECH_ACTIVITY_KIND_SPEECH_STARTED,
                            audio_start_ms = 16L,
                            segment_id = "a",
                        ),
                ).encode(),
            ).single()
        val ended =
            decodeVadStreamEvent(
                VADStreamEvent(
                    kind = VADStreamEventKind.VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY,
                    activity =
                        SpeechActivityEvent(
                            event_type = SpeechActivityKind.SPEECH_ACTIVITY_KIND_SPEECH_ENDED,
                            audio_start_ms = 16L,
                            audio_end_ms = 512L,
                            segment_id = "a",
                        ),
                ).encode(),
            ).single()

        assertIs<VadEvent.SpeechStarted>(started)
        assertEquals(16L, started.timestampMs)
        assertIs<VadEvent.SpeechEnded>(ended)
        assertEquals(512L, ended.timestampMs)
    }
}

@Suppress("unused")
private fun vadStreamSurface(): Flow<RAVADResult> =
    RunAnywhere.streamVAD(emptyFlow())
