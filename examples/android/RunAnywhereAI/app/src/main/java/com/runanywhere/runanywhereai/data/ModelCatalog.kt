package com.runanywhere.runanywhereai.data

import ai.runanywhere.proto.v1.ArchiveStructure
import ai.runanywhere.proto.v1.ArchiveType
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.LoraAdapterCatalogEntry
import ai.runanywhere.proto.v1.ModelCategory
import com.runanywhere.runanywhereai.ui.screens.npu.NPU_MODELS
import com.runanywhere.runanywhereai.ui.screens.npu.category

// Curated catalog, kept in lockstep with the iOS / Flutter / RN example apps.
internal object ModelCatalog {

    private val LLAMA = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP
    private val SHERPA = InferenceFramework.INFERENCE_FRAMEWORK_SHERPA
    private val ONNX = InferenceFramework.INFERENCE_FRAMEWORK_ONNX
    private val QHEXRT = InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT

    private val LANGUAGE = ModelCategory.MODEL_CATEGORY_LANGUAGE
    private val MULTIMODAL = ModelCategory.MODEL_CATEGORY_MULTIMODAL
    private val TAR_GZ = ArchiveType.ARCHIVE_TYPE_TAR_GZ

    val models: List<CatalogModel> by lazy {
        buildList {
            addAll(llm)
            addAll(vlm)
            addAll(speech)
            addAll(misc)
        }
    }

    /**
     * QHexRT (Hexagon NPU) bundles for the probed device architecture,
     * registered like every other catalog entry — one URL through the SDK's
     * canonical from-url path. The URL is an HF folder-bundle ref pinned to
     * the bundle's manifest (`huggingface.co/<repo>/<arch>/<manifest>.json`);
     * commons + the engine-registered QHexRT bundle policy resolve the full
     * file set (sizes, checksums, nested paths) from the Hub tree — the app
     * carries no file lists. Returns an empty list when the NPU is
     * unsupported ([arch] == null), so pickers on other devices never see
     * QHEXRT entries. Source data: `NpuCatalog.NPU_MODELS` (index 0 is the
     * manifest; its resolve/main URL is rewritten to the folder-ref form).
     */
    fun npuModels(arch: String?): List<CatalogModel> {
        if (arch == null) return emptyList()
        return NPU_MODELS.filter { it.arch == arch && it.files.isNotEmpty() }.map { npu ->
            SingleFileModel(
                id = npu.id,
                name = npu.name,
                // Manifest-pinned folder ref, e.g.
                // https://huggingface.co/runanywhere/x_HNPU/v81/x.json
                url = npu.files.first().url.replace("/resolve/main/", "/"),
                framework = QHEXRT,
                category = npu.modality.category(),
                memoryBytes = npu.sizeBytes,
            )
        }
    }

    val loraAdapters = listOf(
        LoraAdapterCatalogEntry(
            id = "abliterated-lora",
            name = "Abliterated LoRA (F16)",
            description = "Removes refusal behavior — model answers directly without disclaimers",
            url = "https://huggingface.co/Void2377/qwen-lora-gguf/resolve/main/qwen2.5-0.5b-abliterated-lora-f16.gguf",
            filename = "qwen2.5-0.5b-abliterated-lora-f16.gguf",
            compatible_models = listOf("qwen2.5-0.5b-instruct-q6_k"),
            size_bytes = 17_620_224,
            default_scale = 1.0f,
        ),
    )

