/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * The main entry point for the RunAnywhere SDK.
 * Two-phase initialization delegates to CppBridge:
 *   * Phase 1 → CppBridge.initialize() → CppBridgeSdkInit.phase1
 *     (rac_sdk_init_phase1_proto) for validation + config/state init.
 *   * Phase 2 → CppBridge.initializeServices() registers platform adapters,
 *     then CppBridgeSdkInit.phase2 runs auth/refresh, device registration,
 *     model assignments, telemetry flush, and model discovery in commons.
 *   * HTTP retry → retryHTTPSetup() calls CppBridgeSdkInit.retryHTTP()
 *     (rac_sdk_retry_http_proto).
 * Kotlin retains only the parts that cannot move into C++:
 *   * Coroutine Mutex + servicesMutex concurrency primitive
 *   * EncryptedSharedPreferences / file-backed SDK params persistence
 *   * JNI platform-plugin/callback registration
 *   * OkHttp HTTP transport implementation and adapter configuration
 */

package com.runanywhere.sdk.public

import android.content.Context
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeAuth
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeDevConfig
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeDevice
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeFileManager
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelPaths
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeSDKEvents
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeSdkInit
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeState
import com.runanywhere.sdk.foundation.constants.SDKConstants
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.foundation.security.AndroidPlatformContext
import com.runanywhere.sdk.generated.convenience.wireString
import com.runanywhere.sdk.infrastructure.logging.Logging
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.public.configuration.SDKEnvironment
import com.runanywhere.sdk.public.configuration.SDKInitParams
import com.runanywhere.sdk.public.events.EventBus
import java.net.URL
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * The RunAnywhere SDK - Single entry point for on-device AI
 *
 * Mirrors the iOS `RunAnywhere` enum (`Sources/RunAnywhere/Public/RunAnywhere.swift`)
 * one-to-one:
 *  - SDK initialization (two-phase: fast sync Phase 1 + async Phase 2)
 *  - State access (isInitialized, areServicesReady, isActive, version, environment)
 *  - Event access via `events` property
 *  - Reset / cleanup / ensureServicesReady() retry path for offline init
 *
 * Feature-specific APIs are available through extension functions in public/extensions/:
 * - STT: RunAnywhere.transcribe(), RunAnywhere.transcribeStream()
 * - TTS: RunAnywhere.synthesize(), RunAnywhere.loadModel(RAModelLoadRequest)
 * - LLM: RunAnywhere.generate(), RunAnywhere.generateStream()
 * - VAD: RunAnywhere.detectSpeech()
 * - VoiceAgent: VoiceAgentStreamAdapter(handle).stream()
 *
 * All AI component logic (LLM, STT, TTS, VAD) is delegated to the C++ runanywhere-commons
 * layer via CppBridge. Kotlin only handles platform-specific operations (HTTP, audio, file I/O).
 */
object RunAnywhere {
    // Private state

    private val logger = SDKLogger("RunAnywhere")

    /**
     * Persisted init params from the most recent [initialize] call. Mirrors
     * Swift's `internal static var initParams: SDKInitParams?`. Consumed by
     * [completeServicesInitialization] and [ensureServicesReady] when the
     * HTTP/auth retry path is invoked.
     */
    @Volatile
    private var _initParams: SDKInitParams? = null

    @Volatile
    private var _currentEnvironment: SDKEnvironment? = null

    @Volatile
    private var _isInitialized: Boolean = false

    @Volatile
    private var _areServicesReady: Boolean = false

    /**
     * Whether HTTP/auth setup succeeded during Phase 2. Tracked separately from
     * [_areServicesReady] so a caller that initialized offline can retry the
     * HTTP path through [ensureServicesReady] without re-running the entire
     * services bootstrap. Mirrors Swift's `hasCompletedHTTPSetup`.
     */
    @Volatile
    private var _hasCompletedHTTPSetup: Boolean = false

