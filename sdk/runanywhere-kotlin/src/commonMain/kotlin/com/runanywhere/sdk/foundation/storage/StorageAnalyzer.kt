package com.runanywhere.sdk.foundation.storage

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.filemanager.SimplifiedFileManager
import com.runanywhere.sdk.models.storage.*
import com.runanywhere.sdk.platform.getPlatformStorageInfo
import kotlinx.datetime.Instant

/**
 * Storage analyzer for SDK storage operations
 * Matches iOS DefaultStorageAnalyzer protocol and implementation
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Storage/DefaultStorageAnalyzer.swift
 */
interface StorageAnalyzer {
    suspend fun analyzeStorage(): StorageInfo
    suspend fun getAppStorage(): AppStorageInfo
    suspend fun getDeviceStorage(): DeviceStorageInfo
    suspend fun getModelStorage(): ModelStorageInfo
    fun getStorageAvailability(deviceStorage: DeviceStorageInfo): StorageAvailability
    fun generateRecommendations(appStorage: AppStorageInfo, deviceStorage: DeviceStorageInfo): List<StorageRecommendation>
}

/**
 * Default implementation of StorageAnalyzer
 * Matches iOS DefaultStorageAnalyzer class
 */
@OptIn(kotlin.time.ExperimentalTime::class)
@Suppress("DEPRECATION")
class DefaultStorageAnalyzer(
    private val fileManager: SimplifiedFileManager = SimplifiedFileManager.shared,
    private val logger: SDKLogger = SDKLogger.shared
) : StorageAnalyzer {

    /**
     * Analyze overall storage
     * Matches iOS analyzeStorage() method
     */
    override suspend fun analyzeStorage(): StorageInfo {
        logger.debug("Starting storage analysis")

        val appStorage = getAppStorage()
        val deviceStorage = getDeviceStorage()
        val modelStorage = getModelStorage()
        val availability = getStorageAvailability(deviceStorage)
        val recommendations = generateRecommendations(appStorage, deviceStorage)

        return StorageInfo(
            appStorage = appStorage,
            deviceStorage = deviceStorage,
            modelStorage = modelStorage,
            availability = availability,
            recommendations = recommendations,
            lastUpdated = kotlinx.datetime.Instant.fromEpochMilliseconds(System.currentTimeMillis())
        )
    }

    /**
     * Get app-specific storage information
     * Matches iOS getAppStorage() method
     */
    override suspend fun getAppStorage(): AppStorageInfo {
        val modelsSize = fileManager.directorySize(fileManager.modelsDirectory.toString())
        val cacheSize = fileManager.directorySize(fileManager.cacheDirectory.toString())
        val tempSize = fileManager.directorySize(fileManager.temporaryDirectory.toString())
        val databaseSize = fileManager.directorySize(fileManager.databaseDirectory.toString())
        val logsSize = fileManager.directorySize(fileManager.logsDirectory.toString())

        // Calculate other files (base directory minus known directories)
        val totalUsed = fileManager.directorySize(fileManager.baseDirectory.toString())
        val knownSizes = modelsSize + cacheSize + tempSize + databaseSize + logsSize
        val other = (totalUsed - knownSizes).coerceAtLeast(0L)

        return AppStorageInfo(
            totalUsed = totalUsed,
            models = modelsSize,
            cache = cacheSize,
            temp = tempSize,
            database = databaseSize,
            logs = logsSize,
            other = other
        )
    }

    /**
     * Get device storage information
     * Matches iOS getDeviceStorage() method
     */
    override suspend fun getDeviceStorage(): DeviceStorageInfo {
        val platformInfo = getPlatformStorageInfo(fileManager.baseDirectory.toString())

        val percentageUsed = if (platformInfo.totalSpace > 0) {
            (platformInfo.usedSpace.toDouble() / platformInfo.totalSpace.toDouble()) * 100.0
        } else {
            0.0
        }

        return DeviceStorageInfo(
            totalCapacity = platformInfo.totalSpace,
            available = platformInfo.availableSpace,
            used = platformInfo.usedSpace,
            percentageUsed = percentageUsed
        )
    }

    /**
     * Get model storage information
     * Matches iOS getModelStorage() method
     */
    override suspend fun getModelStorage(): ModelStorageInfo {
        val modelsPath = fileManager.modelsDirectory.toString()
        val modelFiles = fileManager.listFiles(modelsPath)

        val storedModels = mutableListOf<StoredModel>()
        var totalSize = 0L

        modelFiles.forEach { filePath ->
            val size = fileManager.fileSize(filePath) ?: 0L
            totalSize += size

            // Extract model info from filename
            val fileName = filePath.substringAfterLast("/")
            val modelId = fileName.substringBeforeLast(".")
            val format = fileName.substringAfterLast(".", "unknown")

            storedModels.add(
                StoredModel(
                    id = modelId,
                    name = modelId,
                    size = size,
                    path = filePath,
                    format = format,
                    lastAccessed = null, // Would need additional tracking
                    downloadDate = kotlinx.datetime.Instant.fromEpochMilliseconds(System.currentTimeMillis()) // Would need to store actual date
                )
            )
        }

        val largestModel = storedModels.maxByOrNull { it.size }

        return ModelStorageInfo(
            totalCount = storedModels.size,
            downloadedCount = storedModels.size,
            totalSize = totalSize,
            largestModel = largestModel,
            models = storedModels
        )
    }

    /**
     * Determine storage availability status
     * Matches iOS getStorageAvailability() method
     */
    override fun getStorageAvailability(deviceStorage: DeviceStorageInfo): StorageAvailability {
        val availablePercentage = if (deviceStorage.totalCapacity > 0) {
            (deviceStorage.available.toDouble() / deviceStorage.totalCapacity.toDouble()) * 100.0
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
     * Matches iOS generateRecommendations() method
     */
    override fun generateRecommendations(
        appStorage: AppStorageInfo,
        deviceStorage: DeviceStorageInfo
    ): List<StorageRecommendation> {
        val recommendations = mutableListOf<StorageRecommendation>()

        // Recommend clearing cache if > 100 MB
        if (appStorage.cache > 100 * 1024 * 1024) {
            recommendations.add(
                StorageRecommendation(
                    type = RecommendationType.CLEAR_CACHE,
                    description = "Clear SDK cache to free up space",
                    estimatedSpaceSaved = appStorage.cache,
                    action = "Clear cache"
                )
            )
        }

        // Recommend deleting temp files if > 50 MB
        if (appStorage.temp > 50 * 1024 * 1024) {
            recommendations.add(
                StorageRecommendation(
                    type = RecommendationType.DELETE_TEMP_FILES,
                    description = "Remove temporary files",
                    estimatedSpaceSaved = appStorage.temp,
                    action = "Clean temp files"
                )
            )
        }

        // Recommend removing old logs if > 20 MB
        if (appStorage.logs > 20 * 1024 * 1024) {
            recommendations.add(
                StorageRecommendation(
                    type = RecommendationType.REMOVE_OLD_LOGS,
                    description = "Delete old log files",
                    estimatedSpaceSaved = appStorage.logs,
                    action = "Remove logs"
                )
            )
        }

        // Recommend optimizing database if > 50 MB
        if (appStorage.database > 50 * 1024 * 1024) {
            recommendations.add(
                StorageRecommendation(
                    type = RecommendationType.OPTIMIZE_DATABASE,
                    description = "Optimize database to reduce size",
                    estimatedSpaceSaved = appStorage.database / 4, // Estimate 25% reduction
                    action = "Optimize database"
                )
            )
        }

        // Sort by estimated space saved
        return recommendations.sortedByDescending { it.estimatedSpaceSaved }
    }
}
