/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for storage operations.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeFileManager
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelPaths
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelRegistry
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeStorage
import com.runanywhere.sdk.foundation.errors.SDKError
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.ModelArtifactType
import com.runanywhere.sdk.public.extensions.Models.ModelCategory
import com.runanywhere.sdk.public.extensions.Models.ModelFormat
import com.runanywhere.sdk.public.extensions.Models.ModelInfo
import com.runanywhere.sdk.public.extensions.Storage.AppStorageInfo
import com.runanywhere.sdk.public.extensions.Storage.DeviceStorageInfo
import com.runanywhere.sdk.public.extensions.Storage.ModelStorageMetrics
import com.runanywhere.sdk.public.extensions.Storage.StorageAvailability
import com.runanywhere.sdk.public.extensions.Storage.StorageInfo
import java.io.File

private val storageLogger = SDKLogger.shared

// Model storage quota in bytes (default 10GB)
@Volatile
private var maxModelStorageBytes: Long = 10L * 1024 * 1024 * 1024

actual suspend fun RunAnywhere.storageInfo(): StorageInfo {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    val baseDir = File(CppBridgeModelPaths.getBaseDirectory())
    val cacheDir = File(baseDir, "cache")
    val modelsDir = File(baseDir, "models")
    val appSupportDir = File(baseDir, "data")

    // Calculate directory sizes via C++ (recursive traversal in C++, Kotlin provides I/O callbacks)
    val cacheSize = CppBridgeFileManager.calculateDirectorySize(cacheDir.absolutePath)
    val modelsSize = CppBridgeFileManager.calculateDirectorySize(modelsDir.absolutePath)
    val appSupportSize = CppBridgeFileManager.calculateDirectorySize(appSupportDir.absolutePath)

    val appStorage =
        AppStorageInfo(
            documentsSize = modelsSize,
            cacheSize = cacheSize,
            appSupportSize = appSupportSize,
            totalSize = cacheSize + modelsSize + appSupportSize,
        )

    // Get device storage info
    val totalSpace = baseDir.totalSpace
    val freeSpace = baseDir.freeSpace
    val usedSpace = totalSpace - freeSpace

    val deviceStorage =
        DeviceStorageInfo(
            totalSpace = totalSpace,
            freeSpace = freeSpace,
            usedSpace = usedSpace,
        )

    // Get downloaded models from C++ registry and convert to storage metrics
    val downloadedModels = CppBridgeModelRegistry.getDownloaded()
    val modelMetrics =
        downloadedModels.mapNotNull { registryModel ->
            convertToModelStorageMetrics(registryModel)
        }

    return StorageInfo(
        appStorage = appStorage,
        deviceStorage = deviceStorage,
        models = modelMetrics,
    )
}

actual suspend fun RunAnywhere.checkStorageAvailability(requiredBytes: Long): StorageAvailability {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    // Delegate to C++ for storage check (1GB warning threshold logic is in C++)
    val json = CppBridgeFileManager.checkStorageJson(requiredBytes)
    if (json != null) {
        return parseStorageAvailabilityJson(json, requiredBytes)
    }

    // Fallback if C++ call fails
    val baseDir = File(CppBridgeModelPaths.getBaseDirectory())
    val availableSpace = baseDir.freeSpace
    return StorageAvailability(
        isAvailable = availableSpace >= requiredBytes,
        requiredSpace = requiredBytes,
        availableSpace = availableSpace,
        hasWarning = false,
        recommendation = null,
    )
}

actual suspend fun RunAnywhere.cacheSize(): Long {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    return CppBridgeFileManager.cacheSize()
}

actual suspend fun RunAnywhere.clearCache() {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    storageLogger.info("Clearing cache...")

    // Clear the storage cache namespace
    CppBridgeStorage.clear(CppBridgeStorage.StorageNamespace.INFERENCE_CACHE, CppBridgeStorage.StorageType.CACHE)

    // Clear the file cache directory via C++
    CppBridgeFileManager.clearCache()

    storageLogger.info("Cache cleared")
}

actual suspend fun RunAnywhere.setMaxModelStorage(maxBytes: Long) {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    maxModelStorageBytes = maxBytes
    CppBridgeStorage.setQuota(CppBridgeStorage.StorageNamespace.MODELS, maxBytes)
}

actual suspend fun RunAnywhere.modelStorageUsed(): Long {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    return CppBridgeFileManager.modelsStorageUsed()
}

