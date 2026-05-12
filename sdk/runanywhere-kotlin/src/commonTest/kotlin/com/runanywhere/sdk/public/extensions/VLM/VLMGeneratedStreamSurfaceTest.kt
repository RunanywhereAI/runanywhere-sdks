package com.runanywhere.sdk.public.extensions.VLM

import ai.runanywhere.proto.v1.SDKEvent
import ai.runanywhere.proto.v1.VLMImage
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.processImageStream
import com.runanywhere.sdk.public.types.RAVLMGenerationOptions
import kotlinx.coroutines.flow.Flow
import kotlin.test.Test
import kotlin.test.assertEquals

class VLMGeneratedStreamSurfaceTest {
    @Test
    fun `generated SDK event remains the public VLM stream surface`() {
        val event = SDKEvent()

        assertEquals("", event.id)
    }
}

@Suppress("unused")
private fun vlmStreamSurface(image: VLMImage): Flow<SDKEvent> =
    RunAnywhere.processImageStream(image, RAVLMGenerationOptions())
