/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Central coordinator for all C++ bridge operations.
 * Follows iOS CppBridge.swift architecture with two-phase initialization.
 */

package com.runanywhere.sdk.foundation.bridge

import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeDevice
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeEvents
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelAssignment
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgePlatform
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgePlatformAdapter
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeTelemetry
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

/**
 * CppBridge is the central coordinator for all C++ interop via JNI.
 *
 * Initialization follows a two-phase pattern:
 * - Phase 1 (synchronous): Core initialization including platform adapter registration
 * - Phase 2 (asynchronous): Service initialization for model assignment and platform services
 *
 * CRITICAL: Platform adapter must be registered FIRST before any C++ calls.
 *
 * NOTE: This SDK is backend-agnostic. Backend registration (LlamaCPP, ONNX, etc.)
 * is handled by the individual backend modules, not by the core SDK.
 */
object CppBridge {

    private const val TAG = "CppBridge"

    /**
     * SDK environment configuration.
     */
    enum class Environment {
        DEVELOPMENT,
        STAGING,
        PRODUCTION;

        /**
         * Get the C++ compatible environment value.
         */
        val cValue: Int
            get() = ordinal
    }

    @Volatile
    private var _environment: Environment = Environment.DEVELOPMENT

    @Volatile
    private var _isInitialized: Boolean = false

    @Volatile
    private var _servicesInitialized: Boolean = false

    @Volatile
    private var _nativeLibraryLoaded: Boolean = false

    private val lock = Any()

    /**
     * Current SDK environment.
     */
    val environment: Environment
        get() = _environment

    /**
     * Whether Phase 1 initialization is complete.
     */
    val isInitialized: Boolean
        get() = _isInitialized

    /**
     * Whether Phase 2 services initialization is complete.
     */
    val servicesInitialized: Boolean
        get() = _servicesInitialized

    /**
     * Whether the native commons library is loaded.
     * This only indicates the core library - backend availability is separate.
     */
    val isNativeLibraryLoaded: Boolean
        get() = _nativeLibraryLoaded

    /**
     * Phase 1: Core Initialization (Synchronous)
     *
     * Initializes the core SDK components in this order:
     * 1. Native Library Loading - Load core JNI library (if available)
     * 2. Platform Adapter - MUST be before C++ calls
     * 3. Logging configuration
     * 4. Events registration
     * 5. Telemetry initialization
     * 6. Device registration
     *
     * NOTE: Backend registration (LlamaCPP, ONNX) is NOT done here.
     * Backends are registered by the app calling LlamaCPP.register() and ONNX.register()
     * from the respective backend modules.
     *
     * @param environment The SDK environment to use
     */
    fun initialize(environment: Environment = Environment.DEVELOPMENT) {
        synchronized(lock) {
            if (_isInitialized) {
                return
            }

            _environment = environment

            // Try to load native library (optional - SDK works without it for non-inference features)
            tryLoadNativeLibrary()

            // CRITICAL: Register platform adapter FIRST before any C++ calls
            CppBridgePlatformAdapter.register()

            // Configure logging (handled by platform adapter)

            // Register telemetry HTTP callback (just sets isRegistered flag)
            CppBridgeTelemetry.register()

            // Register device callbacks (sets up JNI callbacks for C++ to call)
            CppBridgeDevice.register()

            // Initialize telemetry manager with device info
            // This creates the C++ telemetry manager and sets up HTTP callback
            initializeTelemetryManager(environment)

            // Register analytics events callback AFTER telemetry manager is initialized
            // This routes C++ events (LLM/STT/TTS) to telemetry for batching and HTTP transport
            val telemetryHandle = CppBridgeTelemetry.getTelemetryHandle()
            if (telemetryHandle != 0L) {
                CppBridgeEvents.register(telemetryHandle)
            } else {
                android.util.Log.w(TAG, "Telemetry handle not available, analytics events will not be tracked")
            }

            _isInitialized = true
        }
    }

