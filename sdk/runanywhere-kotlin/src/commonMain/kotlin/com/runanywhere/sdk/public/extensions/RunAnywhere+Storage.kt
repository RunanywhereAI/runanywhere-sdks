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

import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Storage.StorageAvailability
import com.runanywhere.sdk.public.extensions.Storage.StorageInfo

// MARK: - Storage Information

/**
 * Get complete storage information.
 *
 * @return Storage info with device, app, and model storage details
 */
expect suspend fun RunAnywhere.storageInfo(): StorageInfo

/**
 * Check if storage is available for a download.
 *
 * @param requiredBytes Required bytes for the operation
 * @return Storage availability result
 */
expect suspend fun RunAnywhere.checkStorageAvailability(requiredBytes: Long): StorageAvailability

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
): com.runanywhere.sdk.public.extensions.Storage.StorageAvailability

/**
 * Get on-disk metrics for a single model.
 *
 * Mirrors Swift's `RunAnywhere.getModelStorageMetrics(modelId, framework)`.
 */
expect suspend fun RunAnywhere.getModelStorageMetrics(
    modelId: String,
    framework: com.runanywhere.sdk.core.types.InferenceFramework? = null,
): com.runanywhere.sdk.public.extensions.Storage.ModelStorageMetrics?

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
