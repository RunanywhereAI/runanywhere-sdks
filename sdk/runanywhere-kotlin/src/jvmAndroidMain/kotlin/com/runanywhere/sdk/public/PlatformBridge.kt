/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Platform-specific bridge for JVM/Android that connects RunAnywhere to CppBridge.
 * Implements the expect/actual pattern for cross-platform compatibility.
 */

package com.runanywhere.sdk.public

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.CppBridge
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeTelemetry
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
internal actual fun initializePlatformBridge(environment: SDKEnvironment, apiKey: String?, baseURL: String?) {
    logger.info("Initializing CppBridge for environment: $environment")

    val cppEnvironment =
        when (environment) {
            SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT -> CppBridge.Environment.DEVELOPMENT
            SDKEnvironment.SDK_ENVIRONMENT_STAGING -> CppBridge.Environment.STAGING
            SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION -> CppBridge.Environment.PRODUCTION
            SDKEnvironment.SDK_ENVIRONMENT_UNSPECIFIED -> CppBridge.Environment.DEVELOPMENT
        }

    // Configure telemetry base URL if provided
    if (!baseURL.isNullOrEmpty()) {
        CppBridgeTelemetry.setBaseUrl(baseURL)
        logger.info("Telemetry base URL configured: $baseURL")
    }

    CppBridge.initialize(cppEnvironment, apiKey, baseURL)

    // Wire the public EventBus to the canonical native SDKEvent stream
    // so consumers see lifecycle/error/model events emitted by C++.
    // Mirrors Swift EventBus's lazy CppBridge.Events.subscribeSDKEvents
    // call. Safe to invoke even when the native lib failed to load
    // (the actual no-ops on UnsatisfiedLinkError).
    EventBus.start()

    logger.info("CppBridge initialization complete. Native library loaded: ${CppBridge.isNativeLibraryLoaded}")
}

/**
 * Initialize CppBridge services (Phase 2).
 * This includes model assignment, platform services, and device registration.
 */
internal actual suspend fun initializePlatformBridgeServices() {
    logger.info("Initializing CppBridge services...")
    CppBridge.initializeServices()
    logger.info("CppBridge services initialization complete")
}

/**
 * Shutdown CppBridge and release resources.
 */
internal actual fun shutdownPlatformBridge() {
    logger.info("Shutting down CppBridge...")
    // Tear down the native SDKEvent subscription before C++ commons is
    // shutdown so the unsubscribe call still has a working ABI surface.
    EventBus.stop()
    CppBridge.shutdown()
    logger.info("CppBridge shutdown complete")
}

/**
 * Configure telemetry base URL.
 * This should be called before SDK initialization if using a custom backend URL.
 */
fun configureTelemetryBaseUrl(baseUrl: String) {
    CppBridgeTelemetry.setBaseUrl(baseUrl)
}
