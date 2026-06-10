/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.DownloadCancelRequest
import ai.runanywhere.proto.v1.DownloadCancelResult
import ai.runanywhere.proto.v1.DownloadPlanRequest
import ai.runanywhere.proto.v1.DownloadPlanResult
import ai.runanywhere.proto.v1.DownloadProgress
import ai.runanywhere.proto.v1.DownloadResumeRequest
import ai.runanywhere.proto.v1.DownloadResumeResult
import ai.runanywhere.proto.v1.DownloadStartRequest
import ai.runanywhere.proto.v1.DownloadStartResult
import com.runanywhere.sdk.native.bridge.NativeProtoProgressListener
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.squareup.wire.Message
import com.squareup.wire.ProtoAdapter

private fun <M : Message<M, *>> decodeOrNull(
    adapter: ProtoAdapter<M>,
    bytes: ByteArray?,
    operation: String,
): M? {
    if (bytes == null) return null
    return try {
        adapter.decode(bytes)
    } catch (e: Exception) {
        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.WARN,
            "CppBridgeDownload",
            "Failed to decode $operation result: ${e.message}",
        )
        null
    }
}

/**
 * Thin generated-proto facade over the canonical download workflow ABI.
 *
 * Mirrors iOS [CppBridge+Download.swift](../../../../../../../../../../../../sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Download.swift).
 */
object CppBridgeDownload {
    fun setProgressCallback(onProgress: ((DownloadProgress) -> Boolean)?): Int {
        val listener =
            onProgress?.let {
                NativeProtoProgressListener { bytes ->
                    decodeOrNull(DownloadProgress.ADAPTER, bytes, "downloadProgressCallback")?.let(it) ?: false
                }
            }
        return RunAnywhereBridge.racDownloadSetProgressProtoCallback(listener)
    }

    fun plan(request: DownloadPlanRequest): DownloadPlanResult? =
        decodeOrNull(
            DownloadPlanResult.ADAPTER,
            RunAnywhereBridge.racDownloadPlanProto(DownloadPlanRequest.ADAPTER.encode(request)),
            "downloadPlan",
        )

    fun start(request: DownloadStartRequest): DownloadStartResult? =
        decodeOrNull(
            DownloadStartResult.ADAPTER,
            RunAnywhereBridge.racDownloadStartProto(DownloadStartRequest.ADAPTER.encode(request)),
            "downloadStart",
        )

    fun cancel(request: DownloadCancelRequest): DownloadCancelResult? =
        decodeOrNull(
            DownloadCancelResult.ADAPTER,
            RunAnywhereBridge.racDownloadCancelProto(DownloadCancelRequest.ADAPTER.encode(request)),
            "downloadCancel",
        )

    fun resume(request: DownloadResumeRequest): DownloadResumeResult? =
        decodeOrNull(
            DownloadResumeResult.ADAPTER,
            RunAnywhereBridge.racDownloadResumeProto(DownloadResumeRequest.ADAPTER.encode(request)),
            "downloadResume",
        )

    fun pollProgress(request: ai.runanywhere.proto.v1.DownloadSubscribeRequest): DownloadProgress? =
        decodeOrNull(
            DownloadProgress.ADAPTER,
            RunAnywhereBridge.racDownloadProgressPollProto(
                ai.runanywhere.proto.v1.DownloadSubscribeRequest.ADAPTER
                    .encode(request),
            ),
            "downloadProgressPoll",
        )
}
