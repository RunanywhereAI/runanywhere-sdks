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
import ai.runanywhere.proto.v1.DownloadFailureReason
import ai.runanywhere.proto.v1.DownloadPlanRequest
import ai.runanywhere.proto.v1.DownloadPlanResult
import ai.runanywhere.proto.v1.DownloadProgress
import ai.runanywhere.proto.v1.DownloadStartRequest
import ai.runanywhere.proto.v1.DownloadState
import ai.runanywhere.proto.v1.DownloadSubscribeRequest
import ai.runanywhere.proto.v1.ModelGetRequest
import ai.runanywhere.proto.v1.ModelImportRequest
import ai.runanywhere.proto.v1.ModelListRequest
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeDownload
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelRegistry
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RAModelInfo
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext
import java.io.File

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
    downloadLogger.info("Planning download for ${resolvedModel.id}")

    val planRequest =
        DownloadPlanRequest(
            model_id = resolvedModel.id,
            model = resolvedModel,
            resume_existing = true,
            validate_existing_bytes = true,
            verify_checksums = !resolvedModel.checksum_sha256.isNullOrBlank(),
        )

    val plan =
        planDownload(planRequest)
            ?: throw SDKException.operation("Unable to create a download plan for ${resolvedModel.id}")
    if (!plan.can_start) {
        throw SDKException.operation(
            "Download plan rejected for ${resolvedModel.id}: ${plan.error_message.ifBlank { "plan not startable" }}",
        )
    }

    val startRequest =
        DownloadStartRequest(
            model_id = resolvedModel.id,
            plan = plan,
            resume = plan.can_resume,
            resume_token = plan.resume_token,
            // Commons currently owns planning/progress but not the final registry
            // mutation behind this flag. Persist completion explicitly through the
            // generated model import contract below.
            update_registry_on_completion = false,
        )

    val startResult =
        CppBridgeDownload.start(startRequest)
            ?: throw SDKException.operation("Download start returned null for ${resolvedModel.id}")
    if (!startResult.accepted) {
        throw SDKException.operation(
            "Download could not be started for ${resolvedModel.id}: ${startResult.error_message.ifBlank { "rejected" }}",
        )
    }

    downloadLogger.info("Download accepted for ${resolvedModel.id} (task=${startResult.task_id})")

    startResult.initial_progress?.let { initial ->
        if (reportDownloadProgress(initial, onProgress)) {
            return persistDownloadCompletion(resolvedModel, initial)
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
                return persistDownloadCompletion(resolvedModel, progress)
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
fun RunAnywhere.downloadModelFlow(model: RAModelInfo): Flow<DownloadProgress> =
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

private fun planDownload(request: DownloadPlanRequest): DownloadPlanResult? {
    val plan = CppBridgeDownload.plan(request) ?: return null
    if (plan.can_start ||
        plan.failure_reason != DownloadFailureReason.DOWNLOAD_FAILURE_REASON_OVERSIZE_PARTIAL_BYTES
    ) {
        return plan
    }

    for (filePlan in plan.files) {
        val destinationPath = filePlan.destination_path
        if (destinationPath.isBlank()) continue

        val partialFile = File(destinationPath)
        if (partialFile.exists()) {
            if (partialFile.delete()) {
                downloadLogger.warn("Removed oversize partial download at $destinationPath for ${request.model_id}")
            } else {
                downloadLogger.warn("Failed to remove oversize partial download at $destinationPath for ${request.model_id}")
            }
        }
    }

    return CppBridgeDownload.plan(request)
}

/**
 * Mirrors Swift `RunAnywhere+Storage.swift:reportDownloadProgress(_:onProgress:)`.
 * Invokes the progress callback, then returns true when the progress is
 * terminal-completed (so the caller can branch to [persistDownloadCompletion])
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
            throw SDKException.operation(
                "Download failed: ${progress.error_message.ifBlank { "unknown error" }}",
            )
        DownloadState.DOWNLOAD_STATE_CANCELLED ->
            throw SDKException.invalidArgument("Download cancelled")
        else -> false
    }
}

/**
 * Mirrors Swift `RunAnywhere+Storage.swift:persistDownloadCompletion(model:progress:)`.
 *
 * After a successful download the C++ side has the bytes on disk but the
 * registry's `local_path`/`is_downloaded` flags are not yet set. We patch them
 * via `CppBridgeModelRegistry.importModel(...)` using the proto-canonical
 * `ModelImportRequest` so the next `listModels()` reflects the completed state.
 * Returns the terminal [DownloadProgress] so callers can surface it as the
 * function's return value, matching Swift's shape.
 */
private fun persistDownloadCompletion(model: RAModelInfo, progress: DownloadProgress): DownloadProgress {
    val localPath =
        if (progress.local_path.isNotBlank()) {
            progress.local_path
        } else {
            model.local_path
        }
    if (localPath.isBlank()) {
        downloadLogger.warn(
            "Download completed without a local_path for ${model.id}; skipping registry import",
        )
        return progress
    }
    val nowMs = System.currentTimeMillis()
    val importedModel =
        model.copy(
            local_path = localPath,
            is_downloaded = true,
            is_available = true,
            updated_at_unix_ms = nowMs,
        )
    val request =
        ModelImportRequest(
            model = importedModel,
            source_path = localPath,
            overwrite_existing = true,
            copy_into_managed_storage = false,
            validate_before_register = false,
            files = importedModel.multi_file?.files.orEmpty(),
        )
    try {
        val result = CppBridgeModelRegistry.importModel(request)
        if (!result.success) {
            downloadLogger.warn(
                "Registry import failed for ${model.id}: ${result.error_message.ifBlank { "unknown" }}",
            )
        } else {
            downloadLogger.info("Registered downloaded model ${model.id} at $localPath")
        }
    } catch (e: Exception) {
        downloadLogger.error("Registry import threw for ${model.id}: ${e.message}")
    }
    return progress
}
