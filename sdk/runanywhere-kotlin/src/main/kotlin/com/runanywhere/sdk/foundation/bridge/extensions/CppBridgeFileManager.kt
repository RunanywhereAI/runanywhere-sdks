/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * FileManager extension for CppBridge.
 * C++ owns business logic (recursive dir size, cache clearing, storage checks).
 * Kotlin provides thin I/O callbacks (create dir, delete, list, stat).
 *
 * Follows iOS CppBridge+FileManager.swift architecture.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.InferenceFramework
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * File manager bridge to C++ rac_file_manager.
 *
 * C++ handles: recursive dir size, directory structure, cache clearing, storage checks.
 * Kotlin provides: thin I/O callbacks (create dir, delete, list, stat, file size).
 */
object CppBridgeFileManager {
    @Volatile
    private var isRegistered: Boolean = false
    private val lock = Any()

    /**
     * Register the file I/O callbacks with C++ core.
     * Must be called during SDK initialization after native library is loaded.
     */
    fun register() {
        synchronized(lock) {
            if (isRegistered) return
            RunAnywhereBridge.nativeFileManagerRegisterCallbacks(FileCallbackProvider)
            isRegistered = true
        }
    }

    /**
     * Clear the SDK-owned Cache directory via the commons FileManager. Returns
     * `true` on success. Mirrors Swift `CppBridge.FileManager.clearCache()`.
     */
    fun clearCache(): Boolean = RunAnywhereBridge.nativeFileManagerClearCache() == 0

    /**
     * Clear the SDK-owned Temp directory via the commons FileManager. Returns
     * `true` on success. Mirrors Swift `CppBridge.FileManager.clearTemp()`.
     */
    fun clearTemp(): Boolean = RunAnywhereBridge.nativeFileManagerClearTemp() == 0

    // Swift-parity wrappers (mirror CppBridge+FileManager.swift)
    //
    // Thin JNI passthroughs to the `rac_file_manager_*` C ABI. Paths use Kotlin
    // `String` (vs Swift's `URL`). The framework-aware variants of delete /
    // exists / has-contents share the framework-implicit JNI thunks (B1) — the
    // `framework` parameter is accepted for Swift call-site parity but is not
    // currently forwarded; commons resolves the framework via the registry.

    /**
     * Create the canonical directory structure (Models, Cache, Temp, Downloads)
     * under the configured base directory. Mirrors Swift
     * `CppBridge.FileManager.createDirectoryStructure()`.
     *
     * @return `true` on success.
     */
    fun createDirectoryStructure(): Boolean {
        val root = CppBridgeModelPaths.getBaseDirectory()
        return RunAnywhereBridge.racFileManagerCreateDirectoryStructure(root) == 0
    }

    /**
     * Calculate a directory's recursive size in bytes. Mirrors Swift
     * `CppBridge.FileManager.calculateDirectorySize(at:)`.
     *
     * @param path Absolute path to the directory to measure.
     * @return Total size in bytes, or 0 on error.
     */
    fun calculateDirectorySize(path: String): Long =
        RunAnywhereBridge.racFileManagerCalculateDirectorySize(path)

    /**
     * Total bytes used under the models directory. Mirrors Swift
     * `CppBridge.FileManager.modelsStorageUsed()`.
     */
    fun modelsStorageUsed(): Long = RunAnywhereBridge.racFileManagerModelsStorageUsed()

    /**
     * Total bytes used under the cache directory. Mirrors Swift
     * `CppBridge.FileManager.cacheSize()`.
     */
    fun cacheSize(): Long = RunAnywhereBridge.racFileManagerCacheSize()

    /**
     * Delete a model's on-disk folder. Mirrors Swift
     * `CppBridge.FileManager.deleteModel(modelId:framework:)`.
     *
     * @param modelId Model identifier.
     * @param framework Inference framework (currently informational —
     *   the JNI thunk uses the framework-implicit form and lets commons
     *   resolve the canonical path from the registry).
     * @return `true` on success.
     */
    @Suppress("UNUSED_PARAMETER")
    fun deleteModel(modelId: String, framework: InferenceFramework): Boolean =
        RunAnywhereBridge.racFileManagerDeleteModel(modelId) == 0

    /**
     * Check whether a model's on-disk folder exists. Mirrors Swift
     * `CppBridge.FileManager.modelFolderExists(modelId:framework:)`.
     *
     * @param modelId Model identifier.
     * @param framework Inference framework (currently informational — see
     *   [deleteModel]).
     */
    @Suppress("UNUSED_PARAMETER")
    fun modelFolderExists(modelId: String, framework: InferenceFramework): Boolean =
        RunAnywhereBridge.racFileManagerModelFolderExists(modelId)

