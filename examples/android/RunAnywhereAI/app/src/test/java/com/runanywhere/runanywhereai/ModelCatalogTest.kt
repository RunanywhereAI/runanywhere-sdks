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

        val nano = byId.getValue("llama-3.1-nemotron-nano-8b-v1-q4_k_m") as SingleFileModel
        assertEquals(InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP, nano.framework)
        assertEquals(ModelCategory.MODEL_CATEGORY_LANGUAGE, nano.category)
        assertEquals(4_920_736_864L, nano.downloadBytes)
        assertEquals(6L * 1_024L * 1_024L * 1_024L, nano.memoryBytes)
        assertEquals(4_096, nano.contextLength)
        assertEquals(
            "https://huggingface.co/bartowski/nvidia_Llama-3.1-Nemotron-Nano-8B-v1-GGUF/resolve/6f3d46cfbc39ce7a1bec89654305515d904e8102/nvidia_Llama-3.1-Nemotron-Nano-8B-v1-Q4_K_M.gguf",
            nano.url,
        )

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
            assertEquals(pinAndSize.second, model.downloadBytes)
            assertTrue(model.files.isNotEmpty())
            assertTrue(model.files.all { it.url.contains("/resolve/${pinAndSize.first}/") })
            assertTrue(model.files.all { (it.sizeBytes ?: 0) > 0 })
            assertEquals(pinAndSize.second, model.files.sumOf { it.sizeBytes ?: 0 })
            assertTrue(model.files.any { it.filename == "tokens.txt" })
        }
    }

    @Test
    fun parakeetCtcUsesExactTransformBackedBundleAndRuntimeMemory() {
        val model =
            ModelCatalog.models.single { it.id == "sherpa-nemo-parakeet-ctc-1.1b-int8" }
                as MultiFileModel

        assertEquals(InferenceFramework.INFERENCE_FRAMEWORK_SHERPA, model.framework)
        assertEquals(ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION, model.category)
        assertEquals(2L * 1_024L * 1_024L * 1_024L, model.memoryBytes)
        assertEquals(1_110_024_519L, model.downloadBytes)

        val descriptors = model.descriptors()
        assertEquals(2, descriptors.size)
        assertEquals(model.downloadBytes, descriptors.sumOf { it.size_bytes ?: 0 })

        val primary = descriptors.single { it.filename == "model.int8.onnx" }
        assertEquals(
            "https://huggingface.co/OpenVoiceOS/nvidia-parakeet-ctc-1.1b-onnx/resolve/3ca664a2f106622d599052b4e4ecee5fdfc7e2e5/model.int8.onnx",
            primary.url,
        )
        assertEquals(1_110_014_145L, primary.size_bytes)
        assertEquals(
            "62f73c17a5301c048c7273cf24ef1cd0c3621d3625c5415fbafe5633d7bf2f98",
            primary.checksum_sha256,
        )

        val transform = requireNotNull(primary.post_download_transform)
        assertEquals(1_110_014_069L, transform.source_size_bytes)
        assertEquals(
            "a16056c0a0d8df38c7b57cb019062df116e9e565203c6f25d6ea0c0c1122c84d",
            transform.source_checksum_sha256,
        )
        assertEquals(primary.size_bytes, transform.final_size_bytes)
        assertEquals(primary.checksum_sha256, transform.final_checksum_sha256)
        val payload = requireNotNull(transform.operations.single().append_bytes).payload
        assertEquals(76, payload.size)
        assertEquals(
            "72120a0a766f6361625f73697a6512043130323572170a1273756273616d706c696e675f666163746f72120138721d0a0e6e6f726d616c697a655f74797065120b7065725f66656174757265",
            payload.hex(),
        )

        val tokens = descriptors.single { it.filename == "tokens.txt" }
        assertEquals(
            "https://huggingface.co/OpenVoiceOS/nvidia-parakeet-ctc-1.1b-onnx/resolve/3ca664a2f106622d599052b4e4ecee5fdfc7e2e5/vocab.txt",
            tokens.url,
        )
        assertEquals(10_374L, tokens.size_bytes)
        assertEquals(
            "ed16e1a4e3a3aa379138c0b1888e5d49f993c9d512b2be4d46e90a87afd54921",
            tokens.checksum_sha256,
        )
        assertEquals(null, tokens.post_download_transform)
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
