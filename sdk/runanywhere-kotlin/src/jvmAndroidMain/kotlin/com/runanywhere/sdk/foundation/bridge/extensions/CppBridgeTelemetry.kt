/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Telemetry extension for CppBridge.
 * Provides HTTP callback for C++ core to send telemetry data to backend services.
 *
 * Follows iOS CppBridge+Telemetry.swift architecture.
 * 
 * Architecture:
 * - Creates rac_telemetry_manager via C++ API
 * - Registers HTTP callback for telemetry transport
 * - Uses HTTPService for actual HTTP requests (like Swift uses HTTPService)
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.data.network.HTTPService
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.DeviceInfo
import com.runanywhere.sdk.public.SDKEnvironment
import com.runanywhere.sdk.utils.SDKConstants
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * Telemetry bridge that provides HTTP callback for C++ core telemetry operations.
 *
 * Mirrors iOS CppBridge+Telemetry.swift:
 * - Creates telemetry manager on initialization
 * - Registers HTTP callback for telemetry transport
 * - Uses HTTPService (not raw HttpURLConnection) for HTTP requests
 *
 * Usage:
 * - Called during Phase 1 initialization via CppBridge.initialize()
 * - Must be registered after CppBridgePlatformAdapter is registered
 *
 * Thread Safety:
 * - Uses ReentrantLock for manager access (like Swift NSLock)
 * - HTTP callbacks are executed on background coroutines
 */
object CppBridgeTelemetry {

    private val logger = SDKLogger("CppBridgeTelemetry")

    /**
     * HTTP status categories.
     */
    object HttpStatus {
        fun isSuccess(statusCode: Int): Boolean = statusCode in 200..299
    }

    @Volatile
    private var isRegistered: Boolean = false

    private val lock = ReentrantLock()

    /**
     * Coroutine scope for HTTP operations (like Swift's Task)
     */
    private val httpScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /**
     * Native telemetry manager pointer (like Swift's OpaquePointer)
     * This will be a Long representing the native pointer address
     */
    @Volatile
    private var managerPtr: Long = 0

    /**
     * Optional listener for telemetry events.
     */
    @Volatile
    var telemetryListener: TelemetryListener? = null

    /**
     * Listener interface for telemetry events.
     */
    interface TelemetryListener {
        fun onRequestStart(requestId: String, url: String)
        fun onRequestComplete(requestId: String, statusCode: Int, success: Boolean, errorMessage: String?)
    }

    // ========================================================================
    // INITIALIZATION (mirrors Swift CppBridge.Telemetry.initialize)
    // ========================================================================

    /**
     * Initialize telemetry manager.
     * Mirrors Swift: CppBridge.Telemetry.initialize(environment:)
     *
     * Creates the C++ telemetry manager and registers the HTTP callback.
     *
     * @param environment SDK environment (DEVELOPMENT, STAGING, PRODUCTION)
     */
    fun initialize(environment: SDKEnvironment) {
        lock.withLock {
            // Destroy existing if any
            if (managerPtr != 0L) {
                try {
                    nativeDestroyTelemetryManager(managerPtr)
                } catch (e: UnsatisfiedLinkError) {
                    logger.debug("Native library not loaded, skipping telemetry manager destroy")
                }
                managerPtr = 0
            }

            // Get device info using existing mechanisms
            val deviceId = CppBridgeDevice.getDeviceIdCallback()
            val deviceInfo = DeviceInfo.current

            try {
                // Create telemetry manager
                // rac_telemetry_manager_create(environment, device_id, platform, sdk_version)
                managerPtr = nativeCreateTelemetryManager(
                    environment.cEnvironment,
                    deviceId,
                    SDKConstants.platform,
                    SDKConstants.SDK_VERSION
                )

                if (managerPtr != 0L) {
                    // Set device info
                    // rac_telemetry_manager_set_device_info(manager, device_model, os_version)
                    nativeSetDeviceInfo(
                        managerPtr,
                        deviceInfo.modelName,
                        deviceInfo.osVersion
                    )

                    // Register HTTP callback
                    // rac_telemetry_manager_set_http_callback(manager, callback, user_data)
                    nativeSetHttpCallback(managerPtr)

                    logger.info("Telemetry manager initialized for ${environment.name}")
                } else {
                    logger.warn("Failed to create telemetry manager - native returned null")
                }
            } catch (e: UnsatisfiedLinkError) {
                logger.debug("Native library not loaded, telemetry disabled")
                managerPtr = 0
            }
        }
    }

    /**
     * Shutdown telemetry manager.
     * Mirrors Swift: CppBridge.Telemetry.shutdown()
     */
    fun shutdown() {
        lock.withLock {
            if (managerPtr != 0L) {
                try {
                    // Flush pending events
                    nativeFlush(managerPtr)
                    // Destroy manager
                    nativeDestroyTelemetryManager(managerPtr)
                } catch (e: UnsatisfiedLinkError) {
                    logger.debug("Native library not loaded, skipping shutdown")
                }
                managerPtr = 0
            }
        }
    }

    /**
     * Register the telemetry system.
     * Called during CppBridge.initialize()
     */
    fun register() {
        synchronized(lock) {
            if (isRegistered) {
                return
            }
            isRegistered = true
        }
    }

    /**
     * Check if telemetry is registered.
     */
    fun isRegistered(): Boolean = isRegistered

    // ========================================================================
    // EVENT TRACKING (mirrors Swift CppBridge.Telemetry.trackAnalyticsEvent)
    // ========================================================================

