/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * The main entry point for the RunAnywhere SDK.
 * Two-phase initialization delegates to CppBridge:
 *   * Phase 1 → CppBridge.initialize() → CppBridgeSdkInit.phase1
 *     (rac_sdk_init_phase1_proto) for validation + config/state init.
 *   * Phase 2 → CppBridge.initializeServices() — device registration, HTTP
 *     auth round-trip, telemetry flush (Kotlin-side OkHttp orchestration).
 *   * HTTP retry → retryHTTPSetup() tries the idempotent
 *     CppBridgeSdkInit.retryHTTP() (rac_sdk_retry_http_proto) fast-path before
 *     falling back to re-running the Kotlin Phase 2 services init.
 * Kotlin retains only the parts that cannot move into C++:
 *   * Coroutine Mutex + servicesMutex concurrency primitive
 *   * EncryptedSharedPreferences / file-backed SDK params persistence
 *   * JNI platform-plugin registration on JVM/Android main thread
 *   * HTTP authentication round-trip via OkHttp (deferred per
 *     sdk_init.cpp file header)
 *   * Telemetry flush + model discovery (deferred — handles owned by SDK)
 */

package com.runanywhere.sdk.public

import android.content.Context
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeSdkInit
import com.runanywhere.sdk.foundation.constants.SDKConstants
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.foundation.security.AndroidPlatformContext
import com.runanywhere.sdk.generated.convenience.wireString
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.public.configuration.SDKEnvironment
import com.runanywhere.sdk.public.configuration.SDKInitParams
import com.runanywhere.sdk.public.events.EventBus
import com.runanywhere.sdk.public.extensions.LogLevel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

