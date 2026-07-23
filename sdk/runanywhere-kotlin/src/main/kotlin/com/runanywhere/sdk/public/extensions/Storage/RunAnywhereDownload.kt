/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public download API mirroring Swift `RunAnywhere.downloadModel(...)` in
 * `RunAnywhere+Storage.swift`. Executes the canonical plan → start → poll
 * pattern over `CppBridge.Download`.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.DownloadCancelRequest
import ai.runanywhere.proto.v1.DownloadPlanRequest
import ai.runanywhere.proto.v1.DownloadPlanResult
import ai.runanywhere.proto.v1.DownloadProgress
import ai.runanywhere.proto.v1.DownloadStage
import ai.runanywhere.proto.v1.DownloadStartRequest
import ai.runanywhere.proto.v1.DownloadState
import ai.runanywhere.proto.v1.DownloadSubscribeRequest
import ai.runanywhere.proto.v1.ErrorCategory
import ai.runanywhere.proto.v1.ErrorCode
import ai.runanywhere.proto.v1.ModelGetRequest
import ai.runanywhere.proto.v1.ModelListRequest
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeDownload
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RAModelInfo
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext

private val downloadLogger = SDKLogger("RunAnywhere.Download")

/**
 * Download a registered model. Mirrors Swift `RunAnywhere.downloadModel(_:onProgress:)`:
 * the suspend function owns the plan → start → poll → import loop and returns the
 * terminal [DownloadProgress] so callers can use `val terminal = downloadModel(model) { ui.update(it) }`.
 *
 * Cancellation propagates to the native worker via [CppBridgeDownload.cancel], preserving
 * resume bytes for a later retry.
 */
