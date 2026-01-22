/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Central coordinator for all C++ bridge operations.
 * Follows iOS CppBridge.swift architecture with two-phase initialization.
 */

package com.runanywhere.sdk.foundation.bridge

import com.runanywhere.sdk.foundation.Logging
import com.runanywhere.sdk.foundation.SDKEnvironment
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeAuth
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeDevice
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeEvents
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelAssignment
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgePlatform
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgePlatformAdapter
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeTelemetry
import com.runanywhere.sdk.foundation.logging.SentryDestination
import com.runanywhere.sdk.foundation.logging.SentryManager
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
    private val logger = SDKLogger(TAG)

    /**
     * SDK environment configuration.
     */
    enum class Environment {
        DEVELOPMENT,
        STAGING,
        PRODUCTION,
        ;

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
     * Phase 1: Core Initialization (Synchronous, ~1-5ms, NO network calls)
     *
     * This is a fast, synchronous initialization that can be safely called from any thread,
     * including the main/UI thread. It does NOT make any network calls.
     *
     * Initializes the core SDK components in this order:
     * 1. Native Library Loading - Load core JNI library (if available)
     * 2. Platform Adapter - MUST be before C++ calls
     * 3. Logging configuration
     * 4. Events registration
     * 5. Telemetry configuration (stores credentials, no network)
     *
     * **Important:** Authentication and device registration happen in Phase 2 ([initializeServices]),
     * which MUST be called from a background thread (e.g., `Dispatchers.IO`).
     *
     * NOTE: Backend registration (LlamaCPP, ONNX) is NOT done here.
     * Backends are registered by the app calling LlamaCPP.register() and ONNX.register()
     * from the respective backend modules.
     *
     * Mirrors Swift SDK's initialize() which is also synchronous with no network calls.
     *
     * @param environment The SDK environment to use
     * @param apiKey API key for authentication (required for production/staging)
     * @param baseURL Backend API base URL (required for production/staging)
     */
    fun initialize(
        environment: Environment = Environment.DEVELOPMENT,
        apiKey: String? = null,
        baseURL: String? = null,
    ) {
        synchronized(lock) {
            if (_isInitialized) {
                return
            }

            val initStartTime = System.currentTimeMillis()

            _environment = environment

            // Try to load native library (optional - SDK works without it for non-inference features)
            tryLoadNativeLibrary()

            // CRITICAL: Register platform adapter FIRST before any C++ calls
            CppBridgePlatformAdapter.register()

            // Configure logging with Sentry integration
            // Setup Sentry hooks so Logging can trigger Sentry setup/teardown
            setupSentryHooks(environment)

            // Initialize Sentry if enabled for this environment (staging/production)
            if (environment != Environment.DEVELOPMENT) {
                setupSentryLogging(environment)
            }

            // Register telemetry HTTP callback (just sets isRegistered flag)
            CppBridgeTelemetry.register()

            // CRITICAL: Set environment early so CppBridgeDevice.isDeviceRegisteredCallback()
            // can determine correct behavior for production/staging modes
            CppBridgeTelemetry.setEnvironment(environment.cValue)

            // Configure telemetry base URL and API key ONLY for production/staging mode
            // In development mode, we use Supabase URL from C++ dev config
            // NOTE: Authentication is deferred to Phase 2 (initializeServices) to avoid blocking
            // This matches Swift SDK where authentication is done in completeServicesInitialization()
            // Using warn() for debug logs to ensure visibility in PRODUCTION mode (which filters INFO)
            logger.warn("🔍 CppBridge.initialize: environment=$environment, apiKey=${if (apiKey.isNullOrEmpty()) "EMPTY" else "SET (${apiKey?.length} chars)"}, baseURL=${baseURL?.take(50)}")
            if (environment != Environment.DEVELOPMENT) {
                if (!baseURL.isNullOrEmpty()) {
                    CppBridgeTelemetry.setBaseUrl(baseURL)
                    logger.warn("✅ Telemetry base URL set: ${baseURL.take(50)}...")
                } else {
                    logger.warn("⚠️ baseURL is null or empty, not setting telemetry base URL")
                }
                if (!apiKey.isNullOrEmpty()) {
                    CppBridgeTelemetry.setApiKey(apiKey)
                    logger.warn("✅ Telemetry API key set (${apiKey.length} chars)")
                } else {
                    logger.warn("⚠️ apiKey is null or empty, not setting telemetry API key")
                }
                // Verify values were stored correctly
                val storedBaseUrl = CppBridgeTelemetry.getBaseUrl()
                val storedApiKey = CppBridgeTelemetry.getApiKey()
                logger.warn("🔍 Verification: storedBaseUrl=${storedBaseUrl?.take(50)}, storedApiKey=${if (storedApiKey.isNullOrEmpty()) "EMPTY" else "SET (${storedApiKey?.length} chars)"}")
                // Store credentials for Phase 2 authentication
                // Authentication is deferred to initializeServices() which runs on background thread
                logger.debug("Production/staging mode: authentication will occur in Phase 2 (initializeServices)")
            } else {
                logger.debug("Development mode: using Supabase URL from C++ dev config")
            }

            // Register device callbacks (sets up JNI callbacks for C++ to call)
            CppBridgeDevice.register()

            // Initialize SDK config with version, platform, and auth info
            // This is REQUIRED for device registration to use the correct sdk_version
            // Mirrors Swift SDK's rac_sdk_init() call in CppBridge+State.swift
            initializeSdkConfig(environment, apiKey, baseURL)

            // Initialize telemetry manager with device info
            // This creates the C++ telemetry manager and sets up HTTP callback
            initializeTelemetryManager(environment)

            // Register analytics events callback AFTER telemetry manager is initialized
            // This routes C++ events (LLM/STT/TTS) to telemetry for batching and HTTP transport
            val telemetryHandle = CppBridgeTelemetry.getTelemetryHandle()
            if (telemetryHandle != 0L) {
                CppBridgeEvents.register(telemetryHandle)
                // Emit SDK init started event (mirroring Swift SDK)
                CppBridgeEvents.emitSDKInitStarted()
            } else {
                logger.warn("Telemetry handle not available, analytics events will not be tracked")
            }

            _isInitialized = true

            // Emit SDK init completed event with duration
            val initDurationMs = System.currentTimeMillis() - initStartTime
            CppBridgeEvents.emitSDKInitCompleted(initDurationMs.toDouble())
            logger.info("✅ Phase 1 complete in ${initDurationMs}ms (${environment.name})")
        }
    }

    /**
     * Initialize the C++ telemetry manager with device info.
     * Mirrors Swift SDK's CppBridge.Telemetry.initialize(environment:)
     *
     * Note: If device ID is unavailable (secure storage failure), telemetry is skipped
     * to avoid creating orphaned/duplicate device records. The app continues to function.
     */
    private fun initializeTelemetryManager(environment: Environment) {
        try {
            // Get device ID (persistent UUID) - this may initialize it if not already done
            val deviceId = CppBridgeDevice.getDeviceIdCallback()

            if (deviceId.isEmpty()) {
                // Device ID unavailable - likely secure storage issue
                // Skip telemetry to avoid creating orphaned records with temporary IDs
                logger.error(
                    "Device ID unavailable - telemetry will be disabled for this session. " +
                        "This usually indicates secure storage is not properly initialized. " +
                        "Ensure AndroidPlatformContext.initialize() is called before SDK initialization.",
                )
                return
            }

            // Get device info from provider or defaults
            val provider = CppBridgeDevice.deviceInfoProvider
            val deviceModel = provider?.getDeviceModel() ?: getDefaultDeviceModel()
            val osVersion = provider?.getOSVersion() ?: getDefaultOsVersion()
            val sdkVersion = com.runanywhere.sdk.utils.SDKConstants.VERSION

            logger.info("Initializing telemetry manager: device=$deviceId, model=$deviceModel, os=$osVersion")

            // Initialize telemetry manager with C++ via JNI
            CppBridgeTelemetry.initialize(
                environment = environment.cValue,
                deviceId = deviceId,
                deviceModel = deviceModel,
                osVersion = osVersion,
                sdkVersion = sdkVersion,
            )

            logger.info("✅ Telemetry manager initialized")
        } catch (e: Exception) {
            logger.error("Failed to initialize telemetry manager: ${e.message}")
        }
    }

    /**
     * Initialize SDK configuration with version, platform, and auth info.
     *
     * This sets up the C++ rac_sdk_config which is used by device registration
     * to include the correct sdk_version (instead of "unknown").
     *
     * Mirrors Swift SDK's rac_sdk_init() call in CppBridge+State.swift
     *
     * @param environment SDK environment
     * @param apiKey API key for authentication (required for production/staging)
     * @param baseURL Backend API base URL (required for production/staging)
     */
    private fun initializeSdkConfig(environment: Environment, apiKey: String?, baseURL: String?) {
        try {
            val deviceId = CppBridgeDevice.getDeviceIdCallback()
            val platform = "android"
            val sdkVersion = com.runanywhere.sdk.utils.SDKConstants.SDK_VERSION

            logger.info("Initializing SDK config: version=$sdkVersion, platform=$platform, env=${environment.name}")
            if (!apiKey.isNullOrEmpty()) {
                logger.info("API key provided: ${apiKey.take(10)}...")
            }
            if (!baseURL.isNullOrEmpty()) {
                logger.info("Base URL: $baseURL")
            }

            val result =
                RunAnywhereBridge.racSdkInit(
                    environment = environment.cValue,
                    deviceId = deviceId.ifEmpty { null },
                    platform = platform,
                    sdkVersion = sdkVersion,
                    apiKey = apiKey,
                    baseUrl = baseURL,
                )

            if (result == 0) {
                logger.info("✅ SDK config initialized with version: $sdkVersion")
            } else {
                logger.warn("SDK config init returned: $result")
            }
        } catch (e: Exception) {
            logger.error("Failed to initialize SDK config: ${e.message}")
        }
    }

    /**
     * Get default device model (cross-platform fallback).
     */
    private fun getDefaultDeviceModel(): String {
        return try {
            val buildClass = Class.forName("android.os.Build")
            buildClass.getField("MODEL").get(null) as? String ?: "unknown"
        } catch (e: Exception) {
            System.getProperty("os.name") ?: "unknown"
        }
    }

    /**
     * Get default OS version (cross-platform fallback).
     */
    private fun getDefaultOsVersion(): String {
        return try {
            val versionClass = Class.forName("android.os.Build\$VERSION")
            versionClass.getField("RELEASE").get(null) as? String ?: "unknown"
        } catch (e: Exception) {
            System.getProperty("os.version") ?: "unknown"
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
        logger.info("Starting native library loading sequence...")

        _nativeLibraryLoaded = RunAnywhereBridge.ensureNativeLibraryLoaded()

        if (_nativeLibraryLoaded) {
            logger.info("✅ Native commons library loaded successfully")
            logger.info("AI inference features are AVAILABLE")
        } else {
            logger.warn("❌ Native commons library not available.")
            logger.warn("AI inference features are DISABLED.")
            logger.warn("Ensure librunanywhere_jni.so is in your APK's lib/ folder.")
        }
    }

    /**
     * Phase 2: Services Initialization (Asynchronous)
     *
     * Initializes the service components:
     * 1. Authentication with backend (production/staging only, makes HTTP calls)
     * 2. Model Assignment registration
     * 3. Platform services registration
     * 4. Device registration (triggers backend call)
     *
     * Must be called after [initialize] completes.
     * Must be called from a background thread (e.g., Dispatchers.IO) as it makes network calls.
     * Mirrors Swift SDK's completeServicesInitialization()
     */
    suspend fun initializeServices() {
        synchronized(lock) {
            if (!_isInitialized) {
                throw IllegalStateException("CppBridge.initialize() must be called before initializeServices()")
            }

            if (_servicesInitialized) {
                return
            }

            // Step 1: Authenticate with backend for production/staging mode
            // This is done in Phase 2 (not Phase 1) to avoid blocking main thread
            // Mirrors Swift SDK's CppBridge.Auth.authenticate() in completeServicesInitialization()
            // Using warn() for debug logs to ensure visibility in PRODUCTION mode (which filters INFO)
            logger.warn("🔍 initializeServices: environment=$_environment")
            if (_environment != Environment.DEVELOPMENT) {
                val baseUrl = CppBridgeTelemetry.getBaseUrl()
                val apiKey = CppBridgeTelemetry.getApiKey()
                logger.warn("🔍 initializeServices: baseUrl=${baseUrl?.take(50)}, apiKey=${if (apiKey.isNullOrEmpty()) "EMPTY" else "SET (${apiKey.length} chars)"}")

                if (!apiKey.isNullOrEmpty() && !baseUrl.isNullOrEmpty()) {
                    try {
                        logger.warn("🔐 Authenticating with backend at $baseUrl...")
                        val deviceId = CppBridgeDevice.getDeviceId() ?: CppBridgeDevice.getDeviceIdCallback()
                        logger.warn("🔐 Using deviceId: $deviceId")
                        CppBridgeAuth.authenticate(
                            apiKey = apiKey,
                            baseUrl = baseUrl,
                            deviceId = deviceId,
                            platform = "android",
                            sdkVersion = com.runanywhere.sdk.utils.SDKConstants.SDK_VERSION,
                        )
                        logger.warn("✅ Authentication successful!")
                    } catch (e: Exception) {
                        logger.error("❌ Authentication failed: ${e.message}")
                        logger.error("❌ Exception type: ${e.javaClass.simpleName}")
                        e.printStackTrace()
                        logger.warn("SDK will continue but API requests may fail")
                        // Non-fatal: continue with services initialization
                    }
                } else {
                    logger.warn("⚠️ Missing API key or base URL for authentication - apiKey=${apiKey?.length}, baseUrl=${baseUrl?.length}")
                }
            }

            // Step 2: Register model assignment callbacks
            // Only auto-fetch in staging/production, not development
            val shouldAutoFetch = _environment != Environment.DEVELOPMENT
            CppBridgeModelAssignment.register(autoFetch = shouldAutoFetch)

            // Register platform services callbacks
            CppBridgePlatform.register()

            // Flush any queued telemetry events now that HTTP should be configured
            // This ensures events queued during Phase 1 initialization are sent
            CppBridgeTelemetry.flush()
            logger.debug("Flushed queued telemetry events after services initialization")

            // Trigger device registration with backend (non-blocking, best-effort)
            // Mirrors Swift SDK's CppBridge.Device.registerIfNeeded(environment:)
            try {
                val deviceId = CppBridgeDevice.getDeviceIdCallback()

                // Get build token for development mode (mirrors Swift SDK)
                // Swift: let buildTokenString = environment == .development ? CppBridge.DevConfig.buildToken : nil
                val buildToken =
                    if (_environment == Environment.DEVELOPMENT) {
                        try {
                            val token = RunAnywhereBridge.racDevConfigGetBuildToken()
                            if (!token.isNullOrEmpty()) {
                                logger.debug("Using build token from dev config for device registration")
                                token
                            } else {
                                logger.debug("No build token available in dev config")
                                null
                            }
                        } catch (e: Exception) {
                            logger.warn("Failed to get build token: ${e.message}")
                            null
                        }
                    } else {
                        null // Build token only used in development mode
                    }

                val success =
                    CppBridgeDevice.triggerRegistration(
                        environment = _environment.cValue,
                        buildToken = buildToken,
                    )
                if (success) {
                    logger.info("✅ Device registration triggered")
                    // Emit device registered event
                    CppBridgeEvents.emitDeviceRegistered(deviceId)
                } else {
                    logger.warn("Device registration not triggered (may already be registered)")
                }
            } catch (e: Exception) {
                // Non-critical failure - device registration is best-effort
                logger.warn("Device registration failed (non-critical): ${e.message}")
                // Emit device registration failed event
                CppBridgeEvents.emitDeviceRegistrationFailed(e.message ?: "Unknown error")
            }

            _servicesInitialized = true
            logger.info("✅ Services initialization complete")
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

            // Teardown Sentry logging
            teardownSentryLogging()

            // Clear Sentry hooks
            Logging.sentrySetupHook = null
            Logging.sentryTeardownHook = null

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

    // =============================================================================
    // SENTRY LOGGING INTEGRATION
    // =============================================================================

    /**
     * Setup Sentry hooks so Logging can trigger Sentry setup/teardown dynamically.
     *
     * This allows runtime enabling/disabling of Sentry logging via Logging.setSentryLoggingEnabled()
     */
    private fun setupSentryHooks(environment: Environment) {
        Logging.sentrySetupHook = {
            setupSentryLogging(environment)
        }

        Logging.sentryTeardownHook = {
            teardownSentryLogging()
        }
    }

    /**
     * Initialize Sentry logging for error tracking.
     *
     * Matches iOS SDK's setupSentryLogging() in Logging class.
     *
     * @param environment SDK environment for tagging Sentry events
     */
    private fun setupSentryLogging(environment: Environment) {
        val sdkEnvironment =
            when (environment) {
                Environment.DEVELOPMENT -> SDKEnvironment.DEVELOPMENT
                Environment.STAGING -> SDKEnvironment.STAGING
                Environment.PRODUCTION -> SDKEnvironment.PRODUCTION
            }

        try {
            // Initialize Sentry manager
            SentryManager.initialize(environment = sdkEnvironment)

            if (SentryManager.isInitialized) {
                // Add Sentry destination to logging system
                Logging.addDestinationSync(SentryDestination())
                logger.info("✅ Sentry logging initialized")
            }
        } catch (e: Exception) {
            logger.error("Failed to setup Sentry logging: ${e.message}")
        }
    }

    /**
     * Teardown Sentry logging.
     */
    private fun teardownSentryLogging() {
        try {
            // Remove Sentry destination from logging system
            val sentryDestination =
                Logging.destinations.find {
                    it.identifier == SentryDestination.DESTINATION_ID
                }
            if (sentryDestination != null) {
                Logging.removeDestinationSync(sentryDestination)
            }

            // Close Sentry manager
            SentryManager.close()
            logger.info("Sentry logging disabled")
        } catch (e: Exception) {
            logger.error("Failed to teardown Sentry logging: ${e.message}")
        }
    }
}
