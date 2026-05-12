package com.runanywhere.sdk.public.extensions.VAD

import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.streamVAD
import com.runanywhere.sdk.public.types.RAVADResult
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlin.test.Test
import kotlin.test.assertEquals

class VADGeneratedStreamSurfaceTest {
    @Test
    fun `streamVAD surfaces per-chunk RAVADResult to match Swift`() {
        val result =
            RAVADResult(
                is_speech = true,
                confidence = 0.95f,
            )

        assertEquals(true, result.is_speech)
        assertEquals(0.95f, result.confidence)
    }
}

@Suppress("unused")
private fun vadStreamSurface(): Flow<RAVADResult> =
    RunAnywhere.streamVAD(emptyFlow())
