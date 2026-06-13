/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * UI-oriented helpers for the proto-generated DownloadStage enum.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.DownloadStage

data class DownloadStageProgressRange(
    val start: Double,
    val end: Double,
)

val DownloadStage.displayName: String
    get() =
        when (this) {
            DownloadStage.DOWNLOAD_STAGE_UNSPECIFIED -> "Pending"
            DownloadStage.DOWNLOAD_STAGE_DOWNLOADING -> "Downloading"
            DownloadStage.DOWNLOAD_STAGE_EXTRACTING -> "Extracting"
            DownloadStage.DOWNLOAD_STAGE_VALIDATING -> "Validating"
            DownloadStage.DOWNLOAD_STAGE_COMPLETED -> "Completed"
        }

val DownloadStage.progressRange: DownloadStageProgressRange
    get() =
        when (this) {
            DownloadStage.DOWNLOAD_STAGE_DOWNLOADING -> DownloadStageProgressRange(0.0, 0.80)
            DownloadStage.DOWNLOAD_STAGE_EXTRACTING -> DownloadStageProgressRange(0.80, 0.95)
            DownloadStage.DOWNLOAD_STAGE_VALIDATING -> DownloadStageProgressRange(0.95, 0.99)
            DownloadStage.DOWNLOAD_STAGE_COMPLETED -> DownloadStageProgressRange(1.0, 1.0)
            DownloadStage.DOWNLOAD_STAGE_UNSPECIFIED -> DownloadStageProgressRange(0.0, 0.0)
        }
