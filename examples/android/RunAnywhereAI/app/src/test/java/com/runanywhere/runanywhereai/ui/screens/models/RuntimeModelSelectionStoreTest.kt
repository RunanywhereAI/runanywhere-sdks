package com.runanywhere.runanywhereai.ui.screens.models

import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RuntimeModelSelectionStoreTest {
    @Test
    fun `new lifecycle snapshot replaces stale screen snapshot`() {
        val store = RuntimeModelSelectionStore()

        store.publish(ModelSelectionContext.LLM, snapshot("model-a"))
        assertEquals("model-a", store.snapshot(ModelSelectionContext.LLM)?.id)

        store.publish(ModelSelectionContext.LLM, snapshot("model-b"))
        assertEquals("model-b", store.snapshot(ModelSelectionContext.LLM)?.id)
    }

    @Test
    fun `runtime modalities remain independently scoped`() {
        val store = RuntimeModelSelectionStore()

        store.publish(ModelSelectionContext.STT, snapshot("whisper"))
        store.publish(ModelSelectionContext.TTS, snapshot("kokoro"))
        store.publish(ModelSelectionContext.STT, null)

        assertNull(store.snapshot(ModelSelectionContext.STT))
        assertEquals("kokoro", store.snapshot(ModelSelectionContext.TTS)?.id)
    }

    @Test
    fun `vision checks both native lifecycle aliases and rag is reference selected`() {
        assertEquals(
            listOf(
                ModelCategory.MODEL_CATEGORY_MULTIMODAL,
                ModelCategory.MODEL_CATEGORY_VISION,
            ),
            ModelSelectionContext.VLM.lifecycleCategories,
        )
        assertEquals(emptyList<ModelCategory>(), ModelSelectionContext.RAG_EMBEDDING.lifecycleCategories)
        assertEquals(emptyList<ModelCategory>(), ModelSelectionContext.RAG_LLM.lifecycleCategories)
    }

    private fun snapshot(id: String) = RuntimeModelSnapshot(
        id = id,
        model = ModelInfo(
            id = id,
            name = id,
            category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
            framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        ),
        category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
        framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    )
}
