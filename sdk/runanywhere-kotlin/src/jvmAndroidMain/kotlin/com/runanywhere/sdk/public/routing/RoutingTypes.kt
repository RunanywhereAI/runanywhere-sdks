/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public dev-facing routing types. All routing logic lives in C++ commons —
 * these are pure data classes that cross the JNI boundary as primitives.
 */
package com.runanywhere.sdk.public.routing

/**
 * Capability that a hybrid router dispatches. Values match
 * `rac_routed_capability_t` in commons; do not reorder.
 */
enum class Capability(val value: Int) {
    STT(1),
    LLM(2),
    VLM(3),
    TTS(4),
    VAD(5),
}

/**
 * Routing policy — controls how the router orders eligible candidates.
 *
 * Built-in policies map directly to `rac_routing_policy_t`. [Custom] lets the
 * caller supply a scoring lambda; the router calls it per candidate per
 * request and picks the highest score.
 */
sealed class Policy(val value: Int) {
    object Auto : Policy(0)
    object LocalOnly : Policy(1)
    object CloudOnly : Policy(2)
    object PreferLocal : Policy(3)
    object PreferAccuracy : Policy(4)
    object FrameworkPreferred : Policy(5)

    /**
     * Custom scoring fn. Returns higher score → higher rank.
     * The lambda must be thread-safe (router may call it from request threads).
     *
     * NOTE: custom-policy fn pointers across JNI are not yet wired in this
     * Commons release. Until then, [Custom] is treated as [Auto] internally
     * and a warning is logged. Use built-in policies in the meantime.
     */
    class Custom(val score: (BackendDescriptor, RoutingContext) -> Int) : Policy(99)
}

/**
 * Eligibility predicate. Built-in conditions are encoded into the descriptor
 * as flags ([BackendDescriptor.isLocalOnly], etc.). [Custom] is reserved for
 * future expansion (custom condition fn pointers across JNI are not yet
 * wired — declare with built-in conditions for now).
 */
sealed class Condition {
    object LocalOnly : Condition()
    object NetworkRequired : Condition()
    data class QualityTier(val tier: Int) : Condition()
    data class CostModel(val centsPerMinute: Float) : Condition()
    data class ModelAvailability(val modelId: String, val check: () -> Boolean) : Condition()
    class Custom(val desc: String, val check: (RoutingContext) -> Boolean) : Condition()
}

/**
 * Per-request routing context. Threaded into eligibility filtering and
 * scoring; backends never see this directly.
 */
data class RoutingContext(
    val isOnline: Boolean,
    val policy: Policy = Policy.Auto,
    val preferredFramework: String? = null,
)

/**
 * Backend metadata as registered with a router. Carries the routing-level
 * info; the actual service handle (component) is passed alongside via the
 * capability-specific [HybridRouter] register fns.
 */
data class BackendDescriptor(
    val moduleId: String,
    val moduleName: String,
    val capability: Capability,
    val basePriority: Int,
    val isLocalOnly: Boolean = false,
    val needsNetwork: Boolean = false,
    val costCentsPerMinute: Float = 0.0f,
    val inferenceFramework: String? = null,
)

/**
 * Result of a routed VAD call.
 */
data class RoutedVadResult(
    val isSpeech: Boolean,
    /** Confidence in [0,1], or [Float.NaN] if backend doesn't expose one. */
    val confidence: Float,
    val chosenModuleId: String,
    val wasFallback: Boolean,
    val attemptCount: Int,
)

/**
 * Result of a routed STT call. Includes the chosen backend and cascade info.
 */
data class RoutedSttResult(
    val text: String,
    val language: String,
    val durationMs: Long,
    /** Confidence of the returned result, or [Float.NaN] when no signal. */
    val confidence: Float,
    val chosenModuleId: String,
    val wasFallback: Boolean,
    /** Confidence from the first attempted backend (== [confidence] when no cascade). */
    val primaryConfidence: Float,
    val attemptCount: Int,
    /**
     * Non-zero when the cascade tried a cloud backend after a low-confidence
     * local primary and that cloud attempt failed. Result is the restored
     * local primary; this field tells the caller cascade was attempted.
     */
    val cascadeErrorCode: Int = 0,
    /** Module id of the failed cascade attempt (e.g. "sarvam-cloud"). */
    val cascadeErrorModuleId: String = "",
)