    /**
     * Whether HTTP/auth setup is applicable for the active configuration. False
     * when there is no usable external config (local-only / development without
     * a backend), where [_hasCompletedHTTPSetup] can never become true because
     * there is nothing to connect to. Used by [ensureServicesReady] to skip the
     * retry path in that case, so the Phase 2 service bootstrap is not re-run on
     * every API call. Distinct from a transient offline failure (config present,
     * network down), where retrying is still worthwhile.
     */
    @Volatile
    private var _httpSetupApplicable: Boolean = true

    /**
     * Monotonic timestamp of the last HTTP/auth retry attempted by
     * [ensureServicesReady]. Debounces the recovery path so a backend that
     * never converges does not add a network round-trip to every API call.
     * 0 = never attempted (retry immediately).
     */
    @Volatile
    private var lastHttpRetryAtNs: Long = 0L

    /** Minimum interval between HTTP/auth retries from [ensureServicesReady]. */
    private const val HTTP_RETRY_MIN_INTERVAL_NS: Long = 30_000_000_000L // 30s

    private val lock = Any()
    private val servicesMutex = Mutex()
    private var servicesInitJob: Job? = null

    /**
     * Coroutine scope used to spawn Phase 2 in the background from the
     * synchronous [initialize] call site. Mirrors Swift's
     * `Task.detached(priority: .userInitiated)` spawn. SupervisorJob so a
     * Phase 2 failure does not poison the rest of the SDK.
     */
    private val initScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    // Public properties

    /**
     * Check if SDK is initialized (Phase 1 complete)
     */
    val isInitialized: Boolean
        get() = _isInitialized

    /**
     * Check if services are fully ready (Phase 2 complete)
     */
    val areServicesReady: Boolean
        get() = _areServicesReady

    /**
     * Check if SDK is active and ready for use
     */
    val isActive: Boolean
        get() = _isInitialized && _initParams != null

    /**
     * Current SDK version
     */
    val version: String
        get() = SDKConstants.SDK_VERSION

    /**
     * Current environment (null if not initialized)
     */
    val environment: SDKEnvironment?
        get() = _currentEnvironment

    // Event access

    /**
     * Event bus for SDK event subscriptions.
     *
     * Example usage:
     * ```kotlin
     * RunAnywhere.events.llmEvents.collect { event ->
     *     println("LLM event: ${event.type}")
     * }
     * ```
     */
    val events: EventBus
        get() = EventBus

    // Authentication info (production/staging only)

    /**
     * Get the current user ID from authentication state.
     *
     * @return User ID if authenticated, `null` otherwise.
     */
    fun getUserId(): String? = platformGetUserId()

    /**
     * Get the current organization ID from authentication state.
     *
     * @return Organization ID if authenticated, `null` otherwise.
     */
    fun getOrganizationId(): String? = platformGetOrganizationId()

    /**
     * Check if the SDK is currently authenticated with a valid token.
     *
     * Equivalent to Swift's `RunAnywhere.isAuthenticated` static var.
     */
    val isAuthenticated: Boolean
        get() = platformIsAuthenticated()

    /**
     * Check if this device is registered with the backend.
     *
     * @return true if the device-registration handshake completed successfully.
     */
    fun isDeviceRegistered(): Boolean = platformIsDeviceRegistered()

    /**
     * The persistent device ID. Survives reinstalls (stored in keychain on
     * Apple platforms / EncryptedSharedPreferences on Android).
     *
     * Resolved by commons via the device-identity chain
     * (secure_get → vendor ID → freshly synthesized UUID).
     */
    val deviceId: String
        get() = platformDeviceId()

    // Phase 1: core initialization (synchronous)

