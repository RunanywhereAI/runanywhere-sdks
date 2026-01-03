/*
 * Copyright 2024 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Main entry point for the RunAnywhere SDK.
 * Thin wrapper that delegates to CppBridge for C++ interop.
 *
 * This file mirrors the iOS SDK's RunAnywhere.swift structure.
 */

package com.runanywhere.sdk.public

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.public.events.EventBus
import com.runanywhere.sdk.utils.SDKConstants

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
 * SDK environment configuration.
 */
enum class SDKEnvironment(val cEnvironment: Int) {
    DEVELOPMENT(0),
    STAGING(1),
    PRODUCTION(2);

    companion object {
        fun fromCEnvironment(cEnvironment: Int): SDKEnvironment =
            entries.find { it.cEnvironment == cEnvironment } ?: DEVELOPMENT
    }
}

/**
 * The RunAnywhere SDK - Single entry point for on-device AI
 *
 * This object mirrors the iOS RunAnywhere enum pattern, providing:
 * - SDK initialization (two-phase: fast sync + async services)
 * - State access (isInitialized, areServicesReady, version, environment)
 * - Event access via `events` property
 *
 * Feature-specific APIs are available through extension functions in public/extensions/:
 * - STT: RunAnywhere.transcribe(), RunAnywhere.loadSTTModel()
 * - TTS: RunAnywhere.synthesize(), RunAnywhere.loadTTSVoice()
 * - LLM: RunAnywhere.chat(), RunAnywhere.generate(), RunAnywhere.generateStream()
 * - VAD: RunAnywhere.detectSpeech()
 * - VoiceAgent: RunAnywhere.startVoiceSession()
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

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - Public Properties
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * Check if SDK is initialized (Phase 1 complete)
     */
    val isInitialized: Boolean
        get() = _isInitialized

    /**
     * Alias for isInitialized for compatibility
     */
    val isSDKInitialized: Boolean
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
     * RunAnywhere.initialize(environment = SDKEnvironment.PRODUCTION)
     * ```
     *
     * @param apiKey API key (optional for development, required for production/staging)
     * @param baseURL Backend API base URL (optional)
     * @param environment SDK environment (default: DEVELOPMENT)
     */
    fun initialize(
        apiKey: String? = null,
        baseURL: String? = null,
        environment: SDKEnvironment = SDKEnvironment.DEVELOPMENT,
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
                val logLevel = when (environment) {
                    SDKEnvironment.DEVELOPMENT -> SDKLogger.Companion.LogLevel.DEBUG
                    SDKEnvironment.STAGING -> SDKLogger.Companion.LogLevel.INFO
                    SDKEnvironment.PRODUCTION -> SDKLogger.Companion.LogLevel.WARNING
                }
                SDKLogger.setLogLevel(logLevel)

                // Initialize CppBridge (Phase 1)
                // Note: CppBridge is in jvmAndroidMain, we call it via expect/actual
                initializeCppBridge(environment)

                // Mark Phase 1 complete
                _isInitialized = true

                val initDurationMs = System.currentTimeMillis() - initStartTime
                logger.info("✅ Phase 1 complete in ${initDurationMs}ms (${environment.name})")
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
        initialize(apiKey = apiKey, environment = SDKEnvironment.DEVELOPMENT)
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

        synchronized(lock) {
            if (_areServicesReady) {
                return
            }

            if (!_isInitialized) {
                throw IllegalStateException("SDK must be initialized before completing services initialization")
            }

            logger.info("Initializing services for ${_currentEnvironment?.name} mode...")

            try {
                // Initialize CppBridge services (Phase 2)
                initializeCppBridgeServices()

                // Mark Phase 2 complete
                _areServicesReady = true

                logger.info("✅ Services initialized for ${_currentEnvironment?.name} mode")
            } catch (e: Exception) {
                logger.error("Services initialization failed: ${e.message}")
                throw e
            }
        }
    }

    /**
     * Ensure services are ready before API calls (internal guard)
     * O(1) after first successful initialization
     */
    internal suspend fun ensureServicesReady() {
        if (_areServicesReady) {
            return // O(1) fast path
        }
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
    private fun initializeCppBridge(environment: SDKEnvironment) {
        // This will be implemented via expect/actual to call CppBridge.initialize()
        // For now, this is a placeholder that works in commonMain
        logger.debug("CppBridge initialization requested for $environment")
    }

    /**
     * Initialize CppBridge services (Phase 2)
     * Implementation is in jvmAndroidMain via expect/actual
     */
    private fun initializeCppBridgeServices() {
        // This will be implemented via expect/actual to call CppBridge.initializeServices()
        logger.debug("CppBridge services initialization requested")
    }

    /**
     * Shutdown CppBridge
     * Implementation is in jvmAndroidMain via expect/actual
     */
    private fun shutdownCppBridge() {
        // This will be implemented via expect/actual to call CppBridge.shutdown()
        logger.debug("CppBridge shutdown requested")
    }
}
