package com.runanywhere.runanywhereai.ui.screens.models

import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelInfo
import com.runanywhere.runanywhereai.data.ArchiveModel
import com.runanywhere.runanywhereai.data.CatalogModel
import com.runanywhere.runanywhereai.data.ModelCatalog
import com.runanywhere.runanywhereai.data.MultiFileModel
import com.runanywhere.runanywhereai.data.SingleFileModel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ModelTaxonomyTest {

    @Test
    fun everyNvidiaCatalogRowResolvesToNvidiaOrg() {
        val nvidiaIds = catalogModels()
            .filter { model ->
                val hay = "${model.id} ${model.name}".lowercase()
                listOf(
                    "nemotron", "nemoguard", "cosmos", "canary", "parakeet",
                    "nv_embed", "nv-embed", "nv_rerank", "nvidia",
                ).any { it in hay }
            }
            .map { it.id }

        assertTrue("expected NVIDIA catalog rows", nvidiaIds.isNotEmpty())
        nvidiaIds.forEach { id ->
            assertEquals(id, ModelOrg.NVIDIA, catalogModel(id).org())
        }
    }

    @Test
    fun nvidiaCoversNpuAndCpuAcrossModalities() {
        val nvidia = catalogModels().filter { it.org() == ModelOrg.NVIDIA }
        val frameworks = nvidia.map { it.framework }.toSet()
        val categories = nvidia.map { it.category }.toSet()

        assertTrue(
            "NVIDIA must ship at least one NPU and one CPU/GGUF build",
            InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT in frameworks &&
                (
                    InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP in frameworks ||
                        InferenceFramework.INFERENCE_FRAMEWORK_SHERPA in frameworks
                    ),
        )
        assertTrue(
            "NVIDIA must cover chat",
            ModelCategory.MODEL_CATEGORY_LANGUAGE in categories,
        )
        assertTrue(
            "NVIDIA must cover speech",
            ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION in categories,
        )
        assertTrue(
            "NVIDIA must cover embedding",
            ModelCategory.MODEL_CATEGORY_EMBEDDING in categories,
        )
        assertTrue(
            "NVIDIA must cover vision/multimodal",
            ModelCategory.MODEL_CATEGORY_MULTIMODAL in categories ||
                ModelCategory.MODEL_CATEGORY_VISION in categories,
        )
    }

    @Test
    fun orgGroupsCollapseAnOrgIntoOneCard() {
        val groups = listOf(
            catalogModel("nemotron_nano_8b"),
            catalogModel("nemotron-mini-4b-instruct-q4_k_m"),
            catalogModel("parakeet_ctc_1_1b"),
            catalogModel("qwen3-4b-q4_k_m"),
        ).toOrgGroups()

        assertEquals(listOf(ModelOrg.NVIDIA, ModelOrg.ALIBABA), groups.map { it.org })
        val nvidia = groups.single { it.org == ModelOrg.NVIDIA }
        assertEquals(3, nvidia.optionCount)
        assertTrue(nvidia.hasNpuVariant)
    }

    @Test
    fun orgGroupsOrderByOrgDeclaration() {
        val groups = listOf(
            catalogModel("all-minilm-l6-v2"),
            catalogModel("qwen3-4b-q4_k_m"),
            catalogModel("nemotron-mini-4b-instruct-q4_k_m"),
            catalogModel("whisper_base"),
        ).toOrgGroups()

        assertEquals(
            listOf(ModelOrg.NVIDIA, ModelOrg.ALIBABA, ModelOrg.OPENAI, ModelOrg.OPEN_SOURCE),
            groups.map { it.org },
        )
    }

    @Test
    fun nemotronPrefersNvidiaOverMetaLlama() {
        listOf(
            "nemotron_nano_8b",
            "nemotron-mini-4b-instruct-q4_k_m",
            "llama-3.1-nemotron-nano-4b-v1.1-q4_k_m",
            "llama-3.1-nemotron-nano-8b-v1-q4_k_m",
            "llama_embed_nemotron_8b",
        ).forEach { id ->
            assertEquals(id, ModelOrg.NVIDIA, catalogModel(id).org())
        }
        assertEquals(ModelOrg.META, catalogModel("llama3_2_1b").org())
    }

    @Test
    fun userImportedModelsFallBackToOpenSource() {
        val imported = ModelInfo(
            id = "hf/someone/custom-gguf",
            name = "Custom GGUF",
            framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
            category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
        )
        assertEquals(ModelOrg.OPEN_SOURCE, imported.org())
    }

    @Test
    fun displayTitleDropsBackendAndQuantNoiseButKeepsMeaningfulSuffixes() {
        assertEquals("Parakeet TDT 0.6B v2", catalogModel("sherpa-nemo-parakeet-tdt-0.6b-v2-int8").displayTitle())
        assertEquals("Bonsai-1.7B 1-bit", catalogModel("bonsai-1.7b-q1_0").displayTitle())
        assertEquals("Llama 3.2 1B", catalogModel("llama3_2_1b").displayTitle())
        assertTrue(catalogModel("gemma-4-e2b-it-q8_0").displayTitle().endsWith("(Experimental)"))
    }

    private fun catalogModel(id: String): ModelInfo = catalogModels().single { it.id == id }

    private fun catalogModels(): List<ModelInfo> =
        (ModelCatalog.models + ModelCatalog.npuCatalog).map { it.toModelInfo() }

    private fun CatalogModel.toModelInfo(): ModelInfo = when (this) {
        is SingleFileModel -> ModelInfo(
            id = id,
            name = name,
            framework = framework,
            category = category,
            download_size_bytes = downloadBytes,
            memory_required_bytes = memoryBytes,
        )
        is MultiFileModel -> ModelInfo(
            id = id,
            name = name,
            framework = framework,
            category = category,
            download_size_bytes = downloadBytes,
            memory_required_bytes = memoryBytes,
        )
        is ArchiveModel -> ModelInfo(
            id = id,
            name = name,
            framework = framework,
            category = category,
            download_size_bytes = memoryBytes,
            memory_required_bytes = memoryBytes,
        )
    }
}
