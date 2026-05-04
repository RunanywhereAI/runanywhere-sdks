/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * ModelRegistry extension for CppBridge.
 * Provides direct access to the C++ model registry.
 *
 * Mirrors iOS CppBridge+ModelRegistry.swift architecture:
 * - Uses the global C++ model registry directly via JNI
 * - NO Kotlin-side caching - everything is in C++
 * - Service providers in C++ look up models from this registry
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.InferenceFramework as ProtoInferenceFramework
import ai.runanywhere.proto.v1.ModelCategory as ProtoModelCategory
import ai.runanywhere.proto.v1.ModelFormat as ProtoModelFormat
import ai.runanywhere.proto.v1.ModelInfo as ProtoModelInfo
import ai.runanywhere.proto.v1.ModelInfoList as ProtoModelInfoList
import ai.runanywhere.proto.v1.ModelQuery as ProtoModelQuery
import ai.runanywhere.proto.v1.ModelSource as ProtoModelSource
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import java.io.File

/**
 * Model registry bridge that provides direct access to the C++ model registry.
 *
 * IMPORTANT: This does NOT maintain a Kotlin-side cache. All models are stored
 * in the C++ registry (rac_model_registry) so that C++ service providers can
 * find models when loading. This mirrors the Swift SDK architecture.
 *
 * Usage:
 * - Register models during SDK initialization via [registerModel]
 * - C++ backends will use these models when loading
 * - Download status is updated via [updateDownloadStatus]
 */
object CppBridgeModelRegistry {
    private const val TAG = "CppBridge/CppBridgeModelRegistry"

    /**
     * Model category constants matching C++ RAC_MODEL_CATEGORY_* values.
     */
    object ModelCategory {
        const val LANGUAGE = 0 // RAC_MODEL_CATEGORY_LANGUAGE
        const val SPEECH_RECOGNITION = 1 // RAC_MODEL_CATEGORY_SPEECH_RECOGNITION
        const val SPEECH_SYNTHESIS = 2 // RAC_MODEL_CATEGORY_SPEECH_SYNTHESIS
        const val VISION = 3 // RAC_MODEL_CATEGORY_VISION
        const val IMAGE_GENERATION = 4 // RAC_MODEL_CATEGORY_IMAGE_GENERATION
        const val MULTIMODAL = 5 // RAC_MODEL_CATEGORY_MULTIMODAL
        const val AUDIO = 6 // RAC_MODEL_CATEGORY_AUDIO
        const val EMBEDDING = 7 // RAC_MODEL_CATEGORY_EMBEDDING
        const val VOICE_ACTIVITY_DETECTION = 8 // RAC_MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION
        const val UNKNOWN = 99 // RAC_MODEL_CATEGORY_UNKNOWN
    }

    /**
     * Model type constants (alias for category for backwards compatibility).
     */
    object ModelType {
        const val LLM = ModelCategory.LANGUAGE
        const val STT = ModelCategory.SPEECH_RECOGNITION
        const val TTS = ModelCategory.SPEECH_SYNTHESIS
        const val VAD = ModelCategory.VOICE_ACTIVITY_DETECTION
        const val EMBEDDING = ModelCategory.EMBEDDING
        const val UNKNOWN = ModelCategory.UNKNOWN

        /**
         * Get display name for a model type.
         */
        fun getName(type: Int): String =
            when (type) {
                LLM -> "LLM"
                STT -> "STT"
                TTS -> "TTS"
                VAD -> "VAD"
                EMBEDDING -> "EMBEDDING"
                else -> "UNKNOWN"
            }
    }

    /**
     * Model format constants matching C++ RAC_MODEL_FORMAT_* values.
     */
    object ModelFormat {
        const val ONNX = 0 // RAC_MODEL_FORMAT_ONNX
        const val ORT = 1 // RAC_MODEL_FORMAT_ORT
        const val GGUF = 2 // RAC_MODEL_FORMAT_GGUF
        const val BIN = 3 // RAC_MODEL_FORMAT_BIN
        const val COREML = 4 // RAC_MODEL_FORMAT_COREML
        const val QNN_CONTEXT = 5 // RAC_MODEL_FORMAT_QNN_CONTEXT
        const val UNKNOWN = 99 // RAC_MODEL_FORMAT_UNKNOWN
    }

