/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * ModelPaths extension for CppBridge.
 * Provides model path utilities for C++ core.
 *
 * Follows iOS CppBridge+ModelPaths.swift architecture.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import java.io.File

/**
 * Model paths bridge that provides model path utilities for C++ core.
 *
 * The C++ core needs model path utilities for:
 * - Getting and setting the base directory for model storage
 * - Getting the models directory path
 * - Getting specific model file paths
 * - Managing model file locations across platforms
 *
 * Usage:
 * - Called during Phase 2 initialization in [CppBridge.initializeServices]
 * - Must be registered after [CppBridgePlatformAdapter] is registered
 *
 * Thread Safety:
 * - Registration is thread-safe via synchronized block
 * - All callbacks are thread-safe
 */
object CppBridgeModelPaths {

    /**
     * Model file extension constants.
     */
    object ModelExtension {
        /** GGUF model files (LlamaCPP) */
        const val GGUF = ".gguf"

        /** ONNX model files */
        const val ONNX = ".onnx"

        /** TensorFlow Lite model files */
        const val TFLITE = ".tflite"

        /** JSON metadata files */
        const val JSON = ".json"

        /** Binary model files */
        const val BIN = ".bin"
    }

    /**
     * Model subdirectory names.
     */
    object ModelDirectory {
        /** LLM models directory */
        const val LLM = "llm"

        /** STT models directory */
        const val STT = "stt"

        /** TTS models directory */
        const val TTS = "tts"

        /** VAD models directory */
        const val VAD = "vad"

        /** Embedding models directory */
        const val EMBEDDING = "embedding"

        /** Downloaded models directory */
        const val DOWNLOADS = "downloads"

        /** Cache directory */
        const val CACHE = "cache"
    }

    @Volatile
    private var isRegistered: Boolean = false

    @Volatile
    private var baseDirectory: String? = null

    private val lock = Any()

    /**
     * Tag for logging.
     */
    private const val TAG = "CppBridgeModelPaths"

    /**
     * Default models directory name.
     */
    private const val DEFAULT_MODELS_DIR = "models"

    /**
     * Optional listener for path change events.
     * Set this before calling [register] to receive events.
     */
    @Volatile
    var pathListener: ModelPathListener? = null

    /**
     * Optional provider for platform-specific paths.
     * Set this on Android to provide proper app-specific directories.
     * Setting this resets the base directory so it will be re-initialized
     * with the new provider on next access.
     */
    @Volatile
    private var _pathProvider: ModelPathProvider? = null

    var pathProvider: ModelPathProvider?
        get() = _pathProvider
        set(value) {
            synchronized(lock) {
                _pathProvider = value
                // Reset base directory so it gets re-initialized with the new provider
                if (value != null && baseDirectory != null) {
                    val previousBase = baseDirectory
                    baseDirectory = null
                    CppBridgePlatformAdapter.logCallback(
                        CppBridgePlatformAdapter.LogLevel.DEBUG,
                        TAG,
                        "Path provider set, resetting base directory (was: $previousBase)"
                    )
                }
            }
        }

    /**
     * Listener interface for model path change events.
     */
    interface ModelPathListener {
        /**
         * Called when the base directory changes.
         *
         * @param previousPath The previous base directory
         * @param newPath The new base directory
         */
        fun onBaseDirectoryChanged(previousPath: String?, newPath: String?)

        /**
         * Called when a model directory is created.
         *
         * @param path The directory path that was created
         */
        fun onDirectoryCreated(path: String)

        /**
         * Called when a model file is added.
         *
         * @param modelId The model ID
         * @param path The file path
         */
        fun onModelFileAdded(modelId: String, path: String)
    }

    /**
     * Provider interface for platform-specific model paths.
     */
    interface ModelPathProvider {
        /**
         * Get the app's files directory.
         *
         * On Android, this returns Context.filesDir.
         * On JVM, this returns the user's home directory or working directory.
         *
         * @return The files directory path
         */
        fun getFilesDirectory(): String

        /**
         * Get the app's cache directory.
         *
         * @return The cache directory path
         */
        fun getCacheDirectory(): String

        /**
         * Get the external storage directory (if available).
         *
         * On Android, this returns external files directory.
         * On JVM, this may return null.
         *
         * @return The external storage path, or null if not available
         */
        fun getExternalStorageDirectory(): String?

