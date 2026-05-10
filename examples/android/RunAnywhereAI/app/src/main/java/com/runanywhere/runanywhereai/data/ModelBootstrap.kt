package com.runanywhere.runanywhereai.data

import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.LoraAdapterCatalogEntry
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelFileDescriptor
import ai.runanywhere.proto.v1.ModelRegistryRefreshRequest
import com.runanywhere.sdk.core.onnx.ONNX
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.llm.llamacpp.LlamaCPP
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.availableModels
import com.runanywhere.sdk.public.extensions.lora
import com.runanywhere.sdk.public.extensions.refreshModelRegistry
import com.runanywhere.sdk.public.extensions.registerModel
import com.runanywhere.sdk.public.extensions.registerMultiFileModel
import timber.log.Timber

/**
 * Android model bootstrap. Mirrors the iOS `registerModulesAndModels()` in
 * `examples/ios/RunAnywhereAI/.../RunAnywhereAIApp.swift` and the Flutter
 * equivalent — hardcoded curated catalog seeded via `RunAnywhere.registerModel`
 * / `registerMultiFileModel`. Dev-mode Supabase assignment fetch returns zero
 * models, and the C-ABI proto `rescan_local` path has no filesystem callbacks,
 * so without this seed the Model Selection sheet is empty on first launch.
 */
object ModelBootstrap {
    suspend fun setupModels() {
        Timber.i("Registering backends + curated model catalog + refreshing native registry...")
        registerBackends()
        seedCuratedCatalog()
        seedLoRAAdapters()
        refreshNativeCatalog()
        try {
            RunAnywhere.availableModels().forEach { m ->
                Timber.d("📋 ${m.id}: is_downloaded=${m.is_downloaded} local_path='${m.local_path}'")
            }
        } catch (_: Throwable) { /* dev diag only */ }
    }

    /**
     * Snapshot of model IDs already in the native registry. Used to skip
     * re-registration so we don't overwrite the downloaded `local_path` /
     * `is_downloaded` flags maintained by the C++ self-heal path.
     */
    private suspend fun existingRegistryIds(): Set<String> =
        try {
            RunAnywhere.availableModels().map { it.id }.toSet()
        } catch (_: Throwable) {
            emptySet()
        }

    private fun registerBackends() {
        try {
            LlamaCPP.register(priority = 100)
            ONNX.register(priority = 100)
            Timber.i("Core backends registered")
        } catch (e: Exception) {
            Timber.e(e, "Failed to register core backends")
        }
    }

    /**
     * Seed the curated model catalog. Each call registers a ModelInfo into
     * the native registry via the proto ABI (`rac_model_registry_save_proto`).
     * Failures are logged and do not abort the seed pass.
     *
     * Model list mirrors `RunAnywhereAIApp.swift:registerModulesAndModels`
     * (commit 34e32b68a deleted the equivalent Android `ModelList.kt`).
     */
    private suspend fun seedCuratedCatalog() {
        Timber.i("🌱 Seeding curated model catalog...")
        // Avoid re-registering models that are already in the registry — saving
        // an existing entry would clobber `local_path` / `is_downloaded` set
        // by the download self-heal (KOT-DOWNLOAD-004) and force users to
        // re-download on every app launch.
        val alreadyKnown = existingRegistryIds()
        var registered = 0
        var skipped = 0
        var failed = 0

        for (m in LLM_MODELS) {
            if (m.id in alreadyKnown) { skipped++; continue }
            if (tryRegisterSingle(m)) registered++ else failed++
        }
        for (m in VLM_MULTIFILE_MODELS) {
            if (m.id in alreadyKnown) { skipped++; continue }
            if (tryRegisterMultiFile(m)) registered++ else failed++
        }
        for (m in VLM_SINGLE_MODELS) {
            if (m.id in alreadyKnown) { skipped++; continue }
            if (tryRegisterSingle(m)) registered++ else failed++
        }
        for (m in STT_MODELS) {
            if (m.id in alreadyKnown) { skipped++; continue }
            if (tryRegisterSingle(m)) registered++ else failed++
        }
        for (m in TTS_MODELS) {
            if (m.id in alreadyKnown) { skipped++; continue }
            if (tryRegisterSingle(m)) registered++ else failed++
        }
        for (m in VAD_MODELS) {
            if (m.id in alreadyKnown) { skipped++; continue }
            if (tryRegisterSingle(m)) registered++ else failed++
        }
        for (m in EMBEDDING_MULTIFILE_MODELS) {
            if (m.id in alreadyKnown) { skipped++; continue }
            if (tryRegisterMultiFile(m)) registered++ else failed++
        }

        Timber.i("🌱 Catalog seed complete — registered=$registered, preserved=$skipped, failed=$failed")
    }

