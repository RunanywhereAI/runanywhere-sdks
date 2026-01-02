/*
 * Copyright 2024 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * ModelRegistry extension for CppBridge.
 * Provides model registry callbacks for C++ core.
 *
 * Follows iOS CppBridge+ModelRegistry.swift architecture.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

/**
 * Model registry bridge that provides model registration and discovery callbacks for C++ core.
 *
 * The C++ core needs model registry functionality for:
 * - Registering and discovering available models
 * - Tracking model metadata (version, size, capabilities)
 * - Managing model download status
 * - Querying downloaded models
 * - Persisting model information across sessions
 *
 * Usage:
 * - Called during Phase 2 initialization in [CppBridge.initializeServices]
 * - Must be registered after [CppBridgePlatformAdapter] is registered
 *
 * Thread Safety:
 * - Registration is thread-safe via synchronized block
 * - All callbacks are thread-safe
 */
object CppBridgeModelRegistry {

    /**
     * Model type constants matching C++ RAC_MODEL_TYPE_* values.
     */
    object ModelType {
        /** Large Language Model */
        const val LLM = 0

        /** Speech-to-Text model */
        const val STT = 1

        /** Text-to-Speech model */
        const val TTS = 2

        /** Voice Activity Detection model */
        const val VAD = 3

        /** Embedding model */
        const val EMBEDDING = 4

        /** Unknown model type */
        const val UNKNOWN = 99

        /**
         * Get a human-readable name for the model type.
         */
        fun getName(type: Int): String = when (type) {
            LLM -> "LLM"
            STT -> "STT"
            TTS -> "TTS"
            VAD -> "VAD"
            EMBEDDING -> "EMBEDDING"
            UNKNOWN -> "UNKNOWN"
            else -> "UNKNOWN($type)"
        }
    }

    /**
     * Model status constants matching C++ RAC_MODEL_STATUS_* values.
     */
    object ModelStatus {
        /** Model is not available */
        const val NOT_AVAILABLE = 0

        /** Model is available but not downloaded */
        const val AVAILABLE = 1

        /** Model is being downloaded */
        const val DOWNLOADING = 2

        /** Model is downloaded and ready */
        const val DOWNLOADED = 3

        /** Model download failed */
        const val DOWNLOAD_FAILED = 4

        /** Model is loaded in memory */
        const val LOADED = 5

        /** Model is corrupted or invalid */
        const val CORRUPTED = 6

        /**
         * Get a human-readable name for the model status.
         */
        fun getName(status: Int): String = when (status) {
            NOT_AVAILABLE -> "NOT_AVAILABLE"
            AVAILABLE -> "AVAILABLE"
            DOWNLOADING -> "DOWNLOADING"
            DOWNLOADED -> "DOWNLOADED"
            DOWNLOAD_FAILED -> "DOWNLOAD_FAILED"
            LOADED -> "LOADED"
            CORRUPTED -> "CORRUPTED"
            else -> "UNKNOWN($status)"
        }

        /**
         * Check if the model is ready for use.
         */
        fun isReady(status: Int): Boolean = status == DOWNLOADED || status == LOADED
    }

    /**
     * Model format constants.
     */
    object ModelFormat {
        /** GGUF format (LlamaCPP) */
        const val GGUF = "gguf"

        /** ONNX format */
        const val ONNX = "onnx"

        /** Core ML format (iOS/macOS) */
        const val COREML = "coreml"

        /** TensorFlow Lite format */
        const val TFLITE = "tflite"

        /** Unknown format */
        const val UNKNOWN = "unknown"
    }

    @Volatile
    private var isRegistered: Boolean = false

    private val lock = Any()

    /**
     * In-memory model cache.
     */
    private val modelCache = mutableMapOf<String, ModelInfo>()

    /**
     * Tag for logging.
     */
    private const val TAG = "CppBridgeModelRegistry"

    /**
     * Optional listener for model registry events.
     * Set this before calling [register] to receive events.
     */
    @Volatile
    var registryListener: ModelRegistryListener? = null

