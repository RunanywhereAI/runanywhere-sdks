package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.filemanager.SimplifiedFileManager
import com.runanywhere.sdk.foundation.storage.DefaultStorageAnalyzer
import com.runanywhere.sdk.foundation.storage.StorageAnalyzer
import com.runanywhere.sdk.models.storage.StorageInfo
import com.runanywhere.sdk.public.RunAnywhereSDK

/**
 * Storage extension for RunAnywhere SDK
 * Matches iOS RunAnywhere+Storage.swift extension
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/RunAnywhere+Storage.swift
 *
 * Provides 5 storage APIs matching iOS:
 * 1. getStorageInfo() - Get comprehensive storage information
 * 2. clearCache() - Clear SDK cache
 * 3. cleanTempFiles() - Remove temporary files
 * 4. deleteStoredModel() - Delete a downloaded model
 * 5. getBaseDirectoryURL() - Get SDK base directory path
 */

private val storageAnalyzer: StorageAnalyzer by lazy { DefaultStorageAnalyzer() }
private val fileManager: SimplifiedFileManager by lazy { SimplifiedFileManager.shared }
private val logger: SDKLogger by lazy { SDKLogger.shared }

/**
 * Get comprehensive storage information
 * Matches iOS static func getStorageInfo() async -> StorageInfo
 */
suspend fun RunAnywhereSDK.getStorageInfo(): StorageInfo {
    logger.debug("Getting storage info")

    return try {
        val storageInfo = storageAnalyzer.analyzeStorage()
        logger.info("Storage info retrieved: ${storageInfo.appStorage.totalSize} bytes used, ${storageInfo.storedModels.size} models stored")
        storageInfo
    } catch (e: Exception) {
        logger.error("Failed to get storage info", e)
        throw e
    }
}

/**
 * Clear SDK cache directory
 * Matches iOS static func clearCache() async throws
 */
suspend fun RunAnywhereSDK.clearCache() {
    logger.debug("Clearing cache")

    try {
        val cacheDir = fileManager.cacheDirectory.toString()
        val deleted = fileManager.deleteDirectory(cacheDir)

        if (deleted) {
            // Recreate the directory
            fileManager.createDirectory(cacheDir)
            logger.info("Cache cleared successfully")
        } else {
            logger.warn("Failed to clear cache directory")
        }
    } catch (e: Exception) {
        logger.error("Error clearing cache", e)
        throw e
    }
}

/**
 * Clean temporary files
 * Matches iOS static func cleanTempFiles() async throws
 */
suspend fun RunAnywhereSDK.cleanTempFiles() {
    logger.debug("Cleaning temp files")

    try {
        val tempDir = fileManager.temporaryDirectory.toString()
        val deleted = fileManager.deleteDirectory(tempDir)

        if (deleted) {
            // Recreate the directory
            fileManager.createDirectory(tempDir)
            logger.info("Temp files cleaned successfully")
        } else {
            logger.warn("Failed to clean temp directory")
        }
    } catch (e: Exception) {
        logger.error("Error cleaning temp files", e)
        throw e
    }
}

/**
 * Delete a stored model
 * Matches iOS static func deleteStoredModel(_ modelId: String) async throws
 */
suspend fun RunAnywhereSDK.deleteStoredModel(modelId: String) {
    logger.debug("Deleting model: $modelId")

    try {
        val modelsDir = fileManager.modelsDirectory.toString()
        val modelEntries = fileManager.listFiles(modelsDir)

        // Find files or directories matching the model ID
        val matchingEntries = modelEntries.filter { entryPath ->
            val entryName = entryPath.substringAfterLast("/")
            entryName.startsWith(modelId) ||
            entryName.contains(modelId, ignoreCase = true)
        }

        if (matchingEntries.isEmpty()) {
            logger.warn("Model not found: $modelId")
            throw IllegalArgumentException("Model not found: $modelId")
        }

        var deletedCount = 0
        matchingEntries.forEach { entryPath ->
            // Try to delete as directory first (for ONNX models in folders)
            val deletedAsDir = fileManager.deleteDirectory(entryPath)
            if (deletedAsDir) {
                deletedCount++
                logger.debug("Deleted model directory: $entryPath")
            } else {
                // Try to delete as file
                if (fileManager.deleteFile(entryPath)) {
                    deletedCount++
                    logger.debug("Deleted model file: $entryPath")
                }
            }
        }

        logger.info("Deleted $deletedCount item(s) for model: $modelId")
    } catch (e: Exception) {
        logger.error("Error deleting model: $modelId", e)
        throw e
    }
}

/**
 * Get SDK base directory path
 * Matches iOS static func getBaseDirectoryURL() -> URL
 */
fun RunAnywhereSDK.getBaseDirectoryURL(): String {
    return fileManager.baseDirectory.toString()
}

/**
 * Get models directory path (bonus method for convenience)
 */
fun RunAnywhereSDK.getModelsDirectoryURL(): String {
    return fileManager.modelsDirectory.toString()
}

/**
 * Get cache directory path (bonus method for convenience)
 */
fun RunAnywhereSDK.getCacheDirectoryURL(): String {
    return fileManager.cacheDirectory.toString()
}

/**
 * Get temporary directory path (bonus method for convenience)
 */
fun RunAnywhereSDK.getTempDirectoryURL(): String {
    return fileManager.temporaryDirectory.toString()
}
