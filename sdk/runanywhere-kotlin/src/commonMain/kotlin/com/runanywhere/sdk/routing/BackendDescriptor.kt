/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Backend self-declaration type for hybrid routing.
 */
package com.runanywhere.sdk.routing

import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.core.types.SDKComponent

/**
 * A backend's self-declaration to the router.
 *
 * Each backend creates one BackendDescriptor per capability it supports.
 * A backend that handles both STT and TTS registers two descriptors.
 *
 * Conditions are attached at the capability level so the same provider can
 * declare different constraints for each capability it supports.
 */
data class BackendDescriptor(
    /** Stable identifier matching the backend's moduleId. */
    val moduleId: String,

    /** Human-readable name for logging and debugging. */
    val moduleName: String,

    /** The single capability this descriptor covers (STT, LLM, TTS, etc.). */
    val capability: SDKComponent,

    /** The inference framework powering this backend. */
    val inferenceFramework: InferenceFramework,

    /**
     * Base priority. Higher wins when scores are otherwise equal.
     * Convention: 200 for local, 80-100 for cloud.
     */
    val basePriority: Int = 100,

    /**
     * Conditions this backend declares. All must be satisfied for it to be eligible.
     * Conditions also carry optional preferenceBonus values that affect ranking.
     */
    val conditions: List<RoutingCondition> = emptyList(),
) {
    /** True if every condition is satisfied for the given context. */
    fun isEligible(context: RoutingContext): Boolean =
        conditions.all { it.isSatisfied(context) }

    /** Base score before policy bonuses — basePriority + sum of condition bonuses. */
    fun conditionScore(): Int =
        basePriority + conditions.sumOf { it.preferenceBonus }

    val requiresNetwork: Boolean
        get() = conditions.any { it is RoutingCondition.NetworkRequired }

    val isLocalOnly: Boolean
        get() = conditions.any { it is RoutingCondition.LocalOnly }

    val costModel: RoutingCondition.CostModel?
        get() = conditions.filterIsInstance<RoutingCondition.CostModel>().firstOrNull()

    val qualityTier: RoutingCondition.QualityTier?
        get() = conditions.filterIsInstance<RoutingCondition.QualityTier>().firstOrNull()
}
