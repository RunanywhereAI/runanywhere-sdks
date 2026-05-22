/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.ComponentLifecycleSnapshot
import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.CurrentModelResult
import ai.runanywhere.proto.v1.ModelLoadRequest
import ai.runanywhere.proto.v1.ModelLoadResult
import ai.runanywhere.proto.v1.ModelUnloadRequest
import ai.runanywhere.proto.v1.ModelUnloadResult
import ai.runanywhere.proto.v1.SDKComponent
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.types.RAModelLoadRequest
import com.runanywhere.sdk.public.types.RAModelLoadResult
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
            "CppBridgeModelLifecycle",
            "Failed to decode $operation result: ${e.message}",
        )
        null
    }
}

/**
 * Thin generated-proto facade over the canonical model lifecycle ABI.
 *
 * Mirrors iOS [CppBridge+ModelLifecycle.swift](../../../../../../../../../../../../sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+ModelLifecycle.swift).
 */
object CppBridgeModelLifecycle {
    fun load(request: RAModelLoadRequest): RAModelLoadResult? =
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

    fun reset(): Int = RunAnywhereBridge.racModelLifecycleReset()
}