    /**
     * Inference framework constants matching C++ RAC_FRAMEWORK_* values.
     * IMPORTANT: Must match rac_model_types.h exactly!
     */
    object Framework {
        const val ONNX = 0 // RAC_FRAMEWORK_ONNX
        const val LLAMACPP = 1 // RAC_FRAMEWORK_LLAMACPP
        const val FOUNDATION_MODELS = 2 // RAC_FRAMEWORK_FOUNDATION_MODELS
        const val SYSTEM_TTS = 3 // RAC_FRAMEWORK_SYSTEM_TTS
        const val FLUID_AUDIO = 4 // RAC_FRAMEWORK_FLUID_AUDIO
        const val BUILTIN = 5 // RAC_FRAMEWORK_BUILTIN
        const val NONE = 6 // RAC_FRAMEWORK_NONE
        const val MLX = 7 // RAC_FRAMEWORK_MLX
        const val COREML = 8 // RAC_FRAMEWORK_COREML
        const val WHISPERKIT_COREML = 9 // RAC_FRAMEWORK_WHISPERKIT_COREML
        const val METALRT = 10 // RAC_FRAMEWORK_METALRT
        const val GENIE = 11 // RAC_FRAMEWORK_GENIE
        const val SHERPA = 12 // RAC_FRAMEWORK_SHERPA (Sherpa-ONNX speech engine)
        const val UNKNOWN = 99 // RAC_FRAMEWORK_UNKNOWN
    }

    /**
     * Model status constants.
     */
    object ModelStatus {
        const val NOT_AVAILABLE = 0
        const val AVAILABLE = 1
        const val DOWNLOADING = 2
        const val DOWNLOADED = 3
        const val DOWNLOAD_FAILED = 4
        const val LOADED = 5
        const val CORRUPTED = 6

        fun isReady(status: Int): Boolean = status == DOWNLOADED || status == LOADED
    }

    // ========================================================================
    // PUBLIC API - Mirrors Swift CppBridge.ModelRegistry
    // ========================================================================

    /**
     * Save model to C++ registry.
     *
     * This stores the model in the C++ registry so that C++ service providers
     * (like LlamaCPP) can find it when loading models.
     *
     * @param model The model info to save
     * @throws RuntimeException if save fails
     */
    fun save(model: ProtoModelInfo) {
        log(LogLevel.DEBUG, "Saving model to C++ registry: ${model.id} (framework=${model.framework})")

        val protoResult = registerProto(model)
        val result =
            if (protoResult == null || protoResult == RunAnywhereBridge.RAC_ERROR_FEATURE_NOT_AVAILABLE) {
                saveLegacy(model)
            } else {
                protoResult
            }

        if (result != RunAnywhereBridge.RAC_SUCCESS) {
            log(LogLevel.ERROR, "Failed to save model: ${model.id}, error=$result")
            throw RuntimeException("Failed to save model to C++ registry: $result")
        }

        log(LogLevel.INFO, "Model saved to C++ registry: ${model.id}")
    }

    /**
     * Get model info from C++ registry.
     *
     * @param modelId The model ID
     * @return ModelInfo or null if not found
     */
    fun get(modelId: String): ProtoModelInfo? {
        getProto(modelId)?.let { return it }

        val json = RunAnywhereBridge.racModelRegistryGet(modelId) ?: return null
        return parseModelInfoJson(json)
    }

    /**
     * Get all models from C++ registry.
     *
     * @return List of all models
     */
    fun getAll(): List<ProtoModelInfo> {
        listProto()?.let { return it.models }

        val json = RunAnywhereBridge.racModelRegistryGetAll()
        return parseModelInfoArrayJson(json)
    }

    /**
     * Get downloaded models from C++ registry.
     *
     * @return List of downloaded models
     */
    fun getDownloaded(): List<ProtoModelInfo> {
        listDownloadedProto()?.let { return it.models }

        val json = RunAnywhereBridge.racModelRegistryGetDownloaded()
        return parseModelInfoArrayJson(json)
    }

    /**
     * Query registered models using the generated ModelQuery proto.
     */
    fun query(query: ProtoModelQuery): ProtoModelInfoList =
        queryProto(query) ?: ProtoModelInfoList()

    /**
     * List downloaded models using the generated ModelInfoList proto result.
     */
    fun listDownloaded(): ProtoModelInfoList =
        listDownloadedProto() ?: ProtoModelInfoList(models = getDownloaded())

