/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public proto-backed SDK event stream API.
 * Mirrors Swift's RunAnywhere+SDKEvents.swift one-to-one.
 */

package com.runanywhere.sdk.public.extensions.Events

import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeSDKEventStream
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.events.SDKEvent

/** Imperative SDK-event surface for cross-SDK parity with Swift. */
fun RunAnywhere.subscribeSDKEvents(handler: (SDKEvent) -> Unit): Long =
    CppBridgeSDKEventStream.subscribe(handler)

fun RunAnywhere.unsubscribeSDKEvents(subscriptionId: Long) {
    CppBridgeSDKEventStream.unsubscribe(subscriptionId)
}

fun RunAnywhere.publishSDKEvent(event: SDKEvent): Boolean =
    CppBridgeSDKEventStream.publish(event) == 0

fun RunAnywhere.pollSDKEvent(): SDKEvent? =
    CppBridgeSDKEventStream.poll()

fun RunAnywhere.publishSDKFailure(
    errorCode: Int,
    message: String,
    component: String,
    operation: String,
    recoverable: Boolean = false,
): Boolean =
    CppBridgeSDKEventStream.publishFailure(errorCode, message, component, operation, recoverable) == 0