    /**
     * KOT-LORA-001: Seed the curated LoRA adapter catalog. The deleted
     * `ModelList.kt` registered one adapter (abliterated-lora) for the
     * Qwen 2.5 0.5B base model so the apply/remove pipeline could be
     * exercised from the Chat / LoRA Manager screens. This restores it
     * via the new `RunAnywhere.lora.register(entry)` namespace API.
     *
     * Note: this LoRA was trained against the third-party Void2377
     * re-packaged base GGUF. The base model in this app points to the
     * official Qwen/Qwen2.5-0.5B-Instruct-GGUF release, so adapter weights
     * may not align cleanly — output quality could be degraded even though
     * the LoRA load/apply flow itself remains testable.
     */
    private suspend fun seedLoRAAdapters() {
        val adapters =
            listOf(
                LoraAdapterCatalogEntry(
                    id = "abliterated-lora",
                    name = "Abliterated LoRA (F16)",
                    description = "Removes refusal behavior — model answers directly without disclaimers",
                    url = "https://huggingface.co/Void2377/qwen-lora-gguf/resolve/main/qwen2.5-0.5b-abliterated-lora-f16.gguf",
                    filename = "qwen2.5-0.5b-abliterated-lora-f16.gguf",
                    compatible_models = listOf("qwen2.5-0.5b-instruct-q8_0"),
                    size_bytes = 17_600_000,
                    default_scale = 1.0f,
                ),
            )

        var registered = 0
        var failed = 0
        for (adapter in adapters) {
            try {
                RunAnywhere.lora.register(adapter)
                registered++
            } catch (e: Exception) {
                Timber.e(e, "Failed to register LoRA adapter: ${adapter.id}")
                failed++
            }
        }
        Timber.i("🌱 LoRA adapter seed complete — registered=$registered, failed=$failed")
    }

    private fun tryRegisterSingle(m: SingleFileModel): Boolean =
        try {
            RunAnywhere.registerModel(
                id = m.id,
                name = m.name,
                url = m.url,
                framework = m.framework,
                modality = m.category,
                memoryRequirement = m.memoryBytes,
                supportsLora = m.supportsLora,
                supportsThinking = m.supportsThinking,
            )
            true
        } catch (e: Exception) {
            Timber.e(e, "Failed to register model: ${m.id}")
            false
        }

    private fun tryRegisterMultiFile(m: MultiFileModel): Boolean =
        try {
            RunAnywhere.registerMultiFileModel(
                id = m.id,
                name = m.name,
                files = m.files.map { ModelFileDescriptor(url = it.first, filename = it.second) },
                framework = m.framework,
                modality = m.category,
                memoryRequirement = m.memoryBytes,
            )
            true
        } catch (e: Exception) {
            Timber.e(e, "Failed to register multi-file model: ${m.id}")
            false
        }

    private suspend fun refreshNativeCatalog() {
        try {
            val result =
                RunAnywhere.refreshModelRegistry(
                    ModelRegistryRefreshRequest(
                        include_remote_catalog = true,
                        rescan_local = true,
                        prune_orphans = false,
                        include_downloaded_state = true,
                    ),
                )
            if (result.success) {
                Timber.i(
                    "Native model catalog refreshed: registered=${result.registered_count}, " +
                        "downloaded=${result.downloaded_count}, available=${result.available_count}",
                )
            } else {
                Timber.w(
                    "Native model catalog refresh returned an error: " +
                        result.error_message.ifBlank { "unknown error" },
                )
            }
            result.warnings.forEach { warning ->
                Timber.w("Native model catalog refresh warning: $warning")
            }
        } catch (e: SDKException) {
            Timber.w(
                e,
                "Native model catalog refresh unavailable: ${e.error.message}",
            )
        }
    }

    // MARK: - Catalog data classes

    private data class SingleFileModel(
        val id: String,
        val name: String,
        val url: String,
        val framework: InferenceFramework,
        val category: ModelCategory,
        val memoryBytes: Long,
        val supportsLora: Boolean = false,
        val supportsThinking: Boolean = false,
    )

    private data class MultiFileModel(
        val id: String,
        val name: String,
        val framework: InferenceFramework,
        val category: ModelCategory,
        val memoryBytes: Long,
        /** (url, filename) pairs. First entry is the primary model file. */
        val files: List<Pair<String, String>>,
    )

    // MARK: - Curated catalog

