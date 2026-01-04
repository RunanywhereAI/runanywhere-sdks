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

private val logger = SDKLogger("PlatformBridge")

/**
 * Initialize the CppBridge with the given environment.
 * This loads the native libraries and registers platform adapters.
 *
 * @param environment SDK environment
 * @param apiKey Optional API key for authentication
 * @param baseURL Optional backend API base URL
 */
internal actual fun initializePlatformBridge(
    environment: SDKEnvironment,
    apiKey: String?,
    baseURL: String?
) {
    logger.info("Initializing CppBridge for environment: $environment")

    val cppEnvironment = when (environment) {
        SDKEnvironment.DEVELOPMENT -> CppBridge.Environment.DEVELOPMENT
        SDKEnvironment.STAGING -> CppBridge.Environment.STAGING
        SDKEnvironment.PRODUCTION -> CppBridge.Environment.PRODUCTION
    }

    CppBridge.initialize(cppEnvironment, apiKey, baseURL)

    logger.info("CppBridge initialization complete. Native library loaded: ${CppBridge.isNativeLibraryLoaded}")
}

/**
 * Initialize CppBridge services (Phase 2).
 */
internal actual fun initializePlatformBridgeServices() {
    logger.info("Initializing CppBridge services...")
    // Note: initializeServices is suspend, but we're in non-suspend context
    // For now, we skip the services initialization as it's called separately
    logger.info("CppBridge services initialization deferred")
}

/**
 * Shutdown CppBridge and release resources.
 */
internal actual fun shutdownPlatformBridge() {
    logger.info("Shutting down CppBridge...")
    CppBridge.shutdown()
    logger.info("CppBridge shutdown complete")
}
