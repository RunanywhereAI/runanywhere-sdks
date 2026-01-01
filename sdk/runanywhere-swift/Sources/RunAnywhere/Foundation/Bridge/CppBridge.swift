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
 * Usage:
 * ```swift
 * // Initialize all bridges
 * CppBridge.initialize(environment: .production, apiClient: client)
 *
 * // Access specific bridges
 * CppBridge.Environment.requiresAuth(.production)
 * CppBridge.Telemetry.track(event)
 * CppBridge.Auth.getAccessToken()
 * ```
 *
 * Bridge Extensions (in Extensions/ folder):
 * - CppBridge+Environment.swift - Environment, DevConfig, Endpoints
 * - CppBridge+Telemetry.swift - Events, Telemetry
 * - CppBridge+Device.swift - Device registration
 * - CppBridge+State.swift - SDK state management
 * - CppBridge+HTTP.swift - HTTP transport
 * - CppBridge+Auth.swift - Authentication flow
 * - CppBridge+Services.swift - Service registry
 * - CppBridge+ModelPaths.swift - Model path utilities
 * - CppBridge+ModelRegistry.swift - Model registry
 * - CppBridge+Download.swift - Download manager
 * - ModelTypes+CppBridge.swift - Model type conversions
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
    private static let lock = NSLock()

    /// Current SDK environment
    static var environment: SDKEnvironment {
        lock.lock()
        defer { lock.unlock() }
        return _environment
    }

    /// Whether bridges are initialized
    public static var isInitialized: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isInitialized
    }

    // MARK: - Lifecycle

    /// Initialize all C++ bridges
    /// - Parameter environment: SDK environment
    public static func initialize(environment: SDKEnvironment) {
        lock.lock()
        _environment = environment
        _isInitialized = true
        lock.unlock()

        // Initialize sub-bridges
        Events.register()
        Telemetry.initialize(environment: environment)

        SDKLogger(category: "CppBridge").info("All bridges initialized for \(environment)")
    }

    /// Shutdown all C++ bridges
    public static func shutdown() {
        // Shutdown sub-bridges in reverse order
        Telemetry.shutdown()
        Events.unregister()

        lock.lock()
        _isInitialized = false
        lock.unlock()

        SDKLogger(category: "CppBridge").info("All bridges shutdown")
    }
}
