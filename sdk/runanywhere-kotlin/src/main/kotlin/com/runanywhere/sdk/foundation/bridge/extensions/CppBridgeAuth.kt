/*
 * CppBridge+Auth.kt — RunAnywhere SDK
 *
 * This file was previously a ~150 LOC HTTP-transport adapter built on
 * HttpURLConnection that forwarded request/response bodies to the
 * matching rac_auth_* C ABI. The HTTP transport now lives in the
 * commons libcurl-backed `rac_http_client_*` ABI (exposed via
 * [RunAnywhereBridge.racHttpRequestExecute]). Kotlin now owns zero
 * network plumbing for auth — the whole round-trip (request build →
 * POST → response parse → state update) happens in native code.
 *
 * SDKs still initialize secure storage and expose auth state accessors here;
 * network sequencing lives in commons via CppBridgeSdkInit.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

/**
 * Thin facade over auth state and secure-storage initialization. Auth
 * request-building, response parsing, refresh-window math, and HTTP transport
 * orchestration live in commons.
 */
object CppBridgeAuth {
    private const val TAG = "CppBridge/Auth"

    @Volatile private var initialized: Boolean = false

    /**
     * Initialize the native auth manager with a secure-storage vtable backed
     * by the platform adapter's secureGet/secureSet/secureDelete callbacks.
     *
     * Must be called AFTER [CppBridgePlatformAdapter.register] has wired up
     * the secure-storage delegate, otherwise rac_auth_save_tokens /
     * rac_auth_clear fall back to in-memory-only and tokens are lost across
     * process restarts. Idempotent.
     *
     * Called from [com.runanywhere.sdk.public.RunAnywhere]'s `performCoreInit`
     * during Phase 1.
     */
    fun initialize() {
        if (initialized) return
        synchronized(this) {
            if (initialized) return
            RunAnywhereBridge.racAuthInit()
            com.runanywhere.sdk.infrastructure.logging
                .SDKLogger(TAG)
                .info("Native auth manager initialized with secure storage vtable")
            initialized = true
        }
    }

    val accessToken: String? get() = RunAnywhereBridge.racAuthGetAccessToken()

    val tokenNeedsRefresh: Boolean get() = RunAnywhereBridge.racAuthNeedsRefresh()

    val isAuthenticated: Boolean get() = RunAnywhereBridge.racAuthIsAuthenticated()

    /**
     * Clear all auth state (logout). Delegates to native. Mirrors Swift's
     * `CppBridge.Auth.clearAuth()`.
     *
     * Wipes the in-memory auth state — and, because [initialize] wires up the
     * secure-storage vtable, also deletes the persisted tokens.
     */
    fun clearAuth() {
        RunAnywhereBridge.racAuthReset()
    }
}
