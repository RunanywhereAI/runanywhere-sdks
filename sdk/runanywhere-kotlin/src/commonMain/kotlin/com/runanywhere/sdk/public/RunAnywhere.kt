/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * The main entry point for the RunAnywhere SDK.
 * Two-phase initialization is owned by commons (rac_sdk_init.h, P2-T9):
 *   * Phase 1 → rac_sdk_init_phase1_proto (validate + state init)
 *   * Phase 2 → rac_sdk_init_phase2_proto (device registration, model
 *     assignments, HTTP-state snapshot)
 *   * HTTP retry → rac_sdk_retry_http_proto
 * Kotlin retains only the parts that cannot move into C++:
 *   * Coroutine Mutex + servicesMutex concurrency primitive
 *   * EncryptedSharedPreferences / file-backed SDK params persistence
 *   * JNI platform-plugin registration on JVM/Android main thread
 *   * HTTP authentication round-trip via OkHttp (deferred per
 *     sdk_init.cpp file header)
 *   * Telemetry flush + model discovery (deferred — handles owned by SDK)
 */

package com.runanywhere.sdk.public

import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.public.configuration.SDKEnvironment
import com.runanywhere.sdk.public.configuration.wireString
import com.runanywhere.sdk.public.events.EventBus
import com.runanywhere.sdk.public.extensions.LogLevel
import com.runanywhere.sdk.foundation.constants.SDKConstants
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

// ═══════════════════════════════════════════════════════════════════════════
// SDK INITIALIZATION FLOW (Two-Phase Pattern)
// ═══════════════════════════════════════════════════════════════════════════
//
// PHASE 1: Core Init (Synchronous, ~1-5ms, No Network)
// ─────────────────────────────────────────────────────
//   RunAnywhere.initialize(environment)
//     ├─ CppBridge.initialize()
//     │    ├─ PlatformAdapter.register()  ← File ops, logging, keychain
//     │    ├─ Events.register()           ← Analytics callback
//     │    ├─ Telemetry.initialize()      ← HTTP callback
//     │    └─ Device.register()           ← Device registration
//     └─ Mark: isInitialized = true
//
// PHASE 2: Services Init (Async, ~100-500ms, Network May Be Required)
// ────────────────────────────────────────────────────────────────────
//   RunAnywhere.completeServicesInitialization()
//     ├─ CppBridge.initializeServices()
//     │    ├─ ModelAssignment.register()  ← Model assignment callbacks
//     │    └─ Platform.register()         ← LLM/TTS service callbacks
//     └─ Mark: areServicesReady = true
//
// ═══════════════════════════════════════════════════════════════════════════

/**
 * The RunAnywhere SDK - Single entry point for on-device AI
 *
 * This object mirrors the iOS RunAnywhere enum pattern, providing:
 * - SDK initialization (two-phase: fast sync + async services)
 * - State access (isInitialized, areServicesReady, version, environment)
 * - Event access via `events` property
 *
 * Feature-specific APIs are available through extension functions in public/extensions/:
 * - STT: RunAnywhere.transcribe(), RunAnywhere.transcribeStream()
 * - TTS: RunAnywhere.synthesize(), RunAnywhere.loadModel(RAModelLoadRequest)
 * - LLM: RunAnywhere.generate(), RunAnywhere.generateStream()
 * - VAD: RunAnywhere.detectSpeech()
 * - VoiceAgent: VoiceAgentStreamAdapter(handle).stream() (v3.1)
 *
 * All AI component logic (LLM, STT, TTS, VAD) is delegated to the C++ runanywhere-commons
 * layer via CppBridge. Kotlin only handles platform-specific operations (HTTP, audio, file I/O).
 */
object RunAnywhere {
    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - Private State
    // ═══════════════════════════════════════════════════════════════════════════

    private val logger = SDKLogger("RunAnywhere")

    @Volatile
    private var _currentEnvironment: SDKEnvironment? = null

    @Volatile
    private var _isInitialized: Boolean = false

    @Volatile
    private var _areServicesReady: Boolean = false

    private val lock = Any()
    private val servicesMutex = Mutex()

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
        get() = _isInitialized && _currentEnvironment != null

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
     * This performs fast synchronous initialization. Services initialization
     * is done separately via [completeServicesInitialization].
     *
     * ## Usage Examples
     *
     * ```kotlin
     * // Development mode (default)
     * RunAnywhere.initialize()
     *
     * // Production mode
     * RunAnywhere.initialize(environment = SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION)
     * ```
     *
     * @param apiKey API key (optional for development, required for production/staging)
     * @param baseURL Backend API base URL (optional)
     * @param environment SDK environment (default: DEVELOPMENT)
     */
    fun initialize(
        apiKey: String? = null,
        baseURL: String? = null,
        environment: SDKEnvironment = SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
    ) {
        synchronized(lock) {
            if (_isInitialized) {
                logger.info("SDK already initialized")
                return
            }

            val initStartTime = System.currentTimeMillis()

            try {
                // Store environment
                _currentEnvironment = environment

                // Set log level based on environment
                val logLevel =
                    when (environment) {
                        SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT -> LogLevel.DEBUG
                        SDKEnvironment.SDK_ENVIRONMENT_STAGING -> LogLevel.INFO
                        SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION -> LogLevel.WARNING
                        SDKEnvironment.SDK_ENVIRONMENT_UNSPECIFIED -> LogLevel.DEBUG
                    }
                SDKLogger.setLevel(logLevel)

                // Initialize CppBridge (Phase 1)
                // Note: CppBridge is in jvmAndroidMain, we call it via expect/actual
                initializeCppBridge(environment, apiKey, baseURL)

                // Mark Phase 1 complete
                _isInitialized = true

                val initDurationMs = System.currentTimeMillis() - initStartTime
                logger.info("✅ Phase 1 complete in ${initDurationMs}ms (${environment.wireString})")
            } catch (error: Exception) {
                logger.error("❌ Initialization failed: ${error.message}")
                _currentEnvironment = null
                _isInitialized = false
                throw error
            }
        }
    }

