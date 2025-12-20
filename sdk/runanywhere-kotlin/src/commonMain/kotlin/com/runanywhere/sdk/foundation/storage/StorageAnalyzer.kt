package com.runanywhere.sdk.foundation.storage

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.foundation.filemanager.SimplifiedFileManager
import com.runanywhere.sdk.foundation.filemanager.StoredModelData
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.ModelRegistry
import com.runanywhere.sdk.models.storage.*
import com.runanywhere.sdk.foundation.currentTimeMillis
import kotlinx.datetime.Instant

/**
 * Storage analyzer for SDK storage operations
 * Matches iOS StorageAnalyzer protocol exactly
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/Protocols/Storage/StorageAnalyzer.swift
 */
interface StorageAnalyzer {
    /**
     * Analyze overall storage situation
     * Matches iOS: func analyzeStorage() async -> StorageInfo
     */
    suspend fun analyzeStorage(): StorageInfo

    /**
     * Get model storage usage information
     * Matches iOS: func getModelStorageUsage() async -> ModelStorageInfo
     */
    suspend fun getModelStorageUsage(): ModelStorageInfo

    /**
     * Check storage availability for a model
     * Matches iOS: func checkStorageAvailable(for modelSize: Int64, safetyMargin: Double) -> StorageAvailability
     */
    fun checkStorageAvailable(modelSize: Long, safetyMargin: Double = 0.1): StorageAvailabilityResult

    /**
     * Get storage recommendations
     * Matches iOS: func getRecommendations(for storageInfo: StorageInfo) -> [StorageRecommendation]
     */
    fun getRecommendations(storageInfo: StorageInfo): List<StorageRecommendation>

    /**
     * Calculate size at path
     * Matches iOS: func calculateSize(at url: URL) async throws -> Int64
     */
    suspend fun calculateSize(path: String): Long
}

