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
import ai.runanywhere.proto.v1.DownloadProgress
import ai.runanywhere.proto.v1.DownloadStartRequest
import ai.runanywhere.proto.v1.DownloadState
import ai.runanywhere.proto.v1.DownloadSubscribeRequest
import ai.runanywhere.proto.v1.ModelImportRequest
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

private val downloadLogger = SDKLogger("RunAnywhere.Download")

fun RunAnywhere.downloadModel(model: RAModelInfo): Flow<DownloadProgress> =
    flow {
        if (!RunAnywhere.isInitialized) {
            throw SDKException.notInitialized("SDK not initialized")
        }

        val planRequest =
            DownloadPlanRequest(
                model_id = model.id,
                model = model,
                resume_existing = true,
                validate_existing_bytes = true,
                verify_checksums = !model.checksum_sha256.isNullOrBlank(),
            )

        val plan =
            CppBridgeDownload.plan(planRequest)
                ?: throw SDKException.operation("Unable to create a download plan for ${model.id}")
        if (!plan.can_start) {
            throw SDKException.operation(
                "Download plan rejected for ${model.id}: ${plan.error_message.ifBlank { "plan not startable" }}",
            )
        }

        val startRequest =
            DownloadStartRequest(
                model_id = model.id,
                plan = plan,
                resume = plan.can_resume,
                resume_token = plan.resume_token,
                // Commons currently owns planning/progress but not the final registry
                // mutation behind this flag. Mirror Swift: leave it false and rely on
                // explicit registry updates if needed by callers.
                update_registry_on_completion = false,
            )

        val startResult =
            CppBridgeDownload.start(startRequest)
                ?: throw SDKException.operation("Download start returned null for ${model.id}")
        if (!startResult.accepted) {
            throw SDKException.operation(
                "Download could not be started for ${model.id}: ${startResult.error_message.ifBlank { "rejected" }}",
            )
        }

        downloadLogger.info("⬇️ Download accepted for ${model.id} (task=${startResult.task_id})")

        startResult.initial_progress?.let { initial ->
            emit(initial)
            if (isTerminal(initial)) {
                if (initial.state == DownloadState.DOWNLOAD_STATE_COMPLETED) {
                    persistDownloadCompletion(model, initial)
                }
                return@flow
            }
        }

        val subscribeRequest =
            DownloadSubscribeRequest(
                model_id = startResult.model_id.ifBlank { model.id },
                task_id = startResult.task_id,
            )

        // Track whether the C-side download reached a terminal state. When
        // the Flow collector cancels (UI lifecycle, timeout, `take(n)`) before
        // a terminal poll, the finally block fires `rac_download_cancel_proto`
        // so the detached native worker stops instead of leaking bandwidth,
        // battery, and file handles. Mirrors Swift parity for download Flow
        // ownership: the public Flow owns the lifetime of the native task.
        var reachedTerminal = false
        try {
            while (true) {
                delay(250)
                val progress = CppBridgeDownload.pollProgress(subscribeRequest) ?: continue
                emit(progress)
                if (isTerminal(progress)) {
                    reachedTerminal = true
                    if (progress.state == DownloadState.DOWNLOAD_STATE_FAILED) {
                        throw SDKException.operation(
                            "Download failed for ${model.id}: ${progress.error_message.ifBlank { "unknown error" }}",
                        )
                    }
                    if (progress.state == DownloadState.DOWNLOAD_STATE_CANCELLED) {
                        throw SDKException.invalidArgument("Download cancelled: ${model.id}")
                    }
                    // DOWNLOAD_STATE_COMPLETED — persist into registry.
                    persistDownloadCompletion(model, progress)
                    return@flow
                }
            }
        } finally {
            if (!reachedTerminal) {
                // withContext(NonCancellable) so the cancellation native
                // hand-off still runs even when the outer coroutine is in
                // cancelling state. Preserve resume bytes (delete_partial=false)
                // so a later download can pick up where this one left off.
                withContext(NonCancellable) {
                    try {
                        CppBridgeDownload.cancel(
                            DownloadCancelRequest(
                                task_id = startResult.task_id,
                                model_id = startResult.model_id.ifBlank { model.id },
                                delete_partial_bytes = false,
                            ),
                        )
                        downloadLogger.info(
                            "Download cancelled by collector for ${model.id} " +
                                "(task=${startResult.task_id})",
                        )
                    } catch (e: Throwable) {
                        downloadLogger.warn(
                            "Failed to cancel native download for ${model.id} " +
                                "(task=${startResult.task_id}): ${e.message}",
                        )
                    }
                }
            }
        }
    }

/**
 * Mirrors Swift `RunAnywhere+Storage.swift:persistDownloadCompletion(model:progress:)`.
 *
 * After a successful download the C++ side has the bytes on disk but the
 * registry's `local_path`/`is_downloaded` flags are not yet set. We patch them
 * via `CppBridgeModelRegistry.importModel(...)` using the proto-canonical
 * `ModelImportRequest` so the next `listModels()` reflects the completed state.
 */
private fun persistDownloadCompletion(model: RAModelInfo, progress: DownloadProgress) {
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
        return
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
            downloadLogger.info("📦 Registered downloaded model ${model.id} at $localPath")
        }
    } catch (e: Exception) {
        downloadLogger.error("Registry import threw for ${model.id}: ${e.message}")
    }
}

private fun isTerminal(p: DownloadProgress): Boolean =
    p.state == DownloadState.DOWNLOAD_STATE_COMPLETED ||
        p.state == DownloadState.DOWNLOAD_STATE_FAILED ||
        p.state == DownloadState.DOWNLOAD_STATE_CANCELLED