    /**
     * Remove model from C++ registry.
     *
     * @param modelId The model ID
     * @return true if removed successfully
     */
    fun remove(modelId: String): Boolean {
        val protoResult = removeProto(modelId)
        val result =
            if (protoResult == null || protoResult == RunAnywhereBridge.RAC_ERROR_FEATURE_NOT_AVAILABLE) {
                RunAnywhereBridge.racModelRegistryRemove(modelId)
            } else {
                protoResult
            }
        return result == RunAnywhereBridge.RAC_SUCCESS
    }

    /**
     * Update download status in C++ registry (in-memory only).
     *
     * @param modelId The model ID
     * @param localPath The local path (or null to clear download)
     * @return true if updated successfully
     */
    fun updateDownloadStatus(modelId: String, localPath: String?): Boolean {
        log(LogLevel.DEBUG, "Updating download status: $modelId -> ${localPath ?: "null"}")
        getProto(modelId)?.let { current ->
            val updated =
                current.copy(
                    local_path = localPath.orEmpty(),
                    updated_at_unix_ms = System.currentTimeMillis(),
                )
            val protoResult = updateProto(updated)
            if (protoResult == RunAnywhereBridge.RAC_SUCCESS) {
                return true
            }
            if (protoResult != null && protoResult != RunAnywhereBridge.RAC_ERROR_FEATURE_NOT_AVAILABLE) {
                log(LogLevel.WARN, "Proto download status update failed for $modelId, falling back: $protoResult")
            }
        }

        val result = RunAnywhereBridge.racModelRegistryUpdateDownloadStatus(modelId, localPath)
        return result == RunAnywhereBridge.RAC_SUCCESS
    }

    // ========================================================================
    // CONVENIENCE METHODS - For backwards compatibility
    // ========================================================================

    /**
     * Register a model (alias for save).
     */
    fun registerModel(model: ProtoModelInfo) = save(model)

    /**
     * Check if a model exists.
     */
    fun hasModel(modelId: String): Boolean = get(modelId) != null

    /**
     * Get all registered models.
     */
    fun getAllModels(): List<ProtoModelInfo> = getAll()

    /**
     * Get downloaded models.
     */
    fun getDownloadedModels(): List<ProtoModelInfo> = getDownloaded()

    /**
     * Get models by type/category.
     */
    fun getModelsByType(type: Int): List<ProtoModelInfo> {
        return getAll().filter { protoCategoryToLegacy(it.category) == type }
    }

    /**
     * Get models by proto category.
     */
    fun getModelsByCategory(category: ProtoModelCategory): List<ProtoModelInfo> {
        return getAll().filter { it.category == category }
    }

    /**
     * Scan filesystem and restore downloaded models whose filename matches their model ID.
     * This handles single-file models (GGUF, ONNX) and archive models that extracted into
     * a named directory matching the model ID.
     *
     * For archive models with flat extraction (e.g. Genie), see
     * [RunAnywhere.restorePersistedDownloadPaths] in RunAnywhere+ModelManagement.jvmAndroid.kt.
     *
     * B-AK-17-RAG: Validates that restored model files contain actual bytes (size > 0).
     * Previously a partially-failed download could leave a 0-byte stub on disk, which
     * the scan would happily restore as "downloaded" — the C++ pipeline would then
     * fail with `nativeCreatePipeline returned 0` because ONNX runtime can't parse a
     * 0-byte file. Now we check file size and treat zero-byte stubs as corruption,
     * deleting them so the next download attempt starts clean.
     */
    fun scanAndRestoreDownloadedModels() {
        // Canonical schema: {base}/RunAnywhere/Models/{framework}/{modelId}/
        val baseDir = CppBridgeModelPaths.getBaseDirectory()
        val modelsDir = File(File(baseDir, "RunAnywhere"), "Models")

        if (!modelsDir.exists()) {
            log(LogLevel.DEBUG, "Models directory does not exist: ${modelsDir.absolutePath}")
            return
        }

        log(LogLevel.DEBUG, "Scanning for previously downloaded models...")
        var restoredCount = 0
        var purgedCount = 0

        // Canonical Swift-aligned schema: {base}/RunAnywhere/Models/{framework}/{modelId}/
        // Framework raw names mirror `rac_framework_raw_value` in model_paths.cpp.
        val frameworkDirectories = listOf(
            "LlamaCpp",
            "ONNX",
            "Sherpa",
            "CoreML",
            "FoundationModels",
            "SystemTTS",
            "FluidAudio",
            "WhisperKitCoreML",
            "MetalRT",
            "Genie",
            "BuiltIn",
            "None",
            "Unknown",
        )
        for (dirName in frameworkDirectories) {
            val typeDir = File(modelsDir, dirName)
            if (!typeDir.exists() || !typeDir.isDirectory) continue

            typeDir.listFiles()?.forEach { modelPath ->
                val modelId = modelPath.name
                val existingModel = get(modelId)
                if (existingModel != null && existingModel.local_path.isBlank()) {
                    if (!isModelPathValid(modelPath)) {
                        // Stub or corrupt restore — purge so the model re-downloads cleanly.
                        log(
                            LogLevel.WARN,
                            "Skipping $modelId: on-disk artefact at ${modelPath.absolutePath} " +
                                "is empty/corrupt (0-byte file or empty directory). Purging stub.",
                        )
                        try {
                            if (modelPath.isDirectory) modelPath.deleteRecursively() else modelPath.delete()
                            purgedCount++
                        } catch (e: Exception) {
                            log(LogLevel.ERROR, "Failed to purge stub at ${modelPath.absolutePath}: ${e.message}")
                        }
                        return@forEach
                    }
                    if (updateDownloadStatus(modelId, modelPath.absolutePath)) {
                        restoredCount++
                        log(LogLevel.DEBUG, "Restored $modelId at ${modelPath.absolutePath}")
                    }
                }
            }
        }

        log(LogLevel.INFO, "Filesystem scan complete: restored $restoredCount models, purged $purgedCount stubs")
    }

