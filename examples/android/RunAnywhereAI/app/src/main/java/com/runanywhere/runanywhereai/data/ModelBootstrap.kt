package com.runanywhere.runanywhereai.data

import ai.runanywhere.proto.v1.ArchiveStructure
import ai.runanywhere.proto.v1.ArchiveType
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.LoraAdapterCatalogEntry
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelFileDescriptor
import ai.runanywhere.proto.v1.ModelFileRole
import ai.runanywhere.proto.v1.ModelListRequest
import ai.runanywhere.proto.v1.ModelSource
import com.runanywhere.sdk.core.onnx.ONNX
import com.runanywhere.sdk.features.TTS.System.SystemTTSModule
import com.runanywhere.sdk.llm.llamacpp.LlamaCPP
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.listModels
import com.runanywhere.sdk.public.extensions.lora
import com.runanywhere.sdk.public.extensions.pluginLoader
import com.runanywhere.sdk.public.extensions.registerModel
import com.runanywhere.sdk.public.hybrid.BACKEND
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
        try {
            RunAnywhere.listModels(ModelListRequest()).models?.models.orEmpty().forEach { m ->
                Timber.d("📋 ${m.id}: is_downloaded=${m.is_downloaded} local_path='${m.local_path}'")
            }
        } catch (_: Throwable) {
            // dev diag only
        }
    }

    private suspend fun registerBackends() {
        try {
            LlamaCPP.register()
            ONNX.register()
            // Registers the built-in System TTS plugin so the native engine
            // registry can route TTS requests at runtime. Note: System TTS is
            // exposed differently in each example app today — this is
            // intentionally a documented divergence rather than a single
            // canonical pattern (no shared SDK affordance exists yet):
            //
            //   - Android (here): `SystemTTSModule.register()` seeds a real
            //     built-in `system-tts` `RAModelInfo` (framework =
            //     INFERENCE_FRAMEWORK_SYSTEM_TTS, built_in = true,
            //     is_downloaded = true) into the proto registry via the
            //     SDK module's internal registration path.
            //     `listModels()` returns it like any other ready entry, and
            //     `ModelSelectionBottomSheet` treats
            //     `INFERENCE_FRAMEWORK_SYSTEM_TTS` as built-in alongside
            //     `FOUNDATION_MODELS`, so the picker surfaces System TTS as a
            //     normal registry-backed row (no out-of-band UI plumbing).
            //   - Flutter (Apple only): same SDK-module-seeds-ModelInfo
            //     pattern as Android, gated to iOS/macOS at the example-app
            //     level via `RunAnywhere.models.register('system-tts', ...)`
            //     because the commons `platform` engine plugin is
            //     Apple-only (CMakeLists `if(APPLE AND RAC_BUILD_PLATFORM)`).
            //   - iOS: no `system-tts` ModelInfo is seeded; the picker
            //     short-circuits via a hardcoded `SystemTTSRow` SwiftUI view.
            //   - React Native: builds a synthetic `system-tts`
            //     `ModelInfoSummary` inline at click time.
            //   - Web: System TTS is not currently surfaced.
            //
            // Canonical pattern (what Android + Flutter Apple already share):
            // an SDK module registers a real `system-tts` `RAModelInfo` so the
            // picker treats it like any other ready row. Convergence of iOS
            // and RN onto this pattern is tracked separately (pass2-syn-098)
            // and is a non-blocking polish item.
            SystemTTSModule.register()
            Timber.i("Core backends registered")
        } catch (e: Exception) {
            Timber.e(e, "Failed to register core backends")
        }
        // Diagnostic: list all plugins registered with the unified plugin
        // registry via the public `RunAnywhere.pluginLoader.registeredNames()`
        // surface. Helps debug "no backend route" issues by surfacing exactly
        // which plugin names made it past rac_plugin_register.
        try {
            val names = RunAnywhere.pluginLoader.registeredNames()
            Timber.i("🔌 Plugins registered (count=${names.size}): ${names.joinToString()}")
        } catch (e: Throwable) {
            Timber.w(e, "Plugin diagnostic listing failed")
        }
    }

    /**
     * Seed the curated model catalog. Each call registers a ModelInfo into
     * the native registry via the proto ABI (`rac_register_model_from_url_proto`
     * → `rac_model_registry_register_proto`). The commons registry merges
     * runtime fields (`local_path`, `is_downloaded`, `checksum_sha256`,
     * multi-file per-file `local_path`) from the existing snapshot on
     * re-registration, so re-running this on app launch is idempotent and
     * cannot clobber download progress. Failures are logged and do not abort
     * the seed pass.
     *
     * Model list mirrors `RunAnywhereAIApp.swift:registerModulesAndModels`
     * (commit 34e32b68a deleted the equivalent Android `ModelList.kt`).
     */
    private suspend fun seedCuratedCatalog() {
        Timber.i("🌱 Seeding curated model catalog...")
        var registered = 0
        var failed = 0

        for (m in LLM_MODELS) {
            if (tryRegisterSingle(m)) registered++ else failed++
        }
        for (m in VLM_MULTIFILE_MODELS) {
            if (tryRegisterMultiFile(m)) registered++ else failed++
        }
        for (m in VLM_ARCHIVE_MODELS) {
            if (tryRegisterArchive(m)) registered++ else failed++
        }
        for (m in STT_MODELS) {
            if (tryRegisterArchive(m)) registered++ else failed++
        }
        for (m in TTS_MODELS) {
            if (tryRegisterArchive(m)) registered++ else failed++
        }
        for (m in VAD_MODELS) {
            if (tryRegisterSingle(m)) registered++ else failed++
        }
        for (m in EMBEDDING_MULTIFILE_MODELS) {
            if (tryRegisterMultiFile(m)) registered++ else failed++
        }

        // Sarvam STT — test key, auto-detect language (no languageCode).
        BACKEND.SARVAM.register(
            id = "saaras",
            model = "saaras:v3",
            apiKey = "sk_4mtoxk81_7Eh1NNJXnJJguRc4M8EY9JSa",
        )

        Timber.i("🌱 Catalog seed complete — registered=$registered, failed=$failed")
    }

    /**
     * Seed the curated LoRA adapter catalog. The deleted
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
                    compatible_models = listOf("qwen2.5-0.5b-instruct-q6_k"),
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

    /**
     * Register a single-file model via the canonical
     * `RunAnywhere.registerModel(...)` public API (mirrors Swift's
     * `registerLLM` helper in
     * `examples/ios/RunAnywhereAI/.../App/RunAnywhereAIApp.swift`).
     */
    private suspend fun tryRegisterSingle(m: SingleFileModel): Boolean =
        try {
            RunAnywhere.registerModel(
                id = m.id,
                name = m.name,
                url = m.url,
                framework = m.framework,
                modality = m.category,
                artifactType = null,
                memoryRequirement = m.memoryBytes,
                supportsThinking = m.supportsThinking,
                supportsLora = m.supportsLora,
            )
            true
        } catch (e: Exception) {
            Timber.e(e, "tryRegisterSingle failed: ${m.id}")
            false
        }

    /**
     * Register an archive-based model (sherpa STT/TTS .tar.gz) via the
     * canonical `RunAnywhere.registerModel(archiveUrl:structure:...)`
     * public API. Preserves archive type + on-disk layout so the C++
     * download orchestrator extracts the archive into the directory
     * layout each backend expects (without this, the .tar.gz lands on
     * disk unextracted and the sherpa backend fails to load).
     */
    private suspend fun tryRegisterArchive(m: ArchiveModel): Boolean =
        try {
            RunAnywhere.registerModel(
                archiveUrl = m.url,
                structure = m.structure,
                id = m.id,
                name = m.name,
                framework = m.framework,
                modality = m.category,
                archiveType = m.archiveType,
                memoryRequirement = m.memoryBytes,
                supportsThinking = false,
                supportsLora = false,
            )
            true
        } catch (e: Exception) {
            Timber.e(e, "tryRegisterArchive failed: ${m.id}")
            false
        }

    /**
     * Register a multi-file model (e.g. VLMs with a separate mmproj,
     * MiniLM embedding with vocab.txt) via the canonical
     * `RunAnywhere.registerModel(multiFile:...)` public API. The SDK
     * seeds the proto `expected_files` from the descriptors so the
     * commons download planner walks the per-descriptor loop instead of
     * falling through to the single-URL branch.
     */
    private suspend fun tryRegisterMultiFile(m: MultiFileModel): Boolean =
        try {
            val descriptors =
                m.files.mapIndexed { idx, (url, filename) ->
                    ModelFileDescriptor(
                        url = url,
                        filename = filename,
                        is_required = true,
                        role =
                            if (idx == 0) {
                                ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL
                            } else {
                                ModelFileRole.MODEL_FILE_ROLE_COMPANION
                            },
                    )
                }
            RunAnywhere.registerModel(
                multiFile = descriptors,
                id = m.id,
                name = m.name,
                framework = m.framework,
                modality = m.category,
                memoryRequirement = m.memoryBytes,
                contextLength = null,
                supportsThinking = false,
                source = ModelSource.MODEL_SOURCE_REMOTE,
            )
            true
        } catch (e: Exception) {
            Timber.e(e, "tryRegisterMultiFile failed: ${m.id}")
            false
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

    /**
     * Archive-based model (e.g. sherpa STT/TTS .tar.gz). Mirrors iOS's
     * `registerModel(archive:structure:archive:...)` registration form.
     */
    private data class ArchiveModel(
        val id: String,
        val name: String,
        val url: String,
        val framework: InferenceFramework,
        val category: ModelCategory,
        val memoryBytes: Long,
        val archiveType: ArchiveType,
        val structure: ArchiveStructure,
    )

    // MARK: - Curated catalog

    // Baseline LLM catalog. Mirrors the iOS / Flutter / RN example apps —
    // see `RunAnywhereAIApp.swift:registerModulesAndModels` and
    // `runanywhere_ai_app.dart:_registerModulesAndModels`. Keep these in
    // lockstep so cross-platform demos surface the same model IDs and the
    // shared Solutions YAML resolves on every platform.
    private val LLM_MODELS =
        listOf(
            SingleFileModel(
                id = "smollm2-360m-q8_0",
                name = "SmolLM2 360M Q8_0",
                url = "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
                category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
                memoryBytes = 386_404_416,
            ),
            SingleFileModel(
                id = "llama-2-7b-chat-q4_k_m",
                name = "Llama 2 7B Chat Q4_K_M",
                url = "https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/llama-2-7b-chat.Q4_K_M.gguf",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
                category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
                memoryBytes = 4_000_000_000,
            ),
            SingleFileModel(
                id = "mistral-7b-instruct-q4_k_m",
                name = "Mistral 7B Instruct Q4_K_M",
                url = "https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct-v0.1.Q4_K_M.gguf",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
                category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
                memoryBytes = 4_000_000_000,
            ),
            // Q6_K matches the iOS / Flutter / RN catalogs. The abliterated
            // LoRA above is f16 and applies cleanly across Qwen 2.5 0.5B
            // quantizations, so `compatible_models` points to this ID.
            SingleFileModel(
                id = "qwen2.5-0.5b-instruct-q6_k",
                name = "Qwen 2.5 0.5B Instruct Q6_K",
                url = "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf",
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
                id = "qwen3-4b-q4_k_m",
                name = "Qwen3 4B Q4_K_M",
                url = "https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
                category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
                memoryBytes = 2_800_000_000,
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
                id = "lfm2-350m-q8_0",
                name = "LiquidAI LFM2 350M Q8_0",
                url = "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
                category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
                memoryBytes = 400_000_000,
            ),
            SingleFileModel(
                id = "lfm2-1.2b-tool-q4_k_m",
                name = "LiquidAI LFM2 1.2B Tool Q4_K_M",
                url = "https://huggingface.co/LiquidAI/LFM2-1.2B-Tool-GGUF/resolve/main/LFM2-1.2B-Tool-Q4_K_M.gguf",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
                category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
                memoryBytes = 800_000_000,
            ),
            SingleFileModel(
                id = "lfm2-1.2b-tool-q8_0",
                name = "LiquidAI LFM2 1.2B Tool Q8_0",
                url = "https://huggingface.co/LiquidAI/LFM2-1.2B-Tool-GGUF/resolve/main/LFM2-1.2B-Tool-Q8_0.gguf",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
                category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
                memoryBytes = 1_400_000_000,
            ),
        )

    /**
     * VLM tarballs that must extract into a per-model directory before load.
     * Mirrors `RunAnywhereAIApp.swift` which uses `registerArchive(... archive:
     * .tarGz, structure: .directoryBased)` for the same SmolVLM asset. Going
     * through `tryRegisterArchive` sets `archive_artifact` /
     * `MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE` so the C++ download orchestrator
     * unpacks the archive into the directory layout the llama.cpp VLM backend
     * expects; treating the same URL as a single file would land an
     * unextracted .tar.gz on disk and the backend would fail to load.
     */
    private val VLM_ARCHIVE_MODELS =
        listOf(
            ArchiveModel(
                id = "smolvlm-500m-instruct-q8_0",
                name = "SmolVLM 500M Instruct",
                url = "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-vlm-models-v1/smolvlm-500m-instruct-q8_0.tar.gz",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
                category = ModelCategory.MODEL_CATEGORY_MULTIMODAL,
                memoryBytes = 600_000_000,
                archiveType = ArchiveType.ARCHIVE_TYPE_TAR_GZ,
                structure = ArchiveStructure.ARCHIVE_STRUCTURE_DIRECTORY_BASED,
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
            ArchiveModel(
                id = "sherpa-onnx-whisper-tiny.en",
                name = "Sherpa Whisper Tiny (ONNX)",
                url = "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
                category = ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
                memoryBytes = 75_000_000,
                archiveType = ArchiveType.ARCHIVE_TYPE_TAR_GZ,
                structure = ArchiveStructure.ARCHIVE_STRUCTURE_NESTED_DIRECTORY,
            ),
        )

    private val TTS_MODELS =
        listOf(
            ArchiveModel(
                id = "vits-piper-en_US-lessac-medium",
                name = "Piper TTS (US English - Medium)",
                url = "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
                category = ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
                memoryBytes = 65_000_000,
                archiveType = ArchiveType.ARCHIVE_TYPE_TAR_GZ,
                structure = ArchiveStructure.ARCHIVE_STRUCTURE_NESTED_DIRECTORY,
            ),
            ArchiveModel(
                id = "vits-piper-en_GB-alba-medium",
                name = "Piper TTS (British English)",
                url = "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_GB-alba-medium.tar.gz",
                framework = InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
                category = ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
                memoryBytes = 65_000_000,
                archiveType = ArchiveType.ARCHIVE_TYPE_TAR_GZ,
                structure = ArchiveStructure.ARCHIVE_STRUCTURE_NESTED_DIRECTORY,
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
                // Actual silero_vad.onnx artifact size (verified Content-Length).
                // memoryBytes is passed as memoryRequirement and doubles as
                // download_size_bytes (see RunAnywhereStorage.kt), which feeds the
                // post-finalize download size guard. An over-stated
                // 5 MB tripped the guard on a valid ~2.3 MB download.
                memoryBytes = 2_327_524,
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
