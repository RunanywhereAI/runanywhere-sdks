/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for storage operations.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.foundation.SDKLogger
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

    // Calculate directory sizes
    val cacheSize = calculateDirectorySize(cacheDir)
    val modelsSize = calculateDirectorySize(modelsDir)
    val appSupportSize = calculateDirectorySize(appSupportDir)

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

    val baseDir = File(CppBridgeModelPaths.getBaseDirectory())
    val availableSpace = baseDir.freeSpace
    val isAvailable = availableSpace >= requiredBytes

    // Check if we're getting low on space (less than 1GB after this operation)
    val hasWarning = isAvailable && (availableSpace - requiredBytes) < 1024L * 1024 * 1024

    val recommendation =
        when {
            !isAvailable -> "Not enough storage space. Required: ${formatBytes(requiredBytes)}, Available: ${formatBytes(availableSpace)}"
            hasWarning -> "Storage is running low. Consider clearing cache or removing unused models."
            else -> null
        }

    return StorageAvailability(
        isAvailable = isAvailable,
        requiredSpace = requiredBytes,
        availableSpace = availableSpace,
        hasWarning = hasWarning,
        recommendation = recommendation,
    )
}

actual suspend fun RunAnywhere.cacheSize(): Long {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    val cacheDir = File(CppBridgeModelPaths.getBaseDirectory(), "cache")
    return calculateDirectorySize(cacheDir)
}

actual suspend fun RunAnywhere.clearCache() {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    storageLogger.info("Clearing cache...")

    // Clear the storage cache namespace
    CppBridgeStorage.clear(CppBridgeStorage.StorageNamespace.INFERENCE_CACHE, CppBridgeStorage.StorageType.CACHE)

    // Also clear the file cache directory
    val cacheDir = File(CppBridgeModelPaths.getBaseDirectory(), "cache")
    if (cacheDir.exists()) {
        cacheDir.deleteRecursively()
        cacheDir.mkdirs()
    }

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

    val modelsDir = File(CppBridgeModelPaths.getBaseDirectory(), "models")
    return calculateDirectorySize(modelsDir)
}

// Helper function to calculate directory size recursively
private fun calculateDirectorySize(directory: File): Long {
    if (!directory.exists()) return 0L
    if (directory.isFile) return directory.length()

    var size = 0L
    directory.listFiles()?.forEach { file ->
        size +=
            if (file.isDirectory) {
                calculateDirectorySize(file)
            } else {
                file.length()
            }
    }
    return size
}

// Helper function to format bytes as human-readable string
private fun formatBytes(bytes: Long): String {
    if (bytes < 1024) return "$bytes B"
    val kb = bytes / 1024.0
    if (kb < 1024) return "%.1f KB".format(kb)
    val mb = kb / 1024.0
    if (mb < 1024) return "%.1f MB".format(mb)
    val gb = mb / 1024.0
    return "%.2f GB".format(gb)
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
            CppBridgeModelRegistry.ModelCategory.IMAGE_GENERATION -> ModelCategory.IMAGE_GENERATION
            else -> ModelCategory.LANGUAGE
        }

    // Convert format int to ModelFormat enum
    val format =
        when (registryModel.format) {
            CppBridgeModelRegistry.ModelFormat.GGUF -> ModelFormat.GGUF
            CppBridgeModelRegistry.ModelFormat.ONNX -> ModelFormat.ONNX
            CppBridgeModelRegistry.ModelFormat.ORT -> ModelFormat.ORT
            CppBridgeModelRegistry.ModelFormat.BIN -> ModelFormat.BIN
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
