package com.runanywhere.sdk.public.extensions.VAD

import ai.runanywhere.proto.v1.VADStreamEvent
import ai.runanywhere.proto.v1.VADStreamEventKind
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.streamVAD
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlin.test.Test
import kotlin.test.assertEquals

class VADGeneratedStreamSurfaceTest {
    @Test
    fun `generated VAD stream event remains the public stream surface`() {
        val event =
            VADStreamEvent(
                kind = VADStreamEventKind.VAD_STREAM_EVENT_KIND_STARTED,
            )

        assertEquals(VADStreamEventKind.VAD_STREAM_EVENT_KIND_STARTED, event.kind)
    }
}

@Suppress("unused")
private fun vadStreamSurface(): Flow<VADStreamEvent> =
    RunAnywhere.streamVAD(emptyFlow())
