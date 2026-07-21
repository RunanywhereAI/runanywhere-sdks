/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Central coordinator for all C++ bridge operations.
 * Follows iOS CppBridge.swift architecture with two-phase initialization.
 */

package com.runanywhere.sdk.foundation.bridge

import com.runanywhere.sdk.features.TTS.System.SystemTTSModule
import com.runanywhere.sdk.foundation.bridge.CppBridge.initialize
import com.runanywhere.sdk.foundation.bridge.CppBridge.initializeServices
import com.runanywhere.sdk.foundation.bridge.CppBridge.shutdown
import com.runanywhere.sdk.foundation.bridge.CppBridge.shutdownSuspending
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeDevConfig
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeDevice
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeEnvironment
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeLLM
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgePlatformAdapter
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeSDKEvents
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeSTT
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeState
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeTTS
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeTelemetry
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVAD
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVoiceAgent
import com.runanywhere.sdk.foundation.constants.SDKConstants
import com.runanywhere.sdk.httptransport.OkHttpHttpTransport
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.configuration.SDKEnvironment
import com.runanywhere.sdk.public.configuration.cEnvironment
import kotlinx.coroutines.runBlocking

/** Collects sanitized teardown failures while allowing later cleanup to run. */
internal class ShutdownFailureCollector {
    private var firstFailure: IllegalStateException? = null

    val hasFailure: Boolean
        get() = firstFailure != null

    fun record(message: String) {
        val failure = IllegalStateException(message)
        val first = firstFailure
        if (first == null) {
            firstFailure = failure
        } else {
            first.addSuppressed(failure)
        }
    }

    fun capture(
        message: String,
        action: () -> Unit,
    ): Boolean =
        try {
            action()
            true
        } catch (_: Throwable) {
            record(message)
            false
        }

    fun captureNativeShutdown(action: () -> Int): Boolean {
        val succeeded =
            try {
                action() == RunAnywhereBridge.RAC_SUCCESS
            } catch (_: Throwable) {
                false
            }
        if (!succeeded) {
            record("Native SDK shutdown failed")
        }
        return succeeded
    }

