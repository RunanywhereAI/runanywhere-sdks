package com.runanywhere.runanywhereai

import ai.runanywhere.proto.v1.HexagonArch
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelInfo
import ai.runanywhere.proto.v1.ModelSource
import com.runanywhere.runanywhereai.data.ModelCatalog
import com.runanywhere.runanywhereai.data.PRIVATE_HF_MODEL_IDS
import com.runanywhere.runanywhereai.data.isVisibleForNativeNpuCatalog
import com.runanywhere.runanywhereai.ui.screens.models.requiresHfAuth
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ModelCatalogTest {
    @Test
    fun npuCatalogCarriesValidatedArchitectureSets() {
        assertEquals(v75, declaredIdsFor(HexagonArch.HEXAGON_ARCH_V75))
        assertEquals(v79, declaredIdsFor(HexagonArch.HEXAGON_ARCH_V79))
        assertEquals(v81, declaredIdsFor(HexagonArch.HEXAGON_ARCH_V81))
        assertEquals(emptySet<String>(), declaredIdsFor(HexagonArch.HEXAGON_ARCH_UNKNOWN))
        assertEquals(v75 + v79 + v81, ModelCatalog.npuCatalog.mapTo(mutableSetOf()) { it.id })
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
            assertTrue(model.supportedNpuArches.isNotEmpty())
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
            assertEquals(
                model.id in PRIVATE_HF_MODEL_IDS,
                request.description.orEmpty().contains("Hugging Face token"),
            )
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
            "https://huggingface.co/runanywhere/canary_qwen_2.5b_HNPU/canary-qwen-2.5b.json",
            model.url,
        )
        assertEquals(
            setOf(HexagonArch.HEXAGON_ARCH_V81),
            model.supportedNpuArches,
        )
        assertEquals(ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION, model.category)
    }

    @Test
    fun onlyExplicitlyPrivateNpuRowsRequireAHuggingFaceToken() {
        assertEquals(setOf("kokoro_en"), PRIVATE_HF_MODEL_IDS)
        ModelCatalog.npuCatalog.forEach { model ->
            assertEquals(model.id in PRIVATE_HF_MODEL_IDS, model.requiresHfAuth)
            assertEquals(
                model.id in PRIVATE_HF_MODEL_IDS,
                ModelInfo(
                    id = model.id,
                    framework = model.framework,
                    download_url = model.url,
                ).requiresHfAuth(),
            )
        }
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

    private fun declaredIdsFor(arch: HexagonArch): Set<String> =
        ModelCatalog.npuCatalog
            .filter { arch in it.supportedNpuArches }
            .mapTo(mutableSetOf()) { it.id }

    private val v75 = setOf(
        "lfm2_5_230m", "lfm2_5_350m", "qwen3_0_6b", "qwen3_5_0_8b", "qwen3_5_2b",
        "ternary_bonsai_1_7b", "internvl3_5_1b", "qwen3_vl", "nemotron_ocr",
        "nemotron_ocr_v1", "nemotron_parse", "whisper_base", "whisper_small", "moonshine_tiny",
        "moonshine_base", "parakeet_tdt_0_6b_v2", "parakeet_tdt_0_6b_v3",
        "parakeet_rnnt_1_1b", "canary_1b_flash", "nemotron_asr_streaming", "melotts_en",
        "kokoro_en", "kitten_nano_0_8", "embeddinggemma_300m", "nv_embedqa_1b",
        "nv_rerankqa_1b", "siglip2_base",
    )

    private val v79 = setOf(
        "lfm2_5_230m", "lfm2_5_350m", "qwen3_0_6b", "llama3_2_1b", "gemma4_e2b",
        "phi_tiny_moe", "qwen3_5_0_8b", "qwen3_5_2b", "qwen3_5_4b",
        "deepseek_r1_distill_qwen_1_5b", "internvl3_5_1b", "qwen3_vl", "gemma4_e2b_vlm",
        "whisper_base", "whisper_small", "moonshine_base", "moonshine_tiny", "melotts_en",
        "nv_embedqa_1b", "nv_rerankqa_1b", "embeddinggemma_300m",
        "siglip2_base", "lama_dilated",
    )

    private val v81 = setOf(
        "qwen3_0_6b", "llama3_2_1b", "lfm2_5_230m", "lfm2_5_350m", "gemma4_e2b",
        "gemma4_e4b", "gemma3n_e4b", "phi_tiny_moe", "qwen3_5_0_8b", "qwen3_5_2b",
        "qwen3_5_4b", "deepseek_r1_distill_qwen_1_5b", "deepseek_r1_distill_qwen_7b",
        "ternary_bonsai_1_7b", "nemotron_nano_8b", "nemoguard_content_8b",
        "nemoguard_topic_8b", "qwen3_vl_2b_text", "internvl3_5_1b", "gemma4_e2b_vlm",
        "gemma4_e4b_vlm", "nemotron_nano_vl_8b", "whisper_base", "whisper_small",
        "moonshine_base", "moonshine_tiny", "parakeet_tdt_0_6b_v2", "parakeet_tdt_0_6b_v3",
        "parakeet_rnnt_1_1b", "canary_qwen_2_5b", "canary_1b_flash",
        "nemotron_asr_streaming", "kokoro_en", "melotts_en", "kitten_nano_0_8",
        "kitten_mini_0_1", "kitten_mini_0_8", "kitten_micro_0_8", "kitten_nano_0_2",
        "kitten_nano_0_1", "embeddinggemma_300m", "nv_embedqa_1b", "nv_rerankqa_1b",
        "nv_embedcode_7b", "llama_embed_nemotron_8b", "siglip2_base", "lama_dilated",
    )
}
