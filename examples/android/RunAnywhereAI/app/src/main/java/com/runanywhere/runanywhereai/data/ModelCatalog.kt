package com.runanywhere.runanywhereai.data

import ai.runanywhere.proto.v1.ArchiveStructure
import ai.runanywhere.proto.v1.ArchiveType
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.LoraAdapterCatalogEntry
import ai.runanywhere.proto.v1.ModelCategory

/**
 * One NPU (QHexRT) bundle = one manifest-pinned hf.co folder ref
 * (`https://huggingface.co/<repo>/<arch>/<manifest>.json`). Commons + the
 * engine's bundle policy resolve the full file set (sizes, checksums, nested
 * paths, and the repo-root `config.json` when present) from the Hub tree at
 * registration — no file lists in the app. Context binaries are arch-exact
 * ([arch] is the Hexagon architecture they were compiled for: v75+),
 * so registration filters to the arch probed on the running device.
 */
internal data class NpuBundle(
    val id: String,
    val name: String,
    val category: ModelCategory,
    val arch: String,
    val url: String,
)

// Curated catalog, kept in lockstep with the iOS / Flutter / RN example apps.
internal object ModelCatalog {

    private val LLAMA = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP
    private val SHERPA = InferenceFramework.INFERENCE_FRAMEWORK_SHERPA
    private val ONNX = InferenceFramework.INFERENCE_FRAMEWORK_ONNX
    private val QHEXRT = InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT

    private val LANGUAGE = ModelCategory.MODEL_CATEGORY_LANGUAGE
    private val MULTIMODAL = ModelCategory.MODEL_CATEGORY_MULTIMODAL
    private val STT = ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION
    private val TTS = ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS
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
     * QHEXRT entries. Source data: [npuBundles].
     */
    fun npuModels(arch: String?): List<CatalogModel> {
        if (arch == null) return emptyList()
        return npuBundles.filter { it.arch == arch }.map { npu ->
            SingleFileModel(
                id = npu.id,
                name = npu.name,
                url = npu.url,
                framework = QHEXRT,
                category = npu.category,
                memoryBytes = 0L,
            )
        }
    }

    /** The NPU (QHexRT) catalog — one manifest-pinned hf.co folder ref per bundle. */
    val npuBundles: List<NpuBundle> = listOf(
        NpuBundle("lfm2_5_230m_v79", "LFM2.5 230M (HNPU)", LANGUAGE, "v79",
            "https://huggingface.co/runanywhere/lfm2_5_230m_HNPU/v79/lfm2-5-230m.json"),
        NpuBundle("lfm2_5_230m_v81", "LFM2.5 230M (HNPU)", LANGUAGE, "v81",
            "https://huggingface.co/runanywhere/lfm2_5_230m_HNPU/v81/lfm2-5-230m.json"),
        NpuBundle("lfm2_5_350m_v79", "LFM2.5 350M (HNPU)", LANGUAGE, "v79",
            "https://huggingface.co/runanywhere/lfm2_5_350m_HNPU/v79/lfm2-5-350m-2048.json"),
        NpuBundle("lfm2_5_350m_v81", "LFM2.5 350M (HNPU)", LANGUAGE, "v81",
            "https://huggingface.co/runanywhere/lfm2_5_350m_HNPU/v81/lfm2-5-350m-2048.json"),
        NpuBundle("qwen3_5_0_8b_v81", "Qwen3.5 0.8B (HNPU)", LANGUAGE, "v81",
            "https://huggingface.co/runanywhere/qwen3_5_0_8b_HNPU/v81/qwen3.5-0.8b-1024.json"),
        NpuBundle("qwen3_vl_v79", "Qwen3-VL 2B (HNPU)", MULTIMODAL, "v79",
            "https://huggingface.co/runanywhere/qwen3_vl_HNPU/v79/qwen3vl-2b-vlm-512.json"),
        NpuBundle("internvl3_5_1b_v79", "InternVL3.5 1B (HNPU)", MULTIMODAL, "v79",
            "https://huggingface.co/runanywhere/internvl3_5_1b_HNPU/v79/internvl3_5-1b-512.json"),
        NpuBundle("internvl3_5_1b_v81", "InternVL3.5 1B (HNPU)", MULTIMODAL, "v81",
            "https://huggingface.co/runanywhere/internvl3_5_1b_HNPU/v81/internvl3_5-1b.json"),
        NpuBundle("whisper_base_v79", "Whisper Base (HNPU)", STT, "v79",
            "https://huggingface.co/runanywhere/whisper_base_HNPU/v79/whisper-base.json"),
        NpuBundle("whisper_small_v79", "Whisper Small (HNPU)", STT, "v79",
            "https://huggingface.co/runanywhere/whisper_small_HNPU/v79/whisper-small.json"),
        NpuBundle("moonshine_tiny_v81", "Moonshine Tiny (HNPU)", STT, "v81",
            "https://huggingface.co/runanywhere/moonshine_tiny_HNPU/v81/moonshine-tiny.json"),
        NpuBundle("moonshine_base_v81", "Moonshine Base (HNPU)", STT, "v81",
            "https://huggingface.co/runanywhere/moonshine_base_HNPU/v81/moonshine-base.json"),
        NpuBundle("melotts_en_v79", "MeloTTS EN (HNPU)", TTS, "v79",
            "https://huggingface.co/runanywhere/melotts_en_HNPU/v79/melotts-en.json"),
        NpuBundle("melotts_en_v81", "MeloTTS EN (HNPU)", TTS, "v81",
            "https://huggingface.co/runanywhere/melotts_en_HNPU/v81/melotts-en.json"),
        NpuBundle("kokoro_en_v81", "Kokoro-82M EN (HNPU)", TTS, "v81",
            "https://huggingface.co/runanywhere/kokoro_en_HNPU/v81/kokoro-en.json"),
        NpuBundle("kitten_nano_0_8_v81", "Kitten-nano-0.8-fp32 (HNPU)", TTS, "v81",
            "https://huggingface.co/runanywhere/kitten_nano_0_8_HNPU/v81/kitten_nano08_v81.json"),
        NpuBundle("kitten_mini_0_1_v81", "Kitten-mini-0.1 (HNPU)", TTS, "v81",
            "https://huggingface.co/runanywhere/kitten_mini_0_1_HNPU/v81/kitten_mini01_v81.json"),
    )

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
        MultiFileModel(
            "qwen3.5-0.8b-q4_k_m", "Qwen 3.5 0.8B", LLAMA, MULTIMODAL, 786_962_240,
            files = listOf(
                ModelFile(
                    "https://huggingface.co/bartowski/Qwen_Qwen3.5-0.8B-GGUF/resolve/main/Qwen_Qwen3.5-0.8B-Q4_K_M.gguf",
                    "Qwen_Qwen3.5-0.8B-Q4_K_M.gguf"
                ),
                ModelFile(
                    "https://huggingface.co/bartowski/Qwen_Qwen3.5-0.8B-GGUF/resolve/main/mmproj-Qwen_Qwen3.5-0.8B-bf16.gguf",
                    "mmproj-Qwen_Qwen3.5-0.8B-bf16.gguf"
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
