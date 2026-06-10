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

import ai.runanywhere.proto.v1.InferenceFramework
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.extensions.Models.wireString
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
        // computation that still uses the canonical schema. The string segment
        // is sourced from the codegen-driven `InferenceFramework.wireString`
        // helper (see commonMain/.../Models/ModelTypes.kt) so any future
        // framework added to the proto picks up its path name automatically.
        val frameworkName = racFrameworkIntToProto(framework).wireString
        return File(File(File(base, "RunAnywhere"), "Models"), "$frameworkName${File.separator}$modelId").absolutePath
    }

    /**
     * Map a C++ `RAC_FRAMEWORK_*` int (the values defined in
     * [CppBridgeModelRegistry.Framework]) to the corresponding proto
     * [InferenceFramework] enum. The C++ ABI numbering does NOT match the
     * proto wire numbering, so a small adapter is required.
     *
     * Unknown / unmapped ints fall through to [InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN]
     * which yields the string "Unknown" via the codegen `wireString` helper.
     */
    private fun racFrameworkIntToProto(framework: Int): InferenceFramework =
        when (framework) {
            CppBridgeModelRegistry.Framework.ONNX -> InferenceFramework.INFERENCE_FRAMEWORK_ONNX
            CppBridgeModelRegistry.Framework.LLAMACPP -> InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP
            CppBridgeModelRegistry.Framework.FOUNDATION_MODELS -> InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS
            CppBridgeModelRegistry.Framework.SYSTEM_TTS -> InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS
            CppBridgeModelRegistry.Framework.FLUID_AUDIO -> InferenceFramework.INFERENCE_FRAMEWORK_FLUID_AUDIO
            CppBridgeModelRegistry.Framework.BUILTIN -> InferenceFramework.INFERENCE_FRAMEWORK_BUILT_IN
            CppBridgeModelRegistry.Framework.NONE -> InferenceFramework.INFERENCE_FRAMEWORK_NONE
            CppBridgeModelRegistry.Framework.MLX -> InferenceFramework.INFERENCE_FRAMEWORK_MLX
            CppBridgeModelRegistry.Framework.COREML -> InferenceFramework.INFERENCE_FRAMEWORK_COREML
            CppBridgeModelRegistry.Framework.METALRT -> InferenceFramework.INFERENCE_FRAMEWORK_METALRT
            CppBridgeModelRegistry.Framework.GENIE -> InferenceFramework.INFERENCE_FRAMEWORK_GENIE
            CppBridgeModelRegistry.Framework.SHERPA -> InferenceFramework.INFERENCE_FRAMEWORK_SHERPA
            else -> InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN
        }

    // Swift-parity wrappers (mirror CppBridge+ModelPaths.swift)
    //
    // Thin JNI passthroughs to the `rac_model_paths_*` C ABI. Paths are
    // returned as `String` (Kotlin/JVM idiom) instead of Swift's `URL`.
    // Framework ints are RAC_FRAMEWORK_* values (see [CppBridgeModelRegistry.Framework]).
    // Format ints are rac_model_format_t values.

    /**
     * Set the base directory for model storage. Must be called during SDK
     * initialization. Mirrors Swift `CppBridge.ModelPaths.setBaseDirectory(_:)`.
     *
     * @param baseDir Absolute path to the base directory.
     * @throws SDKException with `ERROR_CODE_INITIALIZATION_FAILED` on failure.
     */
    fun setBaseDirectory(baseDir: String) {
        val result = RunAnywhereBridge.racModelPathsSetBaseDir(baseDir)
        if (result != 0) {
            throw SDKException.make(
                code = ai.runanywhere.proto.v1.ErrorCode.ERROR_CODE_INITIALIZATION_FAILED,
                message = "Failed to set base directory",
                category = ai.runanywhere.proto.v1.ErrorCategory.ERROR_CATEGORY_INTERNAL,
                cAbiCode = result,
            )
        }
        synchronized(lock) {
            baseDirectory = baseDir
        }
        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Base directory set to: $baseDir",
        )
    }

    /**
     * Read back the base directory configured in commons. Mirrors Swift
     * `CppBridge.ModelPaths.baseDirectory`.
     */
    fun configuredBaseDirectory(): String? = RunAnywhereBridge.racModelPathsGetBaseDir()

    /**
     * Get the canonical models directory (`{base_dir}/RunAnywhere/Models/`).
     * Mirrors Swift `CppBridge.ModelPaths.getModelsDirectory()`.
     *
     * @throws SDKException with `ERROR_CODE_INITIALIZATION_FAILED` if base dir is not configured.
     */
    fun getModelsDirectory(): String =
        RunAnywhereBridge.racModelPathsGetModelsDirectory()
            ?: throw SDKException.make(
                code = ai.runanywhere.proto.v1.ErrorCode.ERROR_CODE_INITIALIZATION_FAILED,
                message = "Base directory not configured",
                category = ai.runanywhere.proto.v1.ErrorCategory.ERROR_CATEGORY_INTERNAL,
            )

    /**
     * Get the framework-specific directory (`{base_dir}/RunAnywhere/Models/{framework}/`).
     * Mirrors Swift `CppBridge.ModelPaths.getFrameworkDirectory(framework:)`.
     *
     * @param framework RAC_FRAMEWORK_* int (see [CppBridgeModelRegistry.Framework]).
     * @throws SDKException with `ERROR_CODE_INITIALIZATION_FAILED` if base dir is not configured.
     */
    fun getFrameworkDirectory(framework: Int): String =
        RunAnywhereBridge.racModelPathsGetFrameworkDirectory(framework)
            ?: throw SDKException.make(
                code = ai.runanywhere.proto.v1.ErrorCode.ERROR_CODE_INITIALIZATION_FAILED,
                message = "Base directory not configured",
                category = ai.runanywhere.proto.v1.ErrorCategory.ERROR_CATEGORY_INTERNAL,
            )

    /**
     * Get the expected model path (folder for directory-based, file for single-file).
     * Mirrors Swift `CppBridge.ModelPaths.getExpectedModelPath(modelId:framework:format:)`.
     *
     * @param modelId Model identifier.
     * @param framework RAC_FRAMEWORK_* int (see [CppBridgeModelRegistry.Framework]).
     * @param format rac_model_format_t int (matches proto `ModelFormat.value`).
     * @throws SDKException with `ERROR_CODE_INITIALIZATION_FAILED` if base dir is not configured.
     */
    fun getExpectedModelPath(modelId: String, framework: Int, format: Int): String =
        RunAnywhereBridge.racModelPathsGetExpectedModelPath(modelId, framework, format)
            ?: throw SDKException.make(
                code = ai.runanywhere.proto.v1.ErrorCode.ERROR_CODE_INITIALIZATION_FAILED,
                message = "Base directory not configured",
                category = ai.runanywhere.proto.v1.ErrorCategory.ERROR_CATEGORY_INTERNAL,
            )

    /**
     * Get the cache directory.
     * Mirrors Swift `CppBridge.ModelPaths.getCacheDirectory()`.
     *
     * @throws SDKException with `ERROR_CODE_INITIALIZATION_FAILED` if base dir is not configured.
     */
    fun getCacheDirectory(): String =
        RunAnywhereBridge.racModelPathsGetCacheDirectory()
            ?: throw SDKException.make(
                code = ai.runanywhere.proto.v1.ErrorCode.ERROR_CODE_INITIALIZATION_FAILED,
                message = "Base directory not configured",
                category = ai.runanywhere.proto.v1.ErrorCategory.ERROR_CATEGORY_INTERNAL,
            )

    /**
     * Get the downloads staging directory.
     * Mirrors Swift `CppBridge.ModelPaths.getDownloadsDirectory()`.
     *
     * @throws SDKException with `ERROR_CODE_INITIALIZATION_FAILED` if base dir is not configured.
     */
    fun getDownloadsDirectory(): String =
        RunAnywhereBridge.racModelPathsGetDownloadsDirectory()
            ?: throw SDKException.make(
                code = ai.runanywhere.proto.v1.ErrorCode.ERROR_CODE_INITIALIZATION_FAILED,
                message = "Base directory not configured",
                category = ai.runanywhere.proto.v1.ErrorCategory.ERROR_CATEGORY_INTERNAL,
            )

    /**
     * Get the temp directory.
     * Mirrors Swift `CppBridge.ModelPaths.getTempDirectory()`.
     *
     * @throws SDKException with `ERROR_CODE_INITIALIZATION_FAILED` if base dir is not configured.
     */
    fun getTempDirectory(): String =
        RunAnywhereBridge.racModelPathsGetTempDirectory()
            ?: throw SDKException.make(
                code = ai.runanywhere.proto.v1.ErrorCode.ERROR_CODE_INITIALIZATION_FAILED,
                message = "Base directory not configured",
                category = ai.runanywhere.proto.v1.ErrorCategory.ERROR_CATEGORY_INTERNAL,
            )

    /**
     * Extract the model ID from a canonical model path. Returns null if the
     * path is not a recognized model path.
     * Mirrors Swift `CppBridge.ModelPaths.extractModelId(from:)`.
     */
    fun extractModelId(path: String): String? =
        RunAnywhereBridge.racModelPathsExtractModelId(path)

    /**
     * Extract the framework int from a canonical model path. Returns null if
     * the path is not a recognized model path.
     * Mirrors Swift `CppBridge.ModelPaths.extractFramework(from:)`.
     *
     * @return RAC_FRAMEWORK_* int (see [CppBridgeModelRegistry.Framework]), or null on failure.
     */
    fun extractFramework(path: String): Int? {
        val fw = RunAnywhereBridge.racModelPathsExtractFramework(path)
        return if (fw < 0) null else fw
    }

    /**
     * Check if the given path is a canonical model path (i.e. is within the
     * models directory). Mirrors Swift `CppBridge.ModelPaths.isModelPath(_:)`.
     */
    fun isModelPath(path: String): Boolean =
        RunAnywhereBridge.racModelPathsIsModelPath(path)

    /**
     * Initialize the default base directory.
     * Caller must hold [lock] OR be calling from the synchronized [getBaseDirectory].
     */
    private fun initializeDefaultBaseDirectory(): String {
        val provider = pathProvider
        val basePath =
            if (provider != null) {
                provider.getFilesDirectory()
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
