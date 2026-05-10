/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for storage operations.
 *
 * Mirrors Swift `RunAnywhere+Storage.swift` exactly:
 *   - `getStorageInfo()` (replaces the legacy `storageInfo()` accessor)
 *   - `checkStorageAvailability(request)` returning the proto result
 *   - `planStorageDelete(request)` returning the C++-owned plan
 *   - `deleteStorage(request)` executing or dry-running deletion
 *   - `clearCache()` / `cleanTempFiles()` forwarding to the FileManager bridge
 */

package com.runanywhere.sdk.public.extensions

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
 * Mirrors Swift `RunAnywhere.getStorageInfo()`. Equivalent to calling
 * [getStorageInfo] with the default request that includes device, app and
 * model storage details.
 */
expect suspend fun RunAnywhere.getStorageInfo(): StorageInfo

/**
 * Get storage information through the canonical generated proto API.
 *
 * Mirrors Swift `RunAnywhere.getStorageInfo(_:)`.
 */
expect suspend fun RunAnywhere.getStorageInfo(request: StorageInfoRequest): StorageInfoResult

// MARK: - Storage Availability

/**
 * Check storage availability through the canonical generated proto API.
 *
 * Mirrors Swift `RunAnywhere.checkStorageAvailability(_:)`.
 */
expect suspend fun RunAnywhere.checkStorageAvailability(
    request: StorageAvailabilityRequest,
): StorageAvailabilityResult

// MARK: - Storage Deletion

/**
 * Build a C++-owned safe delete plan.
 *
 * Mirrors Swift `RunAnywhere.planStorageDelete(_:)`.
 */
expect suspend fun RunAnywhere.planStorageDelete(request: StorageDeletePlanRequest): StorageDeletePlan

/**
 * Execute or dry-run a C++-planned storage delete.
 *
 * Mirrors Swift `RunAnywhere.deleteStorage(_:)`.
 */
expect suspend fun RunAnywhere.deleteStorage(request: StorageDeleteRequest): StorageDeleteResult

// MARK: - Cache and Temp

/**
 * Clear the SDK's Cache directory.
 *
 * Mirrors Swift `RunAnywhere.clearCache()`. Forwards to the FileManager
 * bridge `nativeFileManagerClearCache()` thunk.
 */
expect suspend fun RunAnywhere.clearCache()

/**
 * Clear the SDK's Temp directory.
 *
 * Mirrors Swift `RunAnywhere.cleanTempFiles()`. Forwards to the FileManager
 * bridge `nativeFileManagerClearTemp()` thunk.
 */
expect suspend fun RunAnywhere.cleanTempFiles()