    /**
     * Initialize the C++ telemetry manager with device info.
     * Mirrors Swift SDK's CppBridge.Telemetry.initialize(environment:)
     */
    private fun initializeTelemetryManager(environment: Environment) {
        try {
            // Get device ID (persistent UUID) - this may initialize it if not already done
            val deviceId = CppBridgeDevice.getDeviceIdCallback()
            if (deviceId.isEmpty()) {
                android.util.Log.w(TAG, "Device ID not available for telemetry initialization")
                return
            }

            // Get device info from provider or defaults
            val provider = CppBridgeDevice.deviceInfoProvider
            val deviceModel = provider?.getDeviceModel() ?: android.os.Build.MODEL ?: "unknown"
            val osVersion = provider?.getOSVersion() ?: android.os.Build.VERSION.RELEASE ?: "unknown"
            val sdkVersion = com.runanywhere.sdk.utils.SDKConstants.VERSION

            android.util.Log.i(TAG, "Initializing telemetry manager: device=$deviceId, model=$deviceModel, os=$osVersion")

            // Initialize telemetry manager with C++ via JNI
            CppBridgeTelemetry.initialize(
                environment = environment.cValue,
                deviceId = deviceId,
                deviceModel = deviceModel,
                osVersion = osVersion,
                sdkVersion = sdkVersion
            )

            android.util.Log.i(TAG, "✅ Telemetry manager initialized")
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Failed to initialize telemetry manager: ${e.message}")
        }
    }

    /**
     * Try to load the native commons library.
     * This is optional - the SDK works without it for non-inference features.
     *
     * NOTE: Backend registration (LlamaCPP, ONNX) is NOT done here.
     * Apps must call LlamaCPP.register() and ONNX.register() from the
     * respective backend modules to enable AI inference.
     */
    private fun tryLoadNativeLibrary() {
        android.util.Log.i(TAG, "Starting native library loading sequence...")

        _nativeLibraryLoaded = RunAnywhereBridge.ensureNativeLibraryLoaded()

        if (_nativeLibraryLoaded) {
            android.util.Log.i(TAG, "✅ Native commons library loaded successfully")
            android.util.Log.i(TAG, "AI inference features are AVAILABLE")
        } else {
            android.util.Log.w(TAG, "❌ Native commons library not available.")
            android.util.Log.w(TAG, "AI inference features are DISABLED.")
            android.util.Log.w(TAG, "Ensure librunanywhere_jni.so is in your APK's lib/ folder.")
        }
    }

    /**
     * Phase 2: Services Initialization (Asynchronous)
     *
     * Initializes the service components:
     * 1. Model Assignment registration
     * 2. Platform services registration
     * 3. Device registration (triggers backend call)
     *
     * Must be called after [initialize] completes.
     * Mirrors Swift SDK's CppBridge.initializeServices() + completeServicesInitialization()
     */
    suspend fun initializeServices() {
        synchronized(lock) {
            if (!_isInitialized) {
                throw IllegalStateException("CppBridge.initialize() must be called before initializeServices()")
            }

            if (_servicesInitialized) {
                return
            }

            // Register model assignment callbacks
            CppBridgeModelAssignment.register()

            // Register platform services callbacks
            CppBridgePlatform.register()

            // Flush any queued telemetry events
            CppBridgeTelemetry.flush()
            android.util.Log.d(TAG, "Flushed queued telemetry events")

            // Trigger device registration with backend (non-blocking, best-effort)
            // Mirrors Swift SDK's CppBridge.Device.registerIfNeeded(environment:)
            try {
                val success = CppBridgeDevice.triggerRegistration(
                    environment = _environment.cValue,
                    buildToken = null // TODO: Get build token for development mode
                )
                if (success) {
                    android.util.Log.i(TAG, "✅ Device registration triggered")
                } else {
                    android.util.Log.w(TAG, "Device registration not triggered (may already be registered)")
                }
            } catch (e: Exception) {
                // Non-critical failure - device registration is best-effort
                android.util.Log.w(TAG, "Device registration failed (non-critical): ${e.message}")
            }

            _servicesInitialized = true
        }
    }

    /**
     * Shutdown the SDK and release all resources.
     *
     * Unregisters all extensions in reverse order of registration.
     */
    fun shutdown() {
        synchronized(lock) {
            if (!_isInitialized) {
                return
            }

            // Unregister Phase 2 services (reverse order)
            if (_servicesInitialized) {
                CppBridgePlatform.unregister()
                CppBridgeModelAssignment.unregister()
            }

            // Unregister Phase 1 core extensions (reverse order)
            CppBridgeDevice.unregister()
            CppBridgeTelemetry.unregister()
            CppBridgeEvents.unregister()
            CppBridgePlatformAdapter.unregister()

            _servicesInitialized = false
            _isInitialized = false
        }
    }

    /**
     * Check if the C++ core is initialized.
     *
     * @return true if rac_is_initialized() returns true
     */
    fun isNativeInitialized(): Boolean {
        // TODO: Call rac_is_initialized()
        return _isInitialized
    }
}
