/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * ModelPaths extension for CppBridge.
 *
 * This is a THIN Kotlin shim. All path shapes are computed by the C++ core
 * via `rac_model_paths_*`. The canonical schema is Swift-aligned:
 *   `{base_dir}/RunAnywhere/Models/{framework}/{modelId}/`
 *
 * The previous Kotlin-local schema (`{base_dir}/models/{typeName}/{modelId}`)
 * has been removed. Any on-disk artifacts under `{base_dir}/models/` are
 * deleted on first init — users re-download.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import java.io.File

/**
 * Model paths bridge. Computes paths by delegating to the C++ core via JNI
 * so all platforms (Swift, Kotlin, Web, RN, Flutter) agree on the layout.
 *
 * Usage:
 * - Set [pathProvider] (Android supplies `context.filesDir`, JVM falls back
 *   to `~/.runanywhere`) before calling [getBaseDirectory] or any model
 *   lookup. The provider is used to compute the base dir which is then
 *   pushed into the C++ core via `racModelPathsSetBaseDir`.
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
     * Well-known subdirectory names under the base.
     * NOTE: Per-model layout is `{base}/RunAnywhere/Models/{framework}/{modelId}/`,
     * computed by the C++ core. These constants are only for base-dir-adjacent
     * directories (downloads staging, cache).
     */
    object ModelDirectory {
        /** Downloaded models staging directory */
        const val DOWNLOADS = "downloads"

        /** Cache directory */
        const val CACHE = "cache"
    }

    @Volatile
    private var baseDirectory: String? = null

    private val lock = Any()

    /**
     * Tag for logging.
     */
    private const val TAG = "CppBridgeModelPaths"

    /** Legacy schema directory that we nuke on first init (no migration). */
    private const val LEGACY_MODELS_DIR = "models"

    @Volatile
    private var legacyCleanupDone: Boolean = false

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
                        "Path provider set, resetting base directory (was: $previousBase)",
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
     * Sets the base directory for model storage AND pushes it into the C++
     * core via `rac_model_paths_set_base_dir` so the canonical path utilities
     * are usable.
     *
     * @param path The base directory path
     * @return true if set successfully, false otherwise
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun setBaseDirCallback(path: String): Boolean {
        // Hold lock for both file checks and state write to prevent TOCTOU races.
        // File I/O here is fast (mkdirs/exists), and this is called rarely (once at init).
        var previousPath: String? = null
        val success =
            synchronized(lock) {
                try {
                    val file = File(path)

                    // Create directory if it doesn't exist
                    if (!file.exists()) {
                        if (!file.mkdirs()) {
                            CppBridgePlatformAdapter.logCallback(
                                CppBridgePlatformAdapter.LogLevel.ERROR,
                                TAG,
                                "Failed to create base directory: $path",
                            )
                            return@synchronized false
                        }
                    }

                    // Verify it's a directory and writable
                    if (!file.isDirectory) {
                        CppBridgePlatformAdapter.logCallback(
                            CppBridgePlatformAdapter.LogLevel.ERROR,
                            TAG,
                            "Path is not a directory: $path",
                        )
                        return@synchronized false
                    }

                    if (!file.canWrite()) {
                        CppBridgePlatformAdapter.logCallback(
                            CppBridgePlatformAdapter.LogLevel.ERROR,
                            TAG,
                            "Directory is not writable: $path",
                        )
                        return@synchronized false
                    }

                    previousPath = baseDirectory
                    baseDirectory = path

                    CppBridgePlatformAdapter.logCallback(
                        CppBridgePlatformAdapter.LogLevel.DEBUG,
                        TAG,
                        "Base directory set: $path",
                    )

                    // Push into C++ so rac_model_paths_get_model_folder can work.
                    // Swallow any linkage failure here: JNI may not be loaded yet
                    // in pure-JVM test contexts.
                    try {
                        val rc = RunAnywhereBridge.racModelPathsSetBaseDir(path)
                        if (rc != 0) {
                            CppBridgePlatformAdapter.logCallback(
                                CppBridgePlatformAdapter.LogLevel.WARN,
                                TAG,
                                "racModelPathsSetBaseDir returned $rc",
                            )
                        }
                    } catch (t: Throwable) {
                        CppBridgePlatformAdapter.logCallback(
                            CppBridgePlatformAdapter.LogLevel.WARN,
                            TAG,
                            "racModelPathsSetBaseDir unavailable: ${t.message}",
                        )
                    }

                    // One-time cleanup of legacy `{base}/models/` directory.
                    // No migration — user re-downloads what they need.
                    cleanupLegacyModelsDirLocked(path)

                    true
                } catch (e: Exception) {
                    CppBridgePlatformAdapter.logCallback(
                        CppBridgePlatformAdapter.LogLevel.ERROR,
                        TAG,
                        "Failed to set base directory: ${e.message}",
                    )
                    false
                }
            }

        // Notify listener outside lock to avoid holding lock during callbacks
        if (success) {
            try {
                pathListener?.onBaseDirectoryChanged(previousPath, path)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in path listener: ${e.message}",
                )
            }
        }

        return success
    }

    /**
     * Delete the legacy `{base}/models/` directory that was used by the old
     * Kotlin-local path schema. Called at most once per process. No migration.
     * Caller must hold [lock].
     */
    private fun cleanupLegacyModelsDirLocked(basePath: String) {
        if (legacyCleanupDone) return
        legacyCleanupDone = true
        try {
            val legacy = File(basePath, LEGACY_MODELS_DIR)
            if (legacy.exists() && legacy.isDirectory) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Detected legacy model directory ${legacy.absolutePath}; " +
                        "deleting. Re-download any models you need.",
                )
                val deleted = legacy.deleteRecursively()
                if (!deleted) {
                    CppBridgePlatformAdapter.logCallback(
                        CppBridgePlatformAdapter.LogLevel.ERROR,
                        TAG,
                        "Legacy directory cleanup failed for ${legacy.absolutePath}",
                    )
                }
            }
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Legacy cleanup error: ${e.message}",
            )
        }
    }

    /**
     * Get a model path callback.
     *
     * Returns the path for a specific model by ID under the canonical schema,
     * assuming `RAC_FRAMEWORK_UNKNOWN` (no framework hint). Callers that know
     * the framework should use [getModelPath(modelId, framework)] directly.
     *
     * @param modelId The model ID
     * @return The model file path
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getModelPathCallback(modelId: String): String {
        // Default to UNKNOWN framework when caller has no framework info.
        return getModelPath(modelId, CppBridgeModelRegistry.Framework.UNKNOWN)
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
                val deleted =
                    if (file.isDirectory) {
                        file.deleteRecursively()
                    } else {
                        file.delete()
                    }
                if (deleted) {
                    CppBridgePlatformAdapter.logCallback(
                        CppBridgePlatformAdapter.LogLevel.DEBUG,
                        TAG,
                        "Deleted model file: $modelPath",
                    )
                }
                deleted
            }
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Failed to delete model file: ${e.message}",
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
     * Get the path for a specific model (framework = UNKNOWN).
     *
     * @param modelId The model ID
     * @return The model folder path
     */
    fun getModelPath(modelId: String): String {
        return getModelPathCallback(modelId)
    }

    /**
     * Get the canonical path for a model of a specific inference framework.
     *
     * Delegates to the C++ core (`rac_model_paths_get_model_folder`) so all
     * platforms share one schema: `{base}/RunAnywhere/Models/{framework}/{modelId}/`
     *
     * @param modelId The model ID
     * @param framework The inference framework int (see [CppBridgeModelRegistry.Framework])
     * @return The model folder path
     */
    fun getModelPath(modelId: String, framework: Int): String {
        // Ensure base dir is materialised both locally and in C++ before the call.
        val base = getBaseDirCallback()
        val jniPath =
            try {
                RunAnywhereBridge.racModelPathsGetModelFolder(modelId, framework)
            } catch (t: Throwable) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "racModelPathsGetModelFolder unavailable: ${t.message}",
                )
                null
            }
        if (jniPath != null) return jniPath

        // JNI not available (e.g. pure JVM unit tests). Fall back to a local
        // computation that still uses the canonical schema.
        val frameworkName = frameworkRawValue(framework)
        return File(File(File(base, "RunAnywhere"), "Models"), "$frameworkName${File.separator}$modelId").absolutePath
    }

    /**
     * Local mirror of `rac_framework_raw_value` for the JVM-only fallback path.
     * Keep in sync with C++ `rac_framework_raw_value` (model_paths.cpp).
     */
    private fun frameworkRawValue(framework: Int): String =
        when (framework) {
            CppBridgeModelRegistry.Framework.ONNX -> "ONNX"
            CppBridgeModelRegistry.Framework.SHERPA -> "Sherpa"
            CppBridgeModelRegistry.Framework.LLAMACPP -> "LlamaCpp"
            CppBridgeModelRegistry.Framework.COREML -> "CoreML"
            CppBridgeModelRegistry.Framework.FOUNDATION_MODELS -> "FoundationModels"
            CppBridgeModelRegistry.Framework.SYSTEM_TTS -> "SystemTTS"
            CppBridgeModelRegistry.Framework.FLUID_AUDIO -> "FluidAudio"
            CppBridgeModelRegistry.Framework.WHISPERKIT_COREML -> "WhisperKitCoreML"
            CppBridgeModelRegistry.Framework.METALRT -> "MetalRT"
            CppBridgeModelRegistry.Framework.GENIE -> "Genie"
            CppBridgeModelRegistry.Framework.BUILTIN -> "BuiltIn"
            CppBridgeModelRegistry.Framework.NONE -> "None"
            else -> "Unknown"
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
     * Get the temporary file path for a download.
     *
     * @param modelId The model ID
     * @return The temporary file path
     */
    fun getTempDownloadPath(modelId: String): String {
        val downloadsDir = getDownloadsDirectoryCallback()
        return File(downloadsDir, "$modelId.tmp").absolutePath
    }

    /**
     * Move a downloaded file to its final location under the canonical
     * schema: `{base}/RunAnywhere/Models/{framework}/{modelId}/{modelId}.<ext>`
     *
     * For directory-based frameworks (ONNX/Sherpa) the file is placed inside
     * the model folder preserving its original filename.
     *
     * @param tempPath The temporary file path
     * @param modelId The model ID
     * @param framework Inference framework int
     * @return true if moved successfully
     */
    fun moveDownloadToFinal(tempPath: String, modelId: String, framework: Int): Boolean {
        return try {
            val tempFile = File(tempPath)
            if (!tempFile.exists()) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "Temp file does not exist: $tempPath",
                )
                return false
            }

            // Ensure target model folder exists
            val modelFolder = File(getModelPath(modelId, framework))
            if (!modelFolder.exists() && !modelFolder.mkdirs()) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "Failed to create model folder: ${modelFolder.absolutePath}",
                )
                return false
            }

            val finalFile = File(modelFolder, modelId)

            // Delete existing file/directory if present
            if (finalFile.exists()) {
                val deleted =
                    if (finalFile.isDirectory) {
                        finalFile.deleteRecursively()
                    } else {
                        finalFile.delete()
                    }
                if (!deleted) {
                    CppBridgePlatformAdapter.logCallback(
                        CppBridgePlatformAdapter.LogLevel.ERROR,
                        TAG,
                        "Failed to delete existing destination: ${finalFile.absolutePath} (isDir=${finalFile.isDirectory})",
                    )
                    return false
                }
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
                "Moved model to final location: ${finalFile.absolutePath}",
            )

            try {
                pathListener?.onModelFileAdded(modelId, finalFile.absolutePath)
            } catch (e: Exception) {
                // Ignore listener errors
            }

            true
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Failed to move download to final location: ${e.message}",
            )
            false
        }
    }

    /**
     * Initialize the default base directory.
     */
    private fun initializeDefaultBaseDirectory(): String {
        val provider = pathProvider
        val basePath =
            if (provider != null) {
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
                        "Failed to create default base directory: ${e.message}",
                    )
                }

                // Push base dir into C++ core and run legacy cleanup.
                try {
                    val rc = RunAnywhereBridge.racModelPathsSetBaseDir(basePath)
                    if (rc != 0) {
                        CppBridgePlatformAdapter.logCallback(
                            CppBridgePlatformAdapter.LogLevel.WARN,
                            TAG,
                            "racModelPathsSetBaseDir (default) returned $rc",
                        )
                    }
                } catch (t: Throwable) {
                    CppBridgePlatformAdapter.logCallback(
                        CppBridgePlatformAdapter.LogLevel.WARN,
                        TAG,
                        "racModelPathsSetBaseDir (default) unavailable: ${t.message}",
                    )
                }
                cleanupLegacyModelsDirLocked(basePath)
            }
        }

        return basePath
    }
}
