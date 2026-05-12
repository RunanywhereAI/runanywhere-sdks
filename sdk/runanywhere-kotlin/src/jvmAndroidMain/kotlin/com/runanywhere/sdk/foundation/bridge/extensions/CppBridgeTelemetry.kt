/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Telemetry bridge extension for CppBridge.
 *
 * Mirrors Swift's `CppBridge+Telemetry.swift`. C++ owns event logic,
 * JSON serialization, and batching; Kotlin only provides:
 *   - the native telemetry-manager lifecycle (create/destroy/flush),
 *   - the HTTP callback that C++ uses to drain queued events to the
 *     backend — routed through [HTTPClientAdapter] (W2-6).
 *
 * The previous ~600 LOC of bespoke HTTP transport, header parsing, dev-
 * config-aware URL resolution, and listener / interceptor surface has
 * been deleted. All dev-config queries now live in [CppBridgeDevConfig];
 * all HTTP transport routes through [HTTPClientAdapter].
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.foundation.bridge.HTTPClientAdapter
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Telemetry bridge — owns the native `rac_telemetry_manager_*` handle
 * and forwards the HTTP callback from C++ through [HTTPClientAdapter].
 *
 * Thread safety: handle/state mutations are guarded by a [lock] sync
 * block; the HTTP callback dispatches to the shared [scope] running on
 * `Dispatchers.IO`.
 */
object CppBridgeTelemetry {

    private const val TAG = "CppBridgeTelemetry"

    @Volatile private var isRegistered: Boolean = false

    @Volatile private var telemetryManagerHandle: Long = 0

    @Volatile private var _baseUrl: String? = null

    @Volatile private var _apiKey: String? = null

    /**
     * Current SDK environment (0=DEV, 1=STAGING, 2=PRODUCTION). Mirrors
     * Swift's `Telemetry.activeEnvironment`. Set by [setEnvironment] from
     * `CppBridge.initialize` so `CppBridgeDevice.isDeviceRegisteredCallback`
     * can branch on it.
     */
    @Volatile
    var currentEnvironment: Int = 0
        private set

    private val lock = Any()

    /** Background scope for the C++→Kotlin HTTP callback. */
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // ─────────────────────────────────────────────────────────────────
    // Lifecycle (parity with Swift `CppBridge.Events.register/unregister`
    // and `CppBridge.Telemetry.initialize/shutdown`)
    // ─────────────────────────────────────────────────────────────────

    /** Register the telemetry bridge. Idempotent. */
    fun register() {
        synchronized(lock) {
            if (isRegistered) return
            log(CppBridgePlatformAdapter.LogLevel.DEBUG, "Registering telemetry…")
            isRegistered = true
        }
    }

    /**
     * Create the native telemetry manager and wire the HTTP callback.
     * Mirrors Swift's `Telemetry.initialize(environment:)`.
     */
    fun initialize(
        environment: Int,
        deviceId: String,
        deviceModel: String,
        osVersion: String,
        sdkVersion: String,
    ) {
        synchronized(lock) {
            currentEnvironment = environment

            telemetryManagerHandle =
                RunAnywhereBridge.racTelemetryManagerCreate(environment, deviceId, "android", sdkVersion)

            if (telemetryManagerHandle == 0L) {
                log(CppBridgePlatformAdapter.LogLevel.WARN, "Failed to create telemetry manager")
                return
            }

            RunAnywhereBridge.racTelemetryManagerSetDeviceInfo(
                telemetryManagerHandle,
                deviceModel,
                osVersion,
            )

            // HTTP callback shape (matched by JNI lookup):
            //   onHttpRequest(endpoint: String, body: String, bodyLength: Int, requiresAuth: Boolean)
            val httpCallback =
                object {
                    @Suppress("unused")
                    fun onHttpRequest(
                        endpoint: String,
                        body: String,
                        bodyLength: Int,
                        requiresAuth: Boolean,
                    ) {
                        scope.launch { performTelemetryHttp(endpoint, body, requiresAuth) }
                    }
                }
            RunAnywhereBridge.racTelemetryManagerSetHttpCallback(telemetryManagerHandle, httpCallback)

            log(
                CppBridgePlatformAdapter.LogLevel.INFO,
                "Telemetry manager initialized (handle=$telemetryManagerHandle, env=$environment)",
            )
        }
    }

