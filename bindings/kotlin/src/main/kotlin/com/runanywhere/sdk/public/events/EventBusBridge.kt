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

import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeSDKEventStream
import com.runanywhere.sdk.infrastructure.logging.SDKLogger

private val logger = SDKLogger("EventBusBridge")

internal class NativeSubscriptionLifecycle(
    private val subscribe: () -> Long,
    private val unsubscribe: (Long) -> Unit,
) {
    private val lock = Any()
    private var subscriptionId = 0L

    fun start(): Boolean =
        synchronized(lock) {
            if (subscriptionId != 0L) return@synchronized false
            val newSubscriptionId = subscribe()
            if (newSubscriptionId == 0L) return@synchronized false
            subscriptionId = newSubscriptionId
            true
        }

    fun stop(): Boolean =
        synchronized(lock) {
            if (subscriptionId == 0L) return@synchronized false
            unsubscribe(subscriptionId)
            // Keep ownership when unsubscribe throws so shutdown can retry.
            subscriptionId = 0L
            true
        }
}

private val nativeSubscriptionLifecycle =
    NativeSubscriptionLifecycle(
        subscribe = {
            // The native callback fires on a JNI thread; MutableSharedFlow.tryEmit
            // is non-suspending, so this never blocks the publisher.
            CppBridgeSDKEventStream.subscribe { event -> EventBus.emitFromNative(event) }
        },
        unsubscribe = CppBridgeSDKEventStream::unsubscribe,
    )

internal fun startNativeSubscription() {
    try {
        if (nativeSubscriptionLifecycle.start()) {
            logger.debug("Native SDK event subscription started")
        }
    } catch (_: UnsatisfiedLinkError) {
        logger.warn("Native SDK event subscription unavailable")
    } catch (_: Throwable) {
        logger.warn("Native SDK event subscription failed")
    }
}

internal fun stopNativeSubscription(
    lifecycle: NativeSubscriptionLifecycle = nativeSubscriptionLifecycle,
): Boolean {
    try {
        val stopped = lifecycle.stop()
        if (stopped) {
            logger.debug("Native SDK event subscription stopped")
        }
        return stopped
    } catch (error: Throwable) {
        // A thrown unsubscribe leaves NativeSubscriptionLifecycle owning the
        // id. Propagate so CppBridge keeps shutdown retry-required; swallowing
        // here would make the next start silently reuse a retired lifetime.
        logger.warn("Native SDK event unsubscribe failed")
        throw error
    }
}

internal fun publishToNative(event: SDKEvent): Boolean {
    return try {
        CppBridgeSDKEventStream.publish(event) == 0
    } catch (_: UnsatisfiedLinkError) {
        false
    } catch (_: Throwable) {
        logger.warn("Native SDK event publish failed")
        false
    }
}
