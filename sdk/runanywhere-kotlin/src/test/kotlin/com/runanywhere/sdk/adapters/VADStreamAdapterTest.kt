package com.runanywhere.sdk.adapters

import ai.runanywhere.proto.v1.SpeechActivityEvent
import ai.runanywhere.proto.v1.SpeechActivityKind
import ai.runanywhere.proto.v1.VADStreamEvent
import ai.runanywhere.proto.v1.VADStreamEventKind
import com.runanywhere.sdk.public.api.VadEvent
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs

class VADStreamAdapterTest {
    @Test
    fun `adapter forwards SPEECH_ACTIVITY onset without local edge synthesis`() {
        val events =
            VADStreamAdapter.decode(
                VADStreamEvent(
                    kind = VADStreamEventKind.VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY,
                    activity =
                        SpeechActivityEvent(
                            event_type = SpeechActivityKind.SPEECH_ACTIVITY_KIND_SPEECH_STARTED,
                            audio_start_ms = 80L,
                            segment_id = "seg",
                        ),
                ).encode(),
            )

        val started = assertIs<VadEvent.SpeechStarted>(events.single())
        assertEquals(80L, started.timestampMs)
    }
}
