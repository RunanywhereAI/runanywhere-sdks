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

import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import java.io.File

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
