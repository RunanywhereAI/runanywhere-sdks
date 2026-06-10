/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Central coordinator for all C++ bridge operations.
 * Follows iOS CppBridge.swift architecture with two-phase initialization.
 */

package com.runanywhere.sdk.foundation.bridge

import com.runanywhere.sdk.foundation.bridge.CppBridge.initialize
import com.runanywhere.sdk.foundation.bridge.CppBridge.initializeServices
import com.runanywhere.sdk.foundation.bridge.CppBridge.shutdown
import com.runanywhere.sdk.foundation.bridge.CppBridge.shutdownSuspending
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeAuth
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeDevConfig
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeDevice
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeFileManager
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeLLM
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelPaths
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgePlatformAdapter
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeSDKEvents
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeSTT
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeSdkInit
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeState
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeTTS
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeTelemetry
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVAD
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVLM
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVoiceAgent
import com.runanywhere.sdk.foundation.constants.SDKConstants
import com.runanywhere.sdk.httptransport.OkHttpHttpTransport
import com.runanywhere.sdk.infrastructure.logging.Logging
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.infrastructure.logging.SentryDestination
import com.runanywhere.sdk.infrastructure.logging.SentryManager
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.configuration.SDKEnvironment
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking

/**
 * CppBridge is the central coordinator for all C++ interop via JNI.
 *
 * Initialization follows a two-phase pattern:
 * - Phase 1 (synchronous): Core initialization including platform adapter registration
 * - Phase 2 (asynchronous): Platform service wiring, then commons-owned init orchestration
 *
 * CRITICAL: Platform adapter must be registered FIRST before any C++ calls.
 *
 * NOTE: This SDK is backend-agnostic. Backend registration (LlamaCPP, ONNX, etc.)
 * is handled by the individual backend modules, not by the core SDK.
 */
object CppBridge {
    private const val TAG = "CppBridge"
    private val logger = SDKLogger(TAG)

    @Volatile
    private var _environment: SDKEnvironment = SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT

    private val lock = Any()

    /** Coroutine scope for async SDK operations, cancelled on shutdown */
    private val sdkScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /**
     * Current SDK environment.
     */
    val environment: SDKEnvironment
        get() = _environment

    /**
     * Whether Phase 1 initialization is complete.
     *
     * Delegates to [CppBridgeState] which is the canonical owner of the
     * runtime gate flags.
     */
    val isInitialized: Boolean
        get() = CppBridgeState.isInitialized

    /**
     * Whether Phase 2 services initialization is complete.
     *
     * Delegates to [CppBridgeState] which is the canonical owner of the
     * runtime gate flags.
     */
    val servicesInitialized: Boolean
        get() = CppBridgeState.servicesInitialized

