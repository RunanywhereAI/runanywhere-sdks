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
import ai.runanywhere.proto.v1.ModelStorageMetrics
import ai.runanywhere.proto.v1.StorageAvailability
import ai.runanywhere.proto.v1.StorageInfo
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeFileManager
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelPaths
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelRegistry
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeStorage
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

    val json = CppBridgeFileManager.checkStorageJson(requiredBytes)
    if (json != null) {
        return parseStorageAvailabilityJson(json, requiredBytes)
    }

    val baseDir = File(CppBridgeModelPaths.getBaseDirectory())
    val availableSpace = baseDir.freeSpace
    return StorageAvailability(
        is_available = availableSpace >= requiredBytes,
        required_bytes = requiredBytes,
        available_bytes = availableSpace,
    )
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
    val padded = (requiredBytes.toDouble() * (1.0 + safetyMargin)).toLong()
    return checkStorageAvailability(padded)
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
 * Parse storage availability JSON from C++ rac_file_manager_check_storage.
 */
private fun parseStorageAvailabilityJson(json: String, requiredBytes: Long): StorageAvailability {
    val isAvailable = json.contains("\"isAvailable\":true")
    val hasWarning = json.contains("\"hasWarning\":true")

    val availableSpace =
        Regex("\"availableSpace\":(\\d+)")
            .find(json)
            ?.groupValues
            ?.get(1)
            ?.toLongOrNull() ?: 0L

    val recommendation =
        Regex("\"recommendation\":\"([^\"]*)\"")
            .find(json)
            ?.groupValues
            ?.get(1)
            ?.takeIf { it.isNotEmpty() }

    return StorageAvailability(
        is_available = isAvailable,
        required_bytes = requiredBytes,
        available_bytes = availableSpace,
        warning_message = if (hasWarning) "Low storage" else null,
        recommendation = recommendation,
    )
}

/**
 * Convert a CppBridgeModelRegistry.ModelInfo to proto ModelStorageMetrics.
 */
private fun convertToModelStorageMetrics(
    registryModel: CppBridgeModelRegistry.ModelInfo,
): ModelStorageMetrics? {
    val localPath = registryModel.localPath ?: return null
    val sizeOnDisk = calculateDirectorySize(File(localPath))
    return ModelStorageMetrics(
        model_id = registryModel.modelId,
        size_on_disk_bytes = sizeOnDisk,
    )
}
