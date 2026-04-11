/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Condition types backends declare for routing eligibility.
 */
package com.runanywhere.sdk.routing

/**
 * A condition a backend declares about itself.
 *
 * The router evaluates all conditions for each candidate backend against the current
 * RoutingContext. All conditions must pass (logical AND) for the backend to be eligible.
 * If any condition fails, the backend is excluded — not just deprioritised.
 *
 * Conditions can also carry a preferenceBonus that adds to the backend's score when
 * satisfied — used to rank eligible candidates, not to gate them.
 */
sealed interface RoutingCondition {

    /** Returns true if this backend is eligible given the current context. */
    fun isSatisfied(context: RoutingContext): Boolean

    /**
     * Score bonus added when this condition is satisfied.
     * Only affects ranking among eligible backends, not eligibility itself.
     */
    val preferenceBonus: Int get() = 0

    // Hard gates — failing these excludes the backend entirely

    /**
     * Backend requires internet connectivity.
     * Excluded automatically when the device is offline.
     */
    data object NetworkRequired : RoutingCondition {
        override fun isSatisfied(context: RoutingContext) = context.isNetworkAvailable
    }

    /**
     * Backend runs fully on-device with no network traffic.
     * Informational — used by the router to apply LOCAL_ONLY and CLOUD_ONLY policies.
     */
    data object LocalOnly : RoutingCondition {
        override fun isSatisfied(context: RoutingContext) = true
        override val preferenceBonus: Int = 50
    }

    /**
     * Backend requires a model to be loaded in memory before routing here.
     * The [isModelLoaded] lambda is evaluated at routing time (not registration time)
     * so it always reflects current state.
     */
    data class ModelAvailability(
        val modelId: String,
        val isModelLoaded: () -> Boolean,
    ) : RoutingCondition {
        override fun isSatisfied(context: RoutingContext) = isModelLoaded()
    }

    /**
     * Arbitrary condition expressed as a lambda.
     * Use for backend-specific checks that don't fit the other types
     * (e.g., "API key configured?", "license valid?").
     */
    data class Custom(
        val description: String,
        val check: (RoutingContext) -> Boolean,
        override val preferenceBonus: Int = 0,
    ) : RoutingCondition {
        override fun isSatisfied(context: RoutingContext) = check(context)
    }

    // Preference boosters — never exclude, only rank

    /**
     * Declares the quality tier of this backend.
     * Affects ranking when PREFER_ACCURACY policy is active.
     */
    data class QualityTier(
        val quality: BackendQuality,
        override val preferenceBonus: Int = quality.defaultBonus,
    ) : RoutingCondition {
        override fun isSatisfied(context: RoutingContext) = true
    }

    /**
     * Declares the approximate cost of using this backend per minute.
     * Free backends (costPerMinuteCents == 0) receive a bonus under PREFER_LOCAL policy.
     */
    data class CostModel(
        val costPerMinuteCents: Float,
        override val preferenceBonus: Int = if (costPerMinuteCents == 0f) 20 else 0,
    ) : RoutingCondition {
        override fun isSatisfied(context: RoutingContext) = true
        val isFree: Boolean get() = costPerMinuteCents == 0f
    }
}

enum class BackendQuality(val defaultBonus: Int) {
    HIGH(20),
    STANDARD(5),
    LOW(0),
}
