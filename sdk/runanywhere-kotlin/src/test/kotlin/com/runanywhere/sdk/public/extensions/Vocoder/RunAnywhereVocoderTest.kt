package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.CurrentModelResult
import ai.runanywhere.proto.v1.ErrorCategory
import ai.runanywhere.proto.v1.ErrorCode
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.SDKComponent
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.defaultFramework
import com.runanywhere.sdk.public.extensions.Models.displayName
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull

class RunAnywhereVocoderTest {
    @Test
    fun `public surface accepts ergonomic float32 tensors`() {
        val operation: suspend (RunAnywhere, VocoderRequest) -> VocoderResult =
            { sdk, request -> sdk.vocode(request) }
        val request =
            VocoderRequest(
                melSpectrogram = floatArrayOf(0f, 0.25f, -0.5f, 1f),
                batchSize = 1,
                melBinCount = 2,
                frameCount = 2,
            )

        assertNotNull(operation)
        assertEquals(4, request.melSpectrogram.size)
    }

    @Test
    fun `missing lifecycle model fails before vocoder inference`() {
        val error =
            assertFailsWith<SDKException> {
                requireVocoderModelLoaded(CurrentModelResult(found = false))
            }

        assertEquals(ErrorCode.ERROR_CODE_MODEL_NOT_LOADED, error.code)
        assertEquals(ErrorCategory.ERROR_CATEGORY_COMPONENT, error.category)
        assertEquals("Vocoder model not loaded", error.message)
    }

    @Test
    fun `malformed loaded lifecycle snapshot fails closed`() {
        val error =
            assertFailsWith<SDKException> {
                requireVocoderModelLoaded(CurrentModelResult(found = true, model_id = ""))
            }

        assertEquals(ErrorCode.ERROR_CODE_PROCESSING_FAILED, error.code)
        assertEquals(ErrorCategory.ERROR_CATEGORY_INTERNAL, error.category)
    }

    @Test
    fun `loaded lifecycle model returns its exact id`() {
        assertEquals(
            "bigvgan",
            requireVocoderModelLoaded(CurrentModelResult(found = true, model_id = "bigvgan")),
        )
    }

    @Test
    fun `vocoder lifecycle metadata maps to ONNX`() {
        assertEquals("Vocoder", SDKComponent.SDK_COMPONENT_VOCODER.displayName)
        assertEquals(
            InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
            ModelCategory.MODEL_CATEGORY_VOCODER.defaultFramework,
        )
    }
}
