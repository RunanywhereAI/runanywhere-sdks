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

    /**
     * The taxonomy is only a source of truth if it actually names every shipped model.
     * A curated catalog row that falls through to the per-model fallback would surface as
     * a lonely one-off card, which is exactly the mess this table replaced — so adding a
     * model to the catalog must mean adding it to the table.
     */
    @Test
    fun everyCatalogRowResolvesToANamedFamily() {
        val unnamed = catalogModels()
            .filter { it.family().key.startsWith("model-") }
            .map { it.id }

        assertEquals("catalog rows with no family in ModelTaxonomy", emptyList<String>(), unnamed)
    }

    @Test
    fun npuAndCpuBuildsOfASeriesShareOneFamily() {
        val npuLlama = catalogModel("llama3_2_1b")
        val ggufLlama = catalogModel("llama-2-7b-chat-q4_k_m")

        assertEquals(npuLlama.family().key, ggufLlama.family().key)
        assertEquals("Llama", npuLlama.family().title)
        assertEquals(ModelMaker.META, npuLlama.maker())
    }

    @Test
    fun nvidiaChatModelsGroupUnderNemotronRatherThanLlama() {
        listOf(
            "nemotron_nano_8b",
            "nemotron-mini-4b-instruct-q4_k_m",
            "llama-3.1-nemotron-nano-4b-v1.1-q4_k_m",
            "llama-3.1-nemotron-nano-8b-v1-q4_k_m",
        ).forEach { id ->
            val model = catalogModel(id)
            assertEquals(id, "Nemotron", model.family().title)
            assertEquals(id, ModelMaker.NVIDIA, model.maker())
        }
    }

    @Test
    fun everyNvidiaSpeechModelGroupsByItsSeries() {
        val expected = mapOf(
            "parakeet_ctc_1_1b" to "Parakeet",
            "sherpa-nemo-parakeet-ctc-1.1b-int8" to "Parakeet",
            "sherpa-nemo-parakeet-tdt-ctc-0.6b-ja-int8" to "Parakeet",
            "canary_180m_flash" to "Canary",
            "sherpa-nemo-canary-180m-flash-int8" to "Canary",
            "nemotron_asr_streaming" to "Nemotron ASR",
        )

        expected.forEach { (id, title) ->
            val model = catalogModel(id)
            assertEquals(id, title, model.family().title)
            assertEquals(id, ModelMaker.NVIDIA, model.maker())
        }
    }

    /**
     * Bucket scoping is the reason a brand token cannot leak across modalities: the same
     * "llama" and "nemotron" tokens have to mean three different families depending on
     * whether the model chats, sees, or retrieves.
     */
    @Test
    fun brandTokensStayInsideTheirCapabilityBucket() {
        assertEquals("Llama", catalogModel("llama3_2_1b").family().title)
        assertEquals("Nemotron Embed", catalogModel("llama_embed_nemotron_8b").family().title)
        assertEquals("Nemotron Vision", catalogModel("nemotron_nano_vl_8b").family().title)
        assertEquals("Nemotron OCR", catalogModel("nemotron_parse").family().title)
    }

    @Test
    fun eachFamilyKeyKeepsASingleTitleTaglineAndMaker() {
        catalogModels()
            .groupBy { it.family().key }
            .forEach { (key, models) ->
                assertEquals("family $key has conflicting definitions", 1, models.map { it.family() }.distinct().size)
            }
    }

    @Test
    fun userImportedModelsFallBackToTheirOwnFamily() {
        val imported = ModelInfo(
            id = "hf/someone/custom-gguf",
            name = "Custom GGUF",
            framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
            category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
        )

        assertEquals("model-hf/someone/custom-gguf", imported.family().key)
        assertEquals("Custom GGUF", imported.family().title)
        assertEquals(ModelMaker.OPEN_SOURCE, imported.maker())
    }

    @Test
    fun displayTitleDropsBackendAndQuantNoiseButKeepsMeaningfulSuffixes() {
        assertEquals("Parakeet TDT 0.6B v2", catalogModel("sherpa-nemo-parakeet-tdt-0.6b-v2-int8").displayTitle())
        assertEquals("Bonsai-1.7B 1-bit", catalogModel("bonsai-1.7b-q1_0").displayTitle())
        assertEquals("Llama 3.2 1B", catalogModel("llama3_2_1b").displayTitle())
        assertTrue(catalogModel("gemma-4-e2b-it-q8_0").displayTitle().endsWith("(Experimental)"))
    }

    /**
     * Families are grouped smallest-variant-first and ordered by capability bucket, then
     * maker, so a maker's families always appear next to each other in the picker.
     */
    @Test
    fun familyGroupsOrderByBucketThenMaker() {
        val groups = listOf(
            catalogModel("all-minilm-l6-v2"),
            catalogModel("qwen3-4b-q4_k_m"),
            catalogModel("nemotron-mini-4b-instruct-q4_k_m"),
            catalogModel("whisper_base"),
        ).toFamilyGroups()

        assertEquals(
            listOf("Nemotron", "Qwen3", "Whisper", "MiniLM"),
            groups.map { it.family.title },
        )
    }

    @Test
    fun familyGroupFlagsAnNpuBuildFromItsVariantsNotItsName() {
        val llama = listOf(
            catalogModel("llama3_2_1b"),
            catalogModel("llama-2-7b-chat-q4_k_m"),
        ).toFamilyGroups().single()

        assertTrue(llama.hasNpuVariant)
        assertEquals(2, llama.optionCount)
        assertEquals(listOf("Llama 3.2 1B", "Llama 2 7B Chat"), llama.variants.map { it.displayTitle() })
    }

    /**
     * Every picker is scoped to one modality, so a "Voice"/"Vision"/"Documents" tag would
     * print the same word on every card. Family cards therefore lead with a real
     * capability or the feel word, while the tag itself survives for the cross-modality
     * "Also recommended" rows in the chat picker.
     */
    @Test
    fun familyCardsLeadWithCapabilityOrFeelInsteadOfRestatingTheModality() {
        val parakeet = listOf(catalogModel("parakeet_ctc_1_1b")).toFamilyGroups().single()
        assertEquals(ConsumerTagKind.FEEL, parakeet.headlineTag?.kind)

        val nemotron = listOf(catalogModel("nemotron_nano_8b")).toFamilyGroups().single()
        assertEquals(ConsumerTag("Great for tools", ConsumerTagKind.CAPABILITY), nemotron.headlineTag)

        assertTrue(
            catalogModel("parakeet_ctc_1_1b").consumerTags()
                .any { it.label == "Voice" && it.kind == ConsumerTagKind.MODALITY },
        )
    }

    private fun catalogModel(id: String): ModelInfo = catalogModels().single { it.id == id }

    private fun catalogModels(): List<ModelInfo> =
        (ModelCatalog.models + ModelCatalog.npuCatalog).map { it.toModelInfo() }

    // The picker only ever sees registered ModelInfo, so project the catalog rows into the
    // same shape the classification runs against.
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
