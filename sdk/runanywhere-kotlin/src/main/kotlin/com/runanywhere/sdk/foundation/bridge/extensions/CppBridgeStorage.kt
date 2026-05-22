/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.StorageAvailabilityRequest
import ai.runanywhere.proto.v1.StorageAvailabilityResult
import ai.runanywhere.proto.v1.StorageDeletePlan
import ai.runanywhere.proto.v1.StorageDeletePlanRequest
import ai.runanywhere.proto.v1.StorageDeleteRequest
import ai.runanywhere.proto.v1.StorageDeleteResult
import ai.runanywhere.proto.v1.StorageInfoRequest
import ai.runanywhere.proto.v1.StorageInfoResult
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
            "CppBridgeStorage",
            "Failed to decode $operation result: ${e.message}",
        )
        null
    }
}

/**
 * Thin generated-proto facade over the stable storage ABI in commons.
 *
 * Mirrors iOS [CppBridge+Storage.swift](../../../../../../../../../../../../sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Storage.swift).
 */
object CppBridgeStorage {
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
