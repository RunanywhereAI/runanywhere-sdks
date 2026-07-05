package com.runanywhere.runanywhereai.data

import ai.runanywhere.proto.v1.ArchiveStructure
import ai.runanywhere.proto.v1.ArchiveType
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.LoraAdapterCatalogEntry
import ai.runanywhere.proto.v1.ModelCategory


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
     * Registers logical HNPU rows. QHexRT's native bundle resolver chooses the
     * current device arch; unsupported devices or missing arch folders fail
     * during SDK registration and never become picker-visible.
     */
    fun npuModels(): List<CatalogModel> = npuCatalog

    /** Logical HNPU catalog — direct SDK model rows with native-resolved HF URLs. */
    val npuCatalog: List<SingleFileModel> = listOf(
        SingleFileModel("lfm2_5_230m", "LFM2.5 230M (HNPU)", "https://huggingface.co/runanywhere/lfm2_5_230m_HNPU/lfm2-5-230m.json", QHEXRT, LANGUAGE, 0L),
        SingleFileModel("lfm2_5_350m", "LFM2.5 350M (HNPU)", "https://huggingface.co/runanywhere/lfm2_5_350m_HNPU/lfm2-5-350m-2048.json", QHEXRT, LANGUAGE, 0L),
        SingleFileModel("qwen3_5_0_8b", "Qwen3.5 0.8B (HNPU)", "https://huggingface.co/runanywhere/qwen3_5_0_8b_HNPU/qwen3.5-0.8b-1024.json", QHEXRT, LANGUAGE, 0L),
        SingleFileModel("qwen3_5_2b", "Qwen3.5 2B (HNPU)", "https://huggingface.co/runanywhere/qwen3_5_2b_HNPU/qwen3.5-2b-1024.json", QHEXRT, LANGUAGE, 0L),
        SingleFileModel("qwen3_5_4b", "Qwen3.5 4B (HNPU)", "https://huggingface.co/runanywhere/qwen3_5_4b_HNPU/qwen3.5-4b-1024.json", QHEXRT, LANGUAGE, 0L),
        SingleFileModel("qwen3_0_6b", "Qwen3 0.6B (HNPU)", "https://huggingface.co/runanywhere/qwen3_0_6b_HNPU/qwen3-0.6b-1024final.json", QHEXRT, LANGUAGE, 0L),
        SingleFileModel("llama3_2_1b", "Llama 3.2 1B (HNPU)", "https://huggingface.co/runanywhere/llama3_2_1b_HNPU/llama-3.2-1b.json", QHEXRT, LANGUAGE, 0L),
        SingleFileModel("ternary_bonsai_1_7b", "Ternary Bonsai 1.7B (HNPU)", "https://huggingface.co/runanywhere/ternary_bonsai_1_7b_HNPU/ternary-bonsai-1.7b-1024.json", QHEXRT, LANGUAGE, 0L),
        SingleFileModel("phi_tiny_moe", "Phi Tiny MoE (HNPU)", "https://huggingface.co/runanywhere/phi_tiny_moe_HNPU/phimoe.json", QHEXRT, LANGUAGE, 0L),
        SingleFileModel("gemma3n_e4b", "Gemma 3n E4B (HNPU)", "https://huggingface.co/runanywhere/gemma3n_e4b_HNPU/gemma-3n-E4B-it.json", QHEXRT, LANGUAGE, 0L),
        SingleFileModel("gemma4_e2b", "Gemma 4 E2B (HNPU)", "https://huggingface.co/runanywhere/gemma4_e2b_HNPU/gemma4-e2b.json", QHEXRT, LANGUAGE, 0L),
        SingleFileModel("gemma4_e4b", "Gemma 4 E4B (HNPU)", "https://huggingface.co/runanywhere/gemma4_e4b_HNPU/gemma-4-E4B.json", QHEXRT, LANGUAGE, 0L),
        SingleFileModel("deepseek_r1_distill_qwen_1_5b", "DeepSeek R1 Distill Qwen 1.5B (HNPU)", "https://huggingface.co/runanywhere/deepseek_r1_distill_qwen_1_5b_HNPU/DeepSeek-R1-Distill-Qwen-1.5B.json", QHEXRT, LANGUAGE, 0L),
        SingleFileModel("deepseek_r1_distill_qwen_7b", "DeepSeek R1 Distill Qwen 7B (HNPU)", "https://huggingface.co/runanywhere/deepseek_r1_distill_qwen_7b_HNPU/DeepSeek-R1-Distill-Qwen-7B.json", QHEXRT, LANGUAGE, 0L),
        SingleFileModel("nemotron_nano_8b", "Llama 3.1 Nemotron Nano 8B (HNPU)", "https://huggingface.co/runanywhere/nemotron_nano_8b_HNPU/nemotron-nano-8b.json", QHEXRT, LANGUAGE, 0L),
        SingleFileModel("nemoguard_content_8b", "NemoGuard 8B Content Safety (HNPU)", "https://huggingface.co/runanywhere/nemoguard_8b_content_safety_HNPU/nemoguard-content-8b.json", QHEXRT, LANGUAGE, 0L),
        SingleFileModel("nemoguard_topic_8b", "NemoGuard 8B Topic Control (HNPU)", "https://huggingface.co/runanywhere/nemoguard_8b_topic_control_HNPU/nemoguard-topic-8b.json", QHEXRT, LANGUAGE, 0L),
        SingleFileModel("qwen3_vl_2b_text", "Qwen3-VL 2B Text (HNPU)", "https://huggingface.co/runanywhere/qwen3_vl_HNPU/qwen3vl-2b-text-512.json", QHEXRT, LANGUAGE, 0L),
        SingleFileModel("qwen3_vl", "Qwen3-VL 2B (HNPU)", "https://huggingface.co/runanywhere/qwen3_vl_HNPU/qwen3vl-2b-vlm-512.json", QHEXRT, MULTIMODAL, 0L),
        SingleFileModel("internvl3_5_1b", "InternVL3.5 1B (HNPU)", "https://huggingface.co/runanywhere/internvl3_5_1b_HNPU", QHEXRT, MULTIMODAL, 0L),
        SingleFileModel("gemma4_e2b_vlm", "Gemma 4 E2B Image (HNPU)", "https://huggingface.co/runanywhere/gemma4_e2b_HNPU/gemma4-e2b-vlm.json", QHEXRT, MULTIMODAL, 0L),
        SingleFileModel("nemotron_nano_vl_8b", "Llama 3.1 Nemotron Nano VL 8B (HNPU)", "https://huggingface.co/runanywhere/nemotron_nano_vl_8b_HNPU/nemotron-vl-8b-vlm.json", QHEXRT, MULTIMODAL, 0L),
        SingleFileModel("whisper_base", "Whisper Base (HNPU)", "https://huggingface.co/runanywhere/whisper_base_HNPU/whisper-base.json", QHEXRT, STT, 0L),
        SingleFileModel("whisper_small", "Whisper Small (HNPU)", "https://huggingface.co/runanywhere/whisper_small_HNPU/whisper-small.json", QHEXRT, STT, 0L),
        SingleFileModel("moonshine_tiny", "Moonshine Tiny (HNPU)", "https://huggingface.co/runanywhere/moonshine_tiny_HNPU/moonshine-tiny.json", QHEXRT, STT, 0L),
        SingleFileModel("moonshine_base", "Moonshine Base (HNPU)", "https://huggingface.co/runanywhere/moonshine_base_HNPU/moonshine-base.json", QHEXRT, STT, 0L),
        SingleFileModel("parakeet_tdt_0_6b_v2", "Parakeet TDT 0.6B v2 (HNPU)", "https://huggingface.co/runanywhere/parakeet_tdt_0.6b_v2_HNPU/parakeet-tdt-0.6b-v2.json", QHEXRT, STT, 0L),
        SingleFileModel("parakeet_tdt_0_6b_v3", "Parakeet TDT 0.6B v3 (HNPU)", "https://huggingface.co/runanywhere/parakeet_tdt_0.6b_v3_HNPU/parakeet-tdt-0.6b.json", QHEXRT, STT, 0L),
        SingleFileModel("parakeet_rnnt_1_1b", "Parakeet RNNT 1.1B (HNPU)", "https://huggingface.co/runanywhere/parakeet_rnnt_1.1b_HNPU/parakeet-rnnt-1.1b.json", QHEXRT, STT, 0L),
        SingleFileModel("canary_qwen_2_5b", "Canary Qwen 2.5B (HNPU)", "https://huggingface.co/runanywhere/canary_qwen_2.5b_HNPU/canary-qwen-2.5b.json", QHEXRT, STT, 0L),
        SingleFileModel("canary_1b_flash", "Canary-1B-flash (HNPU)", "https://huggingface.co/runanywhere/canary_1b_flash_HNPU/canary-1b-flash.json", QHEXRT, STT, 0L),
        SingleFileModel("nemotron_asr_streaming", "Nemotron ASR Streaming 0.6B (HNPU)", "https://huggingface.co/runanywhere/nemotron_asr_streaming_HNPU/nemotron-3.5-asr-streaming-0.6b.json", QHEXRT, STT, 0L),
        SingleFileModel("melotts_en", "MeloTTS EN (HNPU)", "https://huggingface.co/runanywhere/melotts_en_HNPU/melotts-en.json", QHEXRT, TTS, 0L),
        SingleFileModel("kokoro_en", "Kokoro-82M EN (HNPU)", "https://huggingface.co/runanywhere/kokoro_en_HNPU/kokoro-en.json", QHEXRT, TTS, 0L),
        SingleFileModel("kitten_nano_0_8", "Kitten-nano-0.8-fp32 (HNPU)", "https://huggingface.co/runanywhere/kitten_nano_0_8_HNPU/kitten_nano08_v81.json", QHEXRT, TTS, 0L),
        SingleFileModel("kitten_mini_0_1", "Kitten-mini-0.1 (HNPU)", "https://huggingface.co/runanywhere/kitten_mini_0_1_HNPU/kitten_mini01_v81.json", QHEXRT, TTS, 0L),
        SingleFileModel("kitten_mini_0_8", "Kitten-mini-0.8 (HNPU)", "https://huggingface.co/runanywhere/kitten_mini_0_8_HNPU/kitten_mini08_v81.json", QHEXRT, TTS, 0L),
        SingleFileModel("kitten_micro_0_8", "Kitten-micro-0.8 (HNPU)", "https://huggingface.co/runanywhere/kitten_micro_0_8_HNPU/kitten_micro08_v81.json", QHEXRT, TTS, 0L),
        SingleFileModel("kitten_nano_0_2", "Kitten-nano-0.2 (HNPU)", "https://huggingface.co/runanywhere/kitten_nano_0_2_HNPU/kitten_nano02_v81.json", QHEXRT, TTS, 0L),
        SingleFileModel("kitten_nano_0_1", "Kitten-nano-0.1 (HNPU)", "https://huggingface.co/runanywhere/kitten_nano_0_1_HNPU/kitten_nano01_v81.json", QHEXRT, TTS, 0L),
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
