/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * ModelPaths extension for CppBridge.
 *
 * This is a THIN Kotlin shim. All path shapes are computed by the C++ core
 * via `rac_model_paths_*`. The canonical schema is Swift-aligned:
 *   `{base_dir}/RunAnywhere/Models/{framework}/{modelId}/`
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
    @Volatile
    private var baseDirectory: String? = null

    private val lock = Any()

    /**
     * Tag for logging.
     */
    private const val TAG = "CppBridgeModelPaths"

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
     * Get the base directory for model storage.
     *
     * Ensures the base directory is materialised locally AND pushed into the
     * C++ core via `rac_model_paths_set_base_dir`.
     *
     * @return The base directory path
     */
    fun getBaseDirectory(): String {
        return synchronized(lock) {
            baseDirectory ?: initializeDefaultBaseDirectory()
        }
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
        val base = getBaseDirectory()
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
        val frameworkName =
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
        return File(File(File(base, "RunAnywhere"), "Models"), "$frameworkName${File.separator}$modelId").absolutePath
    }

    /**
     * Initialize the default base directory.
     * Caller must hold [lock] OR be calling from the synchronized [getBaseDirectory].
     */
    private fun initializeDefaultBaseDirectory(): String {
        val provider = pathProvider
        val basePath =
            if (provider != null) {
                val filesDir = provider.getFilesDirectory()
                File(filesDir, "runanywhere").absolutePath
            } else {
                val userHome = System.getProperty("user.home")
                if (userHome != null) {
                    File(userHome, ".runanywhere").absolutePath
                } else {
                    File(System.getProperty("java.io.tmpdir", "/tmp"), "runanywhere").absolutePath
                }
            }

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

        // Push base dir into C++ core so rac_model_paths_get_model_folder can work.
        // Swallow any linkage failure here: JNI may not be loaded yet in pure-JVM
        // test contexts.
        try {
            val rc = RunAnywhereBridge.racModelPathsSetBaseDir(basePath)
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

        return basePath
    }
}
