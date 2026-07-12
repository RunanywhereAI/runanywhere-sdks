package com.runanywhere.runanywhereai

import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelInfo
import ai.runanywhere.proto.v1.ModelSource
import com.runanywhere.runanywhereai.data.ModelCatalog
import com.runanywhere.runanywhereai.data.isVisibleForNativeNpuCatalog
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ModelCatalogTest {
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
