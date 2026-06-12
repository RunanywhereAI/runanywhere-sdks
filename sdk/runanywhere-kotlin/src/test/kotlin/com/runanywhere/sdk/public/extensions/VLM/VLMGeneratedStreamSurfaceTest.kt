package com.runanywhere.sdk.public.extensions.VLM

import ai.runanywhere.proto.v1.VLMImage
import ai.runanywhere.proto.v1.VLMStreamEvent
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.processImageStream
import com.runanywhere.sdk.public.types.RAVLMGenerationOptions
import kotlinx.coroutines.flow.Flow
import kotlin.test.Test
import kotlin.test.assertEquals

class VLMGeneratedStreamSurfaceTest {
    @Test
    fun `generated typed VLMStreamEvent is the public VLM stream surface`() {
        val event = VLMStreamEvent()

        assertEquals(0L, event.seq)
    }
}

@Suppress("unused")
private fun vlmStreamSurface(image: VLMImage): Flow<VLMStreamEvent> =
    RunAnywhere.processImageStream(image, RAVLMGenerationOptions())
