//
//  ModuleDiscovery.swift
//  RunAnywhere SDK
//
//  Handles automatic discovery and registration of SDK modules.
//  Modules register themselves via their static `autoRegister` property.
//

import Foundation

/// Manages automatic module discovery and registration.
///
/// Modules can register themselves for auto-discovery by adding
/// an `autoRegister` static property that calls `ModuleDiscovery.register()`.
///
/// ## Usage
///
/// In your module:
///
/// ```swift
/// extension LlamaCPP {
///     public static let autoRegister: Void = {
///         ModuleDiscovery.register(LlamaCPP.self)
///     }()
/// }
/// ```
///
/// The SDK will automatically discover and register modules during initialization
/// when the module is imported and the `autoRegister` property is accessed.
public enum ModuleDiscovery {
    /// Lock for thread-safe access to registered modules
    private static let lock = NSLock()

    /// Set of registered module IDs (to prevent duplicate registration)
    private static var registeredModuleIds: Set<String> = []

    /// Array of pending module types (to be registered when SDK initializes)
    private static var pendingModules: [any RunAnywhereModule.Type] = []

    /// Whether the SDK has been initialized (modules should register immediately)
    private static var sdkInitialized = false

    // MARK: - Public API

    /// Register a module for auto-discovery.
    ///
    /// If the SDK is already initialized, the module is registered immediately.
    /// Otherwise, it's queued for registration when the SDK initializes.
    ///
    /// - Parameter moduleType: The module type to register
    public static func register<M: RunAnywhereModule>(_ moduleType: M.Type) {
        lock.lock()
        defer { lock.unlock() }

        // Check for duplicate
        guard !registeredModuleIds.contains(M.moduleId) else {
            return
        }

        registeredModuleIds.insert(M.moduleId)

        if sdkInitialized {
            // Register immediately on main actor
            Task { @MainActor in
                M.register()
            }
        } else {
            // Queue for later registration
            pendingModules.append(moduleType)
        }
    }

    /// Called by the SDK during initialization to register all pending modules.
    ///
    /// - Important: This should only be called by `RunAnywhere.initialize()`.
    @MainActor
    internal static func registerPendingModules() {
        lock.lock()
        let modules = pendingModules
        pendingModules.removeAll()
        sdkInitialized = true
        lock.unlock()

        for moduleType in modules {
            moduleType.register()
        }
    }

    /// Reset the discovery state.
    ///
    /// - Important: This should only be called by `RunAnywhere.reset()`.
    internal static func reset() {
        lock.lock()
        registeredModuleIds.removeAll()
        pendingModules.removeAll()
        sdkInitialized = false
        lock.unlock()
    }

    /// Get all registered module IDs.
    ///
    /// - Returns: Set of module identifiers that have been registered.
    public static func registeredModules() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return registeredModuleIds
    }
}
