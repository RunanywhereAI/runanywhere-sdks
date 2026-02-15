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

import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

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
        const val AUDIO = 3 // RAC_MODEL_CATEGORY_AUDIO
        const val VISION = 4 // RAC_MODEL_CATEGORY_VISION
        const val IMAGE_GENERATION = 5 // RAC_MODEL_CATEGORY_IMAGE_GENERATION
        const val MULTIMODAL = 6 // RAC_MODEL_CATEGORY_MULTIMODAL
    }

    /**
     * Model type constants (alias for category for backwards compatibility).
     */
    object ModelType {
        const val LLM = ModelCategory.LANGUAGE
        const val STT = ModelCategory.SPEECH_RECOGNITION
        const val TTS = ModelCategory.SPEECH_SYNTHESIS
        const val VAD = ModelCategory.AUDIO
        const val EMBEDDING = 99
        const val UNKNOWN = 99

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
        const val UNKNOWN = 0 // RAC_MODEL_FORMAT_UNKNOWN
        const val GGUF = 1 // RAC_MODEL_FORMAT_GGUF
        const val ONNX = 2 // RAC_MODEL_FORMAT_ONNX
        const val ORT = 3 // RAC_MODEL_FORMAT_ORT
        const val BIN = 4 // RAC_MODEL_FORMAT_BIN
        const val COREML = 5 // RAC_MODEL_FORMAT_COREML
        const val TFLITE = 6 // RAC_MODEL_FORMAT_TFLITE
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

    /**
     * Model information data class.
     */
    data class ModelInfo(
        val modelId: String,
        val name: String,
        val category: Int,
        val format: Int,
        val framework: Int,
        val downloadUrl: String?,
        val localPath: String?,
        val downloadSize: Long,
        val contextLength: Int,
        val supportsThinking: Boolean,
        val description: String?,
        val status: Int = ModelStatus.AVAILABLE,
    )

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
    fun save(model: ModelInfo) {
        log(LogLevel.DEBUG, "Saving model to C++ registry: ${model.modelId} (framework=${model.framework})")

        val result =
            RunAnywhereBridge.racModelRegistrySave(
                modelId = model.modelId,
                name = model.name,
                category = model.category,
                format = model.format,
                framework = model.framework,
                downloadUrl = model.downloadUrl,
                localPath = model.localPath,
                downloadSize = model.downloadSize,
                contextLength = model.contextLength,
                supportsThinking = model.supportsThinking,
                description = model.description,
            )

        if (result != RunAnywhereBridge.RAC_SUCCESS) {
            log(LogLevel.ERROR, "Failed to save model: ${model.modelId}, error=$result")
            throw RuntimeException("Failed to save model to C++ registry: $result")
        }

        log(LogLevel.INFO, "Model saved to C++ registry: ${model.modelId}")
    }

    /**
     * Get model info from C++ registry.
     *
     * @param modelId The model ID
     * @return ModelInfo or null if not found
     */
    fun get(modelId: String): ModelInfo? {
        val json = RunAnywhereBridge.racModelRegistryGet(modelId) ?: return null
        return parseModelInfoJson(json)
    }

    /**
     * Get all models from C++ registry.
     *
     * @return List of all models
     */
    fun getAll(): List<ModelInfo> {
        val json = RunAnywhereBridge.racModelRegistryGetAll()
        return parseModelInfoArrayJson(json)
    }

    /**
     * Get downloaded models from C++ registry.
     *
     * @return List of downloaded models
     */
    fun getDownloaded(): List<ModelInfo> {
        val json = RunAnywhereBridge.racModelRegistryGetDownloaded()
        return parseModelInfoArrayJson(json)
    }

    /**
     * Remove model from C++ registry.
     *
     * @param modelId The model ID
     * @return true if removed successfully
     */
    fun remove(modelId: String): Boolean {
        val result = RunAnywhereBridge.racModelRegistryRemove(modelId)
        return result == RunAnywhereBridge.RAC_SUCCESS
    }

    /**
     * Update download status in C++ registry.
     *
     * @param modelId The model ID
     * @param localPath The local path (or null to clear download)
     * @return true if updated successfully
     */
    fun updateDownloadStatus(modelId: String, localPath: String?): Boolean {
        log(LogLevel.DEBUG, "Updating download status: $modelId -> ${localPath ?: "null"}")
        val result = RunAnywhereBridge.racModelRegistryUpdateDownloadStatus(modelId, localPath)
        return result == RunAnywhereBridge.RAC_SUCCESS
    }

    // ========================================================================
    // CONVENIENCE METHODS - For backwards compatibility
    // ========================================================================

    /**
     * Register a model (alias for save).
     */
    fun registerModel(model: ModelInfo) = save(model)

    /**
     * Check if a model exists.
     */
    fun hasModel(modelId: String): Boolean = get(modelId) != null

    /**
     * Get all registered models.
     */
    fun getAllModels(): List<ModelInfo> = getAll()

    /**
     * Get downloaded models.
     */
    fun getDownloadedModels(): List<ModelInfo> = getDownloaded()

    /**
     * Get models by type/category.
     */
    fun getModelsByType(type: Int): List<ModelInfo> {
        return getAll().filter { it.category == type }
    }

    /**
     * Scan filesystem and restore downloaded models.
     *
     * This is called during SDK initialization to detect previously
     * downloaded models and update their status in the C++ registry.
     */
    fun scanAndRestoreDownloadedModels() {
        log(LogLevel.DEBUG, "Scanning for previously downloaded models...")

        val baseDir = CppBridgeModelPaths.getBaseDirectory()
        val modelsDir = java.io.File(baseDir, "models")

        if (!modelsDir.exists()) {
            log(LogLevel.DEBUG, "Models directory does not exist: ${modelsDir.absolutePath}")
            return
        }

        val typeDirectories =
            mapOf(
                "llm" to ModelCategory.LANGUAGE,
                "stt" to ModelCategory.SPEECH_RECOGNITION,
                "tts" to ModelCategory.SPEECH_SYNTHESIS,
                "vad" to ModelCategory.AUDIO,
            )

        var restoredCount = 0

        for ((dirName, _) in typeDirectories) {
            val typeDir = java.io.File(modelsDir, dirName)
            if (!typeDir.exists() || !typeDir.isDirectory) continue

            log(LogLevel.DEBUG, "Scanning type directory: ${typeDir.absolutePath}")

            // Scan each model file or folder in this type directory
            typeDir.listFiles()?.forEach { modelPath ->
                // Model can be stored as:
                // 1. A directory containing the model (e.g., models/llm/model-name/)
                // 2. A file directly (e.g., models/llm/model-name)
                val modelId = modelPath.name
                log(LogLevel.DEBUG, "Found: $modelId (isDir=${modelPath.isDirectory}, isFile=${modelPath.isFile})")

                // Check if this model exists in registry
                val existingModel = get(modelId)
                if (existingModel != null) {
                    // Update with local path
                    if (updateDownloadStatus(modelId, modelPath.absolutePath)) {
                        restoredCount++
                        log(LogLevel.DEBUG, "Restored downloaded model: $modelId at ${modelPath.absolutePath}")
                    }
                } else {
                    log(LogLevel.DEBUG, "Model $modelId not found in registry, skipping")
                }
            }
        }

        log(LogLevel.INFO, "Scan complete: Restored $restoredCount previously downloaded models")
    }

    // ========================================================================
    // JSON PARSING - Parse C++ JSON responses
    // ========================================================================

    private fun parseModelInfoJson(json: String): ModelInfo? {
        if (json == "null" || json.isBlank()) return null

        return try {
            ModelInfo(
                modelId = extractString(json, "model_id") ?: return null,
                name = extractString(json, "name") ?: "",
                category = extractInt(json, "category"),
                format = extractInt(json, "format"),
                framework = extractInt(json, "framework"),
                downloadUrl = extractString(json, "download_url"),
                localPath = extractString(json, "local_path"),
                downloadSize = extractLong(json, "download_size"),
                contextLength = extractInt(json, "context_length"),
                supportsThinking = extractBoolean(json, "supports_thinking"),
                description = extractString(json, "description"),
                status = if (extractString(json, "local_path") != null) ModelStatus.DOWNLOADED else ModelStatus.AVAILABLE,
            )
        } catch (e: Exception) {
            log(LogLevel.ERROR, "Failed to parse model JSON: ${e.message}")
            null
        }
    }

    private fun parseModelInfoArrayJson(json: String): List<ModelInfo> {
        if (json == "[]" || json.isBlank()) return emptyList()

        val models = mutableListOf<ModelInfo>()

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
