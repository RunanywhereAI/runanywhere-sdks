/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Callback contract for a named hybrid-router custom filter.
 *
 * A predicate is registered by name through the cross-SDK
 * `rac_hybrid_custom_filter` table in commons (see
 * RunAnywhereBridge.racHybridRegisterCustomFilter). Commons invokes
 * [evaluate] during candidate filtering — the Kotlin layer no longer
 * pre-filters or toggles router slots host-side. The predicate name on the
 * wire (`CustomFilter.name`) is what links the policy proto entry to the
 * registered callback.
 */

package com.runanywhere.sdk.public.hybrid

/**
 * Eligibility test for a single hybrid-router candidate.
 *
 * Invoked by commons (not Kotlin) on the request thread while it filters the
 * offline / online candidates for a routing decision. Keep it fast and
 * side-effect-free.
 *
 * The native bridge resolves this type by exact JNI signature
 * (`evaluate(Ljava/lang/String;)Z`), so the method name and shape must not
 * drift from the C++ lookup in `rac_hybrid_custom_filter_jni.cpp`.
 */
fun interface CustomFilterPredicate {
    /**
     * Decide whether the candidate identified by [modelId] stays eligible.
     *
     * @param modelId The candidate model id commons is currently filtering.
     * @return `true` to keep the candidate, `false` to drop it.
     */
    fun evaluate(modelId: String): Boolean
}
