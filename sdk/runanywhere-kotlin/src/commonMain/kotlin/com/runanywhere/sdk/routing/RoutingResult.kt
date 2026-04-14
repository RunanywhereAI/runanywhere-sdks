/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Routing metadata returned alongside transcription results.
 */
package com.runanywhere.sdk.routing

/**
 * Metadata about the routing decision for a request.
 *
 * Returned alongside the actual result so the UI can display
 * which backend handled the request and whether it was a fallback.
 */
data class RoutingResult(
    /** The backend that produced the final result. */
    val backendId: String,

    /** Human-readable backend name for display. */
    val backendName: String,

    /** True if the result came from a fallback after the primary backend's
     *  confidence was below the threshold. */
    val wasFallback: Boolean = false,

    /** Confidence score from the primary backend (before fallback decision).
     *  Null if no confidence check was performed. */
    val primaryConfidence: Float? = null,

    /** The confidence threshold used for the fallback decision. */
    val confidenceThreshold: Float? = null,
)
