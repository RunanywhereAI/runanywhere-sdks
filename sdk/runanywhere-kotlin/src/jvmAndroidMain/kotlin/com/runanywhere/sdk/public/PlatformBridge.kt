/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Platform-specific bridge for JVM/Android that connects RunAnywhere to CppBridge.
 * Implements the expect/actual pattern for cross-platform compatibility.
 */

package com.runanywhere.sdk.public

import android.util.Log
import com.runanywhere.sdk.foundation.bridge.CppBridge

private const val TAG = "PlatformBridge"

/**
 * Initialize the CppBridge with the given environment.
 * This loads the native libraries and registers platform adapters.
 */
internal actual fun initializePlatformBridge(environment: SDKEnvironment) {
    Log.i(TAG, "Initializing CppBridge for environment: $environment")

    val cppEnvironment = when (environment) {
        SDKEnvironment.DEVELOPMENT -> CppBridge.Environment.DEVELOPMENT
        SDKEnvironment.STAGING -> CppBridge.Environment.STAGING
        SDKEnvironment.PRODUCTION -> CppBridge.Environment.PRODUCTION
    }

    CppBridge.initialize(cppEnvironment)

    Log.i(TAG, "CppBridge initialization complete. Native library loaded: ${CppBridge.isNativeLibraryLoaded}")
}

/**
 * Initialize CppBridge services (Phase 2).
 */
internal actual fun initializePlatformBridgeServices() {
    Log.i(TAG, "Initializing CppBridge services...")
    // Note: initializeServices is suspend, but we're in non-suspend context
    // For now, we skip the services initialization as it's called separately
    Log.i(TAG, "CppBridge services initialization deferred")
}

/**
 * Shutdown CppBridge and release resources.
 */
internal actual fun shutdownPlatformBridge() {
    Log.i(TAG, "Shutting down CppBridge...")
    CppBridge.shutdown()
    Log.i(TAG, "CppBridge shutdown complete")
}
