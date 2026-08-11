package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.CurrentModelResult
import ai.runanywhere.proto.v1.ErrorCode
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.SDKComponent
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.extensions.Models.defaultFramework
import com.runanywhere.sdk.public.extensions.Models.displayName
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class RunAnywhereSegmentationTest {
    @Test
    fun `missing lifecycle model fails before segmentation inference`() {
        val error =
            assertFailsWith<SDKException> {
                requireSegmentationModelLoaded(CurrentModelResult(found = false))
            }

        assertEquals(ErrorCode.ERROR_CODE_MODEL_NOT_LOADED, error.code)
    }

    @Test
    fun `semantic segmentation lifecycle metadata maps to ONNX`() {
        assertEquals(
            "Semantic Segmentation",
            SDKComponent.SDK_COMPONENT_SEMANTIC_SEGMENTATION.displayName,
        )
        assertEquals(
            InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
            ModelCategory.MODEL_CATEGORY_SEMANTIC_SEGMENTATION.defaultFramework,
        )
    }
}
