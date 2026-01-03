/*
 * Copyright 2024 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for model management operations.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelRegistry
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeLLM
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeSTT
import com.runanywhere.sdk.foundation.errors.SDKError
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.DownloadProgress
import com.runanywhere.sdk.public.extensions.Models.DownloadState
import com.runanywhere.sdk.public.extensions.Models.ModelCategory
import com.runanywhere.sdk.public.extensions.Models.ModelInfo
import com.runanywhere.sdk.public.extensions.Models.ModelFormat
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

// Convert CppBridgeModelRegistry.ModelInfo to public ModelInfo
private fun CppBridgeModelRegistry.ModelInfo.toPublicModelInfo(): ModelInfo {
    return ModelInfo(
        id = this.modelId,
        name = this.name,
        category = when (this.type) {
            CppBridgeModelRegistry.ModelType.LLM -> ModelCategory.LANGUAGE
            CppBridgeModelRegistry.ModelType.STT -> ModelCategory.SPEECH_RECOGNITION
            CppBridgeModelRegistry.ModelType.TTS -> ModelCategory.SPEECH_SYNTHESIS
            CppBridgeModelRegistry.ModelType.VAD -> ModelCategory.AUDIO
            CppBridgeModelRegistry.ModelType.EMBEDDING -> ModelCategory.LANGUAGE
            else -> ModelCategory.LANGUAGE
        },
        format = when (this.format) {
            CppBridgeModelRegistry.ModelFormat.GGUF -> ModelFormat.GGUF
            CppBridgeModelRegistry.ModelFormat.ONNX -> ModelFormat.ONNX
            else -> ModelFormat.UNKNOWN
        },
        downloadURL = this.downloadUrl,
        localPath = this.localPath,
        downloadSize = this.size,
        framework = InferenceFramework.LLAMA_CPP,
        description = this.metadata["description"]
    )
}

private fun getAllBridgeModels(): List<CppBridgeModelRegistry.ModelInfo> {
    // Parse the JSON from getAllModelsCallback
    val json = CppBridgeModelRegistry.getAllModelsCallback()
    return parseModelInfoListJson(json)
}

private fun parseModelInfoListJson(json: String): List<CppBridgeModelRegistry.ModelInfo> {
    // Simple JSON parsing for model info array
    val models = mutableListOf<CppBridgeModelRegistry.ModelInfo>()
    if (json == "[]" || json.isBlank()) return models
    // Full JSON parsing would need kotlinx.serialization - simplified for now
    return models
}

actual suspend fun RunAnywhere.availableModels(): List<ModelInfo> {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }
    return getAllBridgeModels().map { it.toPublicModelInfo() }
}

actual suspend fun RunAnywhere.models(category: ModelCategory): List<ModelInfo> {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }
    val type = when (category) {
        ModelCategory.LANGUAGE -> CppBridgeModelRegistry.ModelType.LLM
        ModelCategory.SPEECH_RECOGNITION -> CppBridgeModelRegistry.ModelType.STT
        ModelCategory.SPEECH_SYNTHESIS -> CppBridgeModelRegistry.ModelType.TTS
        ModelCategory.AUDIO -> CppBridgeModelRegistry.ModelType.VAD
        else -> return emptyList()
    }
    val json = CppBridgeModelRegistry.getModelsByTypeCallback(type)
    return parseModelInfoListJson(json).map { it.toPublicModelInfo() }
}

actual suspend fun RunAnywhere.downloadedModels(): List<ModelInfo> {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }
    val json = CppBridgeModelRegistry.getDownloadedModelsCallback()
    return parseModelInfoListJson(json).map { it.toPublicModelInfo() }
}

actual suspend fun RunAnywhere.model(modelId: String): ModelInfo? {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }
    CppBridgeModelRegistry.getModelInfoCallback(modelId) ?: return null
    // Would need to parse single model JSON - simplified for now
    return null
}

actual fun RunAnywhere.downloadModel(modelId: String): Flow<DownloadProgress> = flow {
    emit(DownloadProgress(
        modelId = modelId,
        progress = 0f,
        bytesDownloaded = 0,
        totalBytes = null,
        state = DownloadState.PENDING
    ))

    // Update status to downloading
    CppBridgeModelRegistry.updateModelStatusCallback(modelId, CppBridgeModelRegistry.ModelStatus.DOWNLOADING)

    // TODO: Implement actual download via CppBridge.Download
    // For now just mark as complete
    CppBridgeModelRegistry.updateModelStatusCallback(modelId, CppBridgeModelRegistry.ModelStatus.DOWNLOADED)

    emit(DownloadProgress(
        modelId = modelId,
        progress = 1f,
        bytesDownloaded = 0,
        totalBytes = null,
        state = DownloadState.COMPLETED
    ))
}

actual suspend fun RunAnywhere.cancelDownload(modelId: String) {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }
    CppBridgeModelRegistry.updateModelStatusCallback(modelId, CppBridgeModelRegistry.ModelStatus.AVAILABLE)
}

actual suspend fun RunAnywhere.isModelDownloaded(modelId: String): Boolean {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }
    val json = CppBridgeModelRegistry.getModelInfoCallback(modelId) ?: return false
    // Check if status indicates downloaded - simplified
    return json.contains("\"status\":3") || json.contains("\"status\":5")
}

actual suspend fun RunAnywhere.deleteModel(modelId: String) {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }
    CppBridgeModelRegistry.deleteModelInfoCallback(modelId)
}

actual suspend fun RunAnywhere.deleteAllModels() {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }
    // Would need to parse and delete each - simplified
}

actual suspend fun RunAnywhere.refreshModelRegistry() {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }
    // Trigger registry refresh via native call
    // TODO: Implement via CppBridge
}

actual suspend fun RunAnywhere.loadLLMModel(modelId: String) {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    val json = CppBridgeModelRegistry.getModelInfoCallback(modelId)
        ?: throw SDKError.model("Model '$modelId' not found in registry")

    // Extract local path from JSON
    val localPathMatch = Regex("\"localPath\"\\s*:\\s*\"([^\"]+)\"").find(json)
    val localPath = localPathMatch?.groupValues?.get(1)
        ?: throw SDKError.model("Model '$modelId' is not downloaded")

    CppBridgeLLM.loadModel(localPath, modelId)
}

actual suspend fun RunAnywhere.unloadLLMModel() {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }
    CppBridgeLLM.unload()
}

actual suspend fun RunAnywhere.isLLMModelLoaded(): Boolean {
    return CppBridgeLLM.isLoaded
}

actual suspend fun RunAnywhere.loadSTTModel(modelId: String) {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    val json = CppBridgeModelRegistry.getModelInfoCallback(modelId)
        ?: throw SDKError.model("Model '$modelId' not found in registry")

    // Extract local path from JSON
    val localPathMatch = Regex("\"localPath\"\\s*:\\s*\"([^\"]+)\"").find(json)
    val localPath = localPathMatch?.groupValues?.get(1)
        ?: throw SDKError.model("Model '$modelId' is not downloaded")

    CppBridgeSTT.loadModel(localPath, modelId)
}