    /** Flush pending telemetry events through the native manager. */
    fun flush() {
        synchronized(lock) {
            if (telemetryManagerHandle != 0L) {
                RunAnywhereBridge.racTelemetryManagerFlush(telemetryManagerHandle)
            }
        }
    }

    /** Tear down the telemetry bridge. */
    fun unregister() {
        synchronized(lock) {
            if (!isRegistered) return
            if (telemetryManagerHandle != 0L) {
                RunAnywhereBridge.racTelemetryManagerDestroy(telemetryManagerHandle)
                telemetryManagerHandle = 0
            }
            isRegistered = false
            log(CppBridgePlatformAdapter.LogLevel.DEBUG, "Telemetry unregistered")
        }
    }

    /** Native telemetry manager handle (0 if not initialized). */
    fun getTelemetryHandle(): Long = telemetryManagerHandle

    // ─────────────────────────────────────────────────────────────────
    // Configuration (called by CppBridge.kt + PlatformBridge.kt during
    // Phase 1 init). Mirrors Swift, where the same values feed
    // `CppBridge.HTTP.configure(baseURL:apiKey:)`.
    // ─────────────────────────────────────────────────────────────────

    fun setBaseUrl(url: String) {
        _baseUrl = url
    }

    fun setApiKey(key: String) {
        _apiKey = key
    }

    fun getBaseUrl(): String? = _baseUrl

    fun getApiKey(): String? = _apiKey

    /** Set the active environment so callbacks can branch on prod vs dev. */
    fun setEnvironment(environment: Int) {
        currentEnvironment = environment
        val label =
            when (environment) {
                0 -> "DEVELOPMENT"
                1 -> "STAGING"
                else -> "PRODUCTION"
            }
        log(CppBridgePlatformAdapter.LogLevel.DEBUG, "Environment set to: $environment ($label)")
    }

    /**
     * Whether the current configuration is usable for outbound HTTP.
     * Mirrors Swift's `CppBridge.DevConfig.hasUsableSupabaseConfig` (dev)
     * + `HTTPClientAdapter.hasUsableConfiguration` (prod) gating.
     */
    fun hasUsableNetworkConfig(environment: Int = currentEnvironment): Boolean =
        if (environment == 0) {
            CppBridgeDevConfig.hasUsableSupabaseConfig
        } else {
            CppBridgeDevConfig.isUsableHTTPURL(_baseUrl) &&
                CppBridgeDevConfig.isUsableCredential(_apiKey)
        }

    // ─────────────────────────────────────────────────────────────────
    // HTTP callback path
    // ─────────────────────────────────────────────────────────────────

    /**
     * Forward a telemetry HTTP request from C++ through the canonical
     * [HTTPClientAdapter]. Mirrors Swift's `performTelemetryHTTP(...)`.
     *
     * Skipped silently when the adapter has no usable configuration —
     * matches Swift's `CppBridge.HTTP.hasUsableConfiguration` + `isConfigured`
     * preflight.
     */
    private suspend fun performTelemetryHttp(path: String, json: String, requiresAuth: Boolean) {
        if (currentEnvironment == 0 && !CppBridgeDevConfig.hasUsableSupabaseConfig) {
            log(CppBridgePlatformAdapter.LogLevel.DEBUG, "Skipping telemetry: no usable dev config")
            return
        }
        if (!HTTPClientAdapter.hasUsableConfiguration || !HTTPClientAdapter.isConfigured) {
            log(CppBridgePlatformAdapter.LogLevel.DEBUG, "Skipping telemetry: HTTPClientAdapter not configured")
            return
        }
        try {
            HTTPClientAdapter.post(path, json, requiresAuth = requiresAuth)
            log(CppBridgePlatformAdapter.LogLevel.DEBUG, "Telemetry sent to $path")
        } catch (e: Exception) {
            log(CppBridgePlatformAdapter.LogLevel.ERROR, "Telemetry HTTP failed for $path: ${e.message}")
        }
    }

    private fun log(level: Int, message: String) {
        CppBridgePlatformAdapter.logCallback(level, TAG, message)
    }
}
