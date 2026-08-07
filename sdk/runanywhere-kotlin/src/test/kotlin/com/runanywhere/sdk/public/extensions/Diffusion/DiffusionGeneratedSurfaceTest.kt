package com.runanywhere.sdk.public.extensions.Diffusion

import ai.runanywhere.proto.v1.DiffusionGenerationOptions
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.inpaint
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * `DiffusionMode`/`DiffusionGenerationOptions.mode` are deleted outright
 * (idl/diffusion.proto): mode is inferred, never declared -- no image =
 * text-to-image, image = image-to-image, image + mask_image = inpainting.
 * `input_image`/`input_image_media_type` were renamed `image`/
 * `image_media_type`; `report_intermediate_images` is deleted too.
 */
class DiffusionGeneratedSurfaceTest {
    @Test
    fun `inpainting is inferred from image plus mask_image presence, not a declared mode`() {
        val options =
            DiffusionGenerationOptions(
                prompt = "remove object",
                image = okio.ByteString.of(1, 2, 3),
                mask_image = okio.ByteString.of(4, 5, 6),
            )

        assertEquals("remove object", options.prompt)
        assertTrue(options.image != null && options.mask_image != null)
    }
}

@Suppress("unused")
private suspend fun inpaintSurface(image: ByteArray, mask: ByteArray) =
    RunAnywhere.inpaint(inputImage = image, maskImage = mask)
