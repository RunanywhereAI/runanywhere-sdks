/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Singleton registry for hybrid router initialization.
 */
package com.runanywhere.sdk.routing

import com.runanywhere.sdk.backends.stt.SarvamSTTBackend
import com.runanywhere.sdk.backends.stt.WhisperSTTBackend
import com.runanywhere.sdk.core.types.SDKComponent
import com.runanywhere.sdk.foundation.SDKLogger

/**
 * Singleton that owns the HybridRouter and maps moduleId to concrete backend objects.
 *
 * Initialize once at SDK startup via [initialize]. After that, call [resolveSTT]
 * to get an ordered candidate list and [sttBackendFor] to get the executable backend.
 *
 * To add a new STT provider: instantiate it and pass to [initialize] — nothing else changes.
 */
object HybridRouterRegistry {

    private val logger = SDKLogger("HybridRouterRegistry")

    private val router = HybridRouter()
    private val sttBackends = mutableMapOf<String, STTBackend>()

    @Volatile
    private var isInitialized = false

    /**
     * Register all backends with the router.
     *
     * Called during SDK platform initialization. Safe to call multiple times —
     * subsequent calls after the first are no-ops.
     *
     * To add a new backend, add it to the list below and register it.
     */
    fun initialize() {
        synchronized(this) {
            if (isInitialized) return

            val backends: List<STTBackend> = listOf(
                WhisperSTTBackend(),
                SarvamSTTBackend(),
            )

            backends.forEach { backend ->
                router.register(backend)
                backend.descriptors().forEach { descriptor ->
                    sttBackends[descriptor.moduleId] = backend
                }
            }

            isInitialized = true
            logger.info("HybridRouterRegistry initialized with ${backends.size} STT backends")
        }
    }

    /**
     * Resolve an ordered candidate list for an STT request.
     *
     * Returns descriptors sorted most-preferred first. Empty if no backend qualifies.
     */
    fun resolveSTT(context: RoutingContext): List<BackendDescriptor> =
        router.resolve(SDKComponent.STT, context)

    /**
     * Return the executable STTBackend for a given moduleId.
     */
    fun sttBackendFor(moduleId: String): STTBackend? = sttBackends[moduleId]

    fun shutdown() {
        synchronized(this) {
            sttBackends.clear()
            isInitialized = false
            logger.info("HybridRouterRegistry shut down")
        }
    }
}
