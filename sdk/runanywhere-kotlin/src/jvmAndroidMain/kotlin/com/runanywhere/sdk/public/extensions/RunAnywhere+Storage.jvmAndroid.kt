/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for storage operations.
 * Wave 2 KOTLIN: now uses proto-canonical StorageInfo / StorageAvailability /
 * ModelStorageMetrics / DeviceStorageInfo / AppStorageInfo.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.AppStorageInfo
import ai.runanywhere.proto.v1.DeviceStorageInfo
import ai.runanywhere.proto.v1.ModelInfo as ProtoModelInfo
import ai.runanywhere.proto.v1.ModelStorageMetrics
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
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeFileManager
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelPaths
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelRegistry
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeStorage
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeStorageProto
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import java.io.File

private val storageLogger = SDKLogger.shared

@Volatile
private var maxModelStorageBytes: Long = 10L * 1024 * 1024 * 1024

actual suspend fun RunAnywhere.storageInfo(): StorageInfo {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    return storageInfo(
        StorageInfoRequest(
            include_device = true,
            include_app = true,
            include_models = true,
        ),
    ).info ?: throw SDKException.storage("Storage info result did not include info")
}

actual suspend fun RunAnywhere.storageInfo(request: StorageInfoRequest): StorageInfoResult {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    return CppBridgeStorageProto.info(request)
        ?: throw SDKException.storage("Native storage info proto API unavailable")
}

@Suppress("unused")
private suspend fun RunAnywhere.storageInfoLegacy(): StorageInfo {
    val baseDir = File(CppBridgeModelPaths.getBaseDirectory())
    val cacheDir = File(baseDir, "cache")
    // Canonical model schema: {base}/RunAnywhere/Models/
    val modelsDir = File(File(baseDir, "RunAnywhere"), "Models")
    val appSupportDir = File(baseDir, "data")

    val cacheSize = CppBridgeFileManager.calculateDirectorySize(cacheDir.absolutePath)
    val modelsSize = CppBridgeFileManager.calculateDirectorySize(modelsDir.absolutePath)
    val appSupportSize = CppBridgeFileManager.calculateDirectorySize(appSupportDir.absolutePath)

    val appStorage =
        AppStorageInfo(
            documents_bytes = modelsSize,
            cache_bytes = cacheSize,
            app_support_bytes = appSupportSize,
            total_bytes = cacheSize + modelsSize + appSupportSize,
        )

    val totalSpace = baseDir.totalSpace
    val freeSpace = baseDir.freeSpace
    val usedSpace = totalSpace - freeSpace
    val usedPercent = if (totalSpace > 0) (usedSpace.toFloat() / totalSpace.toFloat()) * 100f else 0f

    val deviceStorage =
        DeviceStorageInfo(
            total_bytes = totalSpace,
            free_bytes = freeSpace,
            used_bytes = usedSpace,
            used_percent = usedPercent,
        )

    val downloadedModels = CppBridgeModelRegistry.getDownloaded()
    val modelMetrics =
        downloadedModels.mapNotNull { registryModel ->
            convertToModelStorageMetrics(registryModel)
        }

    return StorageInfo(
        app = appStorage,
        device = deviceStorage,
        total_models = modelMetrics.size,
        total_models_bytes = modelMetrics.sumOf { it.size_on_disk_bytes },
        models = modelMetrics,
    )
}

actual suspend fun RunAnywhere.checkStorageAvailability(requiredBytes: Long): StorageAvailability {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

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
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    return CppBridgeStorageProto.availability(request)
        ?: throw SDKException.storage("Native storage availability proto API unavailable")
}

actual suspend fun RunAnywhere.storageDeletePlan(request: StorageDeletePlanRequest): StorageDeletePlan {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    return CppBridgeStorageProto.deletePlan(request)
        ?: throw SDKException.storage("Native storage delete plan proto API unavailable")
}

actual suspend fun RunAnywhere.deleteStorage(request: StorageDeleteRequest): StorageDeleteResult {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    return CppBridgeStorageProto.delete(request)
        ?: throw SDKException.storage("Native storage delete proto API unavailable")
}

actual suspend fun RunAnywhere.cacheSize(): Long {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    return CppBridgeFileManager.cacheSize()
}

actual suspend fun RunAnywhere.clearCache() {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    storageLogger.info("Clearing cache...")
    CppBridgeStorage.clear(CppBridgeStorage.StorageNamespace.INFERENCE_CACHE, CppBridgeStorage.StorageType.CACHE)
    CppBridgeFileManager.clearCache()
    storageLogger.info("Cache cleared")
}

actual suspend fun RunAnywhere.setMaxModelStorage(maxBytes: Long) {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    maxModelStorageBytes = maxBytes
    CppBridgeStorage.setQuota(CppBridgeStorage.StorageNamespace.MODELS, maxBytes)
}

actual suspend fun RunAnywhere.modelStorageUsed(): Long {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    return CppBridgeFileManager.modelsStorageUsed()
}

actual suspend fun RunAnywhere.checkStorageAvailability(
    requiredBytes: Long,
    safetyMargin: Double,
): StorageAvailability {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    return checkStorageAvailability(
        StorageAvailabilityRequest(
            required_bytes = requiredBytes,
            safety_margin = safetyMargin,
        ),
    ).availability ?: throw SDKException.storage("Storage availability result did not include availability")
}

actual suspend fun RunAnywhere.getModelStorageMetrics(
    modelId: String,
    framework: com.runanywhere.sdk.core.types.InferenceFramework?,
): ModelStorageMetrics? {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    val info = storageInfo()
    return info.models.firstOrNull { it.model_id == modelId }
}

actual suspend fun RunAnywhere.cleanTempFiles() {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    CppBridgeFileManager.clearCache()
}

actual fun RunAnywhere.getBaseDirectoryPath(): String =
    CppBridgeModelPaths.getBaseDirectory()

private fun calculateDirectorySize(directory: File): Long {
    if (!directory.exists()) return 0L
    return CppBridgeFileManager.calculateDirectorySize(directory.absolutePath)
}

/**
 * Convert a registry ModelInfo proto to proto ModelStorageMetrics.
 */
private fun convertToModelStorageMetrics(
    registryModel: ProtoModelInfo,
): ModelStorageMetrics? {
    val localPath = registryModel.local_path.takeIf { it.isNotEmpty() } ?: return null
    val sizeOnDisk = calculateDirectorySize(File(localPath))
    return ModelStorageMetrics(
        model_id = registryModel.id,
        size_on_disk_bytes = sizeOnDisk,
    )
}
