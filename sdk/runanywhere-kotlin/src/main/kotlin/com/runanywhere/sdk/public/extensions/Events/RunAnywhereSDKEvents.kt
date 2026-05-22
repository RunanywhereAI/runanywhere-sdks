/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public proto-backed SDK event stream API.
 *
 * Mirrors Swift sdk/runanywhere-swift/.../Events/RunAnywhere+SDKEvents.swift.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeSDKEventStream
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RASDKEvent


fun RunAnywhere.subscribeSDKEvents(handler: (RASDKEvent) -> Boolean): Long =
    CppBridgeSDKEventStream.subscribe(handler)

fun RunAnywhere.unsubscribeSDKEvents(subscriptionId: Long) {
    CppBridgeSDKEventStream.unsubscribe(subscriptionId)
}

fun RunAnywhere.publishSDKEvent(event: RASDKEvent): Int =
    CppBridgeSDKEventStream.publish(event)

fun RunAnywhere.pollSDKEvent(): RASDKEvent? =
    CppBridgeSDKEventStream.poll()

fun RunAnywhere.publishSDKFailure(
    errorCode: Int,
    message: String,
    component: String,
    operation: String,
    recoverable: Boolean,
): Int =
    CppBridgeSDKEventStream.publishFailure(
        errorCode = errorCode,
        message = message,
        component = component,
        operation = operation,
        recoverable = recoverable,
    )
