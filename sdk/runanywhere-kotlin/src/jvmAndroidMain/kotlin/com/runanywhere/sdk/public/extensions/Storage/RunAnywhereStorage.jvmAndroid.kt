/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for storage operations.
 *
 * Mirrors Swift `RunAnywhere+Storage.swift`. The legacy Kotlin-only names
 * (`storageInfo`, `storageDeletePlan`, plus the `requiredBytes` /
 * `requiredBytes + safetyMargin` overloads of `checkStorageAvailability`)
 * have been removed in favour of the canonical Swift surface.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.StorageAvailabilityRequest
import ai.runanywhere.proto.v1.StorageAvailabilityResult
import ai.runanywhere.proto.v1.StorageDeletePlan
import ai.runanywhere.proto.v1.StorageDeletePlanRequest
import ai.runanywhere.proto.v1.StorageDeleteRequest
import ai.runanywhere.proto.v1.StorageDeleteResult
import ai.runanywhere.proto.v1.StorageInfoRequest
import ai.runanywhere.proto.v1.StorageInfoResult
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeFileManager
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeStorage
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RAStorageInfo

private fun requireStorageInitialized(sdk: RunAnywhere) {
    if (!sdk.isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
}

actual suspend fun RunAnywhere.getStorageInfo(): RAStorageInfo {
    requireStorageInitialized(this)
    return getStorageInfo(
        StorageInfoRequest(
            include_device = true,
            include_app = true,
            include_models = true,
        ),
    ).info ?: throw SDKException.storage("Storage info result did not include info")
}

actual suspend fun RunAnywhere.getStorageInfo(request: StorageInfoRequest): StorageInfoResult {
    requireStorageInitialized(this)
    return CppBridgeStorage.info(request)
        ?: throw SDKException.storage("Native storage info proto API unavailable")
}

actual suspend fun RunAnywhere.checkStorageAvailability(
    request: StorageAvailabilityRequest,
): StorageAvailabilityResult {
    requireStorageInitialized(this)
    return CppBridgeStorage.availability(request)
        ?: throw SDKException.storage("Native storage availability proto API unavailable")
}

actual suspend fun RunAnywhere.planStorageDelete(request: StorageDeletePlanRequest): StorageDeletePlan {
    requireStorageInitialized(this)
    return CppBridgeStorage.deletePlan(request)
        ?: throw SDKException.storage("Native storage delete plan proto API unavailable")
}

actual suspend fun RunAnywhere.deleteStorage(request: StorageDeleteRequest): StorageDeleteResult {
    requireStorageInitialized(this)
    return CppBridgeStorage.delete(request)
        ?: throw SDKException.storage("Native storage delete proto API unavailable")
}

actual suspend fun RunAnywhere.clearCache() {
    requireStorageInitialized(this)
    if (!CppBridgeFileManager.clearCache()) {
        throw SDKException.storage("Failed to clear cache")
    }
}

actual suspend fun RunAnywhere.cleanTempFiles() {
    requireStorageInitialized(this)
    if (!CppBridgeFileManager.clearTemp()) {
        throw SDKException.storage("Failed to clean temp files")
    }
}
