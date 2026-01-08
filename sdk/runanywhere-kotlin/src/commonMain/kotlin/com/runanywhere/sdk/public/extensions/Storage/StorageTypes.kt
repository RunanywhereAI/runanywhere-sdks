/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Consolidated storage-related types for public API.
 * Includes: storage info, configuration, availability, and model storage metrics.
 *
 * Mirrors Swift StorageTypes.swift exactly.
 */

package com.runanywhere.sdk.public.extensions.Storage

import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.public.extensions.Models.ModelFormat
import com.runanywhere.sdk.public.extensions.Models.ModelInfo
import kotlinx.serialization.Serializable

// MARK: - Device Storage

/**
 * Device storage information.
 * Mirrors Swift DeviceStorageInfo exactly.
 */
@Serializable
data class DeviceStorageInfo(
    /** Total device storage space in bytes */
    val totalSpace: Long,
    /** Free space available in bytes */
    val freeSpace: Long,
    /** Used space in bytes */
    val usedSpace: Long,
) {
    /** Percentage of storage used (0-100) */
    val usagePercentage: Double
        get() = if (totalSpace > 0) usedSpace.toDouble() / totalSpace.toDouble() * 100 else 0.0
}

// MARK: - App Storage

/**
 * App storage breakdown by directory type.
 * Mirrors Swift AppStorageInfo exactly.
 */
@Serializable
data class AppStorageInfo(
    /** Documents directory size in bytes */
    val documentsSize: Long,
    /** Cache directory size in bytes */
    val cacheSize: Long,
    /** Application Support directory size in bytes */
    val appSupportSize: Long,
    /** Total app storage in bytes */
    val totalSize: Long,
)

// MARK: - Model Storage Metrics

/**
 * Storage metrics for a single model.
 * All model metadata (id, name, framework, artifactType, etc.) is in ModelInfo.
 * This struct adds the on-disk storage size.
 *
 * Mirrors Swift ModelStorageMetrics exactly.
 */
@Serializable
data class ModelStorageMetrics(
    /** The model info (contains id, framework, localPath, artifactType, etc.) */
    val model: ModelInfo,
    /** Actual size on disk in bytes (may differ from downloadSize after extraction) */
    val sizeOnDisk: Long,
)

// MARK: - Stored Model (Backward Compatible)

/**
 * Backward-compatible stored model view.
 * Provides a simple view of a stored model with computed properties.
 *
 * Mirrors Swift StoredModel exactly.
 */
@Serializable
data class StoredModel(
    /** Underlying model info */
    val modelInfo: ModelInfo,
    /** Size on disk in bytes */
    val size: Long,
) {
    /** Model ID */
    val id: String get() = modelInfo.id

    /** Model name */
    val name: String get() = modelInfo.name

    /** Model format */
    val format: ModelFormat get() = modelInfo.format

    /** Inference framework */
    val framework: InferenceFramework? get() = modelInfo.framework

    /** Model description */
    val description: String? get() = modelInfo.description

    /** Path to the model on disk */
    val path: String get() = modelInfo.localPath ?: "/unknown"

    /** Checksum (from download info if available) */
    val checksum: String? get() = null

    /** Created date (use current time as fallback) */
    val createdDate: Long get() = System.currentTimeMillis()

    companion object {
        /** Create from ModelStorageMetrics */
        fun from(metrics: ModelStorageMetrics) =
            StoredModel(
                modelInfo = metrics.model,
                size = metrics.sizeOnDisk,
            )
    }
}

// MARK: - Storage Info (Aggregate)

/**
 * Complete storage information including device, app, and model storage.
 * Mirrors Swift StorageInfo exactly.
 */
@Serializable
data class StorageInfo(
    /** App storage usage */
    val appStorage: AppStorageInfo,
    /** Device storage capacity */
    val deviceStorage: DeviceStorageInfo,
    /** Storage metrics for each downloaded model */
    val models: List<ModelStorageMetrics>,
) {
    /** Total size of all models */
    val totalModelsSize: Long
        get() = models.sumOf { it.sizeOnDisk }

    /** Number of stored models */
    val modelCount: Int
        get() = models.size

    /** Stored models array (backward compatible) */
    val storedModels: List<StoredModel>
        get() = models.map { StoredModel.from(it) }

    companion object {
        /** Empty storage info */
        val EMPTY =
            StorageInfo(
                appStorage =
                    AppStorageInfo(
                        documentsSize = 0,
                        cacheSize = 0,
                        appSupportSize = 0,
                        totalSize = 0,
                    ),
                deviceStorage =
                    DeviceStorageInfo(
                        totalSpace = 0,
                        freeSpace = 0,
                        usedSpace = 0,
                    ),
                models = emptyList(),
            )
    }
}

// MARK: - Storage Availability

/**
 * Storage availability check result.
 * Mirrors Swift StorageAvailability exactly.
 */
@Serializable
data class StorageAvailability(
    /** Whether storage is available for the requested operation */
    val isAvailable: Boolean,
    /** Required space in bytes */
    val requiredSpace: Long,
    /** Available space in bytes */
    val availableSpace: Long,
    /** Whether there's a warning (e.g., low space) */
    val hasWarning: Boolean,
    /** Recommendation message if any */
    val recommendation: String?,
)