// ═══════════════════════════════════════════════════════════════════════════
// SDK INITIALIZATION FLOW (Two-Phase Pattern)
// ═══════════════════════════════════════════════════════════════════════════
//
// PHASE 1: Core Init (Synchronous, ~1-5ms, No Network)
// ─────────────────────────────────────────────────────
//   RunAnywhere.initialize(environment)
//     ├─ Build + validate SDKInitParams
//     ├─ CppBridge.initialize()  (via initializePlatformBridge expect)
//     │    ├─ PlatformAdapter.register()  ← File ops, logging, keychain
//     │    ├─ Events.register()           ← Analytics callback
//     │    ├─ Telemetry.initialize()      ← HTTP callback
//     │    ├─ Device.register()           ← Device registration
//     │    └─ CppBridgeSdkInit.phase1 (rac_sdk_init_phase1_proto)
//     │         ← validation + config/state init
//     ├─ Emit SDKInitStarted / SDKInitCompleted events (via CppBridge)
//     └─ Mark: isInitialized = true; spawn Phase 2 in background
//
// PHASE 2: Services Init (Async, ~100-500ms, Network May Be Required)
// ────────────────────────────────────────────────────────────────────
//   RunAnywhere.completeServicesInitialization()
//     ├─ CppBridge.initializeServices()  (via initializePlatformBridgeServices expect)
//     │    ├─ Step 1: HTTP transport + auth round-trip (OkHttp/CppBridgeAuth)
//     │    ├─ Step 2: telemetry flush (CppBridgeTelemetry)
//     │    ├─ Step 3: device registration (CppBridgeDevice.triggerRegistration)
//     └─ Mark: areServicesReady = true; capture hasCompletedHTTPSetup flag
//
// ═══════════════════════════════════════════════════════════════════════════

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
    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - Private State
    // ═══════════════════════════════════════════════════════════════════════════

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

    private val lock = Any()
    private val servicesMutex = Mutex()

    /**
     * Coroutine scope used to spawn Phase 2 in the background from the
     * synchronous [initialize] call site. Mirrors Swift's
     * `Task.detached(priority: .userInitiated)` spawn. SupervisorJob so a
     * Phase 2 failure does not poison the rest of the SDK.
     */
    private val initScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - Public Properties
    // ═══════════════════════════════════════════════════════════════════════════

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

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - Event Access
    // ═══════════════════════════════════════════════════════════════════════════

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

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - Authentication Info (Production/Staging only)
    // ═══════════════════════════════════════════════════════════════════════════

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

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - Phase 1: Core Initialization (Synchronous)
    // ═══════════════════════════════════════════════════════════════════════════

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
                val logLevel =
                    when (params.environment) {
                        SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT -> LogLevel.DEBUG
                        SDKEnvironment.SDK_ENVIRONMENT_STAGING -> LogLevel.INFO
                        SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION -> LogLevel.WARNING
                        SDKEnvironment.SDK_ENVIRONMENT_UNSPECIFIED -> LogLevel.DEBUG
                    }
                SDKLogger.setLevel(logLevel)

                // Hand off to the platform bridge, which loads native libs,
                // registers the platform adapter, runs CppBridgeSdkInit.phase1
                // (rac_sdk_init_phase1_proto — validation + config/state init),
                // and emits SDKInitStarted / SDKInitCompleted events.
                initializePlatformBridge(
                    environment = params.environment,
                    apiKey = params.apiKey,
                    baseURL = params.baseURL,
                )

                _isInitialized = true

                val initDurationMs = System.currentTimeMillis() - initStartTime
                logger.info("Phase 1 complete in ${initDurationMs}ms (${params.environment.wireString})")

                if (startBackgroundServices) {
                    // Spawn Phase 2 in the background. Mirrors Swift's
                    // `Task.detached(priority: .userInitiated) { try await completeServicesInitialization() }`.
                    logger.debug("Starting Phase 2 (services) in background...")
                    initScope.launch {
                        try {
                            completeServicesInitialization()
                            logger.info("Phase 2 complete (background)")
                        } catch (error: Throwable) {
                            logger.warn("Phase 2 failed (non-critical): ${error.message}")
                        }
                    }
                }
            } catch (error: Throwable) {
                logger.error("Initialization failed: ${error.message}")
                // Roll back state on failure so a corrected retry can succeed.
                _initParams = null
                _currentEnvironment = null
                _isInitialized = false
                throw error
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - Phase 2: Services Initialization (Async)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * Complete services initialization (Phase 2). Safe to call multiple times;
     * concurrent callers share the same Mutex so the step list runs at most
     * once. Mirrors Swift's `completeServicesInitialization()` (the
     * `_servicesInitTask` + `_servicesInitLock.sync { ... }` fan-in).
     *
     * The platform bridge runs the Kotlin-side OkHttp orchestration:
     *   1. HTTP transport + auth round-trip (OkHttp/CppBridgeAuth).
     *      Tolerates offline mode — local/cached models stay accessible.
     *   2. Telemetry flush (CppBridgeTelemetry.flush).
     *   3. Device registration (CppBridgeDevice.triggerRegistration).
     *
     * (The commons `rac_sdk_init_phase2_proto` ABI is now bound via
     * `CppBridgeSdkInit.phase2`; Kotlin keeps the OkHttp-backed orchestration
     * here because auth/device/telemetry transport are platform-side, and
     * routes the idempotent HTTP fast-path through `CppBridgeSdkInit.retryHTTP`
     * in [retryHTTPSetup].)
     *
     * HTTPClientAdapter.isConfigured drives [_hasCompletedHTTPSetup] so a
     * later [ensureServicesReady] call can retry HTTP without re-running the
     * rest of the bootstrap.
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
                throw IllegalStateException("SDK must be initialized before completing services initialization")
            }

            val params =
                _initParams
                    ?: throw SDKException.notInitialized("SDK init params missing — call RunAnywhere.initialize() first")

            logger.info("Initializing services for ${params.environment.wireString} mode...")

            try {
                // Delegate to the platform bridge — runs the Kotlin-side
                // OkHttp HTTP auth, telemetry flush, and device registration.
                val httpConfigured = initializePlatformBridgeServices()

                // Decouple "services ready" from "HTTP/auth complete" so
                // offline/local-only Phase 2 still leaves
                // `_hasCompletedHTTPSetup = false`. That keeps the recovery
                // branch in [ensureServicesReady] reachable for the next
                // online call (auth, device registration, telemetry flush,
                // remote catalog/device paths). Mirrors Swift
                // `RunAnywhere.swift:261-265` which derives
                // `hasCompletedHTTPSetup` from `CppBridge.HTTP.shared.isConfigured`.
                _hasCompletedHTTPSetup = httpConfigured
                _areServicesReady = true

                if (httpConfigured) {
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
     *  - Fast path: services ready + HTTP configured → return (O(1)).
     *  - Recovery path: services ready but HTTP failed (offline init) →
     *    retry HTTP setup via [retryHTTPSetup] without re-running Phase 2.
     *  - Cold start path: services not ready → kick off
     *    [completeServicesInitialization].
     *
     * Called by every public feature entry so commonMain consumers do not need
     * to await Phase 2 explicitly. The Mutex guard inside
     * [completeServicesInitialization] serializes concurrent first-callers.
     *
     * @throws IllegalStateException if Phase 1 ([initialize]) has not run.
     */
    internal suspend fun ensureServicesReady() {
        // Fast path — both services and HTTP done.
        if (_areServicesReady && _hasCompletedHTTPSetup) {
            return
        }
        // Recovery path — services done, HTTP failed (offline init).
        if (_areServicesReady && !_hasCompletedHTTPSetup) {
            retryHTTPSetup()
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
     * commons reports `http_configured` (already authenticated), the full
     * Kotlin Phase 2 re-run is skipped. Otherwise it falls back to
     * [initializePlatformBridgeServices] (OkHttp/CppBridgeAuth) so an offline
     * init can complete once connectivity returns.
     */
    private suspend fun retryHTTPSetup() {
        val params = _initParams ?: return
        logger.debug("Retrying HTTP/auth setup for ${params.environment.wireString}...")

        try {
            // Idempotent fast-path: commons returns http_configured=true with
            // no side effects when auth is already established, so we avoid
            // re-running the full Kotlin Phase 2 bootstrap on every call.
            val fastPath = runCatching { CppBridgeSdkInit.retryHTTP() }.getOrNull()
            if (fastPath?.http_configured == true) {
                _hasCompletedHTTPSetup = true
                logger.info("HTTP/Auth already configured (idempotent fast-path)")
                return
            }

            val httpConfigured = initializePlatformBridgeServices()
            _hasCompletedHTTPSetup = httpConfigured
            if (httpConfigured) {
                logger.info("HTTP/Auth setup succeeded on retry")
            } else {
                logger.debug("HTTP/Auth retry still missing usable config; will retry on next call")
            }
        } catch (e: Throwable) {
            logger.debug("HTTP/Auth retry failed (still offline?): ${e.message}")
        }
    }

    /**
     * Ensure SDK is initialized (throws if not)
     */
    internal fun requireInitialized() {
        if (!_isInitialized) {
            throw IllegalStateException("SDK not initialized. Call RunAnywhere.initialize() first.")
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - SDK Reset
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * Reset SDK state
     * Clears all initialization state and releases resources
     */
    suspend fun reset() {
        logger.info("Resetting SDK state...")

        synchronized(lock) {
            // Shutdown CppBridge
            shutdownPlatformBridge()

            _isInitialized = false
            _areServicesReady = false
            _hasCompletedHTTPSetup = false
            _currentEnvironment = null
            _initParams = null
        }

        logger.info("SDK state reset completed")
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Platform-specific bridge functions (expect/actual pattern)
// ═══════════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════
// Platform-specific auth/device state accessors (expect/actual pattern)
// ═══════════════════════════════════════════════════════════════════════════
