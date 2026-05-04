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
import ai.runanywhere.proto.v1.ComponentLifecycleSnapshot
import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.CurrentModelResult
import ai.runanywhere.proto.v1.ModelLoadRequest
import ai.runanywhere.proto.v1.ModelLoadResult
import ai.runanywhere.proto.v1.ModelUnloadRequest
import ai.runanywhere.proto.v1.ModelUnloadResult
import ai.runanywhere.proto.v1.SDKEvent
import ai.runanywhere.proto.v1.StorageAvailabilityRequest
import ai.runanywhere.proto.v1.StorageAvailabilityResult
import ai.runanywhere.proto.v1.StorageDeletePlan
import ai.runanywhere.proto.v1.StorageDeletePlanRequest
import ai.runanywhere.proto.v1.StorageDeleteRequest
import ai.runanywhere.proto.v1.StorageDeleteResult
import ai.runanywhere.proto.v1.StorageInfoRequest
import ai.runanywhere.proto.v1.StorageInfoResult
import ai.runanywhere.proto.v1.SDKComponent
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
            "CppBridgeStableProto",
            "Failed to decode $operation result: ${e.message}",
        )
        null
    }
}

/**
 * Thin generated-proto facade over the stable storage ABI in commons.
 */
object CppBridgeStorageProto {
    fun info(request: StorageInfoRequest): StorageInfoResult? =
        decodeOrNull(
            StorageInfoResult.ADAPTER,
            RunAnywhereBridge.racStorageInfoProto(StorageInfoRequest.ADAPTER.encode(request)),
            "storageInfo",
        )

    fun availability(request: StorageAvailabilityRequest): StorageAvailabilityResult? =
        decodeOrNull(
            StorageAvailabilityResult.ADAPTER,
            RunAnywhereBridge.racStorageAvailabilityProto(StorageAvailabilityRequest.ADAPTER.encode(request)),
            "storageAvailability",
        )

    fun deletePlan(request: StorageDeletePlanRequest): StorageDeletePlan? =
        decodeOrNull(
            StorageDeletePlan.ADAPTER,
            RunAnywhereBridge.racStorageDeletePlanProto(StorageDeletePlanRequest.ADAPTER.encode(request)),
            "storageDeletePlan",
        )

    fun delete(request: StorageDeleteRequest): StorageDeleteResult? =
        decodeOrNull(
            StorageDeleteResult.ADAPTER,
            RunAnywhereBridge.racStorageDeleteProto(StorageDeleteRequest.ADAPTER.encode(request)),
            "storageDelete",
        )
}

/**
 * Thin generated-proto facade over the canonical SDKEvent stream.
 */
object CppBridgeSDKEventStream {
    fun subscribe(onEvent: (SDKEvent) -> Boolean): Long =
        RunAnywhereBridge.racSdkEventSubscribe(
            NativeProtoProgressListener { bytes ->
                decodeOrNull(SDKEvent.ADAPTER, bytes, "sdkEventCallback")?.let(onEvent) ?: false
            },
        )

    fun unsubscribe(subscriptionId: Long) {
        RunAnywhereBridge.racSdkEventUnsubscribe(subscriptionId)
    }

    fun publish(event: SDKEvent): Int =
        RunAnywhereBridge.racSdkEventPublishProto(SDKEvent.ADAPTER.encode(event))

    fun poll(): SDKEvent? =
        decodeOrNull(SDKEvent.ADAPTER, RunAnywhereBridge.racSdkEventPoll(), "sdkEventPoll")

    fun publishFailure(
        errorCode: Int,
        message: String,
        component: String,
        operation: String,
        recoverable: Boolean,
    ): Int =
        RunAnywhereBridge.racSdkEventPublishFailure(errorCode, message, component, operation, recoverable)
}

/**
 * Thin generated-proto facade over the canonical model lifecycle ABI.
 */
object CppBridgeModelLifecycleProto {
    fun load(request: ModelLoadRequest): ModelLoadResult? =
        decodeOrNull(
            ModelLoadResult.ADAPTER,
            RunAnywhereBridge.racModelLifecycleLoadProto(ModelLoadRequest.ADAPTER.encode(request)),
            "modelLifecycleLoad",
        )

    fun unload(request: ModelUnloadRequest): ModelUnloadResult? =
        decodeOrNull(
            ModelUnloadResult.ADAPTER,
            RunAnywhereBridge.racModelLifecycleUnloadProto(ModelUnloadRequest.ADAPTER.encode(request)),
            "modelLifecycleUnload",
        )

    fun currentModel(request: CurrentModelRequest): CurrentModelResult? =
        decodeOrNull(
            CurrentModelResult.ADAPTER,
            RunAnywhereBridge.racModelLifecycleCurrentModelProto(CurrentModelRequest.ADAPTER.encode(request)),
            "modelLifecycleCurrentModel",
        )

    fun snapshot(component: SDKComponent): ComponentLifecycleSnapshot? =
        decodeOrNull(
            ComponentLifecycleSnapshot.ADAPTER,
            RunAnywhereBridge.racComponentLifecycleSnapshotProto(component.value),
            "componentLifecycleSnapshot",
        )
}

/**
 * Thin generated-proto facade over the canonical download workflow ABI.
 */
object CppBridgeDownloadProto {
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
                ai.runanywhere.proto.v1.DownloadSubscribeRequest.ADAPTER.encode(request),
            ),
            "downloadProgressPoll",
        )
}
