package com.runanywhere.sdk.files

import java.io.File

/**
 * Storage information data class
 */
data class StorageInfo(
    val totalSpace: Long,
    val usedSpace: Long,
    val modelCount: Int,
    val cacheSize: Long
)

/**
 * File manager for SDK file operations
 */
class FileManager {
    private val baseDir = File(System.getProperty("user.home"), ".runanywhere")
    private val modelsDir = File(baseDir, "models")
    private val cacheDir = File(baseDir, "cache")
    private val tempDir = File(baseDir, "temp")

    init {
        modelsDir.mkdirs()
        cacheDir.mkdirs()
        tempDir.mkdirs()
    }

    /**
     * Get path for a model file
     */
    fun getModelPath(modelId: String): File {
        return File(modelsDir, "$modelId.bin")
    }

    /**
     * Get path for a cache file
     */
    fun getCachePath(key: String): File {
        return File(cacheDir, key.hashCode().toString())
    }

    /**
     * Create a temporary file
     */
    fun createTempFile(prefix: String, suffix: String): File {
        return File.createTempFile(prefix, suffix, tempDir)
    }

    /**
     * Clean up old temporary files
     */
    fun cleanupOldFiles(maxAge: Long = 7 * 24 * 60 * 60 * 1000) {
        val cutoff = System.currentTimeMillis() - maxAge

        tempDir.walkTopDown().forEach { file ->
            if (file.isFile && file.lastModified() < cutoff) {
                file.delete()
            }
        }
    }

    /**
     * Get storage information
     */
    fun getStorageInfo(): StorageInfo {
        return StorageInfo(
            totalSpace = baseDir.totalSpace,
            usedSpace = baseDir.walkTopDown().sumOf { if (it.isFile) it.length() else 0L },
            modelCount = modelsDir.listFiles()?.filter { it.isFile }?.size ?: 0,
            cacheSize = cacheDir.walkTopDown().sumOf { if (it.isFile) it.length() else 0L }
        )
    }

    /**
     * Clear cache directory
     */
    fun clearCache() {
        cacheDir.walkTopDown()
            .filter { it.isFile }
            .forEach { it.delete() }
    }
}
