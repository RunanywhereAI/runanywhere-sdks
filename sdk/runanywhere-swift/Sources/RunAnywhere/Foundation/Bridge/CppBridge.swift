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

        // Step 2: Events callback (for analytics routing)
        Events.register()

        // Step 3: Telemetry manager (builds JSON, calls HTTP callback)
        Telemetry.initialize(environment: environment)

        // Step 4: Device registration callbacks
        Device.register()

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
        lock.unlock()

        // Model assignment (needs HTTP for API calls)
        ModelAssignment.register()

        // Platform services (Foundation Models, System TTS)
        Platform.register()

        lock.lock()
        _servicesInitialized = true
        lock.unlock()

        SDKLogger(category: "CppBridge").debug("Service bridges initialized")
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