    private val llm = listOf(
        SingleFileModel(
            "smollm2-360m-q8_0",
            "SmolLM2 360M Q8_0",
            "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf",
            LLAMA,
            LANGUAGE,
            386_404_416
        ),
        SingleFileModel(
            "llama-2-7b-chat-q4_k_m",
            "Llama 2 7B Chat Q4_K_M",
            "https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/llama-2-7b-chat.Q4_K_M.gguf",
            LLAMA,
            LANGUAGE,
            4_000_000_000
        ),
        SingleFileModel(
            "mistral-7b-instruct-q4_k_m",
            "Mistral 7B Instruct Q4_K_M",
            "https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct-v0.1.Q4_K_M.gguf",
            LLAMA,
            LANGUAGE,
            4_000_000_000
        ),
        SingleFileModel(
            "qwen2.5-0.5b-instruct-q6_k",
            "Qwen 2.5 0.5B Instruct Q6_K",
            "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf",
            LLAMA,
            LANGUAGE,
            600_000_000,
            supportsLora = true
        ),
        SingleFileModel(
            "qwen2.5-1.5b-instruct-q4_k_m",
            "Qwen 2.5 1.5B Instruct Q4_K_M",
            "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf",
            LLAMA,
            LANGUAGE,
            2_500_000_000
        ),
        SingleFileModel(
            "qwen3-0.6b-q4_k_m",
            "Qwen3 0.6B Q4_K_M",
            "https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf",
            LLAMA,
            LANGUAGE,
            500_000_000,
            supportsThinking = true
        ),
        SingleFileModel(
            "qwen3-1.7b-q4_k_m",
            "Qwen3 1.7B Q4_K_M",
            "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf",
            LLAMA,
            LANGUAGE,
            1_200_000_000,
            supportsThinking = true
        ),
        SingleFileModel(
            "qwen3-4b-q4_k_m",
            "Qwen3 4B Q4_K_M",
            "https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf",
            LLAMA,
            LANGUAGE,
            2_800_000_000,
            supportsThinking = true
        ),
        SingleFileModel(
            "lfm2-350m-q4_k_m",
            "LiquidAI LFM2 350M Q4_K_M",
            "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf",
            LLAMA,
            LANGUAGE,
            250_000_000
        ),
        SingleFileModel(
            "lfm2-350m-q8_0",
            "LiquidAI LFM2 350M Q8_0",
            "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf",
            LLAMA,
            LANGUAGE,
            400_000_000
        ),
        SingleFileModel(
            "lfm2-1.2b-tool-q4_k_m",
            "LiquidAI LFM2 1.2B Tool Q4_K_M",
            "https://huggingface.co/LiquidAI/LFM2-1.2B-Tool-GGUF/resolve/main/LFM2-1.2B-Tool-Q4_K_M.gguf",
            LLAMA,
            LANGUAGE,
            800_000_000
        ),
        SingleFileModel(
            "lfm2-1.2b-tool-q8_0",
            "LiquidAI LFM2 1.2B Tool Q8_0",
            "https://huggingface.co/LiquidAI/LFM2-1.2B-Tool-GGUF/resolve/main/LFM2-1.2B-Tool-Q8_0.gguf",
            LLAMA,
            LANGUAGE,
            1_400_000_000
        ),
    )

    private val vlm = listOf(
        MultiFileModel(
            "lfm2-vl-450m-q8_0", "LFM2-VL 450M", LLAMA, MULTIMODAL, 600_000_000,
            files = listOf(
                ModelFile(
                    "https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/LFM2-VL-450M-Q8_0.gguf",
                    "LFM2-VL-450M-Q8_0.gguf"
                ),
                ModelFile(
                    "https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/mmproj-LFM2-VL-450M-Q8_0.gguf",
                    "mmproj-LFM2-VL-450M-Q8_0.gguf"
                ),
            ),
        ),
        MultiFileModel(
            "qwen2-vl-2b-instruct-q4_k_m", "Qwen2-VL 2B Instruct", LLAMA, MULTIMODAL, 1_800_000_000,
            files = listOf(
                ModelFile(
                    "https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/Qwen2-VL-2B-Instruct-Q4_K_M.gguf",
                    "Qwen2-VL-2B-Instruct-Q4_K_M.gguf"
                ),
                ModelFile(
                    "https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf",
                    "mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf"
                ),
            ),
        ),
        ArchiveModel(
            "smolvlm-500m-instruct-q8_0",
            "SmolVLM 500M Instruct",
            "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-vlm-models-v1/smolvlm-500m-instruct-q8_0.tar.gz",
            LLAMA,
            MULTIMODAL,
            600_000_000,
            TAR_GZ,
            ArchiveStructure.ARCHIVE_STRUCTURE_DIRECTORY_BASED
        ),
    )

    private val speech = listOf(
        ArchiveModel(
            "sherpa-onnx-whisper-tiny.en",
            "Sherpa Whisper Tiny (ONNX)",
            "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz",
            SHERPA,
            ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
            75_000_000,
            TAR_GZ,
            ArchiveStructure.ARCHIVE_STRUCTURE_NESTED_DIRECTORY
        ),
        ArchiveModel(
            "vits-piper-en_US-lessac-medium",
            "Piper TTS (US English - Medium)",
            "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz",
            SHERPA,
            ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
            65_000_000,
            TAR_GZ,
            ArchiveStructure.ARCHIVE_STRUCTURE_NESTED_DIRECTORY
        ),
        ArchiveModel(
            "vits-piper-en_GB-alba-medium",
            "Piper TTS (British English)",
            "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_GB-alba-medium.tar.gz",
            SHERPA,
            ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
            65_000_000,
            TAR_GZ,
            ArchiveStructure.ARCHIVE_STRUCTURE_NESTED_DIRECTORY
        ),
    )

    private val misc = listOf(
        SingleFileModel(
            "silero-vad",
            "Silero VAD",
            "https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx",
            ONNX,
            ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
            // Actual silero_vad.onnx artifact size (verified Content-Length). This value
            // doubles as download_size_bytes, which feeds the post-download size guard —
            // an over-stated 5 MB tripped the guard on a valid ~2.3 MB download.
            2_327_524
        ),
        MultiFileModel(
            "all-minilm-l6-v2",
            "All MiniLM L6 v2 (Embedding)",
            ONNX,
            ModelCategory.MODEL_CATEGORY_EMBEDDING,
            25_500_000,
            files = listOf(
                ModelFile(
                    "https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx",
                    "model.onnx"
                ),
                ModelFile(
                    "https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/vocab.txt",
                    "vocab.txt"
                ),
            ),
        ),
    )
}
