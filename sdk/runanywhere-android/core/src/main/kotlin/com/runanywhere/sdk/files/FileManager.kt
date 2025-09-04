package com.runanywhere.sdk.files

import android.content.Context
import com.runanywhere.sdk.foundation.SDKLogger
import java.io.File

/**
 * Centralized file management for the SDK
 */
object FileManager {

    private lateinit var context: Context
    private val logger = SDKLogger("FileManager")
    private var isInitialized = false

    fun initialize(appContext: Context) {
        context = appContext.applicationContext
        createDirectories()
        isInitialized = true
    }

    val baseDirectory: File
        get() {
            requireInitialized()
            return File(context.filesDir, "runanywhere")
        }

    val modelsDirectory: File
        get() {
            requireInitialized()
            return File(baseDirectory, "models")
        }

    val cacheDirectory: File
        get() {
            requireInitialized()
            return File(baseDirectory, "cache")
        }

    val tempDirectory: File
        get() {
            requireInitialized()
            return File(baseDirectory, "temp")
        }

    private fun createDirectories() {
        listOf(baseDirectory, modelsDirectory, cacheDirectory, tempDirectory).forEach { dir ->
            if (!dir.exists()) {
                dir.mkdirs()
                logger.info("Created directory: ${dir.path}")
            }
        }
    }

    fun getModelPath(modelId: String): File {
        requireInitialized()
        return File(modelsDirectory, "$modelId.bin")
    }

    fun getCachePath(key: String): File {
        requireInitialized()
        return File(cacheDirectory, key.hashCode().toString())
    }

    fun cleanupOldFiles(maxAge: Long = 7 * 24 * 60 * 60 * 1000) {
        requireInitialized()
        val cutoff = System.currentTimeMillis() - maxAge

        tempDirectory.walk().forEach { file ->
            if (file.isFile && file.lastModified() < cutoff) {
                file.delete()
                logger.debug("Deleted old temp file: ${file.name}")
            }
        }
    }

    fun getStorageInfo(): StorageInfo {
        requireInitialized()
        val totalSpace = baseDirectory.totalSpace
        val usedSpace = baseDirectory.walk().sumOf { if (it.isFile) it.length() else 0L }
        val modelCount = modelsDirectory.listFiles()?.filter { it.isFile }?.size ?: 0
        val cacheSize = cacheDirectory.walk().sumOf { if (it.isFile) it.length() else 0L }

        return StorageInfo(
            totalSpace = totalSpace,
            usedSpace = usedSpace,
            modelCount = modelCount,
            cacheSize = cacheSize
        )
    }

    fun modelExists(modelId: String): Boolean {
        requireInitialized()
        return getModelPath(modelId).exists()
    }

    fun deleteModel(modelId: String): Boolean {
        requireInitialized()
        val modelFile = getModelPath(modelId)
        return if (modelFile.exists()) {
            modelFile.delete()
        } else {
            false
        }
    }

    fun clearCache() {
        requireInitialized()
        cacheDirectory.walkTopDown()
            .filter { it.isFile }
            .forEach { it.delete() }
    }

    private fun requireInitialized() {
        if (!isInitialized) {
            throw IllegalStateException("FileManager not initialized. Call FileManager.initialize(context) first.")
        }
    }
}

data class StorageInfo(
    val totalSpace: Long,
    val usedSpace: Long,
    val modelCount: Int,
    val cacheSize: Long
)
