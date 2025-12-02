package com.runanywhere.sdk.foundation.storage

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.foundation.filemanager.SimplifiedFileManager
import com.runanywhere.sdk.models.ModelRegistry
import com.runanywhere.sdk.models.storage.*
import com.runanywhere.sdk.platform.getPlatformStorageInfo
import kotlinx.datetime.Instant

/**
 * Storage analyzer for SDK storage operations
 * Matches iOS DefaultStorageAnalyzer protocol and implementation
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Storage/Analysis/DefaultStorageAnalyzer.swift
 */
interface StorageAnalyzer {
    suspend fun analyzeStorage(): StorageInfo
    suspend fun getAppStorage(): AppStorageInfo
    suspend fun getDeviceStorage(): DeviceStorageInfo
    suspend fun getModelStorage(): ModelStorageInfo
    suspend fun getStoredModelsList(): List<StoredModel>
    fun getStorageAvailability(deviceStorage: DeviceStorageInfo): StorageAvailability
    fun generateRecommendations(storageInfo: StorageInfo): List<StorageRecommendation>
}

/**
 * Default implementation of StorageAnalyzer
 * Matches iOS DefaultStorageAnalyzer class
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Storage/Analysis/DefaultStorageAnalyzer.swift
 */
@OptIn(kotlin.time.ExperimentalTime::class)
@Suppress("DEPRECATION")
class DefaultStorageAnalyzer(
    private val fileManager: SimplifiedFileManager = SimplifiedFileManager.shared,
    private val logger: SDKLogger = SDKLogger.shared
) : StorageAnalyzer {

    /**
     * Get model registry from ServiceContainer
     * Matches iOS's use of modelRegistry for enriching stored model data
     */
    private val modelRegistry: ModelRegistry?
        get() = try {
            ServiceContainer.shared.modelRegistry
        } catch (e: Exception) {
            null
        }

    /**
     * Analyze overall storage
     * Matches iOS analyzeStorage() method
     */
    override suspend fun analyzeStorage(): StorageInfo {
        logger.debug("Starting storage analysis")

        val appStorage = getAppStorage()
        val deviceStorage = getDeviceStorage()
        val storedModels = getStoredModelsList()
        val modelStorage = getModelStorageFromModels(storedModels)
        val availability = getStorageAvailability(deviceStorage)

        val storageInfo = StorageInfo(
            appStorage = appStorage,
            deviceStorage = deviceStorage,
            modelStorage = modelStorage,
            cacheSize = appStorage.cacheSize,
            storedModels = storedModels,
            availability = availability,
            recommendations = emptyList(), // Will be populated below
            lastUpdated = Instant.fromEpochMilliseconds(System.currentTimeMillis())
        )

        val recommendations = generateRecommendations(storageInfo)

        return storageInfo.copy(recommendations = recommendations)
    }

    /**
     * Get app-specific storage information
     * Matches iOS getAppStorage() method - AppStorageInfo structure
     */
    override suspend fun getAppStorage(): AppStorageInfo {
        val modelsSize = fileManager.directorySize(fileManager.modelsDirectory.toString())
        val cacheSize = fileManager.directorySize(fileManager.cacheDirectory.toString())
        val tempSize = fileManager.directorySize(fileManager.temporaryDirectory.toString())
        val databaseSize = fileManager.directorySize(fileManager.databaseDirectory.toString())

        // Total size = models + cache + other app support files
        val totalSize = fileManager.directorySize(fileManager.baseDirectory.toString())

        // App support size = temp + database + other non-model/cache files
        val appSupportSize = (totalSize - modelsSize - cacheSize).coerceAtLeast(0L)

        return AppStorageInfo(
            documentsSize = modelsSize, // Models are stored in documents
            cacheSize = cacheSize,
            appSupportSize = appSupportSize,
            totalSize = totalSize
        )
    }

    /**
     * Get device storage information
     * Matches iOS getDeviceStorageInfo() method
     */
    override suspend fun getDeviceStorage(): DeviceStorageInfo {
        val platformInfo = getPlatformStorageInfo(fileManager.baseDirectory.toString())

        return DeviceStorageInfo(
            totalSpace = platformInfo.totalSpace,
            freeSpace = platformInfo.availableSpace,
            usedSpace = platformInfo.usedSpace
        )
    }

    /**
     * Get model storage information
     * Matches iOS getModelStorageUsage() method
     */
    override suspend fun getModelStorage(): ModelStorageInfo {
        val storedModels = getStoredModelsList()
        return getModelStorageFromModels(storedModels)
    }

    /**
     * Build ModelStorageInfo from stored models list
     */
    private fun getModelStorageFromModels(storedModels: List<StoredModel>): ModelStorageInfo {
        val totalSize = storedModels.sumOf { it.size }
        val largestModel = storedModels.maxByOrNull { it.size }

        return ModelStorageInfo(
            totalSize = totalSize,
            modelCount = storedModels.size,
            largestModel = largestModel,
            models = storedModels
        )
    }

    /**
     * Get list of stored models with enriched information from model registry
     * Matches iOS getStoredModelsList() method
     */
    override suspend fun getStoredModelsList(): List<StoredModel> {
        val storedModels = mutableListOf<StoredModel>()
        val modelsPath = fileManager.modelsDirectory.toString()

        // List all files/directories in models folder
        val modelEntries = fileManager.listFiles(modelsPath)

        // Get registered models from registry for enrichment
        val registeredModels = try {
            modelRegistry?.getAllModels() ?: emptyList()
        } catch (e: Exception) {
            logger.debug("Could not get registered models: ${e.message}")
            emptyList()
        }
        val registeredModelsMap = registeredModels.associateBy { it.id }

        for (entryPath in modelEntries) {
            try {
                // Calculate size (works for both files and directories)
                val size = calculateEntrySize(entryPath)
                if (size <= 0) continue

                // Extract model ID from path
                val fileName = entryPath.substringAfterLast("/")
                val modelId = extractModelId(fileName)

                // Try to find registered model for enrichment
                val registeredModel = registeredModelsMap[modelId]
                    ?: registeredModelsMap.values.find {
                        it.id.contains(modelId, ignoreCase = true) ||
                        modelId.contains(it.id, ignoreCase = true)
                    }

                // Extract format from filename or directory contents
                val format = extractFormat(entryPath, fileName)

                // Get file creation/modification time
                val createdDate = getFileCreatedDate(entryPath)
                val lastUsed = getFileLastAccessedDate(entryPath)

                storedModels.add(
                    StoredModel(
                        id = modelId,
                        name = registeredModel?.name ?: formatDisplayName(modelId),
                        path = entryPath,
                        size = size,
                        format = format,
                        framework = registeredModel?.preferredFramework?.displayName,
                        createdDate = createdDate,
                        lastUsed = lastUsed,
                        contextLength = registeredModel?.contextLength,
                        checksum = null
                    )
                )
            } catch (e: Exception) {
                logger.debug("Error processing model entry $entryPath: ${e.message}")
            }
        }

        return storedModels.sortedByDescending { it.createdDate }
    }

    /**
     * Calculate size of a file or directory
     */
    private fun calculateEntrySize(path: String): Long {
        return try {
            val size = fileManager.fileSize(path)
            if (size != null && size > 0) {
                size
            } else {
                // Might be a directory - calculate directory size
                fileManager.directorySize(path)
            }
        } catch (e: Exception) {
            0L
        }
    }

    /**
     * Extract model ID from filename
     */
    private fun extractModelId(fileName: String): String {
        // Remove common extensions
        return fileName
            .replace(".gguf", "")
            .replace(".onnx", "")
            .replace(".bin", "")
            .replace(".tar.bz2", "")
            .replace(".tar.gz", "")
            .replace(".zip", "")
    }

    /**
     * Extract format from path or filename
     */
    private fun extractFormat(path: String, fileName: String): String {
        return when {
            fileName.endsWith(".gguf") -> "gguf"
            fileName.endsWith(".onnx") -> "onnx"
            fileName.endsWith(".bin") -> "bin"
            // Check if it's a directory containing ONNX files (Sherpa models)
            path.contains("sherpa") || path.contains("whisper") || path.contains("piper") -> "onnx"
            else -> "unknown"
        }
    }

    /**
     * Get file creation date
     */
    private fun getFileCreatedDate(path: String): Instant {
        // For now, use current time as placeholder
        // Platform-specific implementations can override this
        return Instant.fromEpochMilliseconds(System.currentTimeMillis())
    }

    /**
     * Get file last accessed date
     */
    private fun getFileLastAccessedDate(path: String): Instant? {
        // For now, return null
        // Platform-specific implementations can override this
        return null
    }

    /**
     * Format model ID into display name
     */
    private fun formatDisplayName(modelId: String): String {
        return modelId
            .replace("-", " ")
            .replace("_", " ")
            .split(" ")
            .joinToString(" ") { word ->
                word.replaceFirstChar { it.uppercase() }
            }
    }

    /**
     * Determine storage availability status
     * Matches iOS checkStorageAvailable() logic
     */
    override fun getStorageAvailability(deviceStorage: DeviceStorageInfo): StorageAvailability {
        val availablePercentage = if (deviceStorage.totalSpace > 0) {
            (deviceStorage.freeSpace.toDouble() / deviceStorage.totalSpace.toDouble()) * 100.0
        } else {
            0.0
        }

        return when {
            availablePercentage > 20.0 -> StorageAvailability.HEALTHY
            availablePercentage > 10.0 -> StorageAvailability.LOW
            availablePercentage > 5.0 -> StorageAvailability.CRITICAL
            else -> StorageAvailability.FULL
        }
    }

    /**
     * Generate storage recommendations
     * Matches iOS getRecommendations() method
     */
    override fun generateRecommendations(storageInfo: StorageInfo): List<StorageRecommendation> {
        val recommendations = mutableListOf<StorageRecommendation>()

        val freeSpace = storageInfo.deviceStorage.freeSpace
        val totalSpace = storageInfo.deviceStorage.totalSpace

        if (totalSpace > 0) {
            val freePercentage = freeSpace.toDouble() / totalSpace.toDouble()

            // Low storage warning (< 10%)
            if (freePercentage < 0.1) {
                recommendations.add(
                    StorageRecommendation(
                        type = RecommendationType.WARNING,
                        message = "Low storage space. Clear cache to free up space.",
                        action = "Clear Cache"
                    )
                )
            }

            // Critical storage warning (< 5%)
            if (freePercentage < 0.05) {
                recommendations.add(
                    StorageRecommendation(
                        type = RecommendationType.CRITICAL,
                        message = "Critical storage shortage. Consider removing unused models.",
                        action = "Delete Models"
                    )
                )
            }
        }

        // Suggest reviewing models if more than 5 stored
        if (storageInfo.storedModels.size > 5) {
            recommendations.add(
                StorageRecommendation(
                    type = RecommendationType.SUGGESTION,
                    message = "Multiple models stored. Consider removing models you don't use.",
                    action = "Review Models"
                )
            )
        }

        return recommendations
    }
}
