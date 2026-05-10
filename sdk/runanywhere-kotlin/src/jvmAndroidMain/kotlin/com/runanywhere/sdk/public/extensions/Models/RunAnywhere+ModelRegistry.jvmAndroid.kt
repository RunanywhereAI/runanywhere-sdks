/*
 * Copyright 2024 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for proto-backed model registry,
 * discovery, and download operations.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.DownloadCancelRequest
import ai.runanywhere.proto.v1.DownloadCancelResult
import ai.runanywhere.proto.v1.DownloadPlanRequest
import ai.runanywhere.proto.v1.DownloadPlanResult
import ai.runanywhere.proto.v1.DownloadProgress
import ai.runanywhere.proto.v1.DownloadResumeRequest
import ai.runanywhere.proto.v1.DownloadResumeResult
import ai.runanywhere.proto.v1.DownloadStartRequest
import ai.runanywhere.proto.v1.DownloadStartResult
import ai.runanywhere.proto.v1.DownloadState
import ai.runanywhere.proto.v1.DownloadSubscribeRequest
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelFormat
import ai.runanywhere.proto.v1.ModelImportRequest
import ai.runanywhere.proto.v1.ModelImportResult
import ai.runanywhere.proto.v1.ModelInfo
import ai.runanywhere.proto.v1.ModelInfoList
import ai.runanywhere.proto.v1.ModelQuery
import ai.runanywhere.proto.v1.ModelRegistryRefreshRequest
import ai.runanywhere.proto.v1.ModelRegistryRefreshResult
import ai.runanywhere.proto.v1.StorageDeleteRequest
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeDownload
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelFormat
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelRegistry
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeStorage
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.withContext
import java.util.concurrent.ConcurrentHashMap

private val activeDownloadIdsByModel = ConcurrentHashMap<String, String>()
private val modelsLogger = SDKLogger.models

// MARK: - Model Registration Implementation

internal actual fun registerModelInternal(modelInfo: ModelInfo) {
    try {
        CppBridgeModelRegistry.save(modelInfo)
        modelsLogger.info("Registered model: ${modelInfo.name} (${modelInfo.id})")
    } catch (e: Exception) {
        modelsLogger.error("Failed to register model: ${e.message}")
        throw e
    }
}

internal actual fun formatFromUrl(url: String): ModelFormat =
    CppBridgeModelFormat.formatFromUrl(url)

internal actual fun applyInferredArtifact(modelInfo: ModelInfo, url: String): ModelInfo =
    CppBridgeModelFormat.applyInferredArtifact(modelInfo, url)

private fun requireInitialized(sdk: RunAnywhere) {
    if (!sdk.isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
}

private fun getAllBridgeModels(): List<ModelInfo> = CppBridgeModelRegistry.getAll()

actual suspend fun RunAnywhere.availableModels(): List<ModelInfo> {
    requireInitialized(this)
    return getAllBridgeModels()
}

actual suspend fun RunAnywhere.models(category: ModelCategory): List<ModelInfo> {
    requireInitialized(this)
    return CppBridgeModelRegistry.query(ModelQuery(category = category)).models
}

actual suspend fun RunAnywhere.downloadedModels(): List<ModelInfo> {
    requireInitialized(this)
    return CppBridgeModelRegistry.query(ModelQuery(downloaded_only = true)).models
}

actual suspend fun RunAnywhere.model(modelId: String): ModelInfo? {
    requireInitialized(this)
    return CppBridgeModelRegistry.get(modelId)
}

actual suspend fun RunAnywhere.queryModels(query: ModelQuery): ModelInfoList {
    requireInitialized(this)
    return CppBridgeModelRegistry.query(query)
}

actual suspend fun RunAnywhere.downloadedModelsProto(): ModelInfoList {
    requireInitialized(this)
    return CppBridgeModelRegistry.query(ModelQuery(downloaded_only = true))
}

// MARK: - Model Downloads

actual fun RunAnywhere.downloadModel(modelId: String): Flow<DownloadProgress> =
    startDownloadFromPlan(modelId)

actual suspend fun RunAnywhere.planDownload(request: DownloadPlanRequest): DownloadPlanResult {
    requireInitialized(this)
    return CppBridgeDownload.plan(request)
        ?: throw SDKException.download("Native download plan proto API unavailable")
}

actual fun RunAnywhere.startDownload(request: DownloadStartRequest): Flow<DownloadProgress> =
    callbackFlow {
        if (!isInitialized) {
            close(SDKException.notInitialized("SDK not initialized"))
            return@callbackFlow
        }

        val expectedModelId = request.model_id.ifBlank { request.plan?.model_id.orEmpty() }
        var taskId = request.resume_token

        CppBridgeDownload.setProgressCallback { progress ->
            val matchesTask = taskId.isBlank() || progress.task_id == taskId
            val matchesModel = expectedModelId.isBlank() || progress.model_id == expectedModelId
            if (matchesTask && matchesModel) {
                trySend(progress)
                if (progress.isTerminal()) close()
            }
            true
        }

        val result =
            CppBridgeDownload.start(request)
                ?: run {
                    CppBridgeDownload.setProgressCallback(null)
                    close(SDKException.download("Native download start proto API unavailable"))
                    return@callbackFlow
                }
        taskId = result.task_id
        if (expectedModelId.isNotBlank() && taskId.isNotBlank()) {
            activeDownloadIdsByModel[expectedModelId] = taskId
        }
        result.initial_progress?.let {
            trySend(it)
            if (it.isTerminal()) close()
        }
        if (!result.accepted) {
            CppBridgeDownload.setProgressCallback(null)
            close(SDKException.download(result.error_message.ifBlank { "Download was not accepted" }))
            return@callbackFlow
        }

        awaitClose {
            if (expectedModelId.isNotBlank()) activeDownloadIdsByModel.remove(expectedModelId, taskId)
            CppBridgeDownload.setProgressCallback(null)
        }
    }

private fun RunAnywhere.startDownloadFromPlan(modelId: String): Flow<DownloadProgress> =
    callbackFlow {
        if (!isInitialized) {
            close(SDKException.notInitialized("SDK not initialized"))
            return@callbackFlow
        }

        val modelInfo =
            CppBridgeModelRegistry.get(modelId)
                ?: run {
                    close(SDKException.model("Model '$modelId' not found in registry"))
                    return@callbackFlow
                }

        val plan =
            CppBridgeDownload.plan(
                DownloadPlanRequest(
                    model_id = modelId,
                    model = modelInfo,
                    resume_existing = true,
                    validate_existing_bytes = true,
                    verify_checksums = true,
                ),
            ) ?: run {
                close(SDKException.download("Native download plan proto API unavailable"))
                return@callbackFlow
            }

        if (!plan.can_start) {
            close(SDKException.download(plan.error_message.ifBlank { "Download cannot start" }))
            return@callbackFlow
        }

        var taskId = plan.resume_token
        CppBridgeDownload.setProgressCallback { progress ->
            val matchesTask = taskId.isBlank() || progress.task_id == taskId
            if (progress.model_id == modelId && matchesTask) {
                trySend(progress)
                if (progress.state == DownloadState.DOWNLOAD_STATE_COMPLETED) {
                    // KOT-DOWNLOAD-004: C++ `update_registry_on_completion` is a
                    // deferred follow-up (CPP-02). Until then, self-heal the
                    // registry here so `ModelInfo.isDownloadedModel` flips true
                    // and the sheet shows "Use" after download completes.
                    markModelDownloadedInRegistry(modelId, progress.local_path)
                }
                if (progress.isTerminal()) close()
            }
            true
        }

        val result =
            CppBridgeDownload.start(
                DownloadStartRequest(
                    model_id = modelId,
                    plan = plan,
                    resume = plan.can_resume,
                    resume_token = plan.resume_token,
                    update_registry_on_completion = true,
                ),
            ) ?: run {
                CppBridgeDownload.setProgressCallback(null)
                close(SDKException.download("Native download start proto API unavailable"))
                return@callbackFlow
            }

        taskId = result.task_id
        if (taskId.isNotBlank()) activeDownloadIdsByModel[modelId] = taskId
        result.initial_progress?.let {
            trySend(it)
            if (it.isTerminal()) close()
        }
        if (!result.accepted) {
            CppBridgeDownload.setProgressCallback(null)
            close(SDKException.download(result.error_message.ifBlank { "Download was not accepted" }))
            return@callbackFlow
        }

        awaitClose {
            activeDownloadIdsByModel.remove(modelId, taskId)
            CppBridgeDownload.setProgressCallback(null)
        }
    }

private fun DownloadProgress.isTerminal(): Boolean =
    state == DownloadState.DOWNLOAD_STATE_COMPLETED ||
        state == DownloadState.DOWNLOAD_STATE_FAILED ||
        state == DownloadState.DOWNLOAD_STATE_CANCELLED

actual suspend fun RunAnywhere.startDownloadProto(request: DownloadStartRequest): DownloadStartResult {
    requireInitialized(this)
    return CppBridgeDownload.start(request)
        ?: throw SDKException.download("Native download start proto API unavailable")
}

actual suspend fun RunAnywhere.cancelDownload(request: DownloadCancelRequest): DownloadCancelResult {
    requireInitialized(this)
    val result =
        CppBridgeDownload.cancel(request)
            ?: throw SDKException.download("Native download cancel proto API unavailable")
    if (result.model_id.isNotBlank()) activeDownloadIdsByModel.remove(result.model_id, result.task_id)
    return result
}

actual suspend fun RunAnywhere.resumeDownload(request: DownloadResumeRequest): DownloadResumeResult {
    requireInitialized(this)
    return CppBridgeDownload.resume(request)
        ?: throw SDKException.download("Native download resume proto API unavailable")
}

actual suspend fun RunAnywhere.downloadProgress(request: DownloadSubscribeRequest): DownloadProgress? {
    requireInitialized(this)
    return CppBridgeDownload.pollProgress(request)
}

actual suspend fun RunAnywhere.cancelDownload(modelId: String) {
    requireInitialized(this)
    val taskId = activeDownloadIdsByModel.remove(modelId).orEmpty()
    val result =
        CppBridgeDownload.cancel(
            DownloadCancelRequest(
                task_id = taskId,
                model_id = modelId,
                delete_partial_bytes = true,
            ),
        ) ?: throw SDKException.download("Native download cancel proto API unavailable")
    if (!result.success) {
        throw SDKException.download(result.error_message.ifBlank { "Failed to cancel download for '$modelId'" })
    }
}

actual suspend fun RunAnywhere.isModelDownloaded(modelId: String): Boolean {
    requireInitialized(this)
    val model = CppBridgeModelRegistry.get(modelId) ?: return false
    return model.local_path.isNotEmpty() || model.is_downloaded == true
}

actual suspend fun RunAnywhere.deleteModel(modelId: String) {
    requireInitialized(this)
    deleteStorageForModels(listOf(modelId))
}

actual suspend fun RunAnywhere.deleteAllModels() {
    requireInitialized(this)
    val modelIds = downloadedModels().map { it.id }
    if (modelIds.isNotEmpty()) {
        deleteStorageForModels(modelIds)
    }
}

private fun deleteStorageForModels(modelIds: List<String>) {
    val result =
        CppBridgeStorage.delete(
            StorageDeleteRequest(
                model_ids = modelIds,
                delete_files = true,
                clear_registry_paths = true,
                unload_if_loaded = true,
                allow_platform_delete = true,
            ),
        ) ?: throw SDKException.storage("Native storage delete proto API unavailable")
    if (!result.success) {
        throw SDKException.storage(result.error_message.ifBlank { "Failed to delete model storage" })
    }
}

actual suspend fun RunAnywhere.refreshModelRegistry(
    includeRemoteCatalog: Boolean,
    rescanLocal: Boolean,
    pruneOrphans: Boolean,
): ModelRegistryRefreshResult =
    refreshModelRegistry(
        ModelRegistryRefreshRequest(
            include_remote_catalog = includeRemoteCatalog,
            rescan_local = rescanLocal,
            prune_orphans = pruneOrphans,
            include_downloaded_state = true,
        ),
    )

actual suspend fun RunAnywhere.refreshModelRegistry(
    request: ModelRegistryRefreshRequest,
): ModelRegistryRefreshResult {
    requireInitialized(this)
    modelsLogger.info("Refreshing model registry via generated proto JNI")
    return withContext(Dispatchers.IO) {
        CppBridgeModelRegistry.refresh(request)
            ?: throw SDKException.model("Native model registry refresh proto API unavailable")
    }
}

// MARK: - Model Import

/**
 * Mirrors Swift `RunAnywhere.importModel(_:)`. Imports a platform-normalized
 * local model into the C++ registry.
 *
 * NOTE: The native commons proto thunk `rac_model_registry_import_proto` is
 * not yet exposed through the Kotlin JNI bridge — see
 * [com.runanywhere.sdk.native.bridge.RunAnywhereBridge] (no
 * `racModelRegistryImportProto` external fun exists). Until that thunk is
 * wired, this implementation falls back to merging the supplied
 * [ModelImportRequest.model] into the registry via
 * [CppBridgeModelRegistry.save], which is functionally equivalent to the
 * `registerModel` flow.
 */
