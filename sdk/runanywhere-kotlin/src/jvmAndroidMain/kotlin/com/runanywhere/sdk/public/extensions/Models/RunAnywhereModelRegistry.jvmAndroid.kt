/*
 * Copyright 2024 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actuals for the Swift-parity model registry surface.
 *
 * Mirrors Swift `RunAnywhere+ModelRegistry.swift` exactly: listModels,
 * queryModels, getModel, downloadedModels. The Swift implementation
 * delegates to `CppBridge.ModelRegistry.shared` (`.list` / `.get` /
 * default-request fan-out). The Kotlin bridge does not yet expose a
 * dedicated `list(ModelListRequest)` thunk, so we synthesise the
 * canonical `ModelListResult` envelope here by composing the existing
 * `query` / `getAll` proto entry points on `CppBridgeModelRegistry`.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.ModelGetRequest
import ai.runanywhere.proto.v1.ModelGetResult
import ai.runanywhere.proto.v1.ModelInfoList
import ai.runanywhere.proto.v1.ModelListRequest
import ai.runanywhere.proto.v1.ModelListResult
import ai.runanywhere.proto.v1.ModelQuery
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelRegistry
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RAModelInfo

private val modelsLogger = SDKLogger.models

// MARK: - Internal Registration Helper

internal actual fun registerModelInternal(modelInfo: RAModelInfo) {
    try {
        CppBridgeModelRegistry.save(modelInfo)
        modelsLogger.info("Registered model: ${modelInfo.name} (${modelInfo.id})")
    } catch (e: Exception) {
        modelsLogger.error("Failed to register model: ${e.message}")
        throw e
    }
}

// MARK: - Swift-Parity Discovery API

actual suspend fun RunAnywhere.listModels(request: ModelListRequest): ModelListResult {
    if (!isInitialized) {
        return ModelListResult(success = false, error_message = "SDK not initialized")
    }
    val infoList =
        if (request.query != null) {
            CppBridgeModelRegistry.query(request.query)
        } else {
            ModelInfoList(models = CppBridgeModelRegistry.getAll())
        }
    return modelListResult(infoList)
}

actual suspend fun RunAnywhere.queryModels(query: ModelQuery): ModelListResult =
    listModels(ModelListRequest(query = query))

actual suspend fun RunAnywhere.getModel(request: ModelGetRequest): ModelGetResult {
    if (!isInitialized) {
        return ModelGetResult(found = false, error_message = "SDK not initialized")
    }
    if (request.model_id.isEmpty()) {
        return ModelGetResult(found = false, error_message = "model_id is required")
    }
    val model =
        CppBridgeModelRegistry.get(request.model_id)
            ?: return ModelGetResult(found = false, error_message = "Model not found: ${request.model_id}")
    return ModelGetResult(found = true, model = model)
}

actual suspend fun RunAnywhere.downloadedModels(): ModelListResult =
    queryModels(ModelQuery(downloaded_only = true))

// MARK: - Helpers

private fun modelListResult(list: ModelInfoList): ModelListResult =
    ModelListResult(success = true, models = list)
