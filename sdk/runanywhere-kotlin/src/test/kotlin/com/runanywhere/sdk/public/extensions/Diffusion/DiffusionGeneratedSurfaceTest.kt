package com.runanywhere.sdk.public.extensions.Diffusion

import ai.runanywhere.proto.v1.DiffusionGenerationOptions
import ai.runanywhere.proto.v1.DiffusionMode
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.inpaint
import kotlin.test.Test
import kotlin.test.assertEquals

class DiffusionGeneratedSurfaceTest {
    @Test
    fun `generated inpainting fields remain on the public diffusion carrier`() {
        val options =
            DiffusionGenerationOptions(
                prompt = "remove object",
                mode = DiffusionMode.DIFFUSION_MODE_INPAINTING,
            )

        assertEquals(DiffusionMode.DIFFUSION_MODE_INPAINTING, options.mode)
    }
}

@Suppress("unused")
private suspend fun inpaintSurface(image: ByteArray, mask: ByteArray) =
    RunAnywhere.inpaint(inputImage = image, maskImage = mask)