    /**
     * Validate a model artefact on disk before restoring it as "downloaded".
     *
     * Rules:
     * - Single-file model (e.g. GGUF, single ONNX): file must exist and size > 0.
     * - Directory model (e.g. extracted archive, multi-file embedding):
     *   directory must contain at least one regular file with size > 0.
     *
     * Returns true if the artefact looks like a real, completed download.
     */
    private fun isModelPathValid(modelPath: File): Boolean {
        if (!modelPath.exists()) return false
        if (modelPath.isFile) {
            return modelPath.length() > 0L
        }
        if (modelPath.isDirectory) {
            val children = modelPath.listFiles() ?: return false
            // Walk one level deep and check for any regular file with bytes.
            return children.any { child ->
                when {
                    child.isFile -> child.length() > 0L
                    child.isDirectory -> isModelPathValid(child)
                    else -> false
                }
            }
        }
        return false
    }

    // ========================================================================
    // PROTO ABI + LEGACY FALLBACK
    // ========================================================================

    private fun registerProto(model: ProtoModelInfo): Int? =
        callProtoInt("registerProto") {
            RunAnywhereBridge.racModelRegistryRegisterProto(ProtoModelInfo.ADAPTER.encode(model))
        }

    private fun updateProto(model: ProtoModelInfo): Int? =
        callProtoInt("updateProto") {
            RunAnywhereBridge.racModelRegistryUpdateProto(ProtoModelInfo.ADAPTER.encode(model))
        }

    private fun getProto(modelId: String): ProtoModelInfo? {
        val bytes =
            callProtoBytes("getProto") {
                RunAnywhereBridge.racModelRegistryGetProto(modelId)
            } ?: return null

        return decodeProtoModel(bytes)
    }

    private fun listProto(): ProtoModelInfoList? {
        val bytes =
            callProtoBytes("listProto") {
                RunAnywhereBridge.racModelRegistryListProto()
            } ?: return null

        return try {
            ProtoModelInfoList.ADAPTER.decode(bytes)
        } catch (e: Exception) {
            log(LogLevel.WARN, "Failed to decode ModelInfoList proto: ${e.message}")
            null
        }
    }

    private fun queryProto(query: ProtoModelQuery): ProtoModelInfoList? {
        val bytes =
            callProtoBytes("queryProto") {
                RunAnywhereBridge.racModelRegistryQueryProto(ProtoModelQuery.ADAPTER.encode(query))
            } ?: return null

        return decodeModelInfoList(bytes, "ModelQuery")
    }

    private fun listDownloadedProto(): ProtoModelInfoList? {
        val bytes =
            callProtoBytes("listDownloadedProto") {
                RunAnywhereBridge.racModelRegistryListDownloadedProto()
            } ?: return null

        return decodeModelInfoList(bytes, "downloaded ModelInfoList")
    }

