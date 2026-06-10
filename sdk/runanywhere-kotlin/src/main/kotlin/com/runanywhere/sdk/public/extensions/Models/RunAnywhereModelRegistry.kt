/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public proto-backed model registry API.
 *
 * Mirrors Swift sdk/runanywhere-swift/.../Models/RunAnywhere+ModelRegistry.swift:
 *   - listModels(request: ModelListRequest = ModelListRequest()) -> ModelListResult
 *   - queryModels(query: ModelQuery) -> ModelListResult
 *   - getModel(request: ModelGetRequest) -> ModelGetResult
 *   - downloadedModels() -> ModelListResult
 *
 * Internal helper `registerModelInternal` is retained because the LoRA
 * adapter registration and the Android System TTS module both seed the
 * proto registry through it. It is not part of Swift's public surface.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelFormat
import ai.runanywhere.proto.v1.ModelGetRequest
import ai.runanywhere.proto.v1.ModelGetResult
import ai.runanywhere.proto.v1.ModelInfo
import ai.runanywhere.proto.v1.ModelInfoList
import ai.runanywhere.proto.v1.ModelListRequest
import ai.runanywhere.proto.v1.ModelListResult
import ai.runanywhere.proto.v1.ModelQuery
import ai.runanywhere.proto.v1.ModelRegistryRefreshRequest
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelRegistry
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.make
import com.runanywhere.sdk.public.types.RAModelInfo

// MARK: - Registry Discovery (Swift parity)

private val modelsLogger = SDKLogger.models

// MARK: - Internal Registration Helper

internal fun registerModelInternal(modelInfo: RAModelInfo) {
    try {
        CppBridgeModelRegistry.save(modelInfo)
        modelsLogger.info("Registered model: ${modelInfo.name} (${modelInfo.id})")
    } catch (e: Exception) {
        modelsLogger.error("Failed to register model: ${e.message}")
        throw e
    }
}

// MARK: - Public Registration API

suspend fun RunAnywhere.registerModel(modelInfo: RAModelInfo): RAModelInfo {
    if (!isInitialized) {
        throw IllegalStateException("SDK not initialized")
    }
    ensureServicesReady()
    registerModelInternal(modelInfo)
    return modelInfo
}

suspend fun RunAnywhere.registerModel(
    id: String? = null,
    name: String,
    url: String,
    framework: InferenceFramework,
    modality: ModelCategory = ModelCategory.MODEL_CATEGORY_LANGUAGE,
    memoryRequirement: Long? = null,
    supportsThinking: Boolean = false,
    supportsLora: Boolean = false,
): RAModelInfo {
    val model =
        ModelInfo
            .make(
                id = id ?: generatedModelId(url, name),
                name = name,
                category = modality,
                format = ModelFormat.MODEL_FORMAT_UNSPECIFIED,
                framework = framework,
                downloadURL = url,
                downloadSizeBytes = memoryRequirement,
                supportsThinking = supportsThinking,
            ).copy(
                memory_required_bytes = memoryRequirement ?: 0L,
                supports_lora = supportsLora,
            )
    return registerModel(model)
}

// MARK: - Swift-Parity Discovery API

suspend fun RunAnywhere.listModels(request: ModelListRequest = ModelListRequest()): ModelListResult {
    if (!isInitialized) {
        return ModelListResult(success = false, error_message = "SDK not initialized")
    }
    ensureServicesReady()
    val infoList =
        if (request.query != null) {
            CppBridgeModelRegistry.query(request.query)
        } else {
            ModelInfoList(models = CppBridgeModelRegistry.getAll())
        }
    return modelListResult(infoList)
}

suspend fun RunAnywhere.queryModels(query: ModelQuery): ModelListResult =
    listModels(ModelListRequest(query = query))

suspend fun RunAnywhere.getModel(request: ModelGetRequest): ModelGetResult {
    if (!isInitialized) {
        return ModelGetResult(found = false, error_message = "SDK not initialized")
    }
    ensureServicesReady()
    if (request.model_id.isEmpty()) {
        return ModelGetResult(found = false, error_message = "model_id is required")
    }
    val model =
        CppBridgeModelRegistry.get(request.model_id)
            ?: return ModelGetResult(found = false, error_message = "Model not found: ${request.model_id}")
    return ModelGetResult(found = true, model = model)
}

suspend fun RunAnywhere.downloadedModels(): ModelListResult =
    queryModels(ModelQuery(downloaded_only = true))

suspend fun RunAnywhere.refreshModelRegistry(
    rescanLocal: Boolean = true,
    includeRemoteCatalog: Boolean = false,
    pruneOrphans: Boolean = false,
) {
    if (!isInitialized) return
    ensureServicesReady()

    if (rescanLocal) {
        CppBridgeModelRegistry.discoverDownloadedModels()
    }

    CppBridgeModelRegistry.refresh(
        ModelRegistryRefreshRequest(
            rescan_local = rescanLocal,
            include_remote_catalog = includeRemoteCatalog,
            prune_orphans = pruneOrphans,
            include_downloaded_state = true,
        ),
    )
}

// MARK: - Helpers

private fun modelListResult(list: ModelInfoList): ModelListResult =
    ModelListResult(success = true, models = list)

private fun generatedModelId(url: String, name: String): String {
    val source = url.substringAfterLast('/').substringBeforeLast('.').ifBlank { name }
    return source
        .lowercase()
        .map { if (it.isLetterOrDigit()) it else '-' }
        .joinToString("")
        .trim('-')
        .replace(Regex("-+"), "-")
        .ifBlank { "model-${System.currentTimeMillis()}" }
}