    /**
     * Initialize SDK for development mode (convenience method)
     */
    fun initializeForDevelopment(apiKey: String? = null) {
        initialize(apiKey = apiKey, environment = SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - Phase 2: Services Initialization (Async)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * Complete services initialization (Phase 2)
     *
     * Called automatically on first API call, or can be awaited directly.
     * Safe to call multiple times - returns immediately if already done.
     */
    suspend fun completeServicesInitialization() {
        // Fast path: already completed
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

            logger.info("Initializing services for ${_currentEnvironment?.wireString} mode...")

            try {
                // Initialize CppBridge services (Phase 2)
                initializeCppBridgeServices()

                // Mark Phase 2 complete
                _areServicesReady = true

                logger.info("✅ Services initialized for ${_currentEnvironment?.wireString} mode")
            } catch (e: Exception) {
                logger.error("Services initialization failed: ${e.message}")
                throw e
            }
        }
    }

    /**
     * Ensure services are ready before API calls (internal guard).
     *
     * Mirrors Swift `RunAnywhere.ensureServicesReady()`. Lazily kicks off
     * Phase 2 (`completeServicesInitialization()`) the first time a feature
     * entry is hit, so commonMain consumers do **not** need to make that
     * call explicitly — the same shape as the iOS SDK's `_servicesInitTask`
     * fan-in. The Mutex guard inside [completeServicesInitialization]
     * serializes concurrent first-callers.
     *
     * O(1) after the first successful initialization.
     *
     * @throws IllegalStateException if Phase 1 ([initialize]) has not run.
     */
    internal suspend fun ensureServicesReady() {
        if (_areServicesReady) {
            return // O(1) fast path — Phase 2 already complete
        }
        // Phase 1 must be complete before we can lazily start Phase 2.
        requireInitialized()
        // Auto-start Phase 2 — `completeServicesInitialization` is mutex-guarded
        // and short-circuits if another caller already finished the work.
        completeServicesInitialization()
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
            shutdownCppBridge()

            _isInitialized = false
            _areServicesReady = false
            _currentEnvironment = null
        }

        logger.info("SDK state reset completed")
    }

    /**
     * Cleanup SDK resources without full reset
     */
    suspend fun cleanup() {
        logger.info("Cleaning up SDK resources...")
        // Cleanup logic here
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - CppBridge Integration (expect/actual pattern)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * Initialize CppBridge (Phase 1)
     * Implementation is in jvmAndroidMain via expect/actual
     */
    private fun initializeCppBridge(environment: SDKEnvironment, apiKey: String?, baseURL: String?) {
        logger.debug("CppBridge initialization requested for $environment")
        initializePlatformBridge(environment, apiKey, baseURL)
    }

    /**
     * Initialize CppBridge services (Phase 2)
     * Implementation is in jvmAndroidMain via expect/actual
     */
    private suspend fun initializeCppBridgeServices() {
        logger.debug("CppBridge services initialization requested")
        initializePlatformBridgeServices()
    }

    /**
     * Shutdown CppBridge
     * Implementation is in jvmAndroidMain via expect/actual
     */
    private fun shutdownCppBridge() {
        logger.debug("CppBridge shutdown requested")
        shutdownPlatformBridge()
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Platform-specific bridge functions (expect/actual pattern)
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Initialize platform-specific bridge (Phase 1).
 * On JVM/Android, this calls CppBridge.initialize() to load native libraries.
 *
 * @param environment SDK environment
 * @param apiKey API key for authentication (required for production/staging)
 * @param baseURL Backend API base URL (required for production/staging)
 */
internal expect fun initializePlatformBridge(environment: SDKEnvironment, apiKey: String?, baseURL: String?)

/**
 * Initialize platform-specific bridge services (Phase 2).
 * On JVM/Android, this calls CppBridge.initializeServices().
 */
internal expect suspend fun initializePlatformBridgeServices()

/**
 * Shutdown platform-specific bridge.
 * On JVM/Android, this calls CppBridge.shutdown().
 */
internal expect fun shutdownPlatformBridge()

// ═══════════════════════════════════════════════════════════════════════════
// Platform-specific auth/device state accessors (expect/actual pattern)
// ═══════════════════════════════════════════════════════════════════════════

/** JVM/Android actual routes to `RunAnywhereBridge.racAuthGetUserId()`. */
internal expect fun platformGetUserId(): String?

/** JVM/Android actual routes to `RunAnywhereBridge.racAuthGetOrganizationId()`. */
internal expect fun platformGetOrganizationId(): String?

/** JVM/Android actual routes to `RunAnywhereBridge.racAuthIsAuthenticated()`. */
internal expect fun platformIsAuthenticated(): Boolean

/** JVM/Android actual routes to `CppBridgeDevice.isRegistered()`. */
internal expect fun platformIsDeviceRegistered(): Boolean

/**
 * JVM/Android actual routes to `CppBridgeDevice.getDeviceId()` →
 * `RunAnywhereBridge.racAuthGetDeviceId()` chain, returning empty string when
 * the device hasn't been registered yet.
 */
internal expect fun platformDeviceId(): String