        /**
         * Check if a path is writable.
         *
         * @param path The path to check
         * @return true if the path is writable
         */
        fun isPathWritable(path: String): Boolean
    }

    /**
     * Register the model paths callbacks with C++ core.
     *
     * This must be called during SDK initialization, after [CppBridgePlatformAdapter.register].
     * It is safe to call multiple times; subsequent calls are no-ops.
     */
    fun register() {
        synchronized(lock) {
            if (isRegistered) {
                return
            }

            // Initialize base directory if not set
            if (baseDirectory == null) {
                initializeDefaultBaseDirectory()
            }

            // Register the model paths callbacks with C++ via JNI
            // TODO: Call native registration
            // nativeSetModelPathsCallbacks()

            isRegistered = true

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Model paths callbacks registered. Base dir: $baseDirectory"
            )
        }
    }

    /**
     * Check if the model paths callbacks are registered.
     */
    fun isRegistered(): Boolean = isRegistered

    // ========================================================================
    // MODEL PATH CALLBACKS
    // ========================================================================

    /**
     * Get the base directory callback.
     *
     * Returns the base directory for model storage.
     *
     * @return The base directory path
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getBaseDirCallback(): String {
        return synchronized(lock) {
            baseDirectory ?: initializeDefaultBaseDirectory()
        }
    }

    /**
     * Set the base directory callback.
     *
     * Sets the base directory for model storage.
     *
     * @param path The base directory path
     * @return true if set successfully, false otherwise
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun setBaseDirCallback(path: String): Boolean {
        return try {
            val file = File(path)

            // Create directory if it doesn't exist
            if (!file.exists()) {
                if (!file.mkdirs()) {
                    CppBridgePlatformAdapter.logCallback(
                        CppBridgePlatformAdapter.LogLevel.ERROR,
                        TAG,
                        "Failed to create base directory: $path"
                    )
                    return false
                }
            }

            // Verify it's a directory and writable
            if (!file.isDirectory) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "Path is not a directory: $path"
                )
                return false
            }

            if (!file.canWrite()) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "Directory is not writable: $path"
                )
                return false
            }

            val previousPath = synchronized(lock) {
                val prev = baseDirectory
                baseDirectory = path
                prev
            }

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Base directory set: $path"
            )

            // Notify listener
            try {
                pathListener?.onBaseDirectoryChanged(previousPath, path)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in path listener: ${e.message}"
                )
            }

            true
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Failed to set base directory: ${e.message}"
            )
            false
        }
    }

    /**
     * Get the models directory callback.
     *
     * Returns the directory for storing models.
     *
     * @return The models directory path
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getModelsDirectoryCallback(): String {
        val base = getBaseDirCallback()
        return File(base, DEFAULT_MODELS_DIR).absolutePath
    }

    /**
     * Get a model path callback.
     *
     * Returns the path for a specific model by ID.
     *
     * @param modelId The model ID
     * @return The model file path
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getModelPathCallback(modelId: String): String {
        val modelsDir = getModelsDirectoryCallback()
        return File(modelsDir, modelId).absolutePath
    }

    /**
     * Get model path by type callback.
     *
     * Returns the path for a model of a specific type.
     *
     * @param modelId The model ID
     * @param modelType The model type (see [CppBridgeModelRegistry.ModelType])
     * @return The model file path
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getModelPathByTypeCallback(modelId: String, modelType: Int): String {
        val typeDir = getModelTypeDirectory(modelType)
        return File(typeDir, modelId).absolutePath
    }

    /**
     * Get downloads directory callback.
     *
     * Returns the directory for in-progress downloads.
     *
     * @return The downloads directory path
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getDownloadsDirectoryCallback(): String {
        val base = getBaseDirCallback()
        return File(base, ModelDirectory.DOWNLOADS).absolutePath
    }

    /**
     * Get cache directory callback.
     *
     * Returns the directory for cached model data.
     *
     * @return The cache directory path
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getCacheDirectoryCallback(): String {
        val provider = pathProvider
        if (provider != null) {
            return provider.getCacheDirectory()
        }

        val base = getBaseDirCallback()
        return File(base, ModelDirectory.CACHE).absolutePath
    }

    /**
     * Check if a model exists callback.
     *
     * @param modelId The model ID
     * @return true if the model file exists
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun modelExistsCallback(modelId: String): Boolean {
        val modelPath = getModelPathCallback(modelId)
        return File(modelPath).exists()
    }

    /**
     * Get model file size callback.
     *
     * @param modelId The model ID
     * @return The file size in bytes, or -1 if not found
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getModelFileSizeCallback(modelId: String): Long {
        val modelPath = getModelPathCallback(modelId)
        val file = File(modelPath)
        return if (file.exists()) file.length() else -1L
    }

    /**
     * Create model directory callback.
     *
     * Creates the directory for a specific model type.
     *
     * @param modelType The model type (see [CppBridgeModelRegistry.ModelType])
     * @return true if directory exists or was created, false otherwise
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun createModelDirectoryCallback(modelType: Int): Boolean {
        return try {
            val dirPath = getModelTypeDirectory(modelType)
            val dir = File(dirPath)

            if (dir.exists()) {
                true
            } else {
                val created = dir.mkdirs()
                if (created) {
                    CppBridgePlatformAdapter.logCallback(
                        CppBridgePlatformAdapter.LogLevel.DEBUG,
                        TAG,
                        "Created model directory: $dirPath"
                    )

                    try {
                        pathListener?.onDirectoryCreated(dirPath)
                    } catch (e: Exception) {
                        // Ignore listener errors
                    }
                }
                created
            }
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Failed to create model directory: ${e.message}"
            )
            false
        }
    }

    /**
     * Delete model file callback.
     *
     * @param modelId The model ID
     * @return true if deleted or didn't exist, false on error
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun deleteModelFileCallback(modelId: String): Boolean {
        return try {
            val modelPath = getModelPathCallback(modelId)
            val file = File(modelPath)

            if (!file.exists()) {
                true
            } else {
                val deleted = file.delete()
                if (deleted) {
                    CppBridgePlatformAdapter.logCallback(
                        CppBridgePlatformAdapter.LogLevel.DEBUG,
                        TAG,
                        "Deleted model file: $modelPath"
                    )
                }
                deleted
            }
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Failed to delete model file: ${e.message}"
            )
            false
        }
    }

    /**
     * Get available storage space callback.
     *
     * @return Available space in bytes
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getAvailableStorageCallback(): Long {
        return try {
            val base = getBaseDirCallback()
            File(base).usableSpace
        } catch (e: Exception) {
            -1L
        }
    }

    /**
     * Get total storage space callback.
     *
     * @return Total space in bytes
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getTotalStorageCallback(): Long {
        return try {
            val base = getBaseDirCallback()
            File(base).totalSpace
        } catch (e: Exception) {
            -1L
        }
    }

    // ========================================================================
    // JNI NATIVE DECLARATIONS
    // ========================================================================

    /**
     * Native method to set the model paths callbacks with C++ core.
     *
     * Registers [getBaseDirCallback], [setBaseDirCallback],
     * [getModelsDirectoryCallback], [getModelPathCallback], etc. with C++ core.
     *
     * C API: rac_model_paths_set_callbacks(...)
     */
    @JvmStatic
    private external fun nativeSetModelPathsCallbacks()

    /**
     * Native method to unset the model paths callbacks.
     *
     * Called during shutdown to clean up native resources.
     *
     * C API: rac_model_paths_set_callbacks(nullptr)
     */
    @JvmStatic
    private external fun nativeUnsetModelPathsCallbacks()

    /**
     * Native method to get the base directory from C++ core.
     *
     * @return The base directory path from C++
     *
     * C API: rac_model_paths_get_base_dir()
     */
    @JvmStatic
    external fun nativeGetBaseDir(): String?

    /**
     * Native method to set the base directory in C++ core.
     *
     * @param path The base directory path
     * @return 0 on success, error code on failure
     *
     * C API: rac_model_paths_set_base_dir(path)
     */
    @JvmStatic
    external fun nativeSetBaseDir(path: String): Int

    /**
     * Native method to get the models directory from C++ core.
     *
     * @return The models directory path
     *
     * C API: rac_model_paths_get_models_directory()
     */
    @JvmStatic
    external fun nativeGetModelsDirectory(): String?

    /**
     * Native method to get a model path from C++ core.
     *
     * @param modelId The model ID
     * @return The model file path
     *
     * C API: rac_model_paths_get_model_path(model_id)
     */
    @JvmStatic
    external fun nativeGetModelPath(modelId: String): String?

    /**
     * Native method to resolve a model path from C++ core.
     *
     * Resolves relative paths and validates the model exists.
     *
     * @param modelId The model ID
     * @param modelType The model type
     * @return The resolved model path, or null if not found
     *
     * C API: rac_model_paths_resolve(model_id, type)
     */
    @JvmStatic
    external fun nativeResolvePath(modelId: String, modelType: Int): String?

    // ========================================================================
    // LIFECYCLE MANAGEMENT
    // ========================================================================

    /**
     * Unregister the model paths callbacks and clean up resources.
     *
     * Called during SDK shutdown.
     */
    fun unregister() {
        synchronized(lock) {
            if (!isRegistered) {
                return
            }

            // TODO: Call native unregistration
            // nativeUnsetModelPathsCallbacks()

            pathListener = null
            isRegistered = false
        }
    }

    // ========================================================================
    // UTILITY FUNCTIONS
    // ========================================================================

    /**
     * Set the base directory for model storage.
     *
     * @param path The base directory path
     * @return true if set successfully, false otherwise
     */
    fun setBaseDirectory(path: String): Boolean {
        return setBaseDirCallback(path)
    }

    /**
     * Get the base directory for model storage.
     *
     * @return The base directory path
     */
    fun getBaseDirectory(): String {
        return getBaseDirCallback()
    }

    /**
     * Get the models directory.
     *
     * @return The models directory path
     */
    fun getModelsDirectory(): String {
        return getModelsDirectoryCallback()
    }

    /**
     * Get the path for a specific model.
     *
     * @param modelId The model ID
     * @return The model file path
     */
    fun getModelPath(modelId: String): String {
        return getModelPathCallback(modelId)
    }

    /**
     * Get the path for a model of a specific type.
     *
     * @param modelId The model ID
     * @param modelType The model type (see [CppBridgeModelRegistry.ModelType])
     * @return The model file path
     */
    fun getModelPath(modelId: String, modelType: Int): String {
        return getModelPathByTypeCallback(modelId, modelType)
    }

    /**
     * Get the downloads directory.
     *
     * @return The downloads directory path
     */
    fun getDownloadsDirectory(): String {
        return getDownloadsDirectoryCallback()
    }

    /**
     * Get the cache directory.
     *
     * @return The cache directory path
     */
    fun getCacheDirectory(): String {
        return getCacheDirectoryCallback()
    }

    /**
     * Check if a model file exists.
     *
     * @param modelId The model ID
     * @return true if the model file exists
     */
    fun modelExists(modelId: String): Boolean {
        return modelExistsCallback(modelId)
    }

    /**
     * Get the file size of a model.
     *
     * @param modelId The model ID
     * @return The file size in bytes, or -1 if not found
     */
    fun getModelFileSize(modelId: String): Long {
        return getModelFileSizeCallback(modelId)
    }

    /**
     * Create the directory for a specific model type.
     *
     * @param modelType The model type (see [CppBridgeModelRegistry.ModelType])
     * @return true if directory exists or was created
     */
    fun createModelDirectory(modelType: Int): Boolean {
        return createModelDirectoryCallback(modelType)
    }

    /**
     * Delete a model file.
     *
     * @param modelId The model ID
     * @return true if deleted or didn't exist
     */
    fun deleteModelFile(modelId: String): Boolean {
        return deleteModelFileCallback(modelId)
    }

    /**
     * Get available storage space.
     *
     * @return Available space in bytes
     */
    fun getAvailableStorage(): Long {
        return getAvailableStorageCallback()
    }

    /**
     * Get total storage space.
     *
     * @return Total space in bytes
     */
    fun getTotalStorage(): Long {
        return getTotalStorageCallback()
    }

    /**
     * Check if there is enough storage for a model.
     *
     * @param requiredBytes The required space in bytes
     * @return true if there is enough space
     */
    fun hasEnoughStorage(requiredBytes: Long): Boolean {
        val available = getAvailableStorage()
        return available >= requiredBytes
    }

    /**
     * Ensure all model directories exist.
     *
     * Creates the base directory, models directory, and all type-specific directories.
     *
     * @return true if all directories exist or were created
     */
    fun ensureDirectoriesExist(): Boolean {
        return try {
            // Create base directory
            val base = File(getBaseDirCallback())
            if (!base.exists() && !base.mkdirs()) {
                return false
            }

            // Create models directory
            val modelsDir = File(getModelsDirectoryCallback())
            if (!modelsDir.exists() && !modelsDir.mkdirs()) {
                return false
            }

            // Create downloads directory
            val downloadsDir = File(getDownloadsDirectoryCallback())
            if (!downloadsDir.exists() && !downloadsDir.mkdirs()) {
                return false
            }

            // Create type-specific directories
            for (type in listOf(
                CppBridgeModelRegistry.ModelType.LLM,
                CppBridgeModelRegistry.ModelType.STT,
                CppBridgeModelRegistry.ModelType.TTS,
                CppBridgeModelRegistry.ModelType.VAD,
                CppBridgeModelRegistry.ModelType.EMBEDDING
            )) {
                createModelDirectoryCallback(type)
            }

            true
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Failed to ensure directories exist: ${e.message}"
            )
            false
        }
    }

    /**
     * Get the temporary file path for a download.
     *
     * @param modelId The model ID
     * @return The temporary file path
     */
    fun getTempDownloadPath(modelId: String): String {
        val downloadsDir = getDownloadsDirectoryCallback()
        return File(downloadsDir, "${modelId}.tmp").absolutePath
    }

    /**
     * Move a downloaded file to its final location.
     *
     * @param tempPath The temporary file path
     * @param modelId The model ID
     * @param modelType The model type
     * @return true if moved successfully
     */
    fun moveDownloadToFinal(tempPath: String, modelId: String, modelType: Int): Boolean {
        return try {
            val tempFile = File(tempPath)
            if (!tempFile.exists()) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "Temp file does not exist: $tempPath"
                )
                return false
            }

            // Ensure target directory exists
            createModelDirectoryCallback(modelType)

            val finalPath = getModelPathByTypeCallback(modelId, modelType)
            val finalFile = File(finalPath)

            // Delete existing file if present
            if (finalFile.exists()) {
                finalFile.delete()
            }

            // Move file
            val moved = tempFile.renameTo(finalFile)
            if (!moved) {
                // If rename fails, try copy and delete
                tempFile.copyTo(finalFile, overwrite = true)
                tempFile.delete()
            }

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Moved model to final location: $finalPath"
            )

            try {
                pathListener?.onModelFileAdded(modelId, finalPath)
            } catch (e: Exception) {
                // Ignore listener errors
            }

            true
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Failed to move download to final location: ${e.message}"
            )
            false
        }
    }

    /**
     * Get the directory path for a specific model type.
     */
    private fun getModelTypeDirectory(modelType: Int): String {
        val modelsDir = getModelsDirectoryCallback()
        val typeName = when (modelType) {
            CppBridgeModelRegistry.ModelType.LLM -> ModelDirectory.LLM
            CppBridgeModelRegistry.ModelType.STT -> ModelDirectory.STT
            CppBridgeModelRegistry.ModelType.TTS -> ModelDirectory.TTS
            CppBridgeModelRegistry.ModelType.VAD -> ModelDirectory.VAD
            CppBridgeModelRegistry.ModelType.EMBEDDING -> ModelDirectory.EMBEDDING
            else -> "other"
        }
        return File(modelsDir, typeName).absolutePath
    }

    /**
     * Initialize the default base directory.
     */
    private fun initializeDefaultBaseDirectory(): String {
        val provider = pathProvider
        val basePath = if (provider != null) {
            // Use platform-specific directory
            val filesDir = provider.getFilesDirectory()
            File(filesDir, "runanywhere").absolutePath
        } else {
            // Use user home directory or temp directory as fallback
            val userHome = System.getProperty("user.home")
            if (userHome != null) {
                File(userHome, ".runanywhere").absolutePath
            } else {
                File(System.getProperty("java.io.tmpdir", "/tmp"), "runanywhere").absolutePath
            }
        }

        synchronized(lock) {
            if (baseDirectory == null) {
                baseDirectory = basePath

                // Create the directory
                try {
                    val dir = File(basePath)
                    if (!dir.exists()) {
                        dir.mkdirs()
                    }
                } catch (e: Exception) {
                    CppBridgePlatformAdapter.logCallback(
                        CppBridgePlatformAdapter.LogLevel.WARN,
                        TAG,
                        "Failed to create default base directory: ${e.message}"
                    )
                }
            }
        }

        return basePath
    }
}
