/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Per-domain split of CppBridgeStableProto.kt — owns the canonical
 * `rac_sdk_event_*` proto stream facade. Kept as a top-level object so
 * subscribe/publish/poll callers don't depend on a consolidated file.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.SDKEvent
import com.runanywhere.sdk.native.bridge.NativeProtoProgressListener
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.types.RASDKEvent
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
            "CppBridgeSDKEventStream",
            "Failed to decode $operation result: ${e.message}",
        )
        null
    }
}

/**
 * Thin generated-proto facade over the canonical SDKEvent stream.
 */
object CppBridgeSDKEventStream {
    fun subscribe(onEvent: (RASDKEvent) -> Unit): Long =
        RunAnywhereBridge.racSdkEventSubscribe(
            NativeProtoProgressListener { bytes ->
                decodeOrNull(SDKEvent.ADAPTER, bytes, "sdkEventCallback")?.also(onEvent)
                true
            },
        )

    fun unsubscribe(subscriptionId: Long) {
        RunAnywhereBridge.racSdkEventUnsubscribe(subscriptionId)
    }

    fun publish(event: RASDKEvent): Int =
        RunAnywhereBridge.racSdkEventPublishProto(SDKEvent.ADAPTER.encode(event))

    fun poll(): RASDKEvent? =
        decodeOrNull(SDKEvent.ADAPTER, RunAnywhereBridge.racSdkEventPoll(), "sdkEventPoll")

    fun publishFailure(
        errorCode: Int,
        message: String,
        component: String,
        operation: String,
        recoverable: Boolean,
    ): Int =
        RunAnywhereBridge.racSdkEventPublishFailure(errorCode, message, component, operation, recoverable)

    fun clearQueue(): Int = RunAnywhereBridge.racSdkEventClearQueue()
}