// Delegate to C++ for recursive directory size calculation
private fun calculateDirectorySize(directory: File): Long {
    if (!directory.exists()) return 0L
    return CppBridgeFileManager.calculateDirectorySize(directory.absolutePath)
}

/**
 * Parse storage availability JSON from C++ rac_file_manager_check_storage.
 */
private fun parseStorageAvailabilityJson(json: String, requiredBytes: Long): StorageAvailability {
    // Simple JSON parsing without external library
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
        isAvailable = isAvailable,
        requiredSpace = requiredBytes,
        availableSpace = availableSpace,
        hasWarning = hasWarning,
        recommendation = recommendation,
    )
}

/**
 * Convert a CppBridgeModelRegistry.ModelInfo to ModelStorageMetrics.
 * Calculates actual size on disk from the model's local path.
 */
private fun convertToModelStorageMetrics(
    registryModel: CppBridgeModelRegistry.ModelInfo,
): ModelStorageMetrics? {
    val localPath = registryModel.localPath ?: return null

    // Calculate size on disk
    val modelFile = File(localPath)
    val sizeOnDisk = calculateDirectorySize(modelFile)

    // Convert framework int to InferenceFramework enum
    val framework =
        when (registryModel.framework) {
            CppBridgeModelRegistry.Framework.ONNX -> InferenceFramework.ONNX
            CppBridgeModelRegistry.Framework.LLAMACPP -> InferenceFramework.LLAMA_CPP
            CppBridgeModelRegistry.Framework.FOUNDATION_MODELS -> InferenceFramework.FOUNDATION_MODELS
            CppBridgeModelRegistry.Framework.SYSTEM_TTS -> InferenceFramework.SYSTEM_TTS
            CppBridgeModelRegistry.Framework.FLUID_AUDIO -> InferenceFramework.FLUID_AUDIO
            CppBridgeModelRegistry.Framework.BUILTIN -> InferenceFramework.BUILT_IN
            CppBridgeModelRegistry.Framework.NONE -> InferenceFramework.NONE
            CppBridgeModelRegistry.Framework.GENIE -> InferenceFramework.GENIE
            else -> InferenceFramework.UNKNOWN
        }

    // Convert category int to ModelCategory enum
    val category =
        when (registryModel.category) {
            CppBridgeModelRegistry.ModelCategory.LANGUAGE -> ModelCategory.LANGUAGE
            CppBridgeModelRegistry.ModelCategory.SPEECH_RECOGNITION -> ModelCategory.SPEECH_RECOGNITION
            CppBridgeModelRegistry.ModelCategory.SPEECH_SYNTHESIS -> ModelCategory.SPEECH_SYNTHESIS
            CppBridgeModelRegistry.ModelCategory.AUDIO -> ModelCategory.AUDIO
            CppBridgeModelRegistry.ModelCategory.VISION -> ModelCategory.VISION
            CppBridgeModelRegistry.ModelCategory.MULTIMODAL -> ModelCategory.MULTIMODAL
            // 5 = IMAGE_GENERATION (diffusion) not supported on Kotlin/Android; treat as LANGUAGE
            5 -> ModelCategory.LANGUAGE
            else -> ModelCategory.LANGUAGE
        }

    // Convert format int to ModelFormat enum
    val format =
        when (registryModel.format) {
            CppBridgeModelRegistry.ModelFormat.GGUF -> ModelFormat.GGUF
            CppBridgeModelRegistry.ModelFormat.ONNX -> ModelFormat.ONNX
            CppBridgeModelRegistry.ModelFormat.ORT -> ModelFormat.ORT
            CppBridgeModelRegistry.ModelFormat.BIN -> ModelFormat.BIN
            CppBridgeModelRegistry.ModelFormat.QNN_CONTEXT -> ModelFormat.QNN_CONTEXT
            else -> ModelFormat.UNKNOWN
        }

    // Create public ModelInfo from registry model
    val modelInfo =
        ModelInfo(
            id = registryModel.modelId,
            name = registryModel.name,
            category = category,
            format = format,
            downloadURL = registryModel.downloadUrl,
            localPath = localPath,
            artifactType = ModelArtifactType.SingleFile(),
            downloadSize = registryModel.downloadSize.takeIf { it > 0 },
            framework = framework,
            contextLength = registryModel.contextLength.takeIf { it > 0 },
            supportsThinking = registryModel.supportsThinking,
            description = registryModel.description,
        )

    return ModelStorageMetrics(
        model = modelInfo,
        sizeOnDisk = sizeOnDisk,
    )
}
