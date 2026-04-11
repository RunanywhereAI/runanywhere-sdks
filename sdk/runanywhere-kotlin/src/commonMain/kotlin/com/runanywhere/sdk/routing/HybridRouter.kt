/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Hybrid routing decision engine for backend selection.
 */
package com.runanywhere.sdk.routing

import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.core.types.SDKComponent
import com.runanywhere.sdk.foundation.SDKLogger

/**
 * The routing decision engine.
 *
 * Holds a registry of BackendDescriptors and resolves an ordered candidate list
 * for each incoming request. Callers iterate the list and try each candidate,
 * falling back to the next on failure.
 *
 * HybridRouter is a plain class (not a singleton) to keep it testable in isolation.
 * The singleton pattern lives in HybridRouterRegistry (jvmAndroidMain).
 *
 * Registration is not thread-safe and must happen at startup before any requests.
 * resolve() is read-only after registration and safe to call concurrently.
 */
class HybridRouter {

    private val logger = SDKLogger("HybridRouter")

    // moduleId → list of descriptors for that module
    private val registry = mutableMapOf<String, List<BackendDescriptor>>()

    // -------------------------------------------------------------------------
    // Registration
    // -------------------------------------------------------------------------

    /**
     * Register a backend. The backend declares its own descriptors.
     *
     * ```kotlin
     * router.register(WhisperSTTBackend())
     * router.register(SarvamSTTBackend())
     * ```
     */
    fun register(backend: RoutableBackend) {
        val descriptors = backend.descriptors()
        if (descriptors.isEmpty()) {
            logger.warn("${backend::class.simpleName} returned no descriptors — skipped")
            return
        }
        descriptors.groupBy { it.moduleId }.forEach { (id, group) ->
            registry[id] = group
            logger.info(
                "Registered '$id' for: ${group.joinToString { it.capability.name }}"
            )
        }
    }

    // -------------------------------------------------------------------------
    // Resolution
    // -------------------------------------------------------------------------

    /**
     * Resolve an ordered candidate list for the given capability and context.
     *
     * Returns descriptors sorted most-preferred first. The caller tries them in
     * order and advances to the next on backend failure. Returns an empty list
     * if no backend is eligible — caller should surface a meaningful error.
     */
    fun resolve(capability: SDKComponent, context: RoutingContext): List<BackendDescriptor> {
        val allForCapability = registry.values
            .flatten()
            .filter { it.capability == capability }

        if (allForCapability.isEmpty()) {
            logger.error("No backends registered for ${capability.name}")
            return emptyList()
        }

        // Step 1: hard gate — remove backends whose conditions fail
        val eligible = allForCapability.filter { descriptor ->
            val ok = descriptor.isEligible(context)
            if (!ok) logger.debug("Excluded '${descriptor.moduleId}': condition not satisfied")
            ok
        }

        // Step 2: policy filter
        val candidates = applyPolicyFilter(eligible, context)

        if (candidates.isEmpty()) {
            logger.warn("No candidates after ${context.routingPolicy} filter for ${capability.name}")
            return emptyList()
        }

        // Step 3: score and sort
        return candidates.sortedByDescending { computeScore(it, context) }.also { sorted ->
            logger.debug(
                "${capability.name} routing order: " +
                    sorted.joinToString { "'${it.moduleId}'(${computeScore(it, context)})" }
            )
        }
    }

    // -------------------------------------------------------------------------
    // Internal
    // -------------------------------------------------------------------------

    private fun applyPolicyFilter(
        candidates: List<BackendDescriptor>,
        context: RoutingContext,
    ): List<BackendDescriptor> = when (context.routingPolicy) {
        RoutingPolicy.LOCAL_ONLY ->
            candidates.filter { it.isLocalOnly }

        RoutingPolicy.CLOUD_ONLY ->
            candidates.filter { it.requiresNetwork }

        RoutingPolicy.AUTO,
        RoutingPolicy.PREFER_LOCAL,
        RoutingPolicy.PREFER_ACCURACY,
        RoutingPolicy.FRAMEWORK_PREFERRED -> candidates
    }

    private fun computeScore(descriptor: BackendDescriptor, context: RoutingContext): Int {
        var score = descriptor.conditionScore()

        when (context.routingPolicy) {
            RoutingPolicy.PREFER_LOCAL -> {
                if (descriptor.isLocalOnly) score += 50
                if (descriptor.requiresNetwork) score -= 30
            }
            RoutingPolicy.PREFER_ACCURACY -> {
                if (descriptor.qualityTier?.quality == BackendQuality.HIGH) score += 50
            }
            RoutingPolicy.FRAMEWORK_PREFERRED -> {
                if (context.preferredFramework != null &&
                    descriptor.inferenceFramework == context.preferredFramework
                ) {
                    score += 200
                }
            }
            else -> Unit
        }

        // preferredFramework always adds a bonus even without explicit policy
        if (context.routingPolicy != RoutingPolicy.FRAMEWORK_PREFERRED &&
            context.preferredFramework != null &&
            descriptor.inferenceFramework == context.preferredFramework
        ) {
            score += 200
        }

        return score
    }
}
