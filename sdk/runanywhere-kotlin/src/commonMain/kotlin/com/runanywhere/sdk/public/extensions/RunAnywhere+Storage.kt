package com.runanywhere.sdk.`public`.extensions

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.filemanager.SimplifiedFileManager
import com.runanywhere.sdk.foundation.storage.DefaultStorageAnalyzer
import com.runanywhere.sdk.infrastructure.events.EventPublisher
import com.runanywhere.sdk.infrastructure.events.SDKModelEvent
import com.runanywhere.sdk.infrastructure.events.SDKStorageEvent
import com.runanywhere.sdk.models.storage.StorageInfo
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * RunAnywhere Storage Extensions
 *
 * Public API for storage and download operations.
 * Matches iOS RunAnywhere+Storage.swift exactly.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/RunAnywhere+Storage.swift
 */

private val logger = SDKLogger("RunAnywhere+Storage")

// Storage analyzer instance (lazy initialization like iOS)
private val storageAnalyzer by lazy { DefaultStorageAnalyzer() }

// File manager instance
private val fileManager by lazy { SimplifiedFileManager.shared }

// MARK: - Storage Extensions

/**
 * Get storage information
 * Matches iOS: static func getStorageInfo() async -> StorageInfo
 *
 * Usage:
 * ```kotlin
 * val storageInfo = getStorageInfo()
 * println("Total model size: ${storageInfo.modelStorage.totalSize}")
 * println("Device free space: ${storageInfo.deviceStorage.freeSpace}")
 * ```
 */
suspend fun getStorageInfo(): StorageInfo =
    withContext(Dispatchers.IO) {
        logger.debug("Getting storage info")
        storageAnalyzer.analyzeStorage()
    }

/**
 * Clear cache
 * Matches iOS: static func clearCache() async throws
 *
 * Clears the SDK's cache directory, freeing up storage space.
 * This includes cached downloads, temporary data, and other cached resources.
 *
 * Usage:
 * ```kotlin
 * clearCache()
 * ```
 */
suspend fun clearCache() =
    withContext(Dispatchers.IO) {
        logger.info("Clearing cache")
        val result = fileManager.clearCache()

        if (result) {
            logger.info("Cache cleared successfully")
            EventPublisher.track(SDKStorageEvent.ClearCacheCompleted)
        } else {
            logger.warning("Failed to clear cache")
        }
    }

/**
 * Clean temporary files
 * Matches iOS: static func cleanTempFiles() async throws
 *
 * Removes temporary files created during SDK operations.
 * This includes temporary downloads, processing files, and other temp data.
 *
 * Usage:
 * ```kotlin
 * cleanTempFiles()
 * ```
 */
suspend fun cleanTempFiles() =
    withContext(Dispatchers.IO) {
        logger.info("Cleaning temporary files")
        val result = fileManager.cleanTempFiles()

        if (result) {
            logger.info("Temporary files cleaned successfully")
            EventPublisher.track(SDKStorageEvent.CleanTempCompleted)
        } else {
            logger.warning("Failed to clean temporary files")
        }
    }

/**
 * Delete a stored model
 * Matches iOS: static func deleteStoredModel(_ modelId: String) async throws
 *
 * @param modelId The model identifier
 *
 * Usage:
 * ```kotlin
 * deleteStoredModel("my-model-id")
 * ```
 */
suspend fun deleteStoredModel(modelId: String) =
    withContext(Dispatchers.IO) {
        logger.info("Deleting stored model: $modelId")
        val deleted = fileManager.deleteModel(modelId)

        if (deleted) {
            logger.info("Model deleted successfully: $modelId")
            EventPublisher.track(SDKModelEvent.DeleteCompleted(modelId))
        } else {
            logger.warning("Failed to delete model: $modelId")
        }
    }

/**
 * Get base directory path
 * Matches iOS: static func getBaseDirectoryURL() -> URL
 *
 * @return The base directory path for the SDK
 */
fun getBaseDirectoryPath(): String = fileManager.getBaseDirectoryURL()
