package com.runanywhere.sdk.`public`.extensions

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.infrastructure.events.EventPublisher
import com.runanywhere.sdk.infrastructure.events.SDKModelEvent
import com.runanywhere.sdk.infrastructure.events.SDKStorageEvent
import com.runanywhere.sdk.models.enums.InferenceFramework
import com.runanywhere.sdk.models.storage.StorageInfo
import com.runanywhere.sdk.`public`.RunAnywhere

/**
 * RunAnywhere Storage Extensions
 *
 * Public API for storage and download operations.
 * Matches iOS RunAnywhere+Storage.swift exactly.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/RunAnywhere+Storage.swift
 */

private val logger = SDKLogger("RunAnywhere+Storage")

// MARK: - Storage Extensions

/**
 * Get storage information
 * Matches iOS: static func getStorageInfo() async -> StorageInfo
 *
 * Usage:
 * ```kotlin
 * val storageInfo = RunAnywhere.getStorageInfo()
 * println("Total model size: ${storageInfo.modelStorage.totalSize}")
 * println("Device free space: ${storageInfo.deviceStorage.freeSpace}")
 * ```
 */
suspend fun RunAnywhere.Companion.getStorageInfo(): StorageInfo {
    logger.debug("Getting storage info")
    val storageAnalyzer = ServiceContainer.shared.storageAnalyzer
    return storageAnalyzer.analyzeStorage()
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
 * RunAnywhere.clearCache()
 * ```
 */
suspend fun RunAnywhere.Companion.clearCache() {
    logger.info("Clearing cache")
    val fileManager = ServiceContainer.shared.fileManager
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
 * RunAnywhere.cleanTempFiles()
 * ```
 */
suspend fun RunAnywhere.Companion.cleanTempFiles() {
    logger.info("Cleaning temporary files")
    val fileManager = ServiceContainer.shared.fileManager
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
 * Matches iOS: static func deleteStoredModel(_ modelId: String, framework: InferenceFramework) async throws
 *
 * @param modelId The model identifier
 * @param framework The framework the model belongs to
 *
 * Usage:
 * ```kotlin
 * RunAnywhere.deleteStoredModel("my-model-id", InferenceFramework.LLAMA_CPP)
 * ```
 */
suspend fun RunAnywhere.Companion.deleteStoredModel(
    modelId: String,
    framework: InferenceFramework,
) {
    logger.info("Deleting stored model: $modelId (framework: ${framework.displayName})")
    val fileManager = ServiceContainer.shared.fileManager
    val deleted = fileManager.deleteModel(modelId, framework)

    if (deleted) {
        logger.info("Model deleted successfully: $modelId")
        EventPublisher.track(SDKModelEvent.DeleteCompleted(modelId))
    } else {
        logger.warning("Failed to delete model: $modelId")
    }
}

/**
 * Get base directory URL
 * Matches iOS: static func getBaseDirectoryURL() -> URL
 *
 * @return The base directory path for the SDK
 */
fun RunAnywhere.Companion.getBaseDirectoryPath(): String {
    val fileManager = ServiceContainer.shared.fileManager
    return fileManager.getBaseDirectory()
}

/**
 * Get all downloaded models grouped by framework
 * Matches iOS: static func getDownloadedModels() -> [InferenceFramework: [String]]
 *
 * @return Map of framework to list of model IDs
 */
fun RunAnywhere.Companion.getDownloadedModels(): Map<InferenceFramework, List<String>> {
    val fileManager = ServiceContainer.shared.fileManager
    return fileManager.getAllStoredModels()
}

/**
 * Check if a model is downloaded
 * Matches iOS: static func isModelDownloaded(_ modelId: String, framework: InferenceFramework) -> Bool
 *
 * @param modelId The model identifier
 * @param framework The framework the model belongs to
 * @return True if the model is downloaded, false otherwise
 */
fun RunAnywhere.Companion.isModelDownloaded(
    modelId: String,
    framework: InferenceFramework,
): Boolean {
    val fileManager = ServiceContainer.shared.fileManager
    return fileManager.isModelDownloaded(modelId, framework)
}
