/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Runtime context snapshot for routing decisions.
 */
package com.runanywhere.sdk.routing

import com.runanywhere.sdk.core.types.InferenceFramework

/**
 * Runtime snapshot evaluated by the router for every request.
 *
 * Constructed fresh per request so conditions always see current state
 * (network availability, model load state, etc.).
 */
data class RoutingContext(
    /** True if the device has working internet connectivity right now. */
    val isNetworkAvailable: Boolean,

    /** User's routing policy (default: AUTO). */
    val routingPolicy: RoutingPolicy,

    /**
     * Explicit framework preference from the request options.
     * When set, backends matching this framework receive a large score bonus.
     */
    val preferredFramework: InferenceFramework? = null,

    /**
     * Arbitrary key-value extras for backend-specific conditions.
     * Use sparingly — prefer typed RoutingCondition subclasses.
     */
    val extras: Map<String, Any> = emptyMap(),
)