    /**
     * Initialize the RunAnywhere SDK (Phase 1)
     *
     * Mirrors Swift's `RunAnywhere.initialize(apiKey:baseURL:environment:)`:
     * 1. Builds an [SDKInitParams] envelope from the caller's inputs.
     * 2. Validates inputs via the canonical C++ validator
     *    (`rac_validate_api_key` / `rac_validate_base_url`) — invalid combos
     *    throw [SDKException] before any native state is mutated.
     * 3. Calls the platform bridge, which internally drives Phase 1
     *    (`rac_sdk_init_phase1_proto` via `CppBridgeSdkInit.phase1` for
     *    validation + config/state init), telemetry boot, and the
     *    `emitSDKInitStarted` / `emitSDKInitCompleted` event pair.
     * 4. Spawns Phase 2 in the background via [initScope] so the call
     *    returns synchronously (mirrors Swift's
     *    `Task.detached(priority: .userInitiated)`).
     *
     * ## Usage Examples
     *
     * ```kotlin
     * // Development mode (default)
     * RunAnywhere.initialize()
     *
     * // Production mode
     * RunAnywhere.initialize(
     *     apiKey = "...",
     *     baseURL = "https://api.example.com",
     *     environment = SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
     * )
     * ```
     *
     * @param apiKey API key (optional for development, required for production/staging)
     * @param baseURL Backend API base URL (optional)
     * @param environment SDK environment (default: DEVELOPMENT)
     * @throws SDKException when validation fails for staging/production.
     */
    fun initialize(
        apiKey: String? = null,
        baseURL: String? = null,
        environment: SDKEnvironment = SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
    ) {
        // Build + validate SDKInitParams. Mirrors Swift's branching between
        // `SDKInitParams(forDevelopmentWithAPIKey:)` and `SDKInitParams(apiKey:baseURL:environment:)`.
        val params: SDKInitParams =
            if (environment == SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT) {
                SDKInitParams.forDevelopment(apiKey = apiKey ?: "")
            } else {
                SDKInitParams.create(
                    apiKey = apiKey ?: "",
                    baseURL = baseURL ?: "",
                    environment = environment,
                )
            }

        performCoreInit(params = params, startBackgroundServices = true)
    }

    /**
     * Initialize the RunAnywhere SDK using a typed [URL] for the backend base URL.
     *
     * Mirrors Swift's URL-typed overload while preserving the string-backed
     * [SDKInitParams] contract used by the Android bridge.
     */
    fun initialize(
        apiKey: String,
        baseURL: URL,
        environment: SDKEnvironment = SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
    ) {
        initialize(apiKey = apiKey, baseURL = baseURL.toString(), environment = environment)
    }

    /**
     * Initialize the RunAnywhere SDK with an Android [Context] (Android-specific
     * convenience overload). Absorbs the previously example-side
     * `AndroidPlatformContext.initialize(context)` call so callers do not need
     * to reach into SDK-internal foundation packages.
     *
     * The Context is wired into [AndroidPlatformContext] (which feeds
     * `CppBridgePlatformAdapter` for secure storage and `CppBridgeModelPaths`
     * for filesDir/cacheDir resolution) before Phase 1 starts. Subsequent calls
     * with the same application context are no-ops at the `AndroidPlatformContext`
     * level.
     *
     * Equivalent to the Swift `RunAnywhere.initialize(apiKey:baseURL:environment:)`
     * entry point — Apple platforms do not need an explicit Context handle
     * (Keychain is process-scoped).
     *
     * @param context Android application context (any Context is fine — the
     *                application context will be retained, not the activity).
     * @param apiKey  API key (optional for development).
     * @param baseURL Backend API base URL (optional for development).
     * @param environment SDK environment (default: DEVELOPMENT).
     */
    fun initialize(
        context: Context,
        apiKey: String? = null,
        baseURL: String? = null,
        environment: SDKEnvironment = SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
    ) {
        AndroidPlatformContext.initialize(context)
        initialize(apiKey = apiKey, baseURL = baseURL, environment = environment)
    }

    /**
     * Android [Context] convenience paired with the URL-typed backend overload.
     */
    fun initialize(
        context: Context,
        apiKey: String,
        baseURL: URL,
        environment: SDKEnvironment = SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
    ) {
        AndroidPlatformContext.initialize(context)
        initialize(apiKey = apiKey, baseURL = baseURL, environment = environment)
    }