    /**
     * Check whether a model's on-disk folder exists *and* has files inside.
     * Mirrors Swift `CppBridge.FileManager.modelFolderHasContents(modelId:framework:)`.
     *
     * @param modelId Model identifier.
     * @param framework Inference framework (currently informational — see
     *   [deleteModel]).
     */
    @Suppress("UNUSED_PARAMETER")
    fun modelFolderHasContents(modelId: String, framework: InferenceFramework): Boolean =
        RunAnywhereBridge.racFileManagerModelFolderHasContents(modelId)

    /**
     * Combined storage info — mirrors Swift
     * `CppBridge.FileManager.getStorageInfo()` (which returns
     * `rac_file_manager_storage_info_t`).
     *
     * The JNI thunk returns a 6 × int64 little-endian payload; this wrapper
     * decodes it into [StorageInfo]. Returns null on failure.
     */
    fun getStorageInfo(): StorageInfo? {
        val bytes = RunAnywhereBridge.racFileManagerGetStorageInfo() ?: return null
        if (bytes.size < STORAGE_INFO_PAYLOAD_BYTES) return null
        val buf = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        return StorageInfo(
            deviceTotal = buf.long,
            deviceFree = buf.long,
            modelsSize = buf.long,
            cacheSize = buf.long,
            tempSize = buf.long,
            totalAppSize = buf.long,
        )
    }

    /**
     * Check whether `requiredBytes` are available for download. Mirrors Swift
     * `CppBridge.FileManager.checkStorage(requiredBytes:)` (which returns
     * `rac_storage_availability_t`).
     *
     * The JNI thunk collapses the full availability struct to the
     * `is_available` flag; this wrapper returns it as a `Boolean`.
     */
    fun checkStorage(requiredBytes: Long): Boolean =
        RunAnywhereBridge.racFileManagerCheckStorage(requiredBytes)

    /**
     * Decoded form of `rac_file_manager_storage_info_t` — all sizes are in bytes.
     */
    data class StorageInfo(
        val deviceTotal: Long,
        val deviceFree: Long,
        val modelsSize: Long,
        val cacheSize: Long,
        val tempSize: Long,
        val totalAppSize: Long,
    )

    /** Size of the JNI getStorageInfo payload: 6 × int64. */
    private const val STORAGE_INFO_PAYLOAD_BYTES = 6 * 8

    /**
     * Provides platform file I/O methods called by C++ via JNI.
     * Method signatures must match JNI expectations exactly.
     */
    private object FileCallbackProvider {
        @Suppress("unused") // Called from JNI
        fun createDirectory(path: String, recursive: Boolean): Int {
            return try {
                val dir = File(path)
                val success = if (recursive) dir.mkdirs() else dir.mkdir()
                if (success || dir.exists()) 0 else -180 // RAC_ERROR_DIRECTORY_CREATION_FAILED
            } catch (_: Exception) {
                -180
            }
        }

        @Suppress("unused") // Called from JNI
        fun deletePath(path: String, recursive: Boolean): Int {
            return try {
                val file = File(path)
                if (!file.exists()) return 0
                val success = if (recursive) file.deleteRecursively() else file.delete()
                if (success) 0 else -182 // RAC_ERROR_DELETE_FAILED
            } catch (_: Exception) {
                -182
            }
        }

        @Suppress("unused") // Called from JNI
        fun listDirectory(path: String): Array<String>? {
            return File(path).list()
        }

        @Suppress("unused") // Called from JNI
        fun pathExists(path: String): Boolean {
            return File(path).exists()
        }

        @Suppress("unused") // Called from JNI
        fun isDirectory(path: String): Boolean {
            return File(path).isDirectory
        }

        @Suppress("unused") // Called from JNI
        fun getFileSize(path: String): Long {
            val file = File(path)
            return if (file.isFile) file.length() else -1L
        }

        @Suppress("unused") // Called from JNI
        fun getAvailableSpace(): Long {
            val baseDir = File(CppBridgeModelPaths.getBaseDirectory())
            return baseDir.freeSpace
        }

        @Suppress("unused") // Called from JNI
        fun getTotalSpace(): Long {
            val baseDir = File(CppBridgeModelPaths.getBaseDirectory())
            return baseDir.totalSpace
        }
    }
}
