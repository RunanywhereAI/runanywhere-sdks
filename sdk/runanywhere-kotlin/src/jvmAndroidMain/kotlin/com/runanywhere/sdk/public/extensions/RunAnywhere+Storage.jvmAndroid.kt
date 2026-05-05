/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for storage operations.
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
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeStorageProto
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere

private fun requireStorageInitialized(sdk: RunAnywhere) {
    if (!sdk.isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
}

actual suspend fun RunAnywhere.storageInfo(): StorageInfo {
    requireStorageInitialized(this)
    return storageInfo(
        StorageInfoRequest(
            include_device = true,
            include_app = true,
            include_models = true,
        ),
    ).info ?: throw SDKException.storage("Storage info result did not include info")
}

actual suspend fun RunAnywhere.storageInfo(request: StorageInfoRequest): StorageInfoResult {
    requireStorageInitialized(this)
    return CppBridgeStorageProto.info(request)
        ?: throw SDKException.storage("Native storage info proto API unavailable")
}

actual suspend fun RunAnywhere.checkStorageAvailability(requiredBytes: Long): StorageAvailability {
    requireStorageInitialized(this)
    return checkStorageAvailability(
        StorageAvailabilityRequest(
            required_bytes = requiredBytes,
            safety_margin = 0.0,
        ),
    ).availability ?: throw SDKException.storage("Storage availability result did not include availability")
}

actual suspend fun RunAnywhere.checkStorageAvailability(
    request: StorageAvailabilityRequest,
): StorageAvailabilityResult {
    requireStorageInitialized(this)
    return CppBridgeStorageProto.availability(request)
        ?: throw SDKException.storage("Native storage availability proto API unavailable")
}

actual suspend fun RunAnywhere.storageDeletePlan(request: StorageDeletePlanRequest): StorageDeletePlan {
    requireStorageInitialized(this)
    return CppBridgeStorageProto.deletePlan(request)
        ?: throw SDKException.storage("Native storage delete plan proto API unavailable")
}

actual suspend fun RunAnywhere.deleteStorage(request: StorageDeleteRequest): StorageDeleteResult {
    requireStorageInitialized(this)
    return CppBridgeStorageProto.delete(request)
        ?: throw SDKException.storage("Native storage delete proto API unavailable")
}

actual suspend fun RunAnywhere.checkStorageAvailability(
    requiredBytes: Long,
    safetyMargin: Double,
): StorageAvailability {
    requireStorageInitialized(this)
    return checkStorageAvailability(
        StorageAvailabilityRequest(
            required_bytes = requiredBytes,
            safety_margin = safetyMargin,
        ),
    ).availability ?: throw SDKException.storage("Storage availability result did not include availability")
}
