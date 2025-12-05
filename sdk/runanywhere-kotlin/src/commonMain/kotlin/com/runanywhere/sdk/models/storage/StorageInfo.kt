package com.runanywhere.sdk.models.storage

import kotlinx.datetime.Instant
import kotlinx.serialization.Contextual
import kotlinx.serialization.Serializable

/**
 * Storage information for the SDK
 * Matches iOS StorageInfo struct from RunAnywhere+Storage.swift
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Models/Storage/StorageInfo.swift
 */
@OptIn(kotlin.time.ExperimentalTime::class)
@Serializable
data class StorageInfo(
    val appStorage: AppStorageInfo,
    val deviceStorage: DeviceStorageInfo,
    val modelStorage: ModelStorageInfo,
    val cacheSize: Long,                    // bytes - matches iOS
    val storedModels: List<StoredModel>,    // Matches iOS - direct access to stored models
    val availability: StorageAvailability,
    val recommendations: List<StorageRecommendation>,
    @Contextual val lastUpdated: Instant
) {
    companion object {
        /**
         * Empty storage info for initialization
         * Matches iOS StorageInfo.empty
         */
        val empty = StorageInfo(
            appStorage = AppStorageInfo(
                documentsSize = 0,
                cacheSize = 0,
                appSupportSize = 0,
                totalSize = 0
            ),
            deviceStorage = DeviceStorageInfo(
                totalSpace = 0,
                freeSpace = 0,
                usedSpace = 0
            ),
            modelStorage = ModelStorageInfo(
                totalSize = 0,
                modelCount = 0,
                largestModel = null,
                models = emptyList()
            ),
            cacheSize = 0,
            storedModels = emptyList(),
            availability = StorageAvailability.HEALTHY,
            recommendations = emptyList(),
            lastUpdated = Instant.fromEpochMilliseconds(0)
        )
    }
}

/**
 * App-specific storage information
 * Matches iOS AppStorageInfo struct exactly
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Models/Storage/AppStorageInfo.swift
 */
@Serializable
data class AppStorageInfo(
    val documentsSize: Long,    // bytes - app documents size
    val cacheSize: Long,        // bytes - cache size
    val appSupportSize: Long,   // bytes - app support size
    val totalSize: Long         // bytes - total app storage size
)

/**
 * Device storage information
 * Matches iOS DeviceStorageInfo struct exactly
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Models/Storage/DeviceStorageInfo.swift
 */
@Serializable
data class DeviceStorageInfo(
    val totalSpace: Long,       // bytes - total device storage
    val freeSpace: Long,        // bytes - available space
    val usedSpace: Long         // bytes - used space
) {
    /**
     * Usage percentage (0-100)
     * Matches iOS usagePercentage computed property
     */
    val usagePercentage: Double
        get() = if (totalSpace > 0) {
            (usedSpace.toDouble() / totalSpace.toDouble()) * 100.0
        } else {
            0.0
        }
}

/**
 * Model-specific storage information
 * Matches iOS ModelStorageInfo struct
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Models/Storage/ModelStorageInfo.swift
 */
@Serializable
data class ModelStorageInfo(
    val totalSize: Long,              // bytes - total size of all models
    val modelCount: Int,              // number of stored models
    val largestModel: StoredModel?,   // largest model by size
    val models: List<StoredModel>     // all stored models
)

/**
 * Individual stored model information
 * Matches iOS StoredModel struct exactly
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Models/Storage/StoredModel.swift
 */
@OptIn(kotlin.time.ExperimentalTime::class)
@Serializable
data class StoredModel(
    val id: String,                     // Model ID used for operations like deletion
    val name: String,                   // Display name
    val path: String,                   // File path (iOS uses URL)
    val size: Long,                     // bytes
    val format: String,                 // Model format (e.g., "gguf", "onnx")
    val framework: String?,             // Framework name (e.g., "LlamaCpp", "ONNX")
    @Contextual val createdDate: Instant,           // When the model was downloaded
    @Contextual val lastUsed: Instant?,             // Last time model was used
    val contextLength: Int?,            // Context window size if applicable
    val checksum: String? = null        // Model checksum for verification
)

/**
 * Storage availability status
 * Matches iOS StorageAvailability logic
 */
@Serializable
enum class StorageAvailability {
    HEALTHY,        // > 20% available
    LOW,            // 10-20% available
    CRITICAL,       // 5-10% available
    FULL            // < 5% available
}

/**
 * Storage recommendation
 * Matches iOS StorageRecommendation struct
 */
@Serializable
data class StorageRecommendation(
    val type: RecommendationType,
    val message: String,            // matches iOS 'message' field
    val action: String              // e.g., "Clear Cache", "Delete Models"
)

/**
 * Type of storage recommendation
 * Matches iOS RecommendationType enum
 */
@Serializable
enum class RecommendationType {
    WARNING,        // Low storage warning
    CRITICAL,       // Critical storage shortage
    SUGGESTION      // Optimization suggestion
}
