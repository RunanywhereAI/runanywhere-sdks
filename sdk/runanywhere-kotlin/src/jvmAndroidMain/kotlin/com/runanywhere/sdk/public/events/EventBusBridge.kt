/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actuals for the EventBus native bridge hooks. Wires the
 * canonical native SDKEvent stream (rac_sdk_event_subscribe) into the
 * Kotlin EventBus so consumers see lifecycle, model, error, and other
 * events emitted by C++ commons.
 *
 * Mirrors Swift CppBridge+SDKEvents.swift / EventBus.swift.
 */

package com.runanywhere.sdk.public.events

import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeSDKEventStream
import com.runanywhere.sdk.foundation.errors.CommonsErrorCode
import java.util.concurrent.atomic.AtomicLong

private val logger = SDKLogger("EventBusBridge")

/**
 * Active native subscription id (rac_sdk_event_subscribe handle). Held
 * atomically so [startNativeSubscription] / [stopNativeSubscription] can
 * be called from any thread without coarse locking. Zero means no
 * subscription is currently active.
 */
private val nativeSubscriptionId = AtomicLong(0L)

internal actual fun startNativeSubscription() {
    // Idempotent: if a subscription already exists, leave it in place.
    if (nativeSubscriptionId.get() != 0L) {
        return
    }

    val subscriptionId =
        try {
            // The native callback fires on a JNI thread; we hop straight
            // into MutableSharedFlow.tryEmit (non-suspending) so we never
            // block the caller. Returning true tells the native layer
            // we accepted the event; tryEmit returning false (buffer
            // overrun) is reported up so commons can apply backpressure
            // metrics if it wants to, but we still keep the subscription
            // alive.
            CppBridgeSDKEventStream.subscribe { event ->
                EventBus.emitFromNative(event)
                true
            }
        } catch (e: UnsatisfiedLinkError) {
            logger.warn("Native SDK event subscription unavailable: ${e.message}")
            0L
        } catch (e: Throwable) {
            logger.warn("Native SDK event subscription failed: ${e.message}")
            0L
        }

    if (subscriptionId != 0L) {
        // Lost-race protection: if another thread won and already stored
        // a subscription, immediately tear ours back down to avoid
        // duplicate native subscriptions.
        if (!nativeSubscriptionId.compareAndSet(0L, subscriptionId)) {
            try {
                CppBridgeSDKEventStream.unsubscribe(subscriptionId)
            } catch (_: Throwable) {
                // Best-effort cleanup; swallow.
            }
        } else {
            logger.debug("Native SDK event subscription started (id=$subscriptionId)")
        }
    }
}

internal actual fun stopNativeSubscription() {
    val subscriptionId = nativeSubscriptionId.getAndSet(0L)
    if (subscriptionId == 0L) {
        return
    }
    try {
        CppBridgeSDKEventStream.unsubscribe(subscriptionId)
        logger.debug("Native SDK event subscription stopped (id=$subscriptionId)")
    } catch (e: UnsatisfiedLinkError) {
        // Native lib already torn down; nothing to do.
    } catch (e: Throwable) {
        logger.warn("Native SDK event unsubscribe failed: ${e.message}")
    }
}

internal actual fun publishToNative(event: SDKEvent): Boolean {
    return try {
        CppBridgeSDKEventStream.publish(event) == CommonsErrorCode.RAC_SUCCESS
    } catch (_: UnsatisfiedLinkError) {
        false
    } catch (e: Throwable) {
        logger.warn("Native SDK event publish failed: ${e.message}")
        false
    }
}