    /**
     * Phase 1 core init — delegated to commons. Mirrors Swift's
     * `performCoreInit(with:startBackgroundServices:)`.
     *
     * The platform bridge encapsulates the canonical step list:
     *   * `rac_sdk_init_phase1_proto` via `CppBridgeSdkInit.phase1` for
     *     validation + config/state init.
     *   * SDK config + Keychain auth-storage install.
     *   * `emitSDKInitStarted` / `emitSDKInitCompleted` event emission.
     *
     * On failure the state is rolled back so a second call to [initialize]
     * with corrected inputs can succeed cleanly.
     */
    private fun performCoreInit(params: SDKInitParams, startBackgroundServices: Boolean) {
        synchronized(lock) {
            if (_isInitialized) {
                logger.info("SDK already initialized")
                return
            }

            val initStartTime = System.currentTimeMillis()

            try {
                // Set environment + params first so logging boots with the
                // correct configuration and downstream queries can read the
                // persisted envelope.
                _currentEnvironment = params.environment
                _initParams = params

                // Apply default log level for this environment. Mirrors Swift's
                // `Logging.shared.applyEnvironmentConfiguration(params.environment)`.
                Logging.applyEnvironmentConfiguration(params.environment)

                // Hand off to the platform bridge, which loads native libs,
                // registers the platform adapter, runs CppBridgeSdkInit.phase1
                // (rac_sdk_init_phase1_proto — validation + config/state init),
                // and emits SDKInitStarted / SDKInitCompleted events.
                initializePlatformBridge(
                    environment = params.environment,
                    apiKey = params.apiKey,
                    baseURL = params.baseURL,
                )

                CppBridgeSDKEvents.emitSDKInitStarted()

                CppBridgeAuth.initialize()
                CppBridgeFileManager.register()
                val baseDir = CppBridgeModelPaths.getBaseDirectory()
                logger.debug("Model storage base directory materialized: $baseDir")

                val phase1Result =
                    CppBridgeSdkInit.phase1(
                        environment = params.environment,
                        apiKey = params.apiKey,
                        baseURL = params.baseURL,
                        deviceId = CppBridgeDevice.getDeviceIdCallback(),
                    )
                logger.debug("SDK config initialized: linkedModels=${phase1Result.linked_models_count}")

                // SDK config (rac_sdk_init). Idempotent state re-init is
                // harmless; this call also wires up version/platform metadata
                // that the Phase 1 proto does not touch.
                CppBridgeState.initialize(
                    environment = params.environment,
                    apiKey = params.apiKey,
                    baseURL = params.baseURL,
                    deviceId = CppBridgeDevice.getDeviceIdCallback(),
                )

                _isInitialized = true

                val initDurationMs = System.currentTimeMillis() - initStartTime
                CppBridgeSDKEvents.emitSDKInitCompleted(initDurationMs.toDouble())
                logger.info("Phase 1 complete in ${initDurationMs}ms (${params.environment.wireString})")

                if (startBackgroundServices) {
                    // Spawn Phase 2 in the background. Mirrors Swift's
                    // `Task.detached(priority: .userInitiated) { try await completeServicesInitialization() }`.
                    logger.debug("Starting Phase 2 (services) in background...")
                    servicesInitJob =
                        initScope.launch {
                            try {
                                completeServicesInitialization()
                                logger.debug("Phase 2 complete (background)")
                            } catch (error: Throwable) {
                                logger.warn("Phase 2 failed (non-critical): ${error.message}")
                            } finally {
                                synchronized(lock) {
                                    servicesInitJob = null
                                }
                            }
                        }
                }
            } catch (error: Throwable) {
                logger.error("Initialization failed: ${error.message}")
                CppBridgeSDKEvents.emitSDKInitFailed(SDKException.from(error))
                // Roll back state on failure so a corrected retry can succeed.
                _initParams = null
                _currentEnvironment = null
                _isInitialized = false
                _areServicesReady = false
                _hasCompletedHTTPSetup = false
                _httpSetupApplicable = true
                lastHttpRetryAtNs = 0L
                servicesInitJob = null
                CppBridgeState.reset()
                throw error
            }
        }
    }

    // Phase 2: services initialization (async)

