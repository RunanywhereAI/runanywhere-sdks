/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * DownloadProgress / DownloadStage / DownloadState are generated from
 * `idl/download_service.proto` via Wire. This file exposes the small amount
 * of Kotlin sugar (factory helpers + stage weighting) that SDK consumers
 * use. Mirrors iOS:
 * Sources/RunAnywhere/Infrastructure/Download/Models/Output/DownloadProgress.swift
 */

package com.runanywhere.sdk.infrastructure.download.models.output

import ai.runanywhere.proto.v1.DownloadProgress
import ai.runanywhere.proto.v1.DownloadStage
import ai.runanywhere.proto.v1.DownloadState

// MARK: - Stage Helpers

/** Display name for UI. */
val DownloadStage.displayName: String
    get() =
        when (this) {
            DownloadStage.DOWNLOAD_STAGE_UNSPECIFIED -> "Pending"
            DownloadStage.DOWNLOAD_STAGE_DOWNLOADING -> "Downloading"
            DownloadStage.DOWNLOAD_STAGE_EXTRACTING -> "Extracting"
            DownloadStage.DOWNLOAD_STAGE_VALIDATING -> "Validating"
            DownloadStage.DOWNLOAD_STAGE_COMPLETED -> "Completed"
        }

/**
 * Weight of this stage for overall progress calculation.
 * Download: 0-80%, Extraction: 80-95%, Validation: 95-99%, Completed: 100%.
 */
val DownloadStage.progressRange: Pair<Double, Double>
    get() =
        when (this) {
            DownloadStage.DOWNLOAD_STAGE_DOWNLOADING -> 0.0 to 0.80
            DownloadStage.DOWNLOAD_STAGE_EXTRACTING -> 0.80 to 0.95
            DownloadStage.DOWNLOAD_STAGE_VALIDATING -> 0.95 to 0.99
            DownloadStage.DOWNLOAD_STAGE_COMPLETED -> 1.0 to 1.0
            DownloadStage.DOWNLOAD_STAGE_UNSPECIFIED -> 0.0 to 0.0
        }

// MARK: - Progress Helpers

/**
 * Legacy percentage convenience: returns stage progress for the
 * download stage, and the overall progress everywhere else.
 */
val DownloadProgress.percentage: Double
    get() =
        when (stage) {
            DownloadStage.DOWNLOAD_STAGE_DOWNLOADING -> stage_progress.toDouble()
            else -> overall_progress.toDouble()
        }

/** Download speed (bytes/sec). `null` when unknown. */
val DownloadProgress.speed: Double?
    get() = if (overall_speed_bps > 0f) overall_speed_bps.toDouble() else null

/** Estimated time remaining (seconds). `null` when unknown. */
val DownloadProgress.estimatedTimeRemainingSeconds: Double?
    get() = if (eta_seconds >= 0L) eta_seconds.toDouble() else null

// MARK: - Factories

/** Progress for the extraction stage. */
fun DownloadProgress.Companion.extraction(
    modelId: String,
    progress: Double,
    totalBytes: Long = 0L,
): DownloadProgress =
    DownloadProgress(
        model_id = modelId,
        stage = DownloadStage.DOWNLOAD_STAGE_EXTRACTING,
        state = DownloadState.DOWNLOAD_STATE_EXTRACTING,
        bytes_downloaded = (progress * totalBytes.toDouble()).toLong(),
        total_bytes = totalBytes,
        stage_progress = progress.toFloat(),
        eta_seconds = -1L,
    )

/** Completed progress. */
fun DownloadProgress.Companion.completed(
    modelId: String = "",
    totalBytes: Long,
): DownloadProgress =
    DownloadProgress(
        model_id = modelId,
        stage = DownloadStage.DOWNLOAD_STAGE_COMPLETED,
        state = DownloadState.DOWNLOAD_STATE_COMPLETED,
        bytes_downloaded = totalBytes,
        total_bytes = totalBytes,
        stage_progress = 1.0f,
        eta_seconds = 0L,
    )

/**
 * Failed progress. The canonical proto uses a string error message
 * rather than a Throwable; we capture `message ?: toString()`.
 */
fun DownloadProgress.Companion.failed(
    error: Throwable,
    modelId: String = "",
    bytesDownloaded: Long = 0L,
    totalBytes: Long = 0L,
): DownloadProgress =
    DownloadProgress(
        model_id = modelId,
        stage = DownloadStage.DOWNLOAD_STAGE_DOWNLOADING,
        state = DownloadState.DOWNLOAD_STATE_FAILED,
        bytes_downloaded = bytesDownloaded,
        total_bytes = totalBytes,
        stage_progress = 0f,
        eta_seconds = -1L,
        error_message = error.message ?: error.toString(),
    )

/** Failed progress from a raw error string. */
fun DownloadProgress.Companion.failed(
    error: String,
    modelId: String = "",
    bytesDownloaded: Long = 0L,
    totalBytes: Long = 0L,
): DownloadProgress =
    DownloadProgress(
        model_id = modelId,
        stage = DownloadStage.DOWNLOAD_STAGE_DOWNLOADING,
        state = DownloadState.DOWNLOAD_STATE_FAILED,
        bytes_downloaded = bytesDownloaded,
        total_bytes = totalBytes,
        stage_progress = 0f,
        eta_seconds = -1L,
        error_message = error,
    )