suspend fun RunAnywhere.downloadModel(
    model: RAModelInfo,
    onProgress: (suspend (DownloadProgress) -> Unit)? = null,
): DownloadProgress {
    if (!RunAnywhere.isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    ensureServicesReady()
    val resolvedModel = resolveModelForDownload(model)
    // Commons computes the compatibility verdict from the registry entry, so the
    // preflight can only gate a model that is actually registered. A direct download
    // of a model absent from the registry (resolveModelForDownload's caller-supplied
    // fallback) has no registry entry to evaluate and must proceed straight to
    // planning -- mirroring Swift's downloadModel, which runs no preflight. Gating on
    // registry presence would reject valid direct downloads.
    if (!isModelRegistered(resolvedModel.id)) {
        return downloadCompatibleModel(resolvedModel, onProgress)
    }
    return withModelCompatibilityPreflight(
        operation = ModelCompatibilityOperation.DOWNLOAD,
        resultProvider = { checkModelCompatibility(resolvedModel.id) },
    ) {
        downloadCompatibleModel(resolvedModel, onProgress)
    }
}

private suspend fun RunAnywhere.downloadCompatibleModel(
    resolvedModel: RAModelInfo,
    onProgress: (suspend (DownloadProgress) -> Unit)?,
): DownloadProgress {
    downloadLogger.info("Planning download for ${resolvedModel.id}")

    val planRequest =
        DownloadPlanRequest(
            model_id = resolvedModel.id,
            model = resolvedModel,
            resume_existing = true,
            validate_existing_bytes = true,
            verify_checksums = !resolvedModel.checksum_sha256.isNullOrBlank(),
        )

    val plan = planDownload(planRequest)
    if (plan == null || !plan.can_start) {
        val message = plan?.error_message.orEmpty().ifBlank { "Unable to create a download plan" }
        downloadLogger.error("Download plan rejected for ${resolvedModel.id}: $message")
        throw SDKException.make(
            code = ErrorCode.ERROR_CODE_DOWNLOAD_FAILED,
            message = message,
            category = ErrorCategory.ERROR_CATEGORY_NETWORK,
            shouldLog = false,
        )
    }

    val startRequest =
        DownloadStartRequest(
            model_id = resolvedModel.id,
            plan = plan,
            resume = plan.can_resume,
            resume_token = plan.resume_token,
            // Commons owns the completion registry mutation: the orchestrator's
            // self-heal calls rac_model_registry_update_download_status, which
            // also persists the durable .rac-manifest.binpb sidecar restored on
            // the next cold launch.
            update_registry_on_completion = true,
        )

    val startResult = CppBridgeDownload.start(startRequest)
    if (startResult == null || !startResult.accepted) {
        val message = startResult?.error_message.orEmpty().ifBlank { "The download could not be started" }
        downloadLogger.error("Download start rejected for ${resolvedModel.id}: $message")
        throw SDKException.make(
            code = ErrorCode.ERROR_CODE_DOWNLOAD_FAILED,
            message = message,
            category = ErrorCategory.ERROR_CATEGORY_NETWORK,
            shouldLog = false,
        )
    }

    downloadLogger.info("Download accepted for ${resolvedModel.id} (task=${startResult.task_id})")

    startResult.initial_progress?.let { initial ->
        if (reportDownloadProgress(initial, onProgress)) {
            return initial
        }
    }

    val subscribeRequest =
        DownloadSubscribeRequest(
            model_id = startResult.model_id.ifBlank { resolvedModel.id },
            task_id = startResult.task_id,
        )

    // Track whether the C-side download reached a terminal state. When the
    // coroutine is cancelled before a terminal poll, the finally block fires
    // rac_download_cancel_proto so the detached native worker stops instead of
    // leaking bandwidth, battery, and file handles.
    var reachedTerminal = false
    try {
        while (true) {
            delay(250)
            val progress = CppBridgeDownload.pollProgress(subscribeRequest) ?: continue
            if (reportDownloadProgress(progress, onProgress)) {
                reachedTerminal = true
                return progress
            }
        }
    } finally {
        if (!reachedTerminal) {
            // withContext(NonCancellable) so the cancellation native hand-off
            // still runs even when the outer coroutine is in cancelling state.
            // Preserve resume bytes (delete_partial=false) so a later download
            // can pick up where this one left off.
            withContext(NonCancellable) {
                try {
                    CppBridgeDownload.cancel(
                        DownloadCancelRequest(
                            task_id = startResult.task_id,
                            model_id = startResult.model_id.ifBlank { resolvedModel.id },
                            delete_partial_bytes = false,
                        ),
                    )
                    downloadLogger.info(
                        "Download cancelled for ${resolvedModel.id} (task=${startResult.task_id})",
                    )
                } catch (e: Throwable) {
                    downloadLogger.warn(
                        "Failed to cancel native download for ${resolvedModel.id} " +
                            "(task=${startResult.task_id}): ${e.message}",
                    )
                }
            }
        }
    }
}

/**
 * Flow-shaped convenience wrapper around [downloadModel]. Collects the suspend+callback
 * form into a cold [Flow] for Kotlin consumers who prefer reactive collection.
 */
fun RunAnywhere.downloadModelStream(model: RAModelInfo): Flow<DownloadProgress> =
    flow {
        downloadModel(model) { progress -> emit(progress) }
    }

private suspend fun RunAnywhere.resolveModelForDownload(model: RAModelInfo): RAModelInfo {
    val getResult = getModel(ModelGetRequest(model_id = model.id))
    if (getResult.found) {
        val registryModel = getResult.model ?: return model
        if (!registryModel.download_url.isNullOrBlank() || model.download_url.isNullOrBlank()) {
            return registryModel
        }
        return model
    }

    val listResult = listModels(ModelListRequest())
    if (!listResult.success) return model
    val listed = listResult.models?.models?.firstOrNull { it.id == model.id } ?: return model
    if (!listed.download_url.isNullOrBlank() || model.download_url.isNullOrBlank()) {
        return listed
    }
    return model
}

// True only when commons can produce a compatibility verdict for [modelId] (it
// derives the verdict from the registry entry). Direct downloads of unregistered
// models return false and skip the resource preflight.
private suspend fun RunAnywhere.isModelRegistered(modelId: String): Boolean =
    getModel(ModelGetRequest(model_id = modelId)).found

// Oversize-partial self-healing happens inside the commons planner
// (validate_existing_bytes deletes stale partials and replans as a fresh
// download), so no Kotlin-side retry loop is needed.
private fun planDownload(request: DownloadPlanRequest): DownloadPlanResult? = CppBridgeDownload.plan(request)

/**
 * Mirrors Swift `RunAnywhere+Storage.swift:reportDownloadProgress(_:onProgress:)`.
 * Invokes the progress callback, then returns true when the progress is
 * terminal-completed (commons persists completion + the manifest sidecar)
 * and throws on failure or cancellation.
 */
private suspend fun reportDownloadProgress(
    progress: DownloadProgress,
    onProgress: (suspend (DownloadProgress) -> Unit)?,
): Boolean {
    onProgress?.invoke(progress)
    return when (progress.state) {
        DownloadState.DOWNLOAD_STATE_COMPLETED -> true
        DownloadState.DOWNLOAD_STATE_FAILED ->
            throw SDKException.make(
                code = ErrorCode.ERROR_CODE_DOWNLOAD_FAILED,
                message = progress.error_message.ifBlank { "Download failed" },
                category = ErrorCategory.ERROR_CATEGORY_NETWORK,
                shouldLog = false,
            )
        DownloadState.DOWNLOAD_STATE_CANCELLED ->
            throw SDKException.make(
                code = ErrorCode.ERROR_CODE_CANCELLED,
                message = "Download cancelled",
                category = ErrorCategory.ERROR_CATEGORY_NETWORK,
            )
        else -> progress.stage == DownloadStage.DOWNLOAD_STAGE_COMPLETED
    }
}