    /**
     * Complete services initialization (Phase 2). Safe to call multiple times;
     * concurrent callers share the same Mutex so the step list runs at most
     * once. Mirrors Swift's `completeServicesInitialization()` (the
     * `_servicesInitTask` + `_servicesInitLock.sync { ... }` fan-in).
     *
     * Kotlin first wires the OkHttp transport and platform callbacks via
     * [initializePlatformBridgeServices]. Then `CppBridgeSdkInit.phase2`
     * drives the commons-owned step list: auth/refresh, device registration,
     * assignment fetch, telemetry flush, and downloaded-model discovery.
     *
     * The generated `SdkInitResult` drives [_hasCompletedHTTPSetup] so a later
     * [ensureServicesReady] call can retry HTTP/auth through
     * `CppBridgeSdkInit.retryHTTP` without re-running the rest of the bootstrap.
     */
    suspend fun completeServicesInitialization() {
        // Fast path: already completed.
        if (_areServicesReady) {
            return
        }

        servicesMutex.withLock {
            if (_areServicesReady) {
                return
            }

            if (!_isInitialized) {
                throw SDKException.notInitialized("RunAnywhere")
            }

            val params =
                _initParams
                    ?: throw SDKException.notInitialized("SDK init params missing — call RunAnywhere.initialize() first")

            logger.debug("Initializing services for ${params.environment.wireString} mode")

            try {
                // Configure/register platform adapters first; commons uses
                // those callbacks and the registered OkHttp transport during
                // Phase 2.
                initializePlatformBridgeServices()

                val phase2Result =
                    CppBridgeSdkInit.phase2(
                        buildToken =
                            if (params.environment == SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT) {
                                CppBridgeDevConfig.buildToken
                            } else {
                                null
                            },
                        forceRefreshAssignments = false,
                        flushTelemetry = true,
                        discoverDownloadedModels = true,
                        rescanLocalModels = true,
                    )

                // Decouple "services ready" from "HTTP/auth complete" so
                // offline/local-only Phase 2 still leaves
                // `_hasCompletedHTTPSetup = false`. That keeps the recovery
                // branch in [ensureServicesReady] reachable for the next
                // online call (auth, device registration, telemetry flush,
                // remote catalog/device paths).
                //
                // Record whether HTTP/auth is even applicable: commons owns this
                // decision so all SDKs share the same retry gate. When there is no
                // usable external config (local-only / dev without a backend),
                // `_hasCompletedHTTPSetup` can never flip, so [ensureServicesReady]
                // must not keep retrying on every API call. A transient offline
                // failure (config present, network down) stays applicable.
                _httpSetupApplicable = phase2Result.http_applicable
                _hasCompletedHTTPSetup =
                    phase2Result.has_completed_http_setup ||
                    phase2Result.http_configured
                _areServicesReady = true

                if (phase2Result.warning.isNotEmpty()) {
                    logger.info("Phase 2 warning: ${phase2Result.warning}")
                }
                if (phase2Result.linked_models_count > 0) {
                    logger.info("Phase 2 linked ${phase2Result.linked_models_count} assigned models")
                }

                if (_hasCompletedHTTPSetup) {
                    logger.info("Services initialized for ${params.environment.wireString} mode")
                } else {
                    logger.info(
                        "Services initialized for ${params.environment.wireString} mode " +
                            "(HTTP/auth deferred — will retry on next online call)",
                    )
                }
            } catch (e: Throwable) {
                logger.error("Services initialization failed: ${e.message}")
                throw e
            }
        }
    }

