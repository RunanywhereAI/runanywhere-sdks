/**
 * CppBridge.swift
 *
 * Unified bridge architecture for C++ ↔ Swift interop.
 *
 * All C++ bridges are organized under a single namespace for:
 * - Consistent initialization/shutdown lifecycle
 * - Shared access to platform resources
 * - Clear ownership and dependency management
 *
 * ## Initialization Order
 *
 * ```swift
 * // Phase 1: Core init (sync) - must be called first
 * CppBridge.initialize(environment: .production)
 *   ├─ PlatformAdapter.register()  ← File ops, logging, keychain
 *   ├─ Events.register()           ← Analytics event callback
 *   ├─ Telemetry.initialize()      ← Telemetry HTTP callback
 *   └─ Device.register()           ← Device registration callbacks
 *
 * // Phase 2: Services init (async) - after HTTP is configured
 * await CppBridge.initializeServices()
 *   ├─ ModelAssignment.register()  ← Model assignment callbacks
 *   └─ Platform.register()         ← LLM/TTS service callbacks
 * ```
 *
 * ## Bridge Extensions (in Extensions/ folder)
 *
 * - CppBridge+PlatformAdapter.swift - File ops, logging, keychain, clock
 * - CppBridge+Environment.swift - Environment, DevConfig, Endpoints
 * - CppBridge+Telemetry.swift - Events, Telemetry
 * - CppBridge+Device.swift - Device registration
 * - CppBridge+State.swift - SDK state management
 * - CppBridge+HTTP.swift - HTTP transport
 * - CppBridge+Auth.swift - Authentication flow
 * - CppBridge+Services.swift - Service registry
 * - CppBridge+ModelPaths.swift - Model path utilities
 * - CppBridge+ModelRegistry.swift - Model registry
 * - CppBridge+ModelAssignment.swift - Model assignment
 * - CppBridge+Download.swift - Download manager
 * - CppBridge+Platform.swift - Platform services (Foundation Models, System TTS)
 * - CppBridge+LLM/STT/TTS/VAD.swift - AI component bridges
 * - CppBridge+VoiceAgent.swift - Voice agent bridge
 * - CppBridge+Storage/Strategy.swift - Storage utilities
 */

import CRACommons
import Foundation

// MARK: - Main Bridge Coordinator

/// Central coordinator for all C++ bridges
/// Manages lifecycle and shared resources
public enum CppBridge {

    // MARK: - Shared State

    private static var _environment: SDKEnvironment = .development
    private static var _isInitialized = false
    private static var _servicesInitialized = false
    private static let lock = NSLock()

    /// Current SDK environment
    static var environment: SDKEnvironment {
        lock.lock()
        defer { lock.unlock() }
        return _environment
    }

    /// Whether core bridges are initialized (Phase 1)
    public static var isInitialized: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isInitialized
    }

    /// Whether service bridges are initialized (Phase 2)
    public static var servicesInitialized: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _servicesInitialized
    }

    // MARK: - Phase 1: Core Initialization (Synchronous)

    /// Initialize all core C++ bridges
    ///
    /// This must be called FIRST during SDK initialization, before any C++ operations.
    /// It registers fundamental platform callbacks that C++ needs.
    ///
    /// - Parameter environment: SDK environment
    public static func initialize(environment: SDKEnvironment) {
        lock.lock()
        guard !_isInitialized else {
            lock.unlock()
            return
        }
        _environment = environment
        lock.unlock()

        // Step 1: Platform adapter FIRST (logging, file ops, keychain)
        // This must be registered before any other C++ calls
        PlatformAdapter.register()

        // Step 1.5: Configure C++ logging based on environment
        // In production: disables C++ stderr, logs only go through Swift bridge
        // In development: C++ stderr ON for debugging
        rac_configure_logging(environment.cEnvironment)

        // Step 2: Events callback (for analytics routing)
        Events.register()

        // Step 3: Telemetry manager (builds JSON, calls HTTP callback)
        Telemetry.initialize(environment: environment)

        // Step 4: Device registration callbacks
        Device.register()

        // Step 5: Register built-in backends (memory/vector search)
        let memResult = rac_backend_memory_register()
        if memResult != RAC_SUCCESS && memResult != RAC_ERROR_MODULE_ALREADY_REGISTERED {
            SDKLogger(category: "CppBridge").warning("Memory backend registration failed: \(memResult)")
        }

        lock.lock()
        _isInitialized = true
        lock.unlock()

        SDKLogger(category: "CppBridge").debug("Core bridges initialized for \(environment)")
    }

    // MARK: - Phase 2: Services Initialization (Async)

    /// Initialize service bridges that require HTTP
    ///
    /// Called after HTTP transport is configured. These bridges need
    /// network access to function.
    @MainActor
    public static func initializeServices() {
        lock.lock()
        guard !_servicesInitialized else {
            lock.unlock()
            return
        }
        let currentEnv = _environment
        lock.unlock()

        // Model assignment (needs HTTP for API calls)
        // Only auto-fetch in staging/production, not development
        // IMPORTANT: Register WITHOUT auto-fetch first to avoid MainActor deadlock
        // The HTTP callback uses semaphore.wait() which would block MainActor
        // while the Task{} inside needs MainActor access
        let shouldAutoFetch = currentEnv != .development
        ModelAssignment.register(autoFetch: false)

        // If auto-fetch is needed, trigger it asynchronously off MainActor
        if shouldAutoFetch {
            Task.detached {
                do {
                    _ = try await ModelAssignment.fetch(forceRefresh: true)
                    SDKLogger(category: "CppBridge").info("Auto-fetched model assignments successfully")
                } catch {
                    SDKLogger(category: "CppBridge").warning("Auto-fetch model assignments failed: \(error.localizedDescription)")
                }
            }
        }

        // Platform services (Foundation Models, System TTS)
        Platform.register()

        lock.lock()
        _servicesInitialized = true
        lock.unlock()

        SDKLogger(category: "CppBridge").debug("Service bridges initialized (env: \(currentEnv), autoFetch: \(shouldAutoFetch))")
    }

    // MARK: - Shutdown

    /// Shutdown all C++ bridges
    public static func shutdown() {
        lock.lock()
        let wasInitialized = _isInitialized
        lock.unlock()

        guard wasInitialized else { return }

        // Shutdown in reverse order
        // Note: ModelAssignment and Platform callbacks remain valid (static)

        rac_backend_memory_unregister()
        Telemetry.shutdown()
        Events.unregister()
        // PlatformAdapter callbacks remain valid (static)
        // Device callbacks remain valid (static)

        lock.lock()
        _isInitialized = false
        _servicesInitialized = false
        lock.unlock()

        SDKLogger(category: "CppBridge").debug("All bridges shutdown")
    }
}
