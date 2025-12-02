package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.foundation.filemanager.SimplifiedFileManager
import com.runanywhere.sdk.foundation.storage.DefaultStorageAnalyzer
import com.runanywhere.sdk.foundation.storage.StorageAnalyzer
import com.runanywhere.sdk.models.storage.StorageInfo
import com.runanywhere.sdk.public.RunAnywhereSDK

/**
 * Storage extension for RunAnywhere SDK
 * Matches iOS RunAnywhere+Storage.swift extension exactly
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
 * Get storage information with event reporting
 * Matches iOS static func getStorageInfo() async -> StorageInfo exactly
 *
 * iOS implementation:
 * ```swift
 * static func getStorageInfo() async -> StorageInfo {
 *     events.publish(SDKStorageEvent.infoRequested)
 *     let storageAnalyzer = RunAnywhere.serviceContainer.storageAnalyzer
 *     let storageInfo = await storageAnalyzer.analyzeStorage()
 *     events.publish(SDKStorageEvent.infoRetrieved(info: storageInfo))
 *     return storageInfo
 * }
 * ```
 */
suspend fun RunAnywhereSDK.getStorageInfo(): StorageInfo {
    // Note: Event publishing can be added when event system is implemented
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
 * Clear cache with event reporting
 * Matches iOS static func clearCache() async throws exactly
 *
 * iOS implementation:
 * ```swift
 * static func clearCache() async throws {
 *     events.publish(SDKStorageEvent.clearCacheStarted)
 *     do {
 *         let fileManager = RunAnywhere.serviceContainer.fileManager
 *         try fileManager.clearCache()
 *         events.publish(SDKStorageEvent.clearCacheCompleted)
 *     } catch {
 *         events.publish(SDKStorageEvent.clearCacheFailed(error))
 *         throw error
 *     }
 * }
 * ```
 */
suspend fun RunAnywhereSDK.clearCache() {
    logger.debug("Clearing cache")

    try {
        // Use fileManager.clearCache() directly - matches iOS
        val success = fileManager.clearCache()

        if (success) {
            logger.info("Cache cleared successfully")
        } else {
            logger.warn("Failed to clear cache")
        }
    } catch (e: Exception) {
        logger.error("Error clearing cache", e)
        throw e
    }
}

/**
 * Clean temporary files with event reporting
 * Matches iOS static func cleanTempFiles() async throws exactly
 *
 * iOS implementation:
 * ```swift
 * static func cleanTempFiles() async throws {
 *     events.publish(SDKStorageEvent.cleanTempStarted)
 *     do {
 *         let fileManager = RunAnywhere.serviceContainer.fileManager
 *         try fileManager.cleanTempFiles()
 *         events.publish(SDKStorageEvent.cleanTempCompleted)
 *     } catch {
 *         events.publish(SDKStorageEvent.cleanTempFailed(error))
 *         throw error
 *     }
 * }
 * ```
 */
suspend fun RunAnywhereSDK.cleanTempFiles() {
    logger.debug("Cleaning temp files")

    try {
        // Use fileManager.cleanTempFiles() directly - matches iOS
        val success = fileManager.cleanTempFiles()

        if (success) {
            logger.info("Temp files cleaned successfully")
        } else {
            logger.warn("Failed to clean temp files")
        }
    } catch (e: Exception) {
        logger.error("Error cleaning temp files", e)
        throw e
    }
}

/**
 * Delete stored model with event reporting
 * Matches iOS static func deleteStoredModel(_ modelId: String) async throws exactly
 *
 * iOS implementation:
 * ```swift
 * static func deleteStoredModel(_ modelId: String) async throws {
 *     events.publish(SDKStorageEvent.deleteModelStarted(modelId: modelId))
 *     do {
 *         let fileManager = RunAnywhere.serviceContainer.fileManager
 *         try fileManager.deleteModel(modelId: modelId)
 *         events.publish(SDKStorageEvent.deleteModelCompleted(modelId: modelId))
 *     } catch {
 *         events.publish(SDKStorageEvent.deleteModelFailed(modelId: modelId, error: error))
 *         throw error
 *     }
 * }
 * ```
 *
 * NOTE: iOS SimplifiedFileManager.deleteModel() also removes metadata via:
 * ```swift
 * Task {
 *     let modelInfoService = await ServiceContainer.shared.modelInfoService
 *     try? await modelInfoService.removeModel(modelId)
 * }
 * ```
 * We replicate this behavior here at the extension level.
 */
suspend fun RunAnywhereSDK.deleteStoredModel(modelId: String) {
    logger.debug("Deleting model: $modelId")

    try {
        // Use fileManager.deleteModel() directly - matches iOS
        // This searches framework folders first, then direct folders
        val success = fileManager.deleteModel(modelId)

        if (success) {
            // Remove metadata from ModelInfoService - matches iOS SimplifiedFileManager behavior
            // iOS does this in a fire-and-forget Task, ignoring errors
            try {
                ServiceContainer.shared.modelInfoService.deleteModel(modelId)
                logger.debug("Removed model metadata: $modelId")
            } catch (e: Exception) {
                // Ignore metadata removal errors - matches iOS try? pattern
                logger.warn("Failed to remove model metadata (non-critical): $modelId - ${e.message}")
            }

            logger.info("Deleted model: $modelId")
        } else {
            logger.warn("Model not found: $modelId")
            throw IllegalArgumentException("Model not found: $modelId")
        }
    } catch (e: Exception) {
        logger.error("Error deleting model: $modelId", e)
        throw e
    }
}

/**
 * Get base directory URL
 * Matches iOS static func getBaseDirectoryURL() -> URL exactly
 *
 * iOS implementation:
 * ```swift
 * static func getBaseDirectoryURL() -> URL {
 *     let fileManager = RunAnywhere.serviceContainer.fileManager
 *     return fileManager.getBaseFolder().url
 * }
 * ```
 */
fun RunAnywhereSDK.getBaseDirectoryURL(): String {
    return fileManager.getBaseDirectoryURL()
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
