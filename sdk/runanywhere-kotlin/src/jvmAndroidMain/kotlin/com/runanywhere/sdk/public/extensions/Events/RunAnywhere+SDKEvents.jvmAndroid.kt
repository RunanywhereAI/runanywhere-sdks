/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actuals for the proto-backed SDK event stream API.
 * Forwards to the canonical CppBridgeSDKEventStream facade.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeSDKEventStream
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RASDKEvent

actual fun RunAnywhere.subscribeSDKEvents(handler: (RASDKEvent) -> Boolean): Long =
    CppBridgeSDKEventStream.subscribe(handler)

actual fun RunAnywhere.unsubscribeSDKEvents(subscriptionId: Long) {
    CppBridgeSDKEventStream.unsubscribe(subscriptionId)
}

actual fun RunAnywhere.publishSDKEvent(event: RASDKEvent): Int =
    CppBridgeSDKEventStream.publish(event)

actual fun RunAnywhere.pollSDKEvent(): RASDKEvent? =
    CppBridgeSDKEventStream.poll()

actual fun RunAnywhere.publishSDKFailure(
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