    private fun removeProto(modelId: String): Int? =
        callProtoInt("removeProto") {
            RunAnywhereBridge.racModelRegistryRemoveProto(modelId)
        }

    private fun decodeProtoModel(bytes: ByteArray): ProtoModelInfo? =
        try {
            ProtoModelInfo.ADAPTER.decode(bytes)
        } catch (e: Exception) {
            log(LogLevel.WARN, "Failed to decode ModelInfo proto: ${e.message}")
            null
        }

    private fun decodeModelInfoList(bytes: ByteArray, label: String): ProtoModelInfoList? =
        try {
            ProtoModelInfoList.ADAPTER.decode(bytes)
        } catch (e: Exception) {
            log(LogLevel.WARN, "Failed to decode $label proto: ${e.message}")
            null
        }

    private fun callProtoInt(operation: String, block: () -> Int): Int? =
        try {
            block()
        } catch (e: UnsatisfiedLinkError) {
            log(LogLevel.DEBUG, "Native registry proto ABI unavailable for $operation: ${e.message}")
            null
        }

    private fun callProtoBytes(operation: String, block: () -> ByteArray?): ByteArray? =
        try {
            block()
        } catch (e: UnsatisfiedLinkError) {
            log(LogLevel.DEBUG, "Native registry proto ABI unavailable for $operation: ${e.message}")
            null
        }

    private fun saveLegacy(model: ProtoModelInfo): Int =
        RunAnywhereBridge.racModelRegistrySave(
            modelId = model.id,
            name = model.name,
            category = protoCategoryToLegacy(model.category),
            format = protoFormatToLegacy(model.format),
            framework = protoFrameworkToLegacy(model.framework),
            downloadUrl = model.download_url.takeIf { it.isNotEmpty() },
            localPath = model.local_path.takeIf { it.isNotEmpty() },
            downloadSize = model.download_size_bytes,
            contextLength = model.context_length,
            supportsThinking = model.supports_thinking,
            supportsLora = model.supports_lora,
            description = model.description.takeIf { it.isNotEmpty() },
        )

    // ========================================================================
    // JSON PARSING - Legacy C++ JNI fallback only
    // ========================================================================

    private fun parseModelInfoJson(json: String): ProtoModelInfo? {
        if (json == "null" || json.isBlank()) return null

        return try {
            ProtoModelInfo(
                id = extractString(json, "model_id") ?: return null,
                name = extractString(json, "name") ?: "",
                category = legacyCategoryToProto(extractInt(json, "category")),
                format = legacyFormatToProto(extractInt(json, "format")),
                framework = legacyFrameworkToProto(extractInt(json, "framework")),
                download_url = extractString(json, "download_url") ?: "",
                local_path = extractString(json, "local_path") ?: "",
                download_size_bytes = extractLong(json, "download_size"),
                context_length = extractInt(json, "context_length"),
                supports_thinking = extractBoolean(json, "supports_thinking"),
                supports_lora = extractBoolean(json, "supports_lora"),
                description = extractString(json, "description") ?: "",
                source = ProtoModelSource.MODEL_SOURCE_REMOTE,
            )
        } catch (e: Exception) {
            log(LogLevel.ERROR, "Failed to parse model JSON: ${e.message}")
            null
        }
    }

    private fun parseModelInfoArrayJson(json: String): List<ProtoModelInfo> {
        if (json == "[]" || json.isBlank()) return emptyList()

        val models = mutableListOf<ProtoModelInfo>()

        // Simple array parsing - find each object
        var depth = 0
        var objectStart = -1

        for (i in json.indices) {
            when (json[i]) {
                '{' -> {
                    if (depth == 0) objectStart = i
                    depth++
                }
                '}' -> {
                    depth--
                    if (depth == 0 && objectStart >= 0) {
                        val objectJson = json.substring(objectStart, i + 1)
                        parseModelInfoJson(objectJson)?.let { models.add(it) }
                        objectStart = -1
                    }
                }
            }
        }

        return models
    }

    private fun extractString(json: String, key: String): String? {
        val pattern = """"$key"\s*:\s*"([^"]*)""""
        val regex = Regex(pattern)
        return regex
            .find(json)
            ?.groupValues
            ?.get(1)
            ?.takeIf { it.isNotEmpty() }
    }

    private fun extractInt(json: String, key: String): Int {
        val pattern = """"$key"\s*:\s*(-?\d+)"""
        val regex = Regex(pattern)
        return regex
            .find(json)
            ?.groupValues
            ?.get(1)
            ?.toIntOrNull() ?: 0
    }

