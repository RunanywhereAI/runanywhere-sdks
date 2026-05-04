/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for storage operations.
 * Provides storage information and management.
 *
 * Mirrors Swift RunAnywhere+Storage.swift pattern.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.StorageAvailability
import ai.runanywhere.proto.v1.StorageAvailabilityRequest
import ai.runanywhere.proto.v1.StorageAvailabilityResult
import ai.runanywhere.proto.v1.StorageDeletePlan
import ai.runanywhere.proto.v1.StorageDeletePlanRequest
import ai.runanywhere.proto.v1.StorageDeleteRequest
import ai.runanywhere.proto.v1.StorageDeleteResult
import ai.runanywhere.proto.v1.StorageInfo
import ai.runanywhere.proto.v1.StorageInfoRequest
import ai.runanywhere.proto.v1.StorageInfoResult
import com.runanywhere.sdk.public.RunAnywhere

// MARK: - Storage Information

/**
 * Get complete storage information.
 *
 * @return Storage info with device, app, and model storage details
 */
expect suspend fun RunAnywhere.storageInfo(): StorageInfo

/**
 * Get storage information through the stable generated proto API.
 */
expect suspend fun RunAnywhere.storageInfo(request: StorageInfoRequest): StorageInfoResult

/**
 * Check if storage is available for a download.
 *
 * @param requiredBytes Required bytes for the operation
 * @return Storage availability result
 */
expect suspend fun RunAnywhere.checkStorageAvailability(requiredBytes: Long): StorageAvailability

/**
 * Check storage availability through the stable generated proto API.
 */
expect suspend fun RunAnywhere.checkStorageAvailability(
    request: StorageAvailabilityRequest,
): StorageAvailabilityResult

/**
 * Build a C++-owned safe delete plan.
 */
expect suspend fun RunAnywhere.storageDeletePlan(request: StorageDeletePlanRequest): StorageDeletePlan

/**
 * Execute or dry-run a C++-planned storage delete.
 */
expect suspend fun RunAnywhere.deleteStorage(request: StorageDeleteRequest): StorageDeleteResult

// MARK: - Cache Management

/**
 * Get cache size in bytes.
 *
 * @return Cache size
 */
expect suspend fun RunAnywhere.cacheSize(): Long

/**
 * Clear the SDK cache.
 */
expect suspend fun RunAnywhere.clearCache()

// MARK: - Storage Limits

/**
 * Set maximum storage limit for models.
 *
 * @param maxBytes Maximum bytes to use for model storage
 */
expect suspend fun RunAnywhere.setMaxModelStorage(maxBytes: Long)

/**
 * Get current storage used by models.
 *
 * @return Total bytes used by downloaded models
 */
expect suspend fun RunAnywhere.modelStorageUsed(): Long

// ─────────────────────────────────────────────────────────────────────────────
// Phase 4a — Storage parity with Swift's RunAnywhere+Storage.swift
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Check if storage is available for a download with a safety margin.
 *
 * Mirrors Swift's
 * `RunAnywhere.checkStorageAvailable(for: Int64, safetyMargin: Double = 0.1)`.
 * The default `safetyMargin` of 0.1 matches Swift.
 */
expect suspend fun RunAnywhere.checkStorageAvailability(
    requiredBytes: Long,
    safetyMargin: Double,
): ai.runanywhere.proto.v1.StorageAvailability

/**
 * Get on-disk metrics for a single model.
 *
 * Mirrors Swift's `RunAnywhere.getModelStorageMetrics(modelId, framework)`.
 */
expect suspend fun RunAnywhere.getModelStorageMetrics(
    modelId: String,
    framework: com.runanywhere.sdk.core.types.InferenceFramework? = null,
): ai.runanywhere.proto.v1.ModelStorageMetrics?

/**
 * Clean temporary cache files (downloads-in-progress, archive scratch dirs).
 *
 * Mirrors Swift's `RunAnywhere.cleanTempFiles()`.
 */
expect suspend fun RunAnywhere.cleanTempFiles()

/**
 * Get the SDK's base directory path on disk.
 *
 * Mirrors Swift's `RunAnywhere.getBaseDirectoryURL()` (renamed to match
 * Kotlin's "no URL type at this layer" convention — returns a `String`).
 */
expect fun RunAnywhere.getBaseDirectoryPath(): String
