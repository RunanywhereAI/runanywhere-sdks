package com.runanywhere.sdk.models.storage

import kotlinx.datetime.Instant
import kotlinx.serialization.Contextual
import kotlinx.serialization.Serializable

/**
 * Storage information for the SDK
 * Matches iOS StorageInfo struct from RunAnywhere+Storage.swift
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Storage/StorageInfo.swift
 */
@OptIn(kotlin.time.ExperimentalTime::class)
@Serializable
data class StorageInfo(
    val appStorage: AppStorageInfo,
    val deviceStorage: DeviceStorageInfo,
    val modelStorage: ModelStorageInfo,
    val availability: StorageAvailability,
    val recommendations: List<StorageRecommendation>,
    @Contextual val lastUpdated: Instant
)

/**
 * App-specific storage information
 * Matches iOS AppStorageInfo struct
 */
@Serializable
data class AppStorageInfo(
    val totalUsed: Long,        // bytes
    val models: Long,           // bytes used by models
    val cache: Long,            // bytes used by cache
    val temp: Long,             // bytes used by temp files
    val database: Long,         // bytes used by database
    val logs: Long,             // bytes used by logs
    val other: Long             // bytes used by other files
)

/**
 * Device storage information
 * Matches iOS DeviceStorageInfo struct
 */
@Serializable
data class DeviceStorageInfo(
    val totalCapacity: Long,    // bytes
    val available: Long,        // bytes available
    val used: Long,             // bytes used
    val percentageUsed: Double  // 0.0 to 100.0
)

/**
 * Model-specific storage information
 * Matches iOS ModelStorageInfo struct
 */
@Serializable
data class ModelStorageInfo(
    val totalCount: Int,
    val downloadedCount: Int,
    val totalSize: Long,        // bytes
    val largestModel: StoredModel?,
    val models: List<StoredModel>
)

/**
 * Individual stored model information
 * Matches iOS StoredModel struct
 */
@OptIn(kotlin.time.ExperimentalTime::class)
@Serializable
data class StoredModel(
    val id: String,
    val name: String,
    val size: Long,             // bytes
    val path: String,
    val format: String,
    @Contextual val lastAccessed: Instant?,
    @Contextual val downloadDate: Instant
)

/**
 * Storage availability status
 * Matches iOS StorageAvailability enum
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
    val description: String,
    val estimatedSpaceSaved: Long,  // bytes
    val action: String                  // e.g., "Clear cache", "Delete unused models"
)

/**
 * Type of storage recommendation
 * Matches iOS RecommendationType enum
 */
@Serializable
enum class RecommendationType {
    CLEAR_CACHE,
    DELETE_TEMP_FILES,
    REMOVE_OLD_LOGS,
    DELETE_UNUSED_MODELS,
    OPTIMIZE_DATABASE
}