actual suspend fun RunAnywhere.importModel(request: ModelImportRequest): ModelImportResult {
    requireInitialized(this)
    val model =
        request.model
            ?: return ModelImportResult(
                success = false,
                error_message = "ModelImportRequest.model is required (Kotlin fallback path)",
            )
    val sourcePath = request.source_path
    val nowMs = System.currentTimeMillis()
    val mergedModel =
        if (sourcePath.isNotBlank()) {
            model.copy(
                local_path = sourcePath,
                is_downloaded = true,
                is_available = true,
                updated_at_unix_ms = nowMs,
            )
        } else {
            model.copy(updated_at_unix_ms = nowMs)
        }
    return withContext(Dispatchers.IO) {
        try {
            CppBridgeModelRegistry.save(mergedModel)
            ModelImportResult(
                success = true,
                model = mergedModel,
                local_path = mergedModel.local_path,
                imported_bytes = mergedModel.download_size_bytes,
                registered = true,
                copied_into_managed_storage = false,
            )
        } catch (e: Throwable) {
            modelsLogger.error("Failed to import model '${mergedModel.id}': ${e.message}")
            ModelImportResult(
                success = false,
                model = mergedModel,
                error_message = e.message ?: "Failed to import model",
            )
        }
    }
}

/**
 * Self-heal the registry entry for a model that just finished downloading by
 * setting `is_downloaded=true` and (when provided) `local_path`.
 *
 * Needed because `rac_download_start_proto` honours
 * `update_registry_on_completion=true` only as a logged warning today
 * (commons CPP-02 follow-up). Without this, `ModelInfo.isDownloadedModel`
 * stays false after a successful download and the UI never flips from
 * "Download" → "Use".
 */
private fun markModelDownloadedInRegistry(modelId: String, reportedLocalPath: String) {
    try {
        val existing = CppBridgeModelRegistry.get(modelId) ?: return
        val updated =
            existing.copy(
                is_downloaded = true,
                local_path = reportedLocalPath.ifBlank { existing.local_path },
            )
        CppBridgeModelRegistry.save(updated)
    } catch (_: Throwable) {
        // non-fatal: if save fails, refreshModelRegistry() is the recovery path
    }
}
