package com.runanywhere.runanywhereai.data

import android.util.Log
import com.runanywhere.runanywhereai.data.models.AppModel
import com.runanywhere.sdk.core.onnx.ONNX
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.llm.llamacpp.LlamaCPP
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.LoraAdapterCatalogEntry
import com.runanywhere.sdk.public.extensions.ModelCompanionFile
import com.runanywhere.sdk.public.extensions.Models.ModelCategory
import com.runanywhere.sdk.public.extensions.Models.ModelFileDescriptor
import com.runanywhere.sdk.public.extensions.registerLoraAdapter
import com.runanywhere.sdk.public.extensions.registerModel
import com.runanywhere.sdk.public.extensions.registerMultiFileModel

object ModelList {
    private const val TAG = "ModelList"

    // LLM Models
    private val llmModels = listOf(
        AppModel(id = "smollm2-360m-q8_0", name = "SmolLM2 360M Q8_0",
            url = "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf",
            framework = InferenceFramework.LLAMA_CPP, category = ModelCategory.LANGUAGE,
            memoryRequirement = 500_000_000),
        AppModel(id = "llama-2-7b-chat-q4_k_m", name = "Llama 2 7B Chat Q4_K_M",
            url = "https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/llama-2-7b-chat.Q4_K_M.gguf",
            framework = InferenceFramework.LLAMA_CPP, category = ModelCategory.LANGUAGE,
            memoryRequirement = 4_000_000_000),
        AppModel(id = "mistral-7b-instruct-q4_k_m", name = "Mistral 7B Instruct Q4_K_M",
            url = "https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct-v0.1.Q4_K_M.gguf",
            framework = InferenceFramework.LLAMA_CPP, category = ModelCategory.LANGUAGE,
            memoryRequirement = 4_000_000_000),
        AppModel(id = "qwen2.5-0.5b-instruct-q6_k", name = "Qwen 2.5 0.5B Instruct Q6_K",
            url = "https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf",
            framework = InferenceFramework.LLAMA_CPP, category = ModelCategory.LANGUAGE,
            memoryRequirement = 600_000_000),
        AppModel(id = "lfm2-350m-q4_k_m", name = "LiquidAI LFM2 350M Q4_K_M",
            url = "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf",
            framework = InferenceFramework.LLAMA_CPP, category = ModelCategory.LANGUAGE,
            memoryRequirement = 250_000_000, supportsLoraAdapters = true),
        AppModel(id = "lfm2-350m-q8_0", name = "LiquidAI LFM2 350M Q8_0",
            url = "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf",
            framework = InferenceFramework.LLAMA_CPP, category = ModelCategory.LANGUAGE,
            memoryRequirement = 400_000_000, supportsLoraAdapters = true),
        AppModel(id = "lfm2-1.2b-tool-q4_k_m", name = "LiquidAI LFM2 1.2B Tool Q4_K_M",
            url = "https://huggingface.co/LiquidAI/LFM2-1.2B-Tool-GGUF/resolve/main/LFM2-1.2B-Tool-Q4_K_M.gguf",
            framework = InferenceFramework.LLAMA_CPP, category = ModelCategory.LANGUAGE,
            memoryRequirement = 800_000_000),
        AppModel(id = "lfm2-1.2b-tool-q8_0", name = "LiquidAI LFM2 1.2B Tool Q8_0",
            url = "https://huggingface.co/LiquidAI/LFM2-1.2B-Tool-GGUF/resolve/main/LFM2-1.2B-Tool-Q8_0.gguf",
            framework = InferenceFramework.LLAMA_CPP, category = ModelCategory.LANGUAGE,
            memoryRequirement = 1_400_000_000),
    )

