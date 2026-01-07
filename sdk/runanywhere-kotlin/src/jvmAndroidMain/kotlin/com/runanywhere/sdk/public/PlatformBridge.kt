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
import kotlinx.coroutines.runBlocking

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

    val cppEnvironment = when (environment) {
        SDKEnvironment.DEVELOPMENT -> CppBridge.Environment.DEVELOPMENT
        SDKEnvironment.STAGING -> CppBridge.Environment.STAGING
        SDKEnvironment.PRODUCTION -> CppBridge.Environment.PRODUCTION
    }

    // Configure telemetry base URL if provided
    if (!baseURL.isNullOrEmpty()) {
        CppBridgeTelemetry.setBaseUrl(baseURL)
        logger.info("Telemetry base URL configured: $baseURL")
    }

    CppBridge.initialize(cppEnvironment, apiKey, baseURL)

    logger.info("CppBridge initialization complete. Native library loaded: ${CppBridge.isNativeLibraryLoaded}")
}

/**
 * Initialize CppBridge services (Phase 2).
 * This includes model assignment, platform services, and device registration.
 */
internal actual fun initializePlatformBridgeServices() {
    logger.info("Initializing CppBridge services...")

    // Use runBlocking to call the suspend function
    // This is safe because services initialization is typically called once
    runBlocking {
        CppBridge.initializeServices()
    }

    logger.info("CppBridge services initialization complete")
}

/**
 * Shutdown CppBridge and release resources.
 */
internal actual fun shutdownPlatformBridge() {
    logger.info("Shutting down CppBridge...")
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
