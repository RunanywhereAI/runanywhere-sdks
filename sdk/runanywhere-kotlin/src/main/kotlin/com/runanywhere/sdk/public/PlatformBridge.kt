/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Platform-specific bridge for JVM/Android that connects RunAnywhere to CppBridge.
 * Implements the expect/actual pattern for cross-platform compatibility.
 */

package com.runanywhere.sdk.public

import com.runanywhere.sdk.foundation.bridge.CppBridge
import com.runanywhere.sdk.foundation.bridge.HTTPClientAdapter
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeDevice
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeTelemetry
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.configuration.SDKEnvironment
import com.runanywhere.sdk.public.events.EventBus

private const val TAG = "PlatformBridge"
private val logger = SDKLogger(TAG)

/**
 * Initialize the CppBridge with the given environment.
 * This loads the native libraries and registers platform adapters.
 *
 * @param environment SDK environment
 * @param apiKey API key for authentication (required for production/staging)
 * @param baseURL Backend API base URL (required for production/staging)
 */
internal fun initializePlatformBridge(environment: SDKEnvironment, apiKey: String?, baseURL: String?) {
    logger.debug("Initializing CppBridge for environment: $environment")

    // Normalize UNSPECIFIED -> DEVELOPMENT so the downstream C-ABI call gets a valid value.
    val resolvedEnvironment =
        if (environment == SDKEnvironment.SDK_ENVIRONMENT_UNSPECIFIED) {
            SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT
        } else {
            environment
        }

    // Configure telemetry base URL if provided
    if (!baseURL.isNullOrEmpty()) {
        CppBridgeTelemetry.setBaseUrl(baseURL)
        logger.debug("Telemetry base URL configured: $baseURL")
    }

    CppBridge.initialize(resolvedEnvironment, apiKey, baseURL)

    // Wire the public EventBus to the canonical native SDKEvent stream
    // so consumers see lifecycle/error/model events emitted by C++.
    // Mirrors Swift EventBus's lazy CppBridge.Events.subscribeSDKEvents
    // call. Safe to invoke even when the native lib failed to load
    // (the actual no-ops on UnsatisfiedLinkError).
    EventBus.start()

    logger.debug("CppBridge initialization complete. Native library loaded: ${CppBridge.isNativeLibraryLoaded}")
}

/**
 * Initialize CppBridge services (Phase 2).
 * This includes model assignment, platform services, and device registration.
 *
 * Returns `true` when the HTTP client adapter was configured with a usable
 * external URL + credential, so commonMain can mark `_hasCompletedHTTPSetup`
 * accordingly. Returns `false` for the offline/local-only path where Phase 2
 * still completes but auth/device-registration/telemetry are deferred until
 * the next [RunAnywhere.ensureServicesReady] call retries HTTP setup.
 */
internal suspend fun initializePlatformBridgeServices(): Boolean {
    logger.debug("Initializing CppBridge services...")
    CppBridge.initializeServices()
    val httpConfigured = HTTPClientAdapter.isConfigured
    logger.debug(
        "CppBridge services initialization complete (httpConfigured=$httpConfigured)",
    )
    return httpConfigured
}

/**
 * Shutdown CppBridge and release resources.
 */
internal fun shutdownPlatformBridge() {
    logger.debug("Shutting down CppBridge...")
    // Tear down the native SDKEvent subscription before C++ commons is
    // shutdown so the unsubscribe call still has a working ABI surface.
    EventBus.stop()
    CppBridge.shutdown()
    logger.debug("CppBridge shutdown complete")
}

// Auth + device-state actuals — route directly through `rac_auth_*` and
// CppBridgeDevice thunks. No Kotlin-side cache.

internal fun platformGetUserId(): String? = RunAnywhereBridge.racAuthGetUserId()

internal fun platformGetOrganizationId(): String? = RunAnywhereBridge.racAuthGetOrganizationId()

internal fun platformIsAuthenticated(): Boolean = RunAnywhereBridge.racAuthIsAuthenticated()

internal fun platformIsDeviceRegistered(): Boolean = CppBridgeDevice.isRegistered()

internal fun platformDeviceId(): String =
    CppBridgeDevice.getDeviceId() ?: RunAnywhereBridge.racAuthGetDeviceId() ?: ""
