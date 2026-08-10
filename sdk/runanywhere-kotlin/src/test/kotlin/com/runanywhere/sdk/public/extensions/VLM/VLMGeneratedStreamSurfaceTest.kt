package com.runanywhere.sdk.public.extensions.VLM

import ai.runanywhere.proto.v1.VLMImage
import ai.runanywhere.proto.v1.VLMStreamEvent
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.processImageStream
import kotlinx.coroutines.flow.Flow
import kotlin.test.Test
import kotlin.test.assertEquals

class VLMGeneratedStreamSurfaceTest {
    @Test
    fun `generated typed VLMStreamEvent is the public VLM stream surface`() {
        val event = VLMStreamEvent()

        assertEquals(0L, event.timestamp_us)
    }
}

// `RAVLMGenerationOptions` is deleted outright (idl/vlm_options.proto); the
// (image, options) overload now takes (image, prompt, options:
// RALLMGenerationOptions = defaults()).
@Suppress("unused")
private fun vlmStreamSurface(image: VLMImage): Flow<VLMStreamEvent> =
    RunAnywhere.processImageStream(image, "describe this image")