    /**
     * Ensure services are ready before API calls (internal guard).
     *
     * Mirrors Swift `RunAnywhere.ensureServicesReady()`:
     *  - Fast path: services ready, and HTTP either done or not applicable →
     *    return (O(1)).
     *  - Recovery path: services ready, HTTP applicable but not yet completed
     *    (offline init with a backend configured) → retry HTTP/auth via
     *    [retryHTTPSetup]. This uses the idempotent commons retry path and is
     *    gated on [_httpSetupApplicable] to avoid retrying on every call in
     *    local-only mode where HTTP can never complete.
     *  - Cold start path: services not ready → kick off
     *    [completeServicesInitialization].
     *
     * Called by every public feature entry so commonMain consumers do not need
     * to await Phase 2 explicitly. The Mutex guard inside
     * [completeServicesInitialization] serializes concurrent first-callers.
     *
     * @throws SDKException if Phase 1 ([initialize]) has not run.
     */
    internal suspend fun ensureServicesReady() {
        if (_areServicesReady) {
            // Retry HTTP/auth only when it is applicable (a backend is
            // configured) but has not completed yet — e.g. an offline init that
            // can succeed once connectivity returns. When HTTP is not applicable
            // (local-only / no external config), skip: retrying would re-run the
            // whole Phase 2 bootstrap on every API call and never converge.
            //
            // The retry is a synchronous network round-trip through commons.
            // Hop to IO — public API entries are routinely called from the
            // main thread, and an unreachable backend would otherwise freeze
            // the UI for a connect-timeout on every call. Debounced so the
            // never-converging case does not add a network round-trip to
            // every API call.
            if (!_hasCompletedHTTPSetup && _httpSetupApplicable) {
                val nowNs = System.nanoTime()
                val lastNs = lastHttpRetryAtNs
                if (lastNs == 0L || nowNs - lastNs >= HTTP_RETRY_MIN_INTERVAL_NS) {
                    lastHttpRetryAtNs = nowNs
                    withContext(Dispatchers.IO) { retryHTTPSetup() }
                }
            }
            return
        }
        // Cold start path — Phase 1 must already be complete.
        requireInitialized()
        completeServicesInitialization()
    }

    /**
     * Retry HTTP/auth after an offline initialization. Mirrors Swift's
     * private `retryHTTPSetup()`.
     *
     * Tries the idempotent commons fast-path
     * `CppBridgeSdkInit.retryHTTP()` (`rac_sdk_retry_http_proto`) first: when
     * commons reports `http_configured` / `has_completed_http_setup`, the
     * retry has converged. Otherwise the SDK remains in offline-friendly mode
     * and will try again on the next guarded call.
     */
    private suspend fun retryHTTPSetup() {
        val params = _initParams ?: return
        logger.debug("Retrying HTTP/auth setup for ${params.environment.wireString}...")

        try {
            val retryResult = CppBridgeSdkInit.retryHTTP()
            _hasCompletedHTTPSetup =
                retryResult.has_completed_http_setup ||
                retryResult.http_configured
            if (retryResult.warning.isNotEmpty()) {
                logger.debug("HTTP retry warning: ${retryResult.warning}")
            }
            if (_hasCompletedHTTPSetup) {
                logger.info("HTTP/Auth already configured (idempotent fast-path)")
                return
            }

            logger.debug("HTTP/Auth retry still incomplete; will retry on next call")
        } catch (e: Throwable) {
            logger.debug("HTTP/Auth retry failed (still offline?): ${e.message}")
        }
    }

    /**
     * Ensure SDK is initialized (throws if not)
     */
    internal fun requireInitialized() {
        if (!_isInitialized) {
            throw SDKException.notInitialized("RunAnywhere")
        }
    }

    // SDK reset

    /**
     * Reset SDK state
     * Clears all initialization state and releases resources
     */
    suspend fun reset() {
        logger.info("Resetting SDK state...")

        synchronized(lock) {
            servicesInitJob?.cancel()
            servicesInitJob = null

            // Shutdown CppBridge, then clear persisted C++ state + auth.
            // Mirrors Swift reset(): CppBridge.shutdown() → CppBridge.State.shutdown().
            shutdownPlatformBridge()
            CppBridgeState.shutdown()

            _isInitialized = false
            _areServicesReady = false
            _hasCompletedHTTPSetup = false
            _httpSetupApplicable = true
            lastHttpRetryAtNs = 0L
            _currentEnvironment = null
            _initParams = null
        }

        logger.info("SDK state reset completed")
    }
}

// Platform-specific bridge functions and auth/device state accessors.