    /**
     * Model information data class.
     */
    data class ModelInfo(
        val modelId: String,
        val name: String,
        val version: String,
        val type: Int,
        val format: String,
        val size: Long,
        val status: Int,
        val localPath: String?,
        val downloadUrl: String?,
        val checksum: String?,
        val metadata: Map<String, String>
    ) {
        /**
         * Check if the model is ready for use.
         */
        fun isReady(): Boolean = ModelStatus.isReady(status)

        /**
         * Get the model type name.
         */
        fun getTypeName(): String = ModelType.getName(type)

        /**
         * Get the status name.
         */
        fun getStatusName(): String = ModelStatus.getName(status)
    }

    /**
     * Listener interface for model registry events.
     */
    interface ModelRegistryListener {
        /**
         * Called when a model is registered.
         *
         * @param modelId The model ID
         * @param modelInfo The model information
         */
        fun onModelRegistered(modelId: String, modelInfo: ModelInfo)

        /**
         * Called when a model is unregistered.
         *
         * @param modelId The model ID
         */
        fun onModelUnregistered(modelId: String)

        /**
         * Called when a model's status changes.
         *
         * @param modelId The model ID
         * @param previousStatus The previous status
         * @param newStatus The new status
         */
        fun onModelStatusChanged(modelId: String, previousStatus: Int, newStatus: Int)

        /**
         * Called when the model registry is refreshed.
         *
         * @param modelCount The number of models in the registry
         */
        fun onRegistryRefreshed(modelCount: Int)
    }