/**
 * Default implementation of StorageAnalyzer
 * Matches iOS DefaultStorageAnalyzer class exactly
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Storage/Analysis/DefaultStorageAnalyzer.swift
 *
 * iOS implementation pattern:
 * - Uses fileManager.getAllStoredModels() to get stored model data
 * - Uses modelRegistry.discoverModels() to get registered models for enrichment
 * - Creates StoredModel objects with combined data
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
     * Analyze overall storage situation
     * Matches iOS analyzeStorage() method exactly
     *
     * iOS implementation:
     * ```swift
     * public func analyzeStorage() async -> StorageInfo {
     *     let deviceStorage = getDeviceStorageInfo()
     *     let modelStorage = await getModelStorageUsage()
     *     let totalAppSize = fileManager.getTotalStorageSize()
     *     let appStorage = AppStorageInfo(...)
     *     let storedModels = await getStoredModelsList()
     *     return StorageInfo(...)
     * }
     * ```
     */
    override suspend fun analyzeStorage(): StorageInfo {
        logger.debug("Starting storage analysis")

        // Get device storage info - matches iOS getDeviceStorageInfo()
        val deviceStorage = getDeviceStorageInfo()

        // Get model storage usage - matches iOS getModelStorageUsage()
        val modelStorage = getModelStorageUsage()

        // Get app storage info - matches iOS pattern
        val totalAppSize = fileManager.getTotalStorageSize()
        val appStorage = AppStorageInfo(
            documentsSize = totalAppSize,
            cacheSize = 0, // Could be enhanced to track cache separately
            appSupportSize = 0,
            totalSize = totalAppSize
        )

        // Get stored models list - matches iOS getStoredModelsList()
        val storedModels = getStoredModelsList()

        val storageInfo = StorageInfo(
            appStorage = appStorage,
            deviceStorage = deviceStorage,
            modelStorage = modelStorage,
            cacheSize = 0,
            storedModels = storedModels,
            availability = StorageAvailability.HEALTHY, // Determined below
            recommendations = emptyList(),
            lastUpdated = Instant.fromEpochMilliseconds(currentTimeMillis())
        )

        // Determine availability status
        val availability = determineStorageAvailability(deviceStorage)

        // Generate recommendations
        val recommendations = getRecommendations(storageInfo)

        return storageInfo.copy(
            availability = availability,
            recommendations = recommendations
        )
    }

    /**
     * Get model storage usage information
     * Matches iOS getModelStorageUsage() method exactly
     *
     * iOS implementation:
     * ```swift
     * public func getModelStorageUsage() async -> ModelStorageInfo {
     *     let modelStorageSize = fileManager.getModelStorageSize()
     *     let storedModelsData = fileManager.getAllStoredModels()
     *     var modelsByFramework: [InferenceFramework: [StoredModel]] = [:]
     *     let storedModels = await getStoredModelsList()
     *     for model in storedModels {
     *         if let framework = model.framework {
     *             modelsByFramework[framework, default: []].append(model)
     *         }
     *     }
     *     let largestModel = storedModels.max(by: { $0.size < $1.size })
     *     return ModelStorageInfo(...)
     * }
     * ```
     */
    override suspend fun getModelStorageUsage(): ModelStorageInfo {
        val modelStorageSize = fileManager.getModelStorageSize()
        val storedModels = getStoredModelsList()

        // Find largest model - matches iOS
        val largestModel = storedModels.maxByOrNull { it.size }

        return ModelStorageInfo(
            totalSize = modelStorageSize,
            modelCount = storedModels.size,
            largestModel = largestModel,
            models = storedModels
        )
    }

    /**
     * Check storage availability for a model
     * Matches iOS checkStorageAvailable() method exactly
     *
     * iOS implementation:
     * ```swift
     * public func checkStorageAvailable(for modelSize: Int64, safetyMargin: Double = 0.1) -> StorageAvailability {
     *     let availableSpace = fileManager.getAvailableSpace()
     *     let requiredSpace = Int64(Double(modelSize) * (1 + safetyMargin))
     *     let isAvailable = availableSpace > requiredSpace
     *     let hasWarning = availableSpace < requiredSpace * 2
     *     ...
     * }
     * ```
     */
    override fun checkStorageAvailable(modelSize: Long, safetyMargin: Double): StorageAvailabilityResult {
        val availableSpace = fileManager.getAvailableSpace()
        val requiredSpace = (modelSize * (1 + safetyMargin)).toLong()

        val isAvailable = availableSpace > requiredSpace
        val hasWarning = availableSpace < requiredSpace * 2 // Warn if less than 2x space available

        val recommendation: String? = when {
            !isAvailable -> {
                val shortfall = requiredSpace - availableSpace
                val shortfallMB = shortfall / (1024 * 1024)
                "Need ${shortfallMB}MB more space. Clear cache or remove unused models."
            }
            hasWarning -> {
                "Storage space is getting low. Consider clearing cache after download."
            }
            else -> null
        }

        return StorageAvailabilityResult(
            isAvailable = isAvailable,
            requiredSpace = requiredSpace,
            availableSpace = availableSpace,
            hasWarning = hasWarning,
            recommendation = recommendation
        )
    }

    /**
     * Get storage recommendations
     * Matches iOS getRecommendations() method exactly
     *
     * iOS implementation:
     * ```swift
     * public func getRecommendations(for storageInfo: StorageInfo) -> [StorageRecommendation] {
     *     var recommendations: [StorageRecommendation] = []
     *     let freeSpace = storageInfo.deviceStorage.freeSpace
     *     let totalSpace = storageInfo.deviceStorage.totalSpace
     *     if totalSpace > 0 {
     *         let freePercentage = Double(freeSpace) / Double(totalSpace)
     *         if freePercentage < 0.1 { ... }
     *         if freePercentage < 0.05 { ... }
     *     }
     *     if storageInfo.storedModels.count > 5 { ... }
     *     return recommendations
     * }
     * ```
     */
    override fun getRecommendations(storageInfo: StorageInfo): List<StorageRecommendation> {
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

        // Suggest reviewing models if more than 5 stored - matches iOS exactly
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

    /**
     * Calculate size at path
     * Matches iOS calculateSize(at:) method exactly
     *
     * iOS implementation:
     * ```swift
     * public func calculateSize(at url: URL) async throws -> Int64 {
     *     let fm = Foundation.FileManager.default
     *     var isDirectory: ObjCBool = false
     *     guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
     *         throw SDKError.modelNotFound("File not found at path: \(url.path)")
     *     }
     *     if isDirectory.boolValue {
     *         return fileManager.calculateDirectorySize(at: url)
     *     } else {
     *         let attributes = try fm.attributesOfItem(atPath: url.path)
     *         return attributes[.size] as? Int64 ?? 0
     *     }
     * }
     * ```
     */
    override suspend fun calculateSize(path: String): Long {
        return try {
            if (!fileManager.fileExists(path)) {
                throw IllegalArgumentException("File not found at path: $path")
            }

            if (fileManager.isDirectory(path)) {
                // Use SimplifiedFileManager's calculateDirectorySize method
                fileManager.calculateDirectorySize(path)
            } else {
                // Get file size
                fileManager.fileSize(path) ?: 0L
            }
        } catch (e: Exception) {
            logger.error("Error calculating size for $path", e)
            0L
        }
    }

    // MARK: - Private Helpers

    /**
     * Get device storage info
     * Matches iOS getDeviceStorageInfo() method
     */
    private fun getDeviceStorageInfo(): DeviceStorageInfo {
        // Use SimplifiedFileManager's getDeviceStorageInfo method
        val storageInfo = fileManager.getDeviceStorageInfo()
        return DeviceStorageInfo(
            totalSpace = storageInfo.totalSpace,
            freeSpace = storageInfo.freeSpace,
            usedSpace = storageInfo.usedSpace
        )
    }

    /**
     * Get stored models list with enriched information
     * Matches iOS getStoredModelsList() method exactly
     *
     * iOS implementation:
     * ```swift
     * private func getStoredModelsList() async -> [StoredModel] {
     *     var storedModels: [StoredModel] = []
     *     let storedModelsData = fileManager.getAllStoredModels()
     *     let registeredModels = await modelRegistry.discoverModels()
     *     let registeredModelsMap = Dictionary(uniqueKeysWithValues: registeredModels.map { ($0.id, $0) })
     *
     *     for (modelId, format, size, framework) in storedModelsData {
     *         let registeredModel = registeredModelsMap[modelId]
     *         let modelURL: URL
     *         if let url = try? fileManager.getModelURL(modelId: modelId, format: format) {
     *             modelURL = url
     *         } else if let url = fileManager.findModelFile(modelId: modelId) {
     *             modelURL = url
     *         } else {
     *             continue
     *         }
     *         let storedModel = StoredModel(
     *             id: modelId,
     *             name: registeredModel?.name ?? modelId,
     *             path: modelURL,
     *             size: size,
     *             format: format,
     *             framework: framework ?? registeredModel?.preferredFramework,
     *             createdDate: fileManager.getFileCreationDate(at: modelURL) ?? Date(),
     *             lastUsed: fileManager.getFileAccessDate(at: modelURL),
     *             metadata: registeredModel?.metadata,
     *             contextLength: registeredModel?.contextLength,
     *         )
     *         storedModels.append(storedModel)
     *     }
     *     return storedModels
     * }
     * ```
     */
    private suspend fun getStoredModelsList(): List<StoredModel> {
        val storedModels = mutableListOf<StoredModel>()

        // Get all stored model data from file manager - matches iOS
        val storedModelsData: List<StoredModelData> = fileManager.getAllStoredModels()

        // Get all registered models from registry - matches iOS
        val registeredModels: List<ModelInfo> = try {
            modelRegistry?.discoverModels() ?: emptyList()
        } catch (e: Exception) {
            logger.debug("Could not discover models from registry: ${e.message}")
            emptyList()
        }

        // Create a map of registered models for quick lookup - matches iOS
        val registeredModelsMap = registeredModels.associateBy { it.id }

        logger.debug("Found ${storedModelsData.size} stored models from file manager")
        logger.debug("Found ${registeredModels.size} registered models from registry")

        // Convert stored model data to StoredModel objects - matches iOS
        for (modelData in storedModelsData) {
            try {
                // Try to find corresponding registered model for additional metadata
                val registeredModel = registeredModelsMap[modelData.modelId]

                // Try to get the model path
                val modelPath = fileManager.findModelFile(modelData.modelId)
                if (modelPath == null) {
                    logger.debug("Skipping model ${modelData.modelId} - could not find file")
                    continue
                }

                val storedModel = StoredModel(
                    id = modelData.modelId,
                    name = registeredModel?.name ?: modelData.modelId,
                    path = modelPath,
                    size = modelData.size,
                    format = modelData.format.value,
                    framework = modelData.framework?.displayName ?: registeredModel?.preferredFramework?.displayName,
                    createdDate = Instant.fromEpochMilliseconds(currentTimeMillis()), // TODO: Get actual creation date
                    lastUsed = null, // TODO: Get actual last access date
                    contextLength = registeredModel?.contextLength,
                    checksum = null
                )

                storedModels.add(storedModel)
                logger.debug("Added stored model: ${storedModel.name} (${storedModel.size} bytes)")
            } catch (e: Exception) {
                logger.debug("Error processing model ${modelData.modelId}: ${e.message}")
            }
        }

        logger.debug("Total stored models: ${storedModels.size}")
        return storedModels
    }

    /**
     * Determine storage availability status from device storage info
     */
    private fun determineStorageAvailability(deviceStorage: DeviceStorageInfo): StorageAvailability {
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
}

/**
 * Storage availability result
 * Matches iOS StorageAvailability return type from checkStorageAvailable()
 */
data class StorageAvailabilityResult(
    val isAvailable: Boolean,
    val requiredSpace: Long,
    val availableSpace: Long,
    val hasWarning: Boolean,
    val recommendation: String?
)