    fun throwIfAny() {
        firstFailure?.let { throw it }
    }
}

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

    @Volatile
    private var shutdownInProgress: Boolean = false

    @Volatile
    private var shutdownRetryRequired: Boolean = false

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
     */
    fun initialize(environment: SDKEnvironment = SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT) {
        synchronized(lock) {
            check(!shutdownInProgress) { "CppBridge shutdown is in progress" }
            check(!shutdownRetryRequired) { "CppBridge reset is required before initialization" }
            if (CppBridgeState.isInitialized) {
                return
            }

            val initStartTime = System.currentTimeMillis()

            _environment = environment

            // Try to load native library (optional - SDK works without it for non-inference features)
            tryLoadNativeLibrary()

            // CRITICAL: Register platform adapter FIRST before any C++ calls
            CppBridgePlatformAdapter.register()

            // Install the OkHttp HTTP transport BEFORE
            // any network I/O happens (device registration, model assignment
            // fetch, telemetry, auth all go through rac_http_request_*). The
            // adapter gives us the Android system trust store + proxy +
            // NetworkSecurityConfig for free and fixes the rc=77 SSL failure
            // on ~5% of devices. Safe to no-op if the native lib is missing.
            registerOkHttpTransport()

            if (CppBridgeState.nativeLibraryLoaded) {
                RunAnywhereBridge.racConfigureLogging(environment.cEnvironment)
            }

            // CRITICAL: Set environment early so CppBridgeDevice.isDeviceRegisteredCallback()
            // can determine correct behavior for production/staging modes
            CppBridgeTelemetry.setEnvironment(environment)

            // Resolve the durable identity and register device callbacks before
            // telemetry can consume it. Any KeyStore/persistence error aborts
            // initialization with the exact commons rac_result_t.
            CppBridgeDevice.register()

            initializeTelemetryManager(environment)

            // Register analytics events callback AFTER telemetry manager is initialized
            // This routes C++ events (LLM/STT/TTS) to telemetry for batching and HTTP transport
            val telemetryHandle = CppBridgeTelemetry.getTelemetryHandle()
            if (telemetryHandle != 0L) {
                CppBridgeSDKEvents.register(telemetryHandle)
            } else {
                logger.warn("Telemetry handle not available, analytics events will not be tracked")
            }

            CppBridgeState.isInitialized = true

            val initDurationMs = System.currentTimeMillis() - initStartTime
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
            if (!CppBridgeEnvironment.shouldSendTelemetry(environment)) {
                logger.debug("Telemetry disabled for $environment")
                return
            }
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

    /** Shut down native core state while the platform adapter is still valid. */
    private fun shutdownNativeCore(failures: ShutdownFailureCollector): Boolean {
        if (!CppBridgeState.nativeLibraryLoaded) return true
        val succeeded = failures.captureNativeShutdown(RunAnywhereBridge::racShutdown)
        if (!succeeded) {
            logger.warn("Native SDK shutdown failed")
        }
        return succeeded
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
            check(!shutdownInProgress) { "CppBridge shutdown is in progress" }
            check(!shutdownRetryRequired) { "CppBridge reset is required before services initialization" }
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
            //
            // Effective config from commons state, for every environment:
            // staging resolves the baked keyless base URL, dev/prod use whatever
            // the app passed. There is no direct-to-datastore (dev Supabase)
            // path — the backend is always reached through this base URL, and
            // auth stays in C++. Mirrors Swift's `_performServicesInitialization`
            // Step 1.
            if (!HTTPClientAdapter.isConfigured) {
                val effectiveBaseUrl =
                    RunAnywhereBridge.racStateGetBaseUrl()
                        ?.takeIf { it.isNotEmpty() }
                        ?: CppBridgeTelemetry.getBaseUrl()
                val apiKey = CppBridgeTelemetry.getApiKey()
                val configured =
                    if (!effectiveBaseUrl.isNullOrEmpty() &&
                        CppBridgeDevConfig.isUsableHTTPURL(effectiveBaseUrl)
                    ) {
                        HTTPClientAdapter.configure(effectiveBaseUrl, apiKey)
                        true
                    } else {
                        logger.debug("HTTP adapter disabled: no usable external config")
                        false
                    }
                logger.info(
                    "Phase 2 HTTP adapter configuration: configured=$configured " +
                        "(isConfigured=${HTTPClientAdapter.isConfigured})",
                )
            } else {
                logger.info("Phase 2 HTTP adapter already configured (isConfigured=true)")
            }

            SystemTTSModule.register()

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
     * destroy() methods are actor-isolated. The compatibility entry point is
     * non-suspending and awaits the same teardown via `runBlocking`; coroutine
     * callers should prefer [shutdownSuspending].
     *
     * Order (matching Swift CppBridge.shutdown() exactly):
     * 1. Destroy stateful AI component bridges (LLM → STT → TTS → VAD → VoiceAgent)
     * 2. Unregister Phase 2 services, Phase 1 core extensions in reverse order.
     *
     * Each component destroy is wrapped in try/catch so a failure in one
     * component does not abort the rest of the shutdown sequence.
     */
    fun shutdown() {
        runBlocking { shutdownSuspending() }
    }

    /** Tear down Phase 1 state after an initialization failure. */
    internal fun rollbackInitialization(afterNativeShutdown: () -> Unit = {}) {
        val failures = ShutdownFailureCollector()
        synchronized(lock) {
            if (shutdownInProgress) return
            shutdownInProgress = true
            try {
                CppBridgeDevice.unregister()
                shutdownNativeCore(failures)
                if (!runPostNativeShutdownHook(afterNativeShutdown)) {
                    failures.record("Post-native shutdown hook failed")
                }
                failures.capture("SDK event teardown failed") { CppBridgeSDKEvents.unregister() }
                failures.capture("Telemetry teardown failed") { CppBridgeTelemetry.unregister() }
                failures.capture("System TTS teardown failed") { SystemTTSModule.unregister() }
                failures.capture("HTTP transport teardown failed") { unregisterOkHttpTransport() }
                failures.capture("HTTP configuration teardown failed") { HTTPClientAdapter.reset() }
                failures.capture("Platform adapter teardown failed") { CppBridgePlatformAdapter.unregister() }

                // A failed partial rollback remains retryable through the
                // public reset path. Do not clear the bridge/native-loaded
                // gates until every cleanup step succeeds.
                if (!failures.hasFailure) {
                    failures.capture("Bridge state teardown failed") { CppBridgeState.shutdown() }
                }
                shutdownRetryRequired = failures.hasFailure
            } finally {
                shutdownInProgress = false
            }
        }
        failures.throwIfAny()
    }

    /**
     * Suspending shutdown that matches Swift `CppBridge.shutdown() async`.
     *
     * Awaits AI component actor destruction sequentially before tearing down
     * telemetry/events/platform adapter. Prefer this from already-suspending
     * callers to avoid the `runBlocking` bridge in [shutdown].
     */
    suspend fun shutdownSuspending() {
        shutdownSuspending(afterNativeShutdown = {})
    }

    /**
     * Platform-facade shutdown hook placed after the terminal native event and
     * before event and telemetry dependencies are detached.
     */
    internal suspend fun shutdownSuspending(afterNativeShutdown: () -> Unit) {
        // Claim teardown under the synchronous lifecycle lock, then release it
        // before awaiting component and telemetry work.
        synchronized(lock) {
            if ((!CppBridgeState.isInitialized && !shutdownRetryRequired) || shutdownInProgress) return
            shutdownInProgress = true
        }

        val failures = ShutdownFailureCollector()

        // Destroy AI components sequentially before tearing down Telemetry/Events.
        // Each call is best-effort: a failure in one bridge must not block the rest.
        // Matches Swift CppBridge.shutdown() ordering exactly:
        //   LLM → STT → TTS → VAD → VoiceAgent
        try {
            CppBridgeLLM.destroy()
        } catch (_: Throwable) {
            logger.warn("LLM bridge teardown failed")
            failures.record("LLM bridge teardown failed")
        }
        try {
            CppBridgeSTT.destroy()
        } catch (_: Throwable) {
            logger.warn("STT bridge teardown failed")
            failures.record("STT bridge teardown failed")
        }
        try {
            CppBridgeTTS.destroy()
        } catch (_: Throwable) {
            logger.warn("TTS bridge teardown failed")
            failures.record("TTS bridge teardown failed")
        }
        try {
            CppBridgeVAD.destroy()
        } catch (_: Throwable) {
            logger.warn("VAD bridge teardown failed")
            failures.record("VAD bridge teardown failed")
        }
        try {
            CppBridgeVoiceAgent.destroy()
        } catch (_: Throwable) {
            logger.warn("Voice-agent bridge teardown failed")
            failures.record("Voice-agent bridge teardown failed")
        }

        try {
            synchronized(lock) {
                // Stop native device callbacks before canonical shutdown begins.
                CppBridgeDevice.unregister()

                // Canonical native shutdown publishes its terminal lifecycle event
                // while EventBus, telemetry, HTTP, logging, and platform services
                // are still available.
                shutdownNativeCore(failures)
                if (!runPostNativeShutdownHook(afterNativeShutdown)) {
                    failures.record("Post-native shutdown hook failed")
                }

                if (!failures.capture("SDK event teardown failed") { CppBridgeSDKEvents.unregister() }) {
                    logger.warn("SDK event teardown failed")
                }
            }

            // Native flush callbacks run on this lifetime's replaceable scope.
            // Drain it before HTTP credentials or transport are released.
            try {
                CppBridgeTelemetry.unregisterSuspending()
            } catch (_: Throwable) {
                logger.warn("Telemetry callback drain failed during shutdown")
                failures.record("Telemetry callback drain failed during shutdown")
            }

            synchronized(lock) {
                if (!failures.capture("System TTS teardown failed") { SystemTTSModule.unregister() }) {
                    logger.warn("System TTS teardown failed")
                }

                // Telemetry flush/destroy above may use HTTP, so release the
                // transport and copied credentials only after telemetry is gone.
                if (!failures.capture("HTTP transport teardown failed") { unregisterOkHttpTransport() }) {
                    logger.warn("HTTP transport teardown failed")
                }
                if (!failures.capture("HTTP configuration teardown failed") { HTTPClientAdapter.reset() }) {
                    logger.warn("HTTP configuration teardown failed")
                }

                if (!failures.capture("Platform adapter teardown failed") { CppBridgePlatformAdapter.unregister() }) {
                    logger.warn("Platform adapter teardown failed")
                }

                // Keep the Kotlin/native-loaded gates intact after any failure
                // so a fail-closed RunAnywhere.reset() retry re-enters this
                // canonical teardown. Clear them only after every step succeeds.
                if (!failures.hasFailure &&
                    !failures.capture("Bridge state teardown failed") { CppBridgeState.shutdown() }
                ) {
                    logger.warn("Bridge state teardown failed")
                }
                shutdownRetryRequired = failures.hasFailure
            }
        } finally {
            synchronized(lock) {
                shutdownInProgress = false
            }
        }

        failures.throwIfAny()
    }

    private fun runPostNativeShutdownHook(hook: () -> Unit): Boolean =
        try {
            hook()
            true
        } catch (_: Throwable) {
            logger.warn("Post-native shutdown hook failed")
            false
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
}
