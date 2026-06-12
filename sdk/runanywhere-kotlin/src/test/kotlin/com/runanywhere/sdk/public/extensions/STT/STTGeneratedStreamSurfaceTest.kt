package com.runanywhere.sdk.public.extensions.STT

import ai.runanywhere.proto.v1.STTStreamEvent
import ai.runanywhere.proto.v1.STTStreamEventKind
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.RASTTPartialResult
import com.runanywhere.sdk.public.extensions.transcribeStream
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlin.test.Test
import kotlin.test.assertEquals

class STTGeneratedStreamSurfaceTest {
    @Test
    fun `generated STT stream event remains the public stream surface`() {
        val event =
            STTStreamEvent(
                kind = STTStreamEventKind.STT_STREAM_EVENT_KIND_STARTED,
            )

        assertEquals(STTStreamEventKind.STT_STREAM_EVENT_KIND_STARTED, event.kind)
    }
}

@Suppress("unused")
private fun sttStreamSurface(): Flow<RASTTPartialResult> =
    RunAnywhere.transcribeStream(audio = emptyFlow(), options = null)
