/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public, structured routing-policy types for the STT hybrid router.
 *
 * The policy is a *declaration* of how the C router should choose between the
 * offline and online candidate; the router (in commons) owns every routing /
 * cascade / rank decision. This file only lets the caller express filters /
 * cascade / rank as Kotlin values — the proto-byte marshalling lives in
 * HybridRouterProto.kt.
 *
 * Mirrors Swift's HybridRoutingPolicy.swift 1:1 (sealed classes instead of
 * Swift enums-with-associated-values).
 */

package com.runanywhere.sdk.hybrid

/**
 * Candidate comparator for a routing policy. Exactly one rank per policy.
 * Backed by the generated `HybridRank` (wire values match `HybridRank` in
 * hybrid_router.proto): `HYBRID_RANK_PREFER_LOCAL_FIRST` prefers the offline
 * candidate, `HYBRID_RANK_PREFER_ONLINE_FIRST` prefers the online candidate.
 */
typealias HybridRank = ai.runanywhere.proto.v1.HybridRank

/**
 * A hard eligibility predicate. Every filter in a policy must pass for a
 * candidate to survive the filter phase (filters AND-compose). Concrete
 * semantics are evaluated inside commons (Network / Battery against the
 * device-state vtable snapshot; Custom against the registered named
 * predicate).
 */
sealed class HybridFilter {
    /**
     * Drops the online candidate when the host has no network. The offline
     * candidate is unaffected. Network state is read from the device-state
     * vtable on every request — never passed in per-call.
     */
    data object Network : HybridFilter()

    /**
     * Requires the candidate to declare at least [tier]. Reserved: v1
     * descriptors carry no quality tier, so commons treats this as a no-op
     * today. Kept for wire/API parity with Swift.
     */
    class Quality(
        val tier: Int = 1,
    ) : HybridFilter()

    /**
     * Drops the online candidate when the device battery is below
     * [minPercent] (0–100). The offline candidate is unaffected.
     */
    class Battery(
        val minPercent: Int = 20,
    ) : HybridFilter()

    /**
     * A caller-supplied named predicate. The lambda is registered with
     * commons under [name] via `rac_hybrid_register_custom_filter`; commons
     * resolves it by name and invokes it once per candidate during filtering.
     * Return `true` to keep the candidate eligible.
     *
     * The lambda runs synchronously on the router's request thread and may
     * be invoked concurrently — keep it fast, reentrant, and side-effect-free.
     *
     * @property name        Wire identity + log label; non-blank, unique per policy.
     * @property description Human-readable purpose for the filter.
     * @property check       `(modelId) -> Boolean` deciding eligibility.
     */
    class Custom(
        val name: String,
        val description: String = "",
        val check: (modelId: String) -> Boolean,
    ) : HybridFilter()
}

/**
 * A mid-request fallback trigger. At most one cascade per policy. Evaluated
 * inside commons on the primary candidate's confidence signal (and on a
 * primary error, treated as "no confidence").
 */
sealed class HybridCascade {
    /**
     * Fall back to the secondary candidate when the primary's confidence
     * falls below [threshold] (`[0..1]`), or when the primary errors.
     */
    class Confidence(
        val threshold: Float,
    ) : HybridCascade()
}

/**
 * The full routing policy attached to a model pair: filters (AND-composed),
 * an optional cascade, and a rank. Defaults to `PREFER_LOCAL_FIRST` with no
 * filters or cascade — i.e. "use the local candidate, fall back to online on
 * hard failure".
 */
class HybridRoutingPolicy(
    val hardFilters: List<HybridFilter> = emptyList(),
    val cascade: HybridCascade? = null,
    val rank: HybridRank = HybridRank.HYBRID_RANK_PREFER_LOCAL_FIRST,
) {
    companion object {
        /** One-filter policy. */
        @JvmStatic
        fun filter(filter: HybridFilter): HybridRoutingPolicy = HybridRoutingPolicy(hardFilters = listOf(filter))

        /** One-cascade policy (no filters, default rank). */
        @JvmStatic
        fun cascade(cascade: HybridCascade): HybridRoutingPolicy = HybridRoutingPolicy(cascade = cascade)

        /** Rank-only policy. */
        @JvmStatic
        fun rank(rank: HybridRank): HybridRoutingPolicy = HybridRoutingPolicy(rank = rank)
    }
}