    // STT / TTS
    private val sttModels = listOf(
        AppModel(id = "sherpa-onnx-whisper-tiny.en", name = "Sherpa Whisper Tiny (ONNX)",
            url = "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz",
            framework = InferenceFramework.ONNX, category = ModelCategory.SPEECH_RECOGNITION,
            memoryRequirement = 75_000_000),
    )
    private val ttsModels = listOf(
        AppModel(id = "vits-piper-en_US-lessac-medium", name = "Piper TTS (US English - Medium)",
            url = "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz",
            framework = InferenceFramework.ONNX, category = ModelCategory.SPEECH_SYNTHESIS,
            memoryRequirement = 65_000_000),
        AppModel(id = "vits-piper-en_GB-alba-medium", name = "Piper TTS (British English)",
            url = "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_GB-alba-medium.tar.gz",
            framework = InferenceFramework.ONNX, category = ModelCategory.SPEECH_SYNTHESIS,
            memoryRequirement = 65_000_000),
    )

    // Embedding
    private val embeddingModels = listOf(
        AppModel(id = "all-minilm-l6-v2", name = "All MiniLM L6 v2 (Embedding)",
            url = "https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx",
            framework = InferenceFramework.ONNX, category = ModelCategory.EMBEDDING,
            memoryRequirement = 25_500_000,
            companionFiles = listOf(
                ModelCompanionFile(url = "https://huggingface.co/Xenova/all-MiniLM-L6-v2/raw/main/vocab.txt", filename = "vocab.txt"),
                ModelCompanionFile(url = "https://huggingface.co/Xenova/all-MiniLM-L6-v2/raw/main/tokenizer.json", filename = "tokenizer.json"),
            )),
    )

    // LoRA Adapters (from Void2377/Qwen on HuggingFace — real standalone LoRA GGUF files)
    private val loraAdapters = listOf(
        LoraAdapterCatalogEntry(
            id = "chat-assistant-lora",
            name = "Chat Assistant",
            description = "Enhances conversational chat ability",
            downloadUrl = "https://huggingface.co/Void2377/Qwen/resolve/main/lora/chat_assistant-lora-Q8_0.gguf",
            filename = "chat_assistant-lora-Q8_0.gguf",
            compatibleModelIds = listOf("lfm2-350m-q4_k_m", "lfm2-350m-q8_0"),
            fileSize = 690_176,
            defaultScale = 1.0f,
        ),
        LoraAdapterCatalogEntry(
            id = "summarizer-lora",
            name = "Summarizer",
            description = "Specialized for text summarization tasks",
            downloadUrl = "https://huggingface.co/Void2377/Qwen/resolve/main/lora/summarizer-lora-Q8_0.gguf",
            filename = "summarizer-lora-Q8_0.gguf",
            compatibleModelIds = listOf("lfm2-350m-q4_k_m", "lfm2-350m-q8_0"),
            fileSize = 690_176,
            defaultScale = 1.0f,
        ),
        LoraAdapterCatalogEntry(
            id = "translator-lora",
            name = "Translator",
            description = "Improves translation between languages",
            downloadUrl = "https://huggingface.co/Void2377/Qwen/resolve/main/lora/translator-lora-Q8_0.gguf",
            filename = "translator-lora-Q8_0.gguf",
            compatibleModelIds = listOf("lfm2-350m-q4_k_m", "lfm2-350m-q8_0"),
            fileSize = 690_176,
            defaultScale = 1.0f,
        ),
        LoraAdapterCatalogEntry(
            id = "sentiment-lora",
            name = "Sentiment Analysis",
            description = "Fine-tuned for sentiment analysis tasks",
            downloadUrl = "https://huggingface.co/Void2377/Qwen/resolve/main/lora/sentiment-lora-Q8_0.gguf",
            filename = "sentiment-lora-Q8_0.gguf",
            compatibleModelIds = listOf("lfm2-350m-q4_k_m", "lfm2-350m-q8_0"),
            fileSize = 690_176,
            defaultScale = 1.0f,
        ),
        LoraAdapterCatalogEntry(
            id = "uncensored-chat-lora",
            name = "Uncensored Chat",
            description = "Removes safety guardrails for uncensored responses",
            downloadUrl = "https://huggingface.co/Void2377/Qwen/resolve/main/lora/uncensored_chat-lora-Q8_0.gguf",
            filename = "uncensored_chat-lora-Q8_0.gguf",
            compatibleModelIds = listOf("lfm2-350m-q4_k_m", "lfm2-350m-q8_0"),
            fileSize = 1_372_160,
            defaultScale = 1.0f,
        ),
    )