    /**
     * Whether the native commons library is loaded.
     * This only indicates the core library - backend availability is separate.
     *
     * Delegates to [CppBridgeState] which is the canonical owner of the
     * runtime gate flags.
     */
    val isNativeLibraryLoaded: Boolean
        get() = CppBridgeState.nativeLibraryLoaded

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
     * **Important:** Authentication, device registration, assignment fetch,
     * telemetry flush, and downloaded-model discovery happen in commons Phase
     * 2 (`rac_sdk_init_phase2_proto`), after [initializeServices] has wired
     * the platform callbacks/transport on a background thread.
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
        environment: SDKEnvironment = SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
        apiKey: String? = null,
        baseURL: String? = null,
    ) {
        synchronized(lock) {
            if (CppBridgeState.isInitialized) {
                return
            }

            val initStartTime = System.currentTimeMillis()

            _environment = environment

            // Try to load native library (optional - SDK works without it for non-inference features)
            tryLoadNativeLibrary()

            // CRITICAL: Register platform adapter FIRST before any C++ calls
            CppBridgePlatformAdapter.register()

            // Initialize the native auth manager with a secure-storage
            // vtable backed by the platform adapter secureGet/secureSet/
            // secureDelete callbacks. Must happen AFTER the adapter is
            // registered (the JNI-side vtable delegates to it) and BEFORE any
            // auth operation. Without this, tokens are lost on every process
            // restart because rac_auth_save_tokens / rac_auth_clear are no-ops.
            CppBridgeAuth.initialize()

            // Install the OkHttp HTTP transport BEFORE
            // any network I/O happens (device registration, model assignment
            // fetch, telemetry, auth all go through rac_http_request_*). The
            // adapter gives us the Android system trust store + proxy +
            // NetworkSecurityConfig for free and fixes the rc=77 SSL failure
            // on ~5% of devices. Safe to no-op if the native lib is missing.
            registerOkHttpTransport()

            setupSentryHooks(environment)

            // Initialize Sentry if enabled for this environment (staging/production)
            if (environment != SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT) {
                setupSentryLogging(environment)
            }

            // Register telemetry HTTP callback (just sets isRegistered flag)
            CppBridgeTelemetry.register()

            // CRITICAL: Set environment early so CppBridgeDevice.isDeviceRegisteredCallback()
            // can determine correct behavior for production/staging modes
            CppBridgeTelemetry.setEnvironment(environment)

            // Configure telemetry base URL and API key ONLY for production/staging mode.
            // In development mode, commons reads Supabase URL/key from dev config.
            // Networked auth is deferred to commons Phase 2 to avoid blocking
            // Phase 1 on the UI thread.
            if (environment != SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT) {
                if (!baseURL.isNullOrEmpty()) {
                    CppBridgeTelemetry.setBaseUrl(baseURL)
                    logger.debug("Telemetry base URL configured")
                }
                if (!apiKey.isNullOrEmpty()) {
                    CppBridgeTelemetry.setApiKey(apiKey)
                    logger.debug("Telemetry API key configured")
                }
                logger.debug("Production/staging mode: authentication will occur in Phase 2 (initializeServices)")
            } else {
                if (CppBridgeDevConfig.hasUsableSupabaseConfig) {
                    logger.debug("Development mode: using Supabase URL from C++ dev config")
                } else {
                    logger.debug("Development mode: no usable Supabase config; external telemetry/auth/device registration disabled")
                }
            }

            CppBridgeDevice.register()

            // REQUIRED before device registration so it uses the correct sdk_version.
            // Mirrors Swift SDK's rac_sdk_init() call in CppBridge+State.swift
            initializeSdkConfig(environment, apiKey, baseURL)

            initializeTelemetryManager(environment)

            // Register analytics events callback AFTER telemetry manager is initialized
            // This routes C++ events (LLM/STT/TTS) to telemetry for batching and HTTP transport
            val telemetryHandle = CppBridgeTelemetry.getTelemetryHandle()
            if (telemetryHandle != 0L) {
                CppBridgeSDKEvents.register(telemetryHandle)
                // Emit SDK init started event (mirroring Swift SDK)
                CppBridgeSDKEvents.emitSDKInitStarted()
            } else {
                logger.warn("Telemetry handle not available, analytics events will not be tracked")
            }

            // Register file manager I/O callbacks for C++ file management
            CppBridgeFileManager.register()

            // Eagerly materialize the model storage base directory AND push it
            // into the C++ core via rac_model_paths_set_base_dir. Without this,
            // rac_model_paths_get_model_folder() returns RAC_ERROR_NOT_INITIALIZED
            // and any rac_download_plan_proto() call fails with "failed to
            // compute model storage path" — blocking all model downloads.
            // CppBridgeModelPaths.pathProvider must already be set by the app
            // (e.g., AndroidPlatformContext.initialize() wires context.filesDir).
            try {
                val baseDir = CppBridgeModelPaths.getBaseDirectory()
                logger.debug("Model storage base directory materialized: $baseDir")
            } catch (t: Throwable) {
                logger.warn("Failed to materialize model storage base dir: ${t.message}")
            }

            CppBridgeState.isInitialized = true

            // Emit SDK init completed event with duration
            val initDurationMs = System.currentTimeMillis() - initStartTime
            CppBridgeSDKEvents.emitSDKInitCompleted(initDurationMs.toDouble())
            logger.debug("Phase 1 complete in ${initDurationMs}ms ($environment)")
        }
    }

    /**
     * Initialize the C++ telemetry manager with device info.
     * Mirrors Swift SDK's CppBridge.Telemetry.initialize(environment:)
     *
     * Note: If device ID is unavailable (secure storage failure), telemetry is skipped
     * to avoid creating orphaned/duplicate device records. The app continues to function.
     */
    private fun initializeTelemetryManager(environment: SDKEnvironment) {
        try {
            // getDeviceIdCallback() may lazily initialize the persistent UUID
            val deviceId = CppBridgeDevice.getDeviceIdCallback()

            if (deviceId.isEmpty()) {
                // Skip telemetry rather than create orphaned records with a temporary ID
                logger.error(
                    "Device ID unavailable - telemetry will be disabled for this session. " + "This usually indicates secure storage is not properly initialized. " + "Ensure AndroidPlatformContext.initialize() is called before SDK initialization.",
                )
                return
            }

            val provider = CppBridgeDevice.deviceInfoProvider
            val deviceModel = provider?.getDeviceModel() ?: getDefaultDeviceModel()
            val osVersion = provider?.getOSVersion() ?: getDefaultOsVersion()
            val sdkVersion = SDKConstants.VERSION

            logger.debug("Initializing telemetry manager: device=$deviceId, model=$deviceModel, os=$osVersion")

            CppBridgeTelemetry.initialize(
                environment = environment,
                deviceId = deviceId,
                deviceModel = deviceModel,
                osVersion = osVersion,
                sdkVersion = sdkVersion,
            )

            logger.debug("Telemetry manager initialized")
        } catch (e: Exception) {
            logger.error("Failed to initialize telemetry manager: ${e.message}")
        }
    }

    /**
     * Initialize SDK configuration (Phase 1 core init) through the canonical
     * commons C ABI `rac_sdk_init_phase1_proto`.
     *
     * Drives validation (`rac_validate_api_key` / `rac_validate_base_url`),
     * persists the api_key/base_url through secure storage, and runs
     * `rac_state_initialize` — replacing the legacy `racSdkInit` struct ABI.
     * The validation contract now runs on Android exactly like iOS, so a
     * malformed apiKey/baseURL is rejected (throws [SDKException]) instead of
     * silently booting.
     *
     * Mirrors Swift's `CppBridge.SdkInit.phase1(...)` call in RunAnywhere.swift.
     *
     * @param environment SDK environment
     * @param apiKey API key for authentication (required for production/staging)
     * @param baseURL Backend API base URL (required for production/staging)
     */
    private fun initializeSdkConfig(environment: SDKEnvironment, apiKey: String?, baseURL: String?) {
        val deviceId = CppBridgeDevice.getDeviceIdCallback()
        logger.debug("Initializing SDK config (phase 1): env=$environment")
        if (!apiKey.isNullOrEmpty()) {
            logger.debug("API key provided: ${apiKey.take(10)}...")
        }
        if (!baseURL.isNullOrEmpty()) {
            logger.debug("Base URL: $baseURL")
        }

        val result =
            CppBridgeSdkInit.phase1(
                environment = environment,
                apiKey = apiKey.orEmpty(),
                baseURL = baseURL.orEmpty(),
                deviceId = deviceId,
            )
        logger.debug(
            "SDK config initialized (phase 1): linkedModels=${result.linked_models_count}",
        )
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
     * Register the OkHttp platform HTTP transport with the C++ core.
     *
     * Installs `rac_http_transport_ops` so that every `rac_http_request_*`
     * call routes through Kotlin's [OkHttpHttpTransport]. Gives Android / JVM
     * consumers the system trust store + NetworkSecurityConfig + proxy +
     * HTTP/2 for free.
     *
     * Routed through [OkHttpHttpTransport.register] (not the raw JNI thunk)
     * so the transport's registration state — and the in-flight stream
     * registry it drains on [OkHttpHttpTransport.unregister] — stays in sync
     * with what the C++ core sees.
     *
     * Guarded: skipped silently when the native library isn't loaded ([OkHttpHttpTransport.register]
     * absorbs the UnsatisfiedLinkError) so the SDK can still boot (without
     * inference) for non-networking use cases.
     */
    private fun registerOkHttpTransport() {
        if (!CppBridgeState.nativeLibraryLoaded) {
            logger.debug("Skipping OkHttp transport registration: native lib not loaded")
            return
        }
        OkHttpHttpTransport.register()
    }

    /**
     * Unregister the OkHttp platform HTTP transport and cancel any in-flight
     * streams. Best-effort — [OkHttpHttpTransport.unregister] logs failures
     * without blocking shutdown.
     */
    private fun unregisterOkHttpTransport() {
        if (!CppBridgeState.nativeLibraryLoaded) return
        OkHttpHttpTransport.unregister()
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
        logger.debug("Starting native library loading sequence")

        CppBridgeState.nativeLibraryLoaded = RunAnywhereBridge.ensureNativeLibraryLoaded()

        if (CppBridgeState.nativeLibraryLoaded) {
            logger.info("Native commons library loaded; AI inference features available")
        } else {
            logger.warn(
                "Native commons library not available; AI inference features disabled. " + "Ensure librunanywhere_jni.so is in your APK's lib/ folder.",
            )
        }
    }

    /**
     * Phase 2: Services Initialization (Asynchronous)
     *
     * Initializes platform service adapters needed by commons Phase 2.
     *
     * Must be called after [initialize] completes.
     * Must be called from a background thread (e.g., Dispatchers.IO).
     * Mirrors Swift SDK's completeServicesInitialization()
     */
    suspend fun initializeServices() {
        // Guard: check and set initializing flag under lock, then release lock for I/O
        synchronized(lock) {
            if (!CppBridgeState.isInitialized) {
                throw IllegalStateException("CppBridge.initialize() must be called before initializeServices()")
            }
            if (CppBridgeState.servicesInitialized || CppBridgeState.servicesInitializing) {
                return
            }
            CppBridgeState.servicesInitializing = true
        }

        try {
            // Configure the Kotlin HTTP adapter used by callback-based
            // platform services. Auth and control-plane orchestration are
            // driven by rac_sdk_init_phase2_proto through the registered
            // OkHttp transport.
            if (!HTTPClientAdapter.isConfigured) {
                val configured =
                    if (_environment == SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT) {
                        CppBridgeDevConfig.configureHTTP()
                    } else {
                        val baseUrl = CppBridgeTelemetry.getBaseUrl()
                        val apiKey = CppBridgeTelemetry.getApiKey()
                        if (!baseUrl.isNullOrEmpty() && !apiKey.isNullOrEmpty()) {
                            HTTPClientAdapter.configure(baseUrl, apiKey)
                            true
                        } else {
                            false
                        }
                    }
                logger.debug("HTTP adapter configuration for callbacks: configured=$configured")
            }

            synchronized(lock) {
                CppBridgeState.servicesInitialized = true
                CppBridgeState.servicesInitializing = false
            }
            logger.debug("Phase 2 services initialization complete")
        } catch (e: Exception) {
            synchronized(lock) {
                CppBridgeState.servicesInitializing = false
            }
            throw e
        }
    }

    /**
     * Shutdown the SDK and release all resources.
     *
     * Mirrors Swift `CppBridge.shutdown()` which is async because AI component
     * destroy() methods are actor-isolated. The Kotlin entry point remains
     * non-suspend to preserve the existing `fun shutdownPlatformBridge()`
     * actual signature; the suspend body is awaited via `runBlocking`. Callers
     * that already live in a coroutine context should prefer [shutdownSuspending].
     *
     * Order (matching Swift CppBridge.shutdown() exactly):
     * 1. Destroy AI component bridges (LLM → STT → TTS → VAD → VoiceAgent → VLM)
     * 2. Unregister Phase 2 services, Phase 1 core extensions in reverse order.
     *
     * Each component destroy is wrapped in try/catch so a failure in one
     * component does not abort the rest of the shutdown sequence.
     */
    fun shutdown() {
        runBlocking { shutdownSuspending() }
    }

    /**
     * Suspending shutdown that matches Swift `CppBridge.shutdown() async`.
     *
     * Awaits AI component actor destruction sequentially before tearing down
     * telemetry/events/platform adapter. Prefer this from already-suspending
     * callers to avoid the `runBlocking` bridge in [shutdown].
     */
    suspend fun shutdownSuspending() {
        // Snapshot initialization state under the lock without holding it
        // across the suspend destroy calls below.
        val wasInitialized =
            synchronized(lock) {
                if (!CppBridgeState.isInitialized) {
                    return
                }
                true
            }
        if (!wasInitialized) return

        // Destroy AI components sequentially before tearing down Telemetry/Events.
        // Each call is best-effort: a failure in one bridge must not block the rest.
        // Matches Swift CppBridge.shutdown() ordering exactly:
        //   LLM → STT → TTS → VAD → VoiceAgent → VLM
        try {
            CppBridgeLLM.destroy()
        } catch (t: Throwable) {
            logger.warn("CppBridgeLLM.destroy() failed during shutdown: ${t.message}")
        }
        try {
            CppBridgeSTT.destroy()
        } catch (t: Throwable) {
            logger.warn("CppBridgeSTT.destroy() failed during shutdown: ${t.message}")
        }
        try {
            CppBridgeTTS.destroy()
        } catch (t: Throwable) {
            logger.warn("CppBridgeTTS.destroy() failed during shutdown: ${t.message}")
        }
        try {
            CppBridgeVAD.destroy()
        } catch (t: Throwable) {
            logger.warn("CppBridgeVAD.destroy() failed during shutdown: ${t.message}")
        }
        try {
            CppBridgeVoiceAgent.destroy()
        } catch (t: Throwable) {
            logger.warn("CppBridgeVoiceAgent.destroy() failed during shutdown: ${t.message}")
        }
        try {
            CppBridgeVLM.destroy()
        } catch (t: Throwable) {
            logger.warn("CppBridgeVLM.destroy() failed during shutdown: ${t.message}")
        }

        synchronized(lock) {
            // Re-check in case a concurrent shutdown already tore things down
            if (!CppBridgeState.isInitialized) {
                return
            }

            // Cancel any pending async operations
            sdkScope.cancel()

            // Unregister Phase 1 core extensions (reverse order)
            CppBridgeDevice.unregister()
            CppBridgeTelemetry.unregister()
            CppBridgeSDKEvents.unregister()

            // Release the OkHttp transport before the
            // platform adapter, so any final rac_http_request_* inside shutdown
            // (e.g. telemetry flush) still has a working HTTP path.
            unregisterOkHttpTransport()

            CppBridgePlatformAdapter.unregister()

            // Teardown Sentry logging
            teardownSentryLogging()

            // Clear Sentry hooks
            Logging.sentrySetupHook = null
            Logging.sentryTeardownHook = null

            CppBridgeState.servicesInitialized = false
            CppBridgeState.servicesInitializing = false
            CppBridgeState.isInitialized = false
        }
    }

    /**
     * Check if the C++ core is initialized.
     *
     * @return true if rac_is_initialized() returns true
     */
    fun isNativeInitialized(): Boolean {
        if (!CppBridgeState.isInitialized || !isNativeLibraryLoaded) return false
        return RunAnywhereBridge.racIsInitialized()
    }

    /**
     * Setup Sentry hooks so Logging can trigger Sentry setup/teardown dynamically.
     *
     * This allows runtime enabling/disabling of Sentry logging via Logging.setSentryLoggingEnabled()
     */
    private fun setupSentryHooks(environment: SDKEnvironment) {
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
    private fun setupSentryLogging(environment: SDKEnvironment) {
        try {
            SentryManager.initialize(environment = environment)

            if (SentryManager.isInitialized) {
                Logging.addDestinationSync(SentryDestination())
                logger.info("Sentry logging initialized")
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
            val sentryDestination =
                Logging.destinations.find {
                    it.identifier == SentryDestination.DESTINATION_ID
                }
            if (sentryDestination != null) {
                Logging.removeDestinationSync(sentryDestination)
            }

            SentryManager.close()
            logger.info("Sentry logging disabled")
        } catch (e: Exception) {
            logger.error("Failed to teardown Sentry logging: ${e.message}")
        }
    }
}
