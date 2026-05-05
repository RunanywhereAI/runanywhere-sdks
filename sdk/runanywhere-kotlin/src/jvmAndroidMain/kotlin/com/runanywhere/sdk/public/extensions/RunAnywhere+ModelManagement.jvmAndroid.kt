/*
 * Copyright 2024 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for model management operations.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.ComponentLifecycleSnapshot
import ai.runanywhere.proto.v1.ComponentLifecycleState
import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.CurrentModelResult
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
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelInfo
import ai.runanywhere.proto.v1.ModelInfoList
import ai.runanywhere.proto.v1.ModelLoadRequest
import ai.runanywhere.proto.v1.ModelLoadResult
import ai.runanywhere.proto.v1.ModelQuery
import ai.runanywhere.proto.v1.ModelRegistryRefreshRequest
import ai.runanywhere.proto.v1.ModelRegistryRefreshResult
import ai.runanywhere.proto.v1.ModelUnloadRequest
import ai.runanywhere.proto.v1.ModelUnloadResult
import ai.runanywhere.proto.v1.SDKComponent
import ai.runanywhere.proto.v1.StorageDeleteRequest
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeDownloadProto
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelLifecycleProto
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelRegistry
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeStorageProto
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.withContext

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

actual suspend fun RunAnywhere.loadModel(request: ModelLoadRequest): ModelLoadResult {
    requireInitialized(this)
    return withContext(Dispatchers.IO) {
        CppBridgeModelLifecycleProto.load(request)
            ?: throw SDKException.model("Native model lifecycle load proto API unavailable")
    }
}

actual suspend fun RunAnywhere.unloadModel(request: ModelUnloadRequest): ModelUnloadResult {
    requireInitialized(this)
    return CppBridgeModelLifecycleProto.unload(request)
        ?: throw SDKException.model("Native model lifecycle unload proto API unavailable")
}

actual suspend fun RunAnywhere.currentModel(request: CurrentModelRequest): CurrentModelResult {
    requireInitialized(this)
    return CppBridgeModelLifecycleProto.currentModel(request)
        ?: throw SDKException.model("Native current model proto API unavailable")
}

actual suspend fun RunAnywhere.componentLifecycleSnapshot(
    component: SDKComponent,
): ComponentLifecycleSnapshot {
    requireInitialized(this)
    return CppBridgeModelLifecycleProto.snapshot(component)
        ?: throw SDKException.model("Native component lifecycle snapshot proto API unavailable")
}

// MARK: - Model Downloads

actual fun RunAnywhere.downloadModel(modelId: String): Flow<DownloadProgress> =
    startDownloadFromPlan(modelId)

actual suspend fun RunAnywhere.planDownload(request: DownloadPlanRequest): DownloadPlanResult {
    requireInitialized(this)
    return CppBridgeDownloadProto.plan(request)
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

        CppBridgeDownloadProto.setProgressCallback { progress ->
            val matchesTask = taskId.isBlank() || progress.task_id == taskId
            val matchesModel = expectedModelId.isBlank() || progress.model_id == expectedModelId
            if (matchesTask && matchesModel) {
                trySend(progress)
                if (progress.isTerminal()) close()
            }
            true
        }

        val result =
            CppBridgeDownloadProto.start(request)
                ?: run {
                    CppBridgeDownloadProto.setProgressCallback(null)
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
            CppBridgeDownloadProto.setProgressCallback(null)
            close(SDKException.download(result.error_message.ifBlank { "Download was not accepted" }))
            return@callbackFlow
        }

        awaitClose {
            if (expectedModelId.isNotBlank()) activeDownloadIdsByModel.remove(expectedModelId, taskId)
            CppBridgeDownloadProto.setProgressCallback(null)
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
            CppBridgeDownloadProto.plan(
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
        CppBridgeDownloadProto.setProgressCallback { progress ->
            val matchesTask = taskId.isBlank() || progress.task_id == taskId
            if (progress.model_id == modelId && matchesTask) {
                trySend(progress)
                if (progress.isTerminal()) close()
            }
            true
        }

        val result =
            CppBridgeDownloadProto.start(
                DownloadStartRequest(
                    model_id = modelId,
                    plan = plan,
                    resume = plan.can_resume,
                    resume_token = plan.resume_token,
                    update_registry_on_completion = true,
                ),
            ) ?: run {
                CppBridgeDownloadProto.setProgressCallback(null)
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
            CppBridgeDownloadProto.setProgressCallback(null)
            close(SDKException.download(result.error_message.ifBlank { "Download was not accepted" }))
            return@callbackFlow
        }

        awaitClose {
            activeDownloadIdsByModel.remove(modelId, taskId)
            CppBridgeDownloadProto.setProgressCallback(null)
        }
    }

private fun DownloadProgress.isTerminal(): Boolean =
    state == DownloadState.DOWNLOAD_STATE_COMPLETED ||
        state == DownloadState.DOWNLOAD_STATE_FAILED ||
        state == DownloadState.DOWNLOAD_STATE_CANCELLED

actual suspend fun RunAnywhere.startDownloadProto(request: DownloadStartRequest): DownloadStartResult {
    requireInitialized(this)
    return CppBridgeDownloadProto.start(request)
        ?: throw SDKException.download("Native download start proto API unavailable")
}

actual suspend fun RunAnywhere.cancelDownload(request: DownloadCancelRequest): DownloadCancelResult {
    requireInitialized(this)
    val result =
        CppBridgeDownloadProto.cancel(request)
            ?: throw SDKException.download("Native download cancel proto API unavailable")
    if (result.model_id.isNotBlank()) activeDownloadIdsByModel.remove(result.model_id, result.task_id)
    return result
}

actual suspend fun RunAnywhere.resumeDownload(request: DownloadResumeRequest): DownloadResumeResult {
    requireInitialized(this)
    return CppBridgeDownloadProto.resume(request)
        ?: throw SDKException.download("Native download resume proto API unavailable")
}

actual suspend fun RunAnywhere.downloadProgress(request: DownloadSubscribeRequest): DownloadProgress? {
    requireInitialized(this)
    return CppBridgeDownloadProto.pollProgress(request)
}

actual suspend fun RunAnywhere.cancelDownload(modelId: String) {
    requireInitialized(this)
    val taskId = activeDownloadIdsByModel.remove(modelId).orEmpty()
    val result =
        CppBridgeDownloadProto.cancel(
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
        CppBridgeStorageProto.delete(
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

// MARK: - Model Loading

actual suspend fun RunAnywhere.loadModel(modelId: String) {
    requireInitialized(this)
    val result = loadModel(ModelLoadRequest(model_id = modelId))
    if (!result.success) {
        throw SDKException.model(
            result.error_message.ifBlank { "Failed to load model '$modelId'" },
        )
    }
}

actual suspend fun RunAnywhere.loadLLMModel(modelId: String) {
    requireInitialized(this)
    val framework =
        CppBridgeModelRegistry.get(modelId)?.framework
            ?: InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED
    val result =
        loadModel(
            ModelLoadRequest(
                model_id = modelId,
                category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
                framework = framework,
            ),
        )
    if (!result.success) {
        throw SDKException.llm(result.error_message.ifBlank { "Failed to load LLM model '$modelId'" })
    }
}

actual suspend fun RunAnywhere.unloadLLMModel() {
    requireInitialized(this)
    unloadModel(ModelUnloadRequest(category = ModelCategory.MODEL_CATEGORY_LANGUAGE))
}

actual val RunAnywhere.isLLMModelLoaded: Boolean
    get() =
        CppBridgeModelLifecycleProto.snapshot(SDKComponent.SDK_COMPONENT_LLM)
            ?.let {
                it.state == ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY &&
                    it.model_id.isNotEmpty()
            } ?: false

actual val RunAnywhere.currentLLMModel: ModelInfo?
    get() {
        val current =
            CppBridgeModelLifecycleProto.currentModel(
                CurrentModelRequest(category = ModelCategory.MODEL_CATEGORY_LANGUAGE),
            ) ?: return null
        current.model?.let { return it }
        val modelId = current.model_id.takeIf { it.isNotEmpty() } ?: return null
        return CppBridgeModelRegistry.get(modelId)
    }

actual suspend fun RunAnywhere.currentSTTModel(): ModelInfo? {
    val current =
        currentModel(CurrentModelRequest(category = ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION))
    current.model?.let { return it }
    val modelId = current.model_id.takeIf { it.isNotEmpty() } ?: return null
    return CppBridgeModelRegistry.get(modelId)
}

actual suspend fun RunAnywhere.loadSTTModel(modelId: String) {
    requireInitialized(this)
    val framework =
        CppBridgeModelRegistry.get(modelId)?.framework
            ?: InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED
    val result =
        loadModel(
            ModelLoadRequest(
                model_id = modelId,
                category = ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
                framework = framework,
            ),
        )
    if (!result.success) {
        throw SDKException.stt(result.error_message.ifBlank { "Failed to load STT model '$modelId'" })
    }
}

// MARK: - Model Assignments
// Deleted in the dead-code wave (KOT-DEAD): the previous
// `fetchModelAssignments` actual built a `ModelAssignmentDto`
// from `CppBridgeModelAssignment.fetchModelAssignments` JSON.
// Both legacy paths were removed. Consumers should call
// `refreshModelRegistry(includeRemoteCatalog = true)` followed by
// `availableModels()` for the proto-backed catalog refresh.
