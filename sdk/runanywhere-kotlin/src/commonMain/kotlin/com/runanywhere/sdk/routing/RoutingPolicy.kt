/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * User-level routing preference enum.
 */
package com.runanywhere.sdk.routing

/**
 * User-level routing preference passed via STTOptions (or future LLMOptions, TTSOptions).
 *
 * Applied after hard-gate condition filtering. Policies further restrict or reorder
 * the candidate set — they never override hard conditions (e.g., NetworkRequired).
 */
enum class RoutingPolicy {
    /** Router decides: local wins by default, cloud is fallback. */
    AUTO,

    /** Prefer local backends. Cloud used only if no local candidate qualifies. */
    PREFER_LOCAL,

    /** Prefer highest-quality backend regardless of cost or locality. */
    PREFER_ACCURACY,

    /** Only cloud backends. Local backends excluded entirely. */
    CLOUD_ONLY,

    /** Only local backends. Cloud excluded entirely — no fallback. */
    LOCAL_ONLY,

    /** Attempt the framework named in preferredFramework first, then AUTO. */
    FRAMEWORK_PREFERRED,
}