    /**
     * Track analytics event from C++.
     * Called by CppBridgeEvents when an analytics event is received.
     *
     * Mirrors Swift: CppBridge.Telemetry.trackAnalyticsEvent(type:data:)
     */
    fun trackAnalyticsEvent(eventType: Int, eventDataJson: String?) {
        lock.withLock {
            val mgr = managerPtr
            if (mgr == 0L) return
        }

        try {
            // rac_telemetry_manager_track_analytics(manager, event_type, event_data)
            nativeTrackAnalyticsEvent(managerPtr, eventType, eventDataJson)
        } catch (e: UnsatisfiedLinkError) {
            logger.debug("Native library not loaded, event not tracked")
        }
    }

    /**
     * Flush pending events.
     * Mirrors Swift: CppBridge.Telemetry.flush()
     */
    fun flush() {
        lock.withLock {
            val mgr = managerPtr
            if (mgr == 0L) return
        }

        try {
            nativeFlush(managerPtr)
        } catch (e: UnsatisfiedLinkError) {
            logger.debug("Native library not loaded, cannot flush")
        }
    }

    // ========================================================================
    // HTTP CALLBACK (mirrors Swift telemetryHttpCallback)
    // ========================================================================

    /**
     * HTTP callback invoked by C++ core to send telemetry data.
     *
     * This is called from JNI when C++ telemetry manager wants to send HTTP requests.
     * Routes to HTTPService (like Swift routes to HTTPService).
     *
     * Mirrors Swift: telemetryHttpCallback(userData:endpoint:jsonBody:jsonLength:requiresAuth:)
     *
     * @param endpoint The API endpoint path (e.g., "/api/v1/sdk/telemetry")
     * @param jsonBody The JSON request body
     * @param requiresAuth Whether request needs authentication
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun telemetryHttpCallback(
        endpoint: String,
        jsonBody: String,
        requiresAuth: Boolean
    ) {
        // Launch HTTP request on background scope (like Swift Task { await })
        httpScope.launch {
            performTelemetryHTTP(endpoint, jsonBody, requiresAuth)
        }
    }

    /**
     * Perform the actual HTTP request.
     * Mirrors Swift: performTelemetryHTTP(path:json:requiresAuth:)
     */
    private suspend fun performTelemetryHTTP(path: String, json: String, requiresAuth: Boolean) {
        // Check if HTTP is configured before attempting request
        if (!HTTPService.isConfigured) {
            logger.debug("HTTP not configured, cannot send telemetry to $path. Events will be queued.")
            return
        }

        try {
            val response = HTTPService.post(path, json, requiresAuth)
            logger.debug("✅ Telemetry sent to $path")
        } catch (e: Exception) {
            logger.error("❌ HTTP failed for telemetry to $path: ${e.message}")
        }
    }

    // ========================================================================
    // LIFECYCLE MANAGEMENT
    // ========================================================================

    /**
     * Unregister telemetry and clean up resources.
     * Called during SDK shutdown.
     */
    fun unregister() {
        synchronized(lock) {
            if (!isRegistered) {
                return
            }

            shutdown()
            telemetryListener = null
            isRegistered = false
        }
    }

    // ========================================================================
    // JNI NATIVE DECLARATIONS
    // ========================================================================

    /**
     * Create telemetry manager.
     * C API: rac_telemetry_manager_create(environment, device_id, platform, sdk_version)
     *
     * @return Native pointer to telemetry manager, or 0 on failure
     */
    @JvmStatic
    private external fun nativeCreateTelemetryManager(
        environment: Int,
        deviceId: String,
        platform: String,
        sdkVersion: String
    ): Long

    /**
     * Destroy telemetry manager.
     * C API: rac_telemetry_manager_destroy(manager)
     */
    @JvmStatic
    private external fun nativeDestroyTelemetryManager(managerPtr: Long)

    /**
     * Set device info on telemetry manager.
     * C API: rac_telemetry_manager_set_device_info(manager, device_model, os_version)
     */
    @JvmStatic
    private external fun nativeSetDeviceInfo(
        managerPtr: Long,
        deviceModel: String,
        osVersion: String
    )

    /**
     * Set HTTP callback on telemetry manager.
     * C API: rac_telemetry_manager_set_http_callback(manager, callback, user_data)
     *
     * The callback will invoke [telemetryHttpCallback] via JNI.
     */
    @JvmStatic
    private external fun nativeSetHttpCallback(managerPtr: Long)

    /**
     * Track analytics event.
     * C API: rac_telemetry_manager_track_analytics(manager, event_type, event_data)
     */
    @JvmStatic
    private external fun nativeTrackAnalyticsEvent(
        managerPtr: Long,
        eventType: Int,
        eventDataJson: String?
    )

    /**
     * Flush pending events.
     * C API: rac_telemetry_manager_flush(manager)
     */
    @JvmStatic
    private external fun nativeFlush(managerPtr: Long)

    // ========================================================================
    // UTILITY FUNCTIONS (for direct Kotlin usage)
    // ========================================================================

    /**
     * Send telemetry data directly from Kotlin.
     * Utility method for sending telemetry from Kotlin code.
     */
    suspend fun sendTelemetry(
        url: String,
        jsonBody: String,
        headers: Map<String, String>? = null
    ): Pair<Int, String?> {
        return try {
            val response = HTTPService.post(url, jsonBody, requiresAuth = false)
            Pair(200, String(response, Charsets.UTF_8))
        } catch (e: Exception) {
            logger.error("sendTelemetry failed: ${e.message}")
            Pair(-1, null)
        }
    }
}