    private fun extractLong(json: String, key: String): Long {
        val pattern = """"$key"\s*:\s*(-?\d+)"""
        val regex = Regex(pattern)
        return regex
            .find(json)
            ?.groupValues
            ?.get(1)
            ?.toLongOrNull() ?: 0L
    }

    private fun extractBoolean(json: String, key: String): Boolean {
        val pattern = """"$key"\s*:\s*(true|false)"""
        val regex = Regex(pattern, RegexOption.IGNORE_CASE)
        return regex
            .find(json)
            ?.groupValues
            ?.get(1)
            ?.lowercase() == "true"
    }

    private fun legacyCategoryToProto(category: Int): ProtoModelCategory =
        when (category) {
            ModelCategory.LANGUAGE -> ProtoModelCategory.MODEL_CATEGORY_LANGUAGE
            ModelCategory.SPEECH_RECOGNITION -> ProtoModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION
            ModelCategory.SPEECH_SYNTHESIS -> ProtoModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS
            ModelCategory.VISION -> ProtoModelCategory.MODEL_CATEGORY_VISION
            ModelCategory.IMAGE_GENERATION -> ProtoModelCategory.MODEL_CATEGORY_IMAGE_GENERATION
            ModelCategory.MULTIMODAL -> ProtoModelCategory.MODEL_CATEGORY_MULTIMODAL
            ModelCategory.AUDIO -> ProtoModelCategory.MODEL_CATEGORY_AUDIO
            ModelCategory.EMBEDDING -> ProtoModelCategory.MODEL_CATEGORY_EMBEDDING
            ModelCategory.VOICE_ACTIVITY_DETECTION -> ProtoModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION
            else -> ProtoModelCategory.MODEL_CATEGORY_UNSPECIFIED
        }

    private fun protoCategoryToLegacy(category: ProtoModelCategory): Int =
        when (category) {
            ProtoModelCategory.MODEL_CATEGORY_LANGUAGE -> ModelCategory.LANGUAGE
            ProtoModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION -> ModelCategory.SPEECH_RECOGNITION
            ProtoModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS -> ModelCategory.SPEECH_SYNTHESIS
            ProtoModelCategory.MODEL_CATEGORY_VISION -> ModelCategory.VISION
            ProtoModelCategory.MODEL_CATEGORY_IMAGE_GENERATION -> ModelCategory.IMAGE_GENERATION
            ProtoModelCategory.MODEL_CATEGORY_MULTIMODAL -> ModelCategory.MULTIMODAL
            ProtoModelCategory.MODEL_CATEGORY_AUDIO -> ModelCategory.AUDIO
            ProtoModelCategory.MODEL_CATEGORY_EMBEDDING -> ModelCategory.EMBEDDING
            ProtoModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION -> ModelCategory.VOICE_ACTIVITY_DETECTION
            ProtoModelCategory.MODEL_CATEGORY_UNSPECIFIED -> ModelCategory.UNKNOWN
        }

    private fun legacyFormatToProto(format: Int): ProtoModelFormat =
        when (format) {
            ModelFormat.ONNX -> ProtoModelFormat.MODEL_FORMAT_ONNX
            ModelFormat.ORT -> ProtoModelFormat.MODEL_FORMAT_ORT
            ModelFormat.GGUF -> ProtoModelFormat.MODEL_FORMAT_GGUF
            ModelFormat.BIN -> ProtoModelFormat.MODEL_FORMAT_BIN
            ModelFormat.COREML -> ProtoModelFormat.MODEL_FORMAT_COREML
            ModelFormat.QNN_CONTEXT -> ProtoModelFormat.MODEL_FORMAT_QNN_CONTEXT
            ModelFormat.UNKNOWN -> ProtoModelFormat.MODEL_FORMAT_UNKNOWN
            else -> ProtoModelFormat.MODEL_FORMAT_UNSPECIFIED
        }