    /**
     * Register the model registry callbacks with C++ core.
     *
     * This must be called during SDK initialization, after [CppBridgePlatformAdapter.register].
     * It is safe to call multiple times; subsequent calls are no-ops.
     */
    fun register() {
        synchronized(lock) {
            if (isRegistered) {
                return
            }

            // Register the model registry callbacks with C++ via JNI
            // TODO: Call native registration
            // nativeSetModelRegistryCallbacks()

            isRegistered = true

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Model registry callbacks registered"
            )
        }
    }

    /**
     * Check if the model registry callbacks are registered.
     */
    fun isRegistered(): Boolean = isRegistered

    // ========================================================================
    // MODEL REGISTRY CALLBACKS
    // ========================================================================

    /**
     * Get model info callback.
     *
     * Returns model information as JSON string for a given model ID.
     *
     * @param modelId The model ID to look up
     * @return JSON-encoded model information, or null if not found
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getModelInfoCallback(modelId: String): String? {
        val model = synchronized(lock) {
            modelCache[modelId]
        } ?: return null

        return modelInfoToJson(model)
    }

    /**
     * Save model info callback.
     *
     * Saves or updates model information in the registry.
     *
     * @param modelId The model ID
     * @param modelInfoJson JSON-encoded model information
     * @return true if saved successfully, false otherwise
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun saveModelInfoCallback(modelId: String, modelInfoJson: String): Boolean {
        return try {
            val modelInfo = parseModelInfoJson(modelId, modelInfoJson)
            val previousModel: ModelInfo?

            synchronized(lock) {
                previousModel = modelCache[modelId]
                modelCache[modelId] = modelInfo
            }

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Model saved: $modelId (${modelInfo.getTypeName()}, ${modelInfo.getStatusName()})"
            )

            // Notify listener
            try {
                if (previousModel == null) {
                    registryListener?.onModelRegistered(modelId, modelInfo)
                } else if (previousModel.status != modelInfo.status) {
                    registryListener?.onModelStatusChanged(modelId, previousModel.status, modelInfo.status)
                }
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in registry listener: ${e.message}"
                )
            }

            true
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Failed to save model info: ${e.message}"
            )
            false
        }
    }

    /**
     * Delete model info callback.
     *
     * Removes a model from the registry.
     *
     * @param modelId The model ID to remove
     * @return true if removed, false if not found
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun deleteModelInfoCallback(modelId: String): Boolean {
        val removed = synchronized(lock) {
            modelCache.remove(modelId)
        }

        if (removed != null) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Model removed: $modelId"
            )

            // Notify listener
            try {
                registryListener?.onModelUnregistered(modelId)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in registry listener onModelUnregistered: ${e.message}"
                )
            }

            return true
        }

        return false
    }

    /**
     * Get all models callback.
     *
     * Returns all registered models as JSON array.
     *
     * @return JSON-encoded array of model information
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getAllModelsCallback(): String {
        val models = synchronized(lock) {
            modelCache.values.toList()
        }

        return buildString {
            append("[")
            models.forEachIndexed { index, model ->
                if (index > 0) append(",")
                append(modelInfoToJson(model))
            }
            append("]")
        }
    }

    /**
     * Get downloaded models callback.
     *
     * Returns all downloaded models as JSON array.
     *
     * @return JSON-encoded array of downloaded model information
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getDownloadedModelsCallback(): String {
        val models = synchronized(lock) {
            modelCache.values.filter { ModelStatus.isReady(it.status) }
        }

        return buildString {
            append("[")
            models.forEachIndexed { index, model ->
                if (index > 0) append(",")
                append(modelInfoToJson(model))
            }
            append("]")
        }
    }

    /**
     * Get models by type callback.
     *
     * Returns all models of a specific type as JSON array.
     *
     * @param modelType The model type to filter by (see [ModelType])
     * @return JSON-encoded array of model information
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getModelsByTypeCallback(modelType: Int): String {
        val models = synchronized(lock) {
            modelCache.values.filter { it.type == modelType }
        }

        return buildString {
            append("[")
            models.forEachIndexed { index, model ->
                if (index > 0) append(",")
                append(modelInfoToJson(model))
            }
            append("]")
        }
    }

    /**
     * Update model status callback.
     *
     * Updates the status of a model in the registry.
     *
     * @param modelId The model ID
     * @param status The new status (see [ModelStatus])
     * @return true if updated, false if model not found
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun updateModelStatusCallback(modelId: String, status: Int): Boolean {
        val previousStatus: Int
        val updated: Boolean

        synchronized(lock) {
            val model = modelCache[modelId]
            if (model == null) {
                return false
            }

            previousStatus = model.status
            if (previousStatus == status) {
                return true // No change needed
            }

            modelCache[modelId] = model.copy(status = status)
            updated = true
        }

        if (updated) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Model status updated: $modelId ${ModelStatus.getName(previousStatus)} -> ${ModelStatus.getName(status)}"
            )

            // Notify listener
            try {
                registryListener?.onModelStatusChanged(modelId, previousStatus, status)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in registry listener onModelStatusChanged: ${e.message}"
                )
            }
        }

        return true
    }

    /**
     * Set model local path callback.
     *
     * Updates the local path of a downloaded model.
     *
     * @param modelId The model ID
     * @param localPath The local file path
     * @return true if updated, false if model not found
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun setModelLocalPathCallback(modelId: String, localPath: String): Boolean {
        synchronized(lock) {
            val model = modelCache[modelId] ?: return false
            modelCache[modelId] = model.copy(localPath = localPath)
        }

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Model local path set: $modelId -> $localPath"
        )

        return true
    }

    /**
     * Check if model exists callback.
     *
     * @param modelId The model ID to check
     * @return true if the model exists in the registry, false otherwise
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun hasModelCallback(modelId: String): Boolean {
        return synchronized(lock) {
            modelCache.containsKey(modelId)
        }
    }

    /**
     * Get model count callback.
     *
     * @return The number of models in the registry
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getModelCountCallback(): Int {
        return synchronized(lock) {
            modelCache.size
        }
    }

    /**
     * Clear registry callback.
     *
     * Removes all models from the registry.
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun clearRegistryCallback() {
        synchronized(lock) {
            modelCache.clear()
        }

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Model registry cleared"
        )

        // Notify listener
        try {
            registryListener?.onRegistryRefreshed(0)
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Error in registry listener onRegistryRefreshed: ${e.message}"
            )
        }
    }

    // ========================================================================
    // JNI NATIVE DECLARATIONS
    // ========================================================================

    /**
     * Native method to set the model registry callbacks with C++ core.
     *
     * Registers [getModelInfoCallback], [saveModelInfoCallback],
     * [getAllModelsCallback], [getDownloadedModelsCallback], etc. with C++ core.
     *
     * C API: rac_model_registry_set_callbacks(...)
     */
    @JvmStatic
    private external fun nativeSetModelRegistryCallbacks()

    /**
     * Native method to unset the model registry callbacks.
     *
     * Called during shutdown to clean up native resources.
     *
     * C API: rac_model_registry_set_callbacks(nullptr)
     */
    @JvmStatic
    private external fun nativeUnsetModelRegistryCallbacks()

    /**
     * Native method to create the model registry.
     *
     * @param configJson JSON configuration for the registry
     * @return 0 on success, error code on failure
     *
     * C API: rac_model_registry_create(config)
     */
    @JvmStatic
    external fun nativeCreate(configJson: String): Int

    /**
     * Native method to destroy the model registry.
     *
     * @return 0 on success, error code on failure
     *
     * C API: rac_model_registry_destroy()
     */
    @JvmStatic
    external fun nativeDestroy(): Int

    /**
     * Native method to get a model from the C++ registry.
     *
     * @param modelId The model ID
     * @return JSON-encoded model info, or null if not found
     *
     * C API: rac_model_registry_get(model_id)
     */
    @JvmStatic
    external fun nativeGet(modelId: String): String?

    /**
     * Native method to save a model to the C++ registry.
     *
     * @param modelInfoJson JSON-encoded model information
     * @return 0 on success, error code on failure
     *
     * C API: rac_model_registry_save(model_info)
     */
    @JvmStatic
    external fun nativeSave(modelInfoJson: String): Int

    /**
     * Native method to get all models from the C++ registry.
     *
     * @return JSON-encoded array of model information
     *
     * C API: rac_model_registry_get_all()
     */
    @JvmStatic
    external fun nativeGetAll(): String

    /**
     * Native method to get all downloaded models from the C++ registry.
     *
     * @return JSON-encoded array of downloaded model information
     *
     * C API: rac_model_registry_get_downloaded()
     */
    @JvmStatic
    external fun nativeGetDownloaded(): String

    /**
     * Native method to refresh the registry from disk.
     *
     * @return 0 on success, error code on failure
     *
     * C API: rac_model_registry_refresh()
     */
    @JvmStatic
    external fun nativeRefresh(): Int

    /**
     * Native method to sync the registry to disk.
     *
     * @return 0 on success, error code on failure
     *
     * C API: rac_model_registry_sync()
     */
    @JvmStatic
    external fun nativeSync(): Int

    // ========================================================================
    // LIFECYCLE MANAGEMENT
    // ========================================================================

    /**
     * Unregister the model registry callbacks and clean up resources.
     *
     * Called during SDK shutdown.
     */
    fun unregister() {
        synchronized(lock) {
            if (!isRegistered) {
                return
            }

            // TODO: Call native unregistration
            // nativeUnsetModelRegistryCallbacks()

            registryListener = null
            modelCache.clear()
            isRegistered = false
        }
    }

    // ========================================================================
    // UTILITY FUNCTIONS
    // ========================================================================

    /**
     * Get a model by ID.
     *
     * @param modelId The model ID
     * @return The model information, or null if not found
     */
    fun getModel(modelId: String): ModelInfo? {
        return synchronized(lock) {
            modelCache[modelId]
        }
    }

    /**
     * Get all registered models.
     *
     * @return List of all model information
     */
    fun getAllModels(): List<ModelInfo> {
        return synchronized(lock) {
            modelCache.values.toList()
        }
    }

    /**
     * Get all downloaded models.
     *
     * @return List of downloaded model information
     */
    fun getDownloadedModels(): List<ModelInfo> {
        return synchronized(lock) {
            modelCache.values.filter { ModelStatus.isReady(it.status) }
        }
    }

    /**
     * Get models by type.
     *
     * @param type The model type (see [ModelType])
     * @return List of models of the specified type
     */
    fun getModelsByType(type: Int): List<ModelInfo> {
        return synchronized(lock) {
            modelCache.values.filter { it.type == type }
        }
    }

    /**
     * Register a model.
     *
     * @param modelInfo The model information to register
     */
    fun registerModel(modelInfo: ModelInfo) {
        saveModelInfoCallback(modelInfo.modelId, modelInfoToJson(modelInfo))
    }

    /**
     * Unregister a model.
     *
     * @param modelId The model ID to unregister
     * @return true if the model was removed, false if not found
     */
    fun unregisterModel(modelId: String): Boolean {
        return deleteModelInfoCallback(modelId)
    }

    /**
     * Update a model's status.
     *
     * @param modelId The model ID
     * @param status The new status (see [ModelStatus])
     * @return true if updated, false if model not found
     */
    fun updateModelStatus(modelId: String, status: Int): Boolean {
        return updateModelStatusCallback(modelId, status)
    }

    /**
     * Check if a model exists.
     *
     * @param modelId The model ID
     * @return true if the model exists
     */
    fun hasModel(modelId: String): Boolean {
        return hasModelCallback(modelId)
    }

    /**
     * Get the number of registered models.
     *
     * @return The model count
     */
    fun getModelCount(): Int {
        return getModelCountCallback()
    }

    /**
     * Clear all models from the registry.
     */
    fun clearRegistry() {
        clearRegistryCallback()
    }

    /**
     * Convert ModelInfo to JSON string.
     */
    private fun modelInfoToJson(model: ModelInfo): String {
        return buildString {
            append("{")
            append("\"model_id\":\"${escapeJson(model.modelId)}\",")
            append("\"name\":\"${escapeJson(model.name)}\",")
            append("\"version\":\"${escapeJson(model.version)}\",")
            append("\"type\":${model.type},")
            append("\"format\":\"${escapeJson(model.format)}\",")
            append("\"size\":${model.size},")
            append("\"status\":${model.status},")
            append("\"local_path\":${if (model.localPath != null) "\"${escapeJson(model.localPath)}\"" else "null"},")
            append("\"download_url\":${if (model.downloadUrl != null) "\"${escapeJson(model.downloadUrl)}\"" else "null"},")
            append("\"checksum\":${if (model.checksum != null) "\"${escapeJson(model.checksum)}\"" else "null"},")
            append("\"metadata\":{")
            model.metadata.entries.forEachIndexed { index, entry ->
                if (index > 0) append(",")
                append("\"${escapeJson(entry.key)}\":\"${escapeJson(entry.value)}\"")
            }
            append("}")
            append("}")
        }
    }

    /**
     * Parse JSON string to ModelInfo.
     */
    private fun parseModelInfoJson(modelId: String, json: String): ModelInfo {
        // Simple JSON parsing (production code should use a proper JSON library)
        val cleanJson = json.trim()

        fun extractString(key: String): String? {
            val pattern = "\"$key\"\\s*:\\s*\"([^\"]*)\""
            val regex = Regex(pattern)
            return regex.find(cleanJson)?.groupValues?.get(1)
        }

        fun extractInt(key: String): Int {
            val pattern = "\"$key\"\\s*:\\s*(-?\\d+)"
            val regex = Regex(pattern)
            return regex.find(cleanJson)?.groupValues?.get(1)?.toIntOrNull() ?: 0
        }

        fun extractLong(key: String): Long {
            val pattern = "\"$key\"\\s*:\\s*(-?\\d+)"
            val regex = Regex(pattern)
            return regex.find(cleanJson)?.groupValues?.get(1)?.toLongOrNull() ?: 0L
        }

        return ModelInfo(
            modelId = extractString("model_id") ?: modelId,
            name = extractString("name") ?: modelId,
            version = extractString("version") ?: "0.0.0",
            type = extractInt("type"),
            format = extractString("format") ?: ModelFormat.UNKNOWN,
            size = extractLong("size"),
            status = extractInt("status"),
            localPath = extractString("local_path"),
            downloadUrl = extractString("download_url"),
            checksum = extractString("checksum"),
            metadata = emptyMap() // Simplified - full implementation would parse nested object
        )
    }

    /**
     * Escape special characters for JSON string.
     */
    private fun escapeJson(value: String): String {
        return value
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
            .replace("\r", "\\r")
            .replace("\t", "\\t")
    }
}
