package com.runanywhere.runanywhereai.ui.screens.models

import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelInfo
import org.junit.Assert.assertEquals
import org.junit.Test

class ModelRecommendationTest {
    @Test
    fun v81FilteredCatalogRecommendsInternVlInsteadOfCpuVisionFallback() {
        val models = listOf(
            model(
                id = "internvl3_5_1b",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
                bytes = 3_067_933_894L,
            ),
            model(
                id = "qwen2-vl-2b-instruct-q4_k_m",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
                bytes = 2_000_000_000L,
            ),
        )

        val recommendation = ModelRecommendation.recommend(
            tier = HardwareTier.HIGH_END,
            hasNpu = true,
            models = models,
        )

        assertEquals("internvl3_5_1b", recommendation.vlm?.id)
    }

    private fun model(
        id: String,
        framework: InferenceFramework,
        bytes: Long,
    ): ModelInfo = ModelInfo(
        id = id,
        name = id,
        framework = framework,
        category = ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        download_size_bytes = bytes,
    )
}
