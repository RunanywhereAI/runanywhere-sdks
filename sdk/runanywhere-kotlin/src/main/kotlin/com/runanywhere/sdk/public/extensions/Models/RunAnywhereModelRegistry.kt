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
 * Discovery-only, like Swift: the public `registerModel(...)` overloads live
 * in Storage/RunAnywhereStorage.kt (mirroring RunAnywhere+Storage.swift).
 *
 * Internal helper `registerModelInternal` is retained because the LoRA
 * adapter registration and the Android System TTS module both seed the
 * proto registry through it. It is not part of Swift's public surface.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.ModelGetRequest
import ai.runanywhere.proto.v1.ModelGetResult
import ai.runanywhere.proto.v1.ModelInfoList
import ai.runanywhere.proto.v1.ModelListRequest
import ai.runanywhere.proto.v1.ModelListResult
import ai.runanywhere.proto.v1.ModelQuery
import ai.runanywhere.proto.v1.ModelRegistryRefreshRequest
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelRegistry
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RAModelInfo
import kotlinx.coroutines.CancellationException

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

// MARK: - Swift-Parity Discovery API

suspend fun RunAnywhere.listModels(request: ModelListRequest = ModelListRequest()): ModelListResult {
    if (!isInitialized) {
        return ModelListResult(success = false, error_message = "SDK not initialized")
    }
    try {
        ensureServicesReady()
    } catch (e: CancellationException) {
        throw e
    } catch (_: Exception) {
    }
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
    try {
        ensureServicesReady()
    } catch (e: CancellationException) {
        throw e
    } catch (_: Exception) {
    }
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
    try {
        ensureServicesReady()
    } catch (e: CancellationException) {
        throw e
    } catch (_: Exception) {
    }

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
