/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * State bridge extension for C++ interop.
 *
 * Centralised SDK runtime state — the four volatile booleans that
 * `CppBridge` uses to gate Phase 1 / Phase 2 initialisation. Owning
 * them in a dedicated namespace lets future refactors split the
 * coordinator (`CppBridge`) from the shared mutable state without
 * churning every consumer call site.
 *
 * Mirrors iOS source of truth:
 *   sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/
 *     CppBridge+State.swift
 *
 * NOTE (B18): the same booleans currently live inside `CppBridge.kt`.
 * Per the task spec the Kotlin coordinator is NOT modified yet, so the
 * fields are intentionally duplicated here. A follow-up will retire the
 * coordinator-side copies and route all reads through this object.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.configuration.SDKEnvironment

/**
 * Shared SDK initialisation state used by `CppBridge`.
 *
 * On Swift, the matching `CppBridge.State` enum exposes both the
 * persisted backend state (`rac_state_*` accessors) and the runtime
 * gate flags (`_isInitialized`, etc.). On Kotlin those concerns are
 * deliberately split:
 *  - the runtime gate flags live in this object;
 *  - the persisted backend state is read directly through
 *    `RunAnywhereBridge.racAuth*` / future `racState*` JNI bindings.
 *
 * Thread safety: all reads/writes use `@Volatile`. Coordination across
 * fields (e.g. clearing `servicesInitializing` on failure) must still
 * be wrapped in a synchronised block by the caller — the same shape
 * the Swift coordinator uses around its `OSAllocatedUnfairLock`.
 */
object CppBridgeState {

    /**
     * Active SDK environment as configured by the consumer.
     *
     * Defaults to development so any pre-init read still returns a
     * sensible value. Updated synchronously inside Phase 1 init.
     */
    @Volatile
    var environment: SDKEnvironment = SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT

    /**
     * Whether Phase 1 (synchronous core init) has completed. Mirrors
     * Swift's `_isInitialized`.
     */
    @Volatile
    var isInitialized: Boolean = false

    /**
     * Whether Phase 2 (async services init) has completed. Mirrors
     * Swift's `_servicesInitialized` flag inside `CppBridge`.
     */
    @Volatile
    var servicesInitialized: Boolean = false

    /**
     * Whether Phase 2 is currently running. Used to deduplicate
     * concurrent `initializeServices()` calls. Mirrors Swift's
     * `_servicesInitializing` flag.
     */
    @Volatile
    var servicesInitializing: Boolean = false

    /**
     * Whether the native commons library was successfully loaded by
     * `RunAnywhereBridge.ensureNativeLibraryLoaded()`. The SDK is still
     * functional for non-inference paths when this is `false`.
     */
    @Volatile
    var nativeLibraryLoaded: Boolean = false

    /**
     * Reset every flag back to its pre-init state. Used by `shutdown`
     * paths and by tests that want a clean slate between cases.
     *
     * Mirrors Swift's `CppBridge.State.reset()`.
     */
    fun reset() {
        environment = SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT
        isInitialized = false
        servicesInitialized = false
        servicesInitializing = false
        nativeLibraryLoaded = false
    }

    /**
     * Convenience query that asks the native side whether `rac_init`
     * already returned success. Mirrors Swift's
     * `CppBridge.State.isInitialized` (the property — distinct from the
     * Kotlin gate flag above).
     *
     * Returns `false` when Phase 1 hasn't completed or the native
     * library isn't loaded; otherwise delegates to
     * `RunAnywhereBridge.racIsInitialized()`.
     */
    fun isNativeInitialized(): Boolean {
        if (!isInitialized || !nativeLibraryLoaded) return false
        return try {
            RunAnywhereBridge.racIsInitialized()
        } catch (_: Throwable) {
            isInitialized
        }
    }
}
