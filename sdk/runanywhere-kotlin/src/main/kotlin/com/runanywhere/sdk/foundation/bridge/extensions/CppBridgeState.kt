/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * State bridge extension for C++ interop.
 *
 * Two concerns live in this object:
 *
 *  1. Centralised SDK runtime gate flags — the four volatile booleans
 *     that `CppBridge` uses to gate Phase 1 / Phase 2 initialisation.
 *     Owning them here lets future refactors split the coordinator
 *     (`CppBridge`) from the shared mutable state without churning every
 *     consumer call site.
 *
 *  2. Persisted backend state accessors — environment, base URL, API
 *     key, device ID, device-registration flag, plus init/shutdown.
 *     These read/write the global `rac_sdk_state` (non-auth state) and
 *     `rac_auth_manager` (auth state) singletons via the `racState*` /
 *     `racAuth*` JNI thunks.
 *
 * Mirrors iOS source of truth:
 *   sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/
 *     CppBridge+State.swift
 *
 * This object is the canonical owner of the four runtime gate flags
 * (`isInitialized`, `servicesInitialized`, `servicesInitializing`,
 * `nativeLibraryLoaded`). `CppBridge.kt` no longer holds private
 * duplicates — its public properties delegate to the volatiles below
 * and writes inside `CppBridge.initialize()` /
 * `CppBridge.completeServicesInitialization()` /
 * `CppBridge.shutdownSuspending()` mutate this object directly under
 * the coordinator's `synchronized(lock)` guards.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.foundation.constants.SDKConstants
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.configuration.SDKEnvironment
import com.runanywhere.sdk.public.configuration.cEnvironment

/**
 * Shared SDK state used by `CppBridge`.
 *
 * On Swift, the matching `CppBridge.State` enum exposes both the
 * persisted backend state (`rac_state_*` accessors) and the runtime
 * gate flags (`_isInitialized`, etc.). Kotlin mirrors that surface
 * here.
 *
 * Thread safety: all in-memory writes use `@Volatile`. Coordination
 * across fields (e.g. clearing `servicesInitializing` on failure) must
 * still be wrapped in a synchronised block by the caller — the same
 * shape the Swift coordinator uses around its `OSAllocatedUnfairLock`.
 */
object CppBridgeState {
    private val logger = SDKLogger("CppBridgeState")

    // Runtime gate flags (Kotlin-only — Swift inlines these into
    // CppBridgeSharedState; here they live alongside the persisted
    // accessors so the future refactor can retire the duplicates in
    // CppBridge.kt without breaking callers).

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

    // Initialization / Shutdown (Swift parity)

    /**
     * Initialize the C++ state manager.
     *
     * Mirrors Swift's `CppBridge.State.initialize(environment:apiKey:baseURL:deviceId:)`
     * which calls `rac_state_initialize` followed by `rac_sdk_init` to
     * populate both the runtime state singleton and the SDK config used
     * by device registration.
     *
     * On Kotlin we don't have a separate `rac_state_initialize` JNI
     * binding yet — `racSdkInit` already populates the SDK state with
     * environment / api key / base URL / device ID, so we route through
     * it here for parity. When the dedicated state-init thunk lands a
     * follow-up can split the two calls.
     */
    fun initialize(
        environment: SDKEnvironment,
        apiKey: String,
        baseURL: String,
        deviceId: String,
    ) {
        val rc =
            RunAnywhereBridge.racSdkInit(
                environment = environment.cEnvironment,
                deviceId = deviceId.ifEmpty { null },
                platform = SDKConstants.SDK_PLATFORM,
                sdkVersion = SDKConstants.SDK_VERSION,
                apiKey = apiKey.ifEmpty { null },
                baseUrl = baseURL.ifEmpty { null },
            )
        if (rc != 0) {
            logger.warn("rac_sdk_init returned $rc during state initialize")
        }
        logger.debug("C++ state initialized")
    }

    /**
     * Shutdown the C++ state manager and clear auth state.
     *
     * Mirrors Swift's `CppBridge.State.shutdown()` which calls
     * `rac_state_shutdown()` + `rac_auth_reset()`. Kotlin routes the
     * state-shutdown half through the `racStateReset` thunk until a
     * dedicated `rac_state_shutdown` thunk exists.
     */
    fun shutdown() {
        try {
            RunAnywhereBridge.racStateReset()
        } catch (t: Throwable) {
            logger.warn("racStateReset threw during state shutdown: ${t.message}")
        }
        try {
            RunAnywhereBridge.racAuthReset()
        } catch (t: Throwable) {
            logger.warn("racAuthReset threw during state shutdown: ${t.message}")
        }
    }

    // Persisted state accessors (rac_sdk_state — non-auth)

    /**
     * Current SDK environment as stored in the C++ state singleton.
     *
     * Mirrors Swift's `CppBridge.State.environment` computed property
     * which delegates to `Environment.fromC(rac_state_get_environment())`.
     */
    val environment: SDKEnvironment
        get() = CppBridgeEnvironment.fromC(RunAnywhereBridge.racStateGetEnvironment())

    /**
     * Configured backend base URL, or `null` if unset / empty.
     * Mirrors Swift's `CppBridge.State.baseURL`.
     */
    val baseURL: String?
        get() = RunAnywhereBridge.racStateGetBaseUrl()?.takeIf { it.isNotEmpty() }

    /**
     * Configured API key, or `null` if unset / empty.
     * Mirrors Swift's `CppBridge.State.apiKey`.
     */
    val apiKey: String?
        get() = RunAnywhereBridge.racStateGetApiKey()?.takeIf { it.isNotEmpty() }

    /**
     * Persistent device ID, or `null` if unset / empty.
     * Mirrors Swift's `CppBridge.State.deviceId`.
     */
    val deviceId: String?
        get() = RunAnywhereBridge.racStateGetDeviceId()?.takeIf { it.isNotEmpty() }

    /**
     * Set the device-registered flag in the C++ state singleton.
     * Mirrors Swift's `CppBridge.State.setDeviceRegistered(_:)`.
     */
    fun setDeviceRegistered(registered: Boolean) {
        RunAnywhereBridge.racStateSetDeviceRegistered(registered)
    }

    /**
     * Whether the device-registered flag is set in the C++ state singleton.
     * Mirrors Swift's `CppBridge.State.isDeviceRegistered`.
     */
    val isDeviceRegistered: Boolean
        get() = RunAnywhereBridge.racStateIsDeviceRegistered()

    // Auth state (delegated to rac_auth_manager)

    // Runtime-gate helpers

    /**
     * Reset every runtime gate flag back to its pre-init state. Used by
     * `shutdown` paths and by tests that want a clean slate between
     * cases.
     *
     * Mirrors Swift's `CppBridge.State.reset()`.
     */
    fun reset() {
        try {
            RunAnywhereBridge.racStateReset()
        } catch (t: Throwable) {
            logger.warn("racStateReset threw during state reset: ${t.message}")
        }
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
        return RunAnywhereBridge.racIsInitialized()
    }
}
