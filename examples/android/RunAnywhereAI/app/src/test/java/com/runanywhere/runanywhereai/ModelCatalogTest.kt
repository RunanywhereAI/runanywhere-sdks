package com.runanywhere.runanywhereai

import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelInfo
import ai.runanywhere.proto.v1.ModelSource
import com.runanywhere.runanywhereai.data.ModelCatalog
import com.runanywhere.runanywhereai.data.MultiFileModel
import com.runanywhere.runanywhereai.data.SingleFileModel
import com.runanywhere.runanywhereai.data.isVisibleForNativeNpuCatalog
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ModelCatalogTest {
    @Test
    fun portableNvidiaRowsUsePinnedReviewedArtifacts() {
        val byId = ModelCatalog.models.associateBy { it.id }

        val mini = byId.getValue("nemotron-mini-4b-instruct-q4_k_m") as SingleFileModel
        assertEquals(InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP, mini.framework)
        assertEquals(ModelCategory.MODEL_CATEGORY_LANGUAGE, mini.category)
        assertTrue(mini.url.contains("/resolve/fb49cde090c86092d89905bea2ffc41c23c2615e/"))

        val embedding = byId.getValue("nemotron-3-embed-1b-q4_k_m") as SingleFileModel
        assertEquals(InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP, embedding.framework)
        assertEquals(ModelCategory.MODEL_CATEGORY_EMBEDDING, embedding.category)
        assertEquals(749_352_096L, embedding.memoryBytes)
        assertTrue(embedding.url.contains("/resolve/06df1fde6f7009c91f6cc3cd520081921929a678/"))

        val embeddingV2 = byId.getValue("llama-nemotron-embed-1b-v2-q4_k_m") as SingleFileModel
        assertEquals(InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP, embeddingV2.framework)
        assertEquals(ModelCategory.MODEL_CATEGORY_EMBEDDING, embeddingV2.category)
        assertEquals(807_690_624L, embeddingV2.memoryBytes)
        assertTrue(embeddingV2.url.contains("/resolve/bf7c9832b1d76f86777379e58b7b74805ee58006/"))
    }

    @Test
    fun nvidiaSherpaRowsUseExactPinnedMultiFileBundles() {
        val byId = ModelCatalog.models.associateBy { it.id }
        val expected = mapOf(
            "sherpa-nemo-parakeet-tdt-0.6b-v2-int8" to
                Pair("1ab9323565ddb038682214b292f588070a538ce2", 661_190_513L),
            "sherpa-nemo-parakeet-tdt-0.6b-v3-int8" to
                Pair("2bda32ec70b097a55adaa07d9a7173915b43cc78", 670_478_772L),
            "sherpa-nemo-canary-180m-flash-int8" to
                Pair("9077164e0d3dd1d5353743e89ceaa1d3a770838c", 207_170_046L),
        )

        expected.forEach { (id, pinAndSize) ->
            val model = byId.getValue(id) as MultiFileModel
            assertEquals(InferenceFramework.INFERENCE_FRAMEWORK_SHERPA, model.framework)
            assertEquals(ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION, model.category)
            assertEquals(pinAndSize.second, model.memoryBytes)
            assertTrue(model.files.isNotEmpty())
            assertTrue(model.files.all { it.url.contains("/resolve/${pinAndSize.first}/") })
            assertTrue(model.files.any { it.filename == "tokens.txt" })
        }
    }

    @Test
    fun npuCatalogMetadataIsPublishableAndUnique() {
        val rows = ModelCatalog.npuCatalog
        assertEquals(rows.size, rows.map { it.id }.distinct().size)
        rows.forEach { model ->
            assertTrue(model.id.isNotBlank())
            assertTrue(model.name.isNotBlank())
            assertTrue(model.url.startsWith("https://"))
            assertTrue(model.memoryBytes > 0)
            assertEquals(InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT, model.framework)
        }
    }

    @Test
    fun qhexrtRequestKeepsTheAppOwnedDefinition() {
        ModelCatalog.npuCatalog.forEach { model ->
            val request = model.toQHexRTRegistrationRequest()
            assertEquals(model.id, request.id)
            assertEquals(model.name, request.name)
            assertEquals(model.url, request.url)
            assertEquals(model.framework, request.framework)
            assertEquals(model.category, request.category)
            assertEquals(ModelSource.MODEL_SOURCE_REMOTE, request.source)
            assertEquals(model.memoryBytes, request.memory_required_bytes)
            assertEquals(model.memoryBytes, request.download_size_bytes)
            assertEquals(model.contextLength, request.context_length)
            assertEquals(model.supportsThinking, request.supports_thinking)
            assertEquals(model.supportsLora, request.supports_lora)
            assertEquals("Qualcomm Hexagon NPU model bundle.", request.description)
        }
    }

    @Test
    fun toolRelevantNpuModelsPublishTheirContextCapabilities() {
        val byId = ModelCatalog.npuCatalog.associateBy { it.id }

        assertEquals(512, byId.getValue("lfm2_5_230m").contextLength)
        assertEquals(2_048, byId.getValue("lfm2_5_350m").contextLength)
        assertEquals(1_024, byId.getValue("qwen3_5_0_8b").contextLength)
        assertEquals(1_024, byId.getValue("qwen3_5_2b").contextLength)
        assertEquals(1_024, byId.getValue("qwen3_5_4b").contextLength)
        assertEquals(512, byId.getValue("internvl3_5_1b").contextLength)
    }

    @Test
    fun canaryQwenUsesTheValidatedV81AsrManifest() {
        val model = ModelCatalog.npuCatalog.single { it.id == "canary_qwen_2_5b" }

        assertEquals(
            "https://huggingface.co/runanywhere/canary_qwen_2.5b_HNPU/v81/canary-qwen-2.5b.json",
            model.url,
        )
        assertEquals(ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION, model.category)
    }

    @Test
    fun pickerShowsOnlyQhexrtRowsReturnedByNativeRegistration() {
        val cpu = ModelInfo(
            id = "cpu-model",
            framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        )
        val npu = ModelInfo(
            id = "npu-model",
            framework = InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
        )

        assertTrue(cpu.isVisibleForNativeNpuCatalog(emptySet()))
        assertFalse(npu.isVisibleForNativeNpuCatalog(emptySet()))
        assertTrue(npu.isVisibleForNativeNpuCatalog(setOf(npu.id)))
    }

}
