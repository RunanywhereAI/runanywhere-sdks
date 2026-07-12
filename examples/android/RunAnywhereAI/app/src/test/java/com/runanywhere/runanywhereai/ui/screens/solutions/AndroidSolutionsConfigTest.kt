package com.runanywhere.runanywhereai.ui.screens.solutions

import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelInfo
import com.runanywhere.runanywhereai.data.ModelCatalog
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidSolutionsConfigTest {
    @Test
    fun preferredDownloadedQHexRTModelsReplaceEveryCanonicalCpuModel() {
        val models = listOf(
            qhex(AndroidSolutionsConfig.PREFERRED_LLM_ID, ModelCategory.MODEL_CATEGORY_LANGUAGE),
            qhex(AndroidSolutionsConfig.PREFERRED_STT_ID, ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION),
            qhex(AndroidSolutionsConfig.PREFERRED_TTS_ID, ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS),
            qhex(AndroidSolutionsConfig.PREFERRED_EMBEDDING_ID, ModelCategory.MODEL_CATEGORY_EMBEDDING),
            model(
                id = AndroidSolutionsConfig.VAD_ID,
                category = ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
                framework = InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
            ),
            model(
                id = "smollm2-360m-q8_0",
                category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
                framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
            ),
            model(
                id = "sherpa-onnx-whisper-tiny.en",
                category = ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
                framework = InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
            ),
            model(
                id = "vits-piper-en_US-lessac-medium",
                category = ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
                framework = InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
            ),
            model(
                id = "all-minilm-l6-v2",
                category = ModelCategory.MODEL_CATEGORY_EMBEDDING,
                framework = InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
            ),
        )

        val resolved = AndroidSolutionsConfig.resolve(models)

        assertTrue(resolved.voice.isReady)
        assertTrue(resolved.rag.isReady)
        assertEquals(
            listOf("qwen3_5_0_8b", "whisper_base", "kokoro_en", "silero-vad"),
            resolved.voice.requiredModelIds,
        )
        assertEquals(
            listOf("embeddinggemma_300m", "qwen3_5_0_8b"),
            resolved.rag.requiredModelIds,
        )
        val executionYamls = listOfNotNull(resolved.voice.yaml, resolved.rag.yaml)
        assertEquals(2, executionYamls.size)
        executionYamls.forEach { yaml ->
            canonicalCpuIds.forEach { oldId -> assertFalse("$oldId leaked into:\n$yaml", oldId in yaml) }
        }
        assertTrue("llm_model_id: \"qwen3_5_0_8b\"" in requireNotNull(resolved.voice.yaml))
        assertTrue("embed_model_id: \"embeddinggemma_300m\"" in requireNotNull(resolved.rag.yaml))
    }

    @Test
    fun downloadedRoleFallbacksWinOverUndownloadedRecommendations() {
        val models = listOf(
            qhex(AndroidSolutionsConfig.PREFERRED_LLM_ID, ModelCategory.MODEL_CATEGORY_LANGUAGE, false),
            qhex("lfm2_5_230m", ModelCategory.MODEL_CATEGORY_LANGUAGE),
            qhex(AndroidSolutionsConfig.PREFERRED_STT_ID, ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION, false),
            qhex("moonshine_tiny", ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION),
            qhex(AndroidSolutionsConfig.PREFERRED_TTS_ID, ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS, false),
            qhex("melotts_en", ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS),
            qhex(AndroidSolutionsConfig.PREFERRED_EMBEDDING_ID, ModelCategory.MODEL_CATEGORY_EMBEDDING, false),
            qhex("nv_embedqa_1b", ModelCategory.MODEL_CATEGORY_EMBEDDING),
            model(
                id = AndroidSolutionsConfig.VAD_ID,
                category = ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
                framework = InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
            ),
        )

        val resolved = AndroidSolutionsConfig.resolve(models)

        assertEquals(
            listOf("lfm2_5_230m", "moonshine_tiny", "melotts_en", "silero-vad"),
            resolved.voice.requiredModelIds,
        )
        assertEquals(listOf("nv_embedqa_1b", "lfm2_5_230m"), resolved.rag.requiredModelIds)
        assertTrue(resolved.voice.isReady)
        assertTrue(resolved.rag.isReady)
    }

    @Test
    fun readinessReportsResolvedCatalogIdsInsteadOfCanonicalCpuIds() {
        val models = listOf(
            qhex(AndroidSolutionsConfig.PREFERRED_LLM_ID, ModelCategory.MODEL_CATEGORY_LANGUAGE, false),
            qhex(AndroidSolutionsConfig.PREFERRED_STT_ID, ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION, false),
            qhex(AndroidSolutionsConfig.PREFERRED_TTS_ID, ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS, false),
            qhex(AndroidSolutionsConfig.PREFERRED_EMBEDDING_ID, ModelCategory.MODEL_CATEGORY_EMBEDDING, false),
            model(
                id = AndroidSolutionsConfig.VAD_ID,
                category = ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
                framework = InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
                downloaded = false,
            ),
        )

        val resolved = AndroidSolutionsConfig.resolve(models)

        assertFalse(resolved.voice.isReady)
        assertFalse(resolved.rag.isReady)
        assertEquals(
            listOf("qwen3_5_0_8b", "whisper_base", "kokoro_en", "silero-vad"),
            resolved.voice.missingModels,
        )
        assertEquals(listOf("embeddinggemma_300m", "qwen3_5_0_8b"), resolved.rag.missingModels)
        (resolved.voice.missingModels + resolved.rag.missingModels).forEach { missing ->
            canonicalCpuIds.forEach { oldId -> assertFalse(oldId in missing) }
        }
    }

    @Test
    fun preferredIdsRemainQHexRTRowsInTheAndroidCatalog() {
        val byId = ModelCatalog.npuCatalog.associateBy { it.id }
        val expected = mapOf(
            AndroidSolutionsConfig.PREFERRED_LLM_ID to ModelCategory.MODEL_CATEGORY_LANGUAGE,
            AndroidSolutionsConfig.PREFERRED_STT_ID to ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
            AndroidSolutionsConfig.PREFERRED_TTS_ID to ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
            AndroidSolutionsConfig.PREFERRED_EMBEDDING_ID to ModelCategory.MODEL_CATEGORY_EMBEDDING,
        )

        expected.forEach { (id, category) ->
            val model = byId[id]
            assertNotNull("$id is absent from the Android QHexRT catalog", model)
            assertEquals(InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT, model?.framework)
            assertEquals(category, model?.category)
        }
    }

    private fun qhex(
        id: String,
        category: ModelCategory,
        downloaded: Boolean = true,
    ): ModelInfo = model(id, category, InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT, downloaded)

    private fun model(
        id: String,
        category: ModelCategory,
        framework: InferenceFramework,
        downloaded: Boolean = true,
    ): ModelInfo = ModelInfo(
        id = id,
        name = id,
        category = category,
        framework = framework,
        is_downloaded = downloaded,
    )

    private val canonicalCpuIds = listOf(
        "smollm2-360m-q8_0",
        "sherpa-onnx-whisper-tiny.en",
        "vits-piper-en_US-lessac-medium",
        "all-minilm-l6-v2",
    )
}
