/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public proto-backed SDK event stream API.
 *
 * Mirrors Swift sdk/runanywhere-swift/.../Events/RunAnywhere+SDKEvents.swift.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RASDKEvent

/**
 * Subscribe to canonical SDK events emitted by the C++ event stream.
 *
 * The [handler] is invoked for every published [SDKEvent]. Returning `true`
 * keeps the subscription active; returning `false` requests the C++ layer
 * to remove it on the next poll.
 *
 * @return The subscription identifier — pass this to [unsubscribeSDKEvents]
 *         to detach early.
 */
expect fun RunAnywhere.subscribeSDKEvents(handler: (RASDKEvent) -> Boolean): Long

/**
 * Detach a previously registered SDK event subscription.
 *
 * @param subscriptionId The handle returned by [subscribeSDKEvents].
 */
expect fun RunAnywhere.unsubscribeSDKEvents(subscriptionId: Long)

/**
 * Publish an [SDKEvent] through the canonical C++ event stream.
 *
 * @return Native result code (`RAC_SUCCESS = 0` on success).
 */
expect fun RunAnywhere.publishSDKEvent(event: RASDKEvent): Int

/**
 * Poll the next pending [SDKEvent] from the C++ event queue.
 *
 * @return The next available event, or `null` when the queue is empty.
 */
expect fun RunAnywhere.pollSDKEvent(): RASDKEvent?

/**
 * Publish a structured failure event.
 *
 * @return Native result code (`RAC_SUCCESS = 0` on success).
 */
expect fun RunAnywhere.publishSDKFailure(
    errorCode: Int,
    message: String,
    component: String,
    operation: String,
    recoverable: Boolean = false,
): Int
