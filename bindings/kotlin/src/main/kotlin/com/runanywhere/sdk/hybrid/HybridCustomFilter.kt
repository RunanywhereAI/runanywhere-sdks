/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Kotlin binding for the cross-SDK named custom-filter callback table
 * (rac_hybrid_custom_filter.h). A HybridFilter.Custom carries only a NAME on
 * the wire; the predicate logic stays host-supplied. This file registers a
 * Kotlin lambda under that name so commons can RESOLVE it by name and INVOKE
 * it during candidate filtering — keeping the custom-filter decision inside
 * commons instead of leaking back into the host layer.
 *
 * Mirrors Swift's internal HybridCustomFilter.swift. The JNI side
 * (rac_hybrid_custom_filter_jni.cpp) owns the predicate GlobalRefs, so no
 * Kotlin-side lifetime map is needed.
 */

package com.runanywhere.sdk.hybrid

import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

/**
 * Eligibility test for a single hybrid-router candidate.
 *
 * Invoked by commons (not Kotlin) on the request thread while it filters the
 * offline / online candidates for a routing decision. Keep it fast and
 * side-effect-free.
 *
 * The native bridge resolves this type by exact JNI signature
 * (`evaluate(Ljava/lang/String;)Z`), so the method name and shape must not
 * drift from the C++ lookup in `rac_hybrid_custom_filter_jni.cpp`. Declared
 * public only because the JNI declaration on
 * [com.runanywhere.sdk.native.bridge.RunAnywhereBridge] references it; it is
 * not part of the supported API surface.
 *
 * @suppress
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

/**
 * Registers/unregisters named eligibility predicates with the commons custom
 * -filter table. The router invokes a registered predicate (by the name in
 * the policy's HybridFilter.Custom) once per candidate during filtering.
 */
internal object HybridCustomFilter {
    private val logger = SDKLogger("Hybrid.CustomFilter")

    /** Register (or replace) the predicate stored under [name]. */
    fun register(
        name: String,
        check: (modelId: String) -> Boolean,
    ): Boolean {
        if (name.isEmpty()) {
            logger.error("custom-filter name must be non-empty")
            return false
        }
        val rc =
            RunAnywhereBridge.racHybridRegisterCustomFilter(
                name = name,
                predicate = CustomFilterPredicate { modelId -> check(modelId) },
            )
        if (rc != RunAnywhereBridge.RAC_SUCCESS) {
            logger.error("racHybridRegisterCustomFilter('$name') failed: rc=$rc")
            return false
        }
        return true
    }

    /** Remove the predicate stored under [name]. No-op when not registered. */
    fun unregister(name: String): Boolean {
        if (name.isEmpty()) {
            return false
        }
        val rc = RunAnywhereBridge.racHybridUnregisterCustomFilter(name)
        if (rc != RunAnywhereBridge.RAC_SUCCESS) {
            logger.error("racHybridUnregisterCustomFilter('$name') failed: rc=$rc")
            return false
        }
        return true
    }
}
