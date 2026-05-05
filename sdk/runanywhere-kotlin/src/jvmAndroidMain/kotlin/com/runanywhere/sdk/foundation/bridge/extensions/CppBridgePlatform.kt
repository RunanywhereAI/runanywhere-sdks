/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Platform extension for CppBridge.
 *
 * Trimmed to the only surface still wired into SDK init: register/unregister.
 * The provider pattern + JSON shuttling for platform LLM/TTS/STT services has
 * been removed because native commons owns the service layer and no Android
 * provider is registered through this path.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

/**
 * Platform bridge lifecycle hook.
 *
 * Invoked from [CppBridge] during Phase 2 init / shutdown so downstream
 * wiring that depends on this hook keeps compiling. No platform services are
 * registered here today; the object is a placeholder for future Android
 * platform-service integration.
 */
object CppBridgePlatform {
    @Volatile
    private var isRegistered: Boolean = false

    private val lock = Any()

    /**
     * Register the platform callbacks with C++ core.
     *
     * Safe to call multiple times; subsequent calls are no-ops.
     */
    fun register() {
        synchronized(lock) {
            if (isRegistered) return
            isRegistered = true
        }
    }

    /**
     * Unregister the platform callbacks.
     *
     * Called during SDK shutdown.
     */
    fun unregister() {
        synchronized(lock) {
            isRegistered = false
        }
    }
}