    // VLM
    private val vlmModels = listOf(
        AppModel(id = "smolvlm-500m-instruct-q8_0", name = "SmolVLM 500M Instruct",
            url = "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-vlm-models-v1/smolvlm-500m-instruct-q8_0.tar.gz",
            framework = InferenceFramework.LLAMA_CPP, category = ModelCategory.MULTIMODAL,
            memoryRequirement = 600_000_000),
        AppModel(id = "lfm2-vl-450m-q8_0", name = "LFM2-VL 450M", url = "",
            framework = InferenceFramework.LLAMA_CPP, category = ModelCategory.MULTIMODAL,
            memoryRequirement = 600_000_000,
            files = listOf(
                ModelFileDescriptor(url = "https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/LFM2-VL-450M-Q8_0.gguf", filename = "LFM2-VL-450M-Q8_0.gguf"),
                ModelFileDescriptor(url = "https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/mmproj-LFM2-VL-450M-Q8_0.gguf", filename = "mmproj-LFM2-VL-450M-Q8_0.gguf"),
            )),
        AppModel(id = "qwen2-vl-2b-instruct-q4_k_m", name = "Qwen2-VL 2B Instruct", url = "",
            framework = InferenceFramework.LLAMA_CPP, category = ModelCategory.MULTIMODAL,
            memoryRequirement = 1_800_000_000,
            files = listOf(
                ModelFileDescriptor(url = "https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/Qwen2-VL-2B-Instruct-Q4_K_M.gguf", filename = "Qwen2-VL-2B-Instruct-Q4_K_M.gguf"),
                ModelFileDescriptor(url = "https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf", filename = "mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf"),
            )),
    )

    fun setupModels() {
        Log.i(TAG, "Registering backends and models...")
        LlamaCPP.register(priority = 100)
        ONNX.register(priority = 100)
        Log.i(TAG, "Backends registered")

        val singleFileModels = llmModels + sttModels + ttsModels
        for (model in singleFileModels) {
            RunAnywhere.registerModel(
                id = model.id, name = model.name, url = model.url,
                framework = model.framework, modality = model.category,
                memoryRequirement = model.memoryRequirement,
                supportsLora = model.supportsLoraAdapters,
            )
        }
        Log.i(TAG, "LLM/STT/TTS models registered (${singleFileModels.size})")

        for (model in embeddingModels) {
            RunAnywhere.registerMultiFileModel(
                id = model.id, name = model.name, primaryUrl = model.url,
                companionFiles = model.companionFiles,
                framework = model.framework, modality = model.category,
                memoryRequirement = model.memoryRequirement,
            )
        }
        Log.i(TAG, "Embedding models registered (${embeddingModels.size})")

        for (model in vlmModels) {
            if (model.files.isNotEmpty()) {
                RunAnywhere.registerMultiFileModel(
                    id = model.id, name = model.name, files = model.files,
                    framework = model.framework, modality = model.category,
                    memoryRequirement = model.memoryRequirement,
                )
            } else {
                RunAnywhere.registerModel(
                    id = model.id, name = model.name, url = model.url,
                    framework = model.framework, modality = model.category,
                    memoryRequirement = model.memoryRequirement,
                )
            }
        }
        Log.i(TAG, "VLM models registered (${vlmModels.size})")

        // Register LoRA adapters
        for (adapter in loraAdapters) {
            RunAnywhere.registerLoraAdapter(adapter)
        }
        Log.i(TAG, "LoRA adapters registered (${loraAdapters.size})")
        Log.i(TAG, "All models registered")
    }
}