    private val LLM_MODELS =
        listOf(
            SingleFileModel(
                id = "smollm2-360m-q8_0",
                name = "SmolLM2 360M Q8_0",
                url = "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
                category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
                memoryBytes = 500_000_000,
            ),
            SingleFileModel(
                id = "qwen2.5-0.5b-instruct-q8_0",
                name = "Qwen 2.5 0.5B Instruct Q8_0",
                url = "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q8_0.gguf",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
                category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
                memoryBytes = 600_000_000,
                supportsLora = true,
            ),
            SingleFileModel(
                id = "qwen2.5-1.5b-instruct-q4_k_m",
                name = "Qwen 2.5 1.5B Instruct Q4_K_M",
                url = "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
                category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
                memoryBytes = 2_500_000_000,
            ),
            SingleFileModel(
                id = "qwen3-0.6b-q4_k_m",
                name = "Qwen3 0.6B Q4_K_M",
                url = "https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
                category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
                memoryBytes = 500_000_000,
                supportsThinking = true,
            ),
            SingleFileModel(
                id = "qwen3-1.7b-q4_k_m",
                name = "Qwen3 1.7B Q4_K_M",
                url = "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
                category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
                memoryBytes = 1_200_000_000,
                supportsThinking = true,
            ),
            SingleFileModel(
                id = "lfm2-350m-q4_k_m",
                name = "LiquidAI LFM2 350M Q4_K_M",
                url = "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
                category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
                memoryBytes = 250_000_000,
            ),
            SingleFileModel(
                id = "lfm2-1.2b-tool-q4_k_m",
                name = "LiquidAI LFM2 1.2B Tool Q4_K_M",
                url = "https://huggingface.co/LiquidAI/LFM2-1.2B-Tool-GGUF/resolve/main/LFM2-1.2B-Tool-Q4_K_M.gguf",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
                category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
                memoryBytes = 800_000_000,
            ),
        )

    private val VLM_SINGLE_MODELS =
        listOf(
            SingleFileModel(
                id = "smolvlm-500m-instruct-q8_0",
                name = "SmolVLM 500M Instruct",
                url = "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-vlm-models-v1/smolvlm-500m-instruct-q8_0.tar.gz",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
                category = ModelCategory.MODEL_CATEGORY_MULTIMODAL,
                memoryBytes = 600_000_000,
            ),
        )

    private val VLM_MULTIFILE_MODELS =
        listOf(
            MultiFileModel(
                id = "lfm2-vl-450m-q8_0",
                name = "LFM2-VL 450M",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
                category = ModelCategory.MODEL_CATEGORY_MULTIMODAL,
                memoryBytes = 600_000_000,
                files =
                    listOf(
                        "https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/LFM2-VL-450M-Q8_0.gguf" to "LFM2-VL-450M-Q8_0.gguf",
                        "https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/mmproj-LFM2-VL-450M-Q8_0.gguf" to "mmproj-LFM2-VL-450M-Q8_0.gguf",
                    ),
            ),
            MultiFileModel(
                id = "qwen2-vl-2b-instruct-q4_k_m",
                name = "Qwen2-VL 2B Instruct",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
                category = ModelCategory.MODEL_CATEGORY_MULTIMODAL,
                memoryBytes = 1_800_000_000,
                files =
                    listOf(
                        "https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/Qwen2-VL-2B-Instruct-Q4_K_M.gguf" to "Qwen2-VL-2B-Instruct-Q4_K_M.gguf",
                        "https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf" to "mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf",
                    ),
            ),
        )

    private val STT_MODELS =
        listOf(
            SingleFileModel(
                id = "sherpa-onnx-whisper-tiny.en",
                name = "Sherpa Whisper Tiny (ONNX)",
                url = "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
                category = ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
                memoryBytes = 75_000_000,
            ),
        )

    private val TTS_MODELS =
        listOf(
            SingleFileModel(
                id = "vits-piper-en_US-lessac-medium",
                name = "Piper TTS (US English - Medium)",
                url = "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
                category = ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
                memoryBytes = 65_000_000,
            ),
            SingleFileModel(
                id = "vits-piper-en_GB-alba-medium",
                name = "Piper TTS (British English)",
                url = "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_GB-alba-medium.tar.gz",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
                category = ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
                memoryBytes = 65_000_000,
            ),
        )

    private val VAD_MODELS =
        listOf(
            SingleFileModel(
                id = "silero-vad",
                name = "Silero VAD",
                url = "https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
                category = ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
                memoryBytes = 5_000_000,
            ),
        )

    private val EMBEDDING_MULTIFILE_MODELS =
        listOf(
            MultiFileModel(
                id = "all-minilm-l6-v2",
                name = "All MiniLM L6 v2 (Embedding)",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
                category = ModelCategory.MODEL_CATEGORY_EMBEDDING,
                memoryBytes = 25_500_000,
                files =
                    listOf(
                        "https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx" to "model.onnx",
                        "https://huggingface.co/Xenova/all-MiniLM-L6-v2/raw/main/vocab.txt" to "vocab.txt",
                    ),
            ),
        )
}
