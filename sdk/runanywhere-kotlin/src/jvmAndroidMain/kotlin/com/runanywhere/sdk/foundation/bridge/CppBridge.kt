/**
 * CppBridge.kt
 *
 * Unified bridge architecture for C++ ↔ Kotlin interop.
 *
 * All C++ bridges are organized under a single namespace for:
 * - Consistent initialization/shutdown lifecycle
 * - Shared access to platform resources
 * - Clear ownership and dependency management
 *
 * ## Initialization Order
 *
 * ```kotlin
 * // Phase 1: Core init (sync) - must be called first
 * CppBridge.initialize(environment = SDKEnvironment.PRODUCTION)
 *   ├─ PlatformAdapter.register()  ← File ops, logging, keychain
 *   ├─ Events.register()           ← Analytics event callback
 *   ├─ Telemetry.initialize()      ← Telemetry HTTP callback
 *   └─ Device.register()           ← Device registration callbacks
 *
 * // Phase 2: Services init (async) - after HTTP is configured
 * CppBridge.initializeServices()
 *   ├─ ModelAssignment.register()  ← Model assignment callbacks
 *   └─ Platform.register()         ← LLM/TTS service callbacks
 * ```
 *
 * ## Bridge Extensions (in Extensions/ folder)
 *
 * - CppBridge+PlatformAdapter.kt - File ops, logging, keychain, clock
 * - CppBridge+Environment.kt - Environment, DevConfig, Endpoints
 * - CppBridge+Telemetry.kt - Events, Telemetry
 * - CppBridge+Device.kt - Device registration
 * - CppBridge+State.kt - SDK state management
 * - CppBridge+HTTP.kt - HTTP transport
 * - CppBridge+Auth.kt - Authentication flow
 * - CppBridge+Services.kt - Service registry
 * - CppBridge+ModelPaths.kt - Model path utilities
 * - CppBridge+ModelRegistry.kt - Model registry
 * - CppBridge+ModelAssignment.kt - Model assignment
 * - CppBridge+Download.kt - Download manager
 * - CppBridge+Platform.kt - Platform services (Foundation Models, System TTS)
 * - CppBridge+LLM/STT/TTS/VAD.kt - AI component bridges
 * - CppBridge+VoiceAgent.kt - Voice agent bridge
 * - CppBridge+Storage/Strategy.kt - Storage utilities
 */

package com.runanywhere.sdk.foundation.bridge

import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.foundation.SDKLogger

// MARK: - Main Bridge Coordinator

/**
 * Central coordinator for all C++ bridges.
 * Manages lifecycle and shared resources.
 *
 * This is the Kotlin equivalent of iOS CppBridge.swift.
 * Uses Kotlin's object (singleton) pattern instead of Swift's enum with static methods.
 */
object CppBridge {

    // MARK: - Private State

    private var _environment: SDKEnvironment = SDKEnvironment.DEVELOPMENT
    private var _isInitialized = false
    private var _servicesInitialized = false
    private val lock = Any()

    private val logger = SDKLogger("CppBridge")

    // MARK: - Public Properties

    /**
     * Current SDK environment.
     */
    val environment: SDKEnvironment
        @Synchronized get() = _environment

    /**
     * Whether core bridges are initialized (Phase 1).
     */
    val isInitialized: Boolean
        @Synchronized get() = _isInitialized

    /**
     * Whether service bridges are initialized (Phase 2).
     */
    val servicesInitialized: Boolean
        @Synchronized get() = _servicesInitialized

    // MARK: - Phase 1: Core Initialization (Synchronous)

    /**
     * Initialize all core C++ bridges.
     *
     * This must be called FIRST during SDK initialization, before any C++ operations.
     * It registers fundamental platform callbacks that C++ needs.
     *
     * @param environment SDK environment
     */
    fun initialize(environment: SDKEnvironment) {
        synchronized(lock) {
            if (_isInitialized) {
                return
            }
            _environment = environment
        }

        // Step 1: Platform adapter FIRST (logging, file ops, keychain)
        // This must be registered before any other C++ calls
        // PlatformAdapter.register()  // TODO: Implement in CppBridge+PlatformAdapter.kt

        // Step 1.5: Configure C++ logging based on environment
        // In production: disables C++ stderr, logs only go through Kotlin bridge
        // In development: C++ stderr ON for debugging
        // rac_configure_logging(environment.cEnvironment)  // TODO: Add JNI binding

        // Step 2: Events callback (for analytics routing)
        // Events.register()  // TODO: Implement in CppBridge+Telemetry.kt

        // Step 3: Telemetry manager (builds JSON, calls HTTP callback)
        // Telemetry.initialize(environment)  // TODO: Implement in CppBridge+Telemetry.kt

        // Step 4: Device registration callbacks
        // Device.register()  // TODO: Implement in CppBridge+Device.kt

        synchronized(lock) {
            _isInitialized = true
        }

        logger.debug("Core bridges initialized for $environment")
    }

    // MARK: - Phase 2: Services Initialization (Async)

    /**
     * Initialize service bridges that require HTTP.
     *
     * Called after HTTP transport is configured. These bridges need
     * network access to function.
     *
     * Note: In iOS this is @MainActor, but Kotlin uses suspend functions
     * or explicit main thread dispatching when needed.
     */
    fun initializeServices() {
        synchronized(lock) {
            if (_servicesInitialized) {
                return
            }
        }

        // Model assignment (needs HTTP for API calls)
        // ModelAssignment.register()  // TODO: Implement in CppBridge+ModelAssignment.kt

        // Platform services (Foundation Models, System TTS)
        // Platform.register()  // TODO: Implement in CppBridge+Platform.kt

        synchronized(lock) {
            _servicesInitialized = true
        }

        logger.debug("Service bridges initialized")
    }

    // MARK: - Shutdown

    /**
     * Shutdown all C++ bridges.
     */
    fun shutdown() {
        val wasInitialized: Boolean
        synchronized(lock) {
            wasInitialized = _isInitialized
        }

        if (!wasInitialized) {
            return
        }

        // Shutdown in reverse order
        // Note: ModelAssignment and Platform callbacks remain valid (static)

        // Telemetry.shutdown()  // TODO: Implement in CppBridge+Telemetry.kt
        // Events.unregister()  // TODO: Implement in CppBridge+Telemetry.kt
        // PlatformAdapter callbacks remain valid (static)
        // Device callbacks remain valid (static)

        synchronized(lock) {
            _isInitialized = false
            _servicesInitialized = false
        }

        logger.debug("All bridges shutdown")
    }
}