    private fun protoFormatToLegacy(format: ProtoModelFormat): Int =
        when (format) {
            ProtoModelFormat.MODEL_FORMAT_ONNX -> ModelFormat.ONNX
            ProtoModelFormat.MODEL_FORMAT_ORT -> ModelFormat.ORT
            ProtoModelFormat.MODEL_FORMAT_GGUF -> ModelFormat.GGUF
            ProtoModelFormat.MODEL_FORMAT_BIN -> ModelFormat.BIN
            ProtoModelFormat.MODEL_FORMAT_COREML -> ModelFormat.COREML
            ProtoModelFormat.MODEL_FORMAT_QNN_CONTEXT -> ModelFormat.QNN_CONTEXT
            ProtoModelFormat.MODEL_FORMAT_UNKNOWN -> ModelFormat.UNKNOWN
            else -> ModelFormat.UNKNOWN
        }

    private fun legacyFrameworkToProto(framework: Int): ProtoInferenceFramework =
        when (framework) {
            Framework.ONNX -> ProtoInferenceFramework.INFERENCE_FRAMEWORK_ONNX
            Framework.LLAMACPP -> ProtoInferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP
            Framework.FOUNDATION_MODELS -> ProtoInferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS
            Framework.SYSTEM_TTS -> ProtoInferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS
            Framework.FLUID_AUDIO -> ProtoInferenceFramework.INFERENCE_FRAMEWORK_FLUID_AUDIO
            Framework.BUILTIN -> ProtoInferenceFramework.INFERENCE_FRAMEWORK_BUILT_IN
            Framework.NONE -> ProtoInferenceFramework.INFERENCE_FRAMEWORK_NONE
            Framework.MLX -> ProtoInferenceFramework.INFERENCE_FRAMEWORK_MLX
            Framework.COREML -> ProtoInferenceFramework.INFERENCE_FRAMEWORK_COREML
            Framework.WHISPERKIT_COREML -> ProtoInferenceFramework.INFERENCE_FRAMEWORK_WHISPERKIT_COREML
            Framework.METALRT -> ProtoInferenceFramework.INFERENCE_FRAMEWORK_METALRT
            Framework.GENIE -> ProtoInferenceFramework.INFERENCE_FRAMEWORK_GENIE
            Framework.SHERPA -> ProtoInferenceFramework.INFERENCE_FRAMEWORK_SHERPA
            Framework.UNKNOWN -> ProtoInferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN
            else -> ProtoInferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED
        }

    private fun protoFrameworkToLegacy(framework: ProtoInferenceFramework): Int =
        when (framework) {
            ProtoInferenceFramework.INFERENCE_FRAMEWORK_ONNX -> Framework.ONNX
            ProtoInferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP -> Framework.LLAMACPP
            ProtoInferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS -> Framework.FOUNDATION_MODELS
            ProtoInferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS -> Framework.SYSTEM_TTS
            ProtoInferenceFramework.INFERENCE_FRAMEWORK_FLUID_AUDIO -> Framework.FLUID_AUDIO
            ProtoInferenceFramework.INFERENCE_FRAMEWORK_BUILT_IN -> Framework.BUILTIN
            ProtoInferenceFramework.INFERENCE_FRAMEWORK_NONE -> Framework.NONE
            ProtoInferenceFramework.INFERENCE_FRAMEWORK_MLX -> Framework.MLX
            ProtoInferenceFramework.INFERENCE_FRAMEWORK_COREML -> Framework.COREML
            ProtoInferenceFramework.INFERENCE_FRAMEWORK_WHISPERKIT_COREML -> Framework.WHISPERKIT_COREML
            ProtoInferenceFramework.INFERENCE_FRAMEWORK_METALRT -> Framework.METALRT
            ProtoInferenceFramework.INFERENCE_FRAMEWORK_GENIE -> Framework.GENIE
            ProtoInferenceFramework.INFERENCE_FRAMEWORK_SHERPA -> Framework.SHERPA
            ProtoInferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN -> Framework.UNKNOWN
            else -> Framework.UNKNOWN
        }

    // ========================================================================
    // LOGGING
    // ========================================================================

    private enum class LogLevel { DEBUG, INFO, WARN, ERROR }

    private fun log(level: LogLevel, message: String) {
        val adapterLevel =
            when (level) {
                LogLevel.DEBUG -> CppBridgePlatformAdapter.LogLevel.DEBUG
                LogLevel.INFO -> CppBridgePlatformAdapter.LogLevel.INFO
                LogLevel.WARN -> CppBridgePlatformAdapter.LogLevel.WARN
                LogLevel.ERROR -> CppBridgePlatformAdapter.LogLevel.ERROR
            }
        CppBridgePlatformAdapter.logCallback(adapterLevel, TAG, message)
    }
}
