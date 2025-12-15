//
//  ModuleRegistry.swift
//  RunAnywhere SDK
//
//  Central registry for tracking and managing loaded modules.
//  Works alongside ServiceRegistry to provide module-level visibility.
//

import Foundation

// MARK: - Module Registry

/// Central registry for tracking loaded RunAnywhere modules.
///
/// This registry provides:
/// - Unified module registration API
/// - Module discovery and introspection
/// - Prevention of duplicate registration
/// - Auto-registration support via module discovery
///
/// ## Usage
///
/// ### Manual Registration (Recommended)
/// ```swift
/// import ONNXRuntime
/// import LlamaCPPRuntime
///
/// // At app startup:
/// ModuleRegistry.shared.register(ONNX.self)
/// ModuleRegistry.shared.register(LlamaCPP.self)
/// ```
///
/// ### Auto-Registration
/// ```swift
/// // Registers all modules that have been imported
/// ModuleRegistry.shared.registerDiscoveredModules()
/// ```
///
/// ### Querying Modules
/// ```swift
/// if ModuleRegistry.shared.isRegistered("onnx") {
///     print("ONNX module is available")
/// }
///
/// let sttModules = ModuleRegistry.shared.modules(for: .stt)
/// ```
@MainActor
public final class ModuleRegistry {
    /// Shared singleton instance
    public static let shared = ModuleRegistry()

    // MARK: - Storage

    private var registeredModules: [String: ModuleMetadata] = [:]
    private var moduleTypes: [String: any RunAnywhereModule.Type] = [:]
    private var storageStrategies: [InferenceFramework: ModelStorageStrategy] = [:]
    private var downloadStrategies: [InferenceFramework: DownloadStrategy] = [:]
    private let logger = SDKLogger(category: "ModuleRegistry")

    private init() {}

    // MARK: - Registration

    /// Register a module with the SDK
    ///
    /// - Parameters:
    ///   - module: The module type to register
    ///   - priority: Override the default priority (optional)
    public func register<M: RunAnywhereModule>(
        _ module: M.Type,
        priority: Int? = nil
    ) {
        let effectivePriority = priority ?? M.defaultPriority

        // Check for duplicate registration
        if registeredModules[M.moduleId] != nil {
            logger.warning("Module '\(M.moduleId)' already registered, skipping")
            return
        }

        // Register the module's services
        M.register(priority: effectivePriority)

        // Store metadata
        let metadata = ModuleMetadata(
            moduleId: M.moduleId,
            moduleName: M.moduleName,
            capabilities: M.capabilities,
            priority: effectivePriority
        )
        registeredModules[M.moduleId] = metadata
        moduleTypes[M.moduleId] = module

        // Store storage strategy if provided
        if let strategy = M.storageStrategy {
            storageStrategies[M.inferenceFramework] = strategy
            logger.info("Storage strategy registered for \(M.inferenceFramework.rawValue)")
        }

        // Store download strategy if provided
        if let strategy = M.downloadStrategy {
            downloadStrategies[M.inferenceFramework] = strategy
            logger.info("Download strategy registered for \(M.inferenceFramework.rawValue)")
        }

        logger.info("Module registered: \(M.moduleName) [\(M.moduleId)] with capabilities: \(M.capabilities.map(\.rawValue).joined(separator: ", "))")
    }

    // MARK: - Discovery

    /// Register all modules that have been discovered.
    /// This should be called at app startup after all imports.
    public func registerDiscoveredModules() {
        let discovered = ModuleDiscovery.discoveredModules
        logger.info("Registering \(discovered.count) discovered modules")

        for moduleType in discovered {
            // Use the moduleId to check if already registered
            if registeredModules[moduleType.moduleId] == nil {
                let metadata = ModuleMetadata(
                    moduleId: moduleType.moduleId,
                    moduleName: moduleType.moduleName,
                    capabilities: moduleType.capabilities,
                    priority: moduleType.defaultPriority
                )

                moduleType.register(priority: moduleType.defaultPriority)
                registeredModules[moduleType.moduleId] = metadata
                moduleTypes[moduleType.moduleId] = moduleType

                // Store storage strategy if provided
                if let strategy = moduleType.storageStrategy {
                    storageStrategies[moduleType.inferenceFramework] = strategy
                    logger.info("Storage strategy registered for \(moduleType.inferenceFramework.rawValue)")
                }

                // Store download strategy if provided
                if let strategy = moduleType.downloadStrategy {
                    downloadStrategies[moduleType.inferenceFramework] = strategy
                    logger.info("Download strategy registered for \(moduleType.inferenceFramework.rawValue)")
                }

                logger.info("Auto-registered module: \(moduleType.moduleName)")
            }
        }
    }

    // MARK: - Querying

    /// Check if a module is registered
    public func isRegistered(_ moduleId: String) -> Bool {
        registeredModules[moduleId] != nil
    }

    /// Get metadata for a registered module
    public func metadata(for moduleId: String) -> ModuleMetadata? {
        registeredModules[moduleId]
    }

    /// Get all registered module IDs
    public var moduleIds: [String] {
        Array(registeredModules.keys).sorted()
    }

    /// Get all registered module metadata
    public var allModules: [ModuleMetadata] {
        Array(registeredModules.values).sorted { $0.moduleId < $1.moduleId }
    }

    /// Get modules that provide a specific capability
    public func modules(for capability: CapabilityType) -> [ModuleMetadata] {
        registeredModules.values
            .filter { $0.capabilities.contains(capability) }
            .sorted { $0.priority > $1.priority }
    }

    /// Get module IDs that provide a specific capability
    public func moduleIds(for capability: CapabilityType) -> [String] {
        modules(for: capability).map(\.moduleId)
    }

    /// Check if any module provides a specific capability
    public func hasCapability(_ capability: CapabilityType) -> Bool {
        registeredModules.values.contains { $0.capabilities.contains(capability) }
    }

    // MARK: - Storage Strategies

    /// Get the storage strategy for a framework
    /// - Parameter framework: The inference framework
    /// - Returns: The registered storage strategy, or nil if none
    public func storageStrategy(for framework: InferenceFramework) -> ModelStorageStrategy? {
        storageStrategies[framework]
    }

    /// Check if a storage strategy is registered for a framework
    public func hasStorageStrategy(for framework: InferenceFramework) -> Bool {
        storageStrategies[framework] != nil
    }

    // MARK: - Download Strategies

    /// Get the download strategy for a framework
    /// - Parameter framework: The inference framework
    /// - Returns: The registered download strategy, or nil if none
    public func downloadStrategy(for framework: InferenceFramework) -> DownloadStrategy? {
        downloadStrategies[framework]
    }

    /// Get all registered download strategies
    public var allDownloadStrategies: [DownloadStrategy] {
        Array(downloadStrategies.values)
    }

    /// Find a download strategy that can handle the given model
    /// - Parameter model: The model to find a strategy for
    /// - Returns: A download strategy that can handle the model, or nil
    public func downloadStrategy(for model: ModelInfo) -> DownloadStrategy? {
        // First try the model's preferred framework
        if let framework = model.preferredFramework,
           let strategy = downloadStrategies[framework],
           strategy.canHandle(model: model) {
            return strategy
        }

        // Then try compatible frameworks
        for framework in model.compatibleFrameworks {
            if let strategy = downloadStrategies[framework],
               strategy.canHandle(model: model) {
                return strategy
            }
        }

        return nil
    }

    /// Check if a download strategy is registered for a framework
    public func hasDownloadStrategy(for framework: InferenceFramework) -> Bool {
        downloadStrategies[framework] != nil
    }

    // MARK: - Reset

    /// Reset all module registrations (useful for testing)
    public func reset() {
        registeredModules.removeAll()
        moduleTypes.removeAll()
        storageStrategies.removeAll()
        downloadStrategies.removeAll()
        ServiceRegistry.shared.reset()
        logger.info("Module registry reset")
    }
}

// MARK: - RunAnywhere Extension

public extension RunAnywhere {
    /// Register a module with the SDK
    ///
    /// ```swift
    /// RunAnywhere.register(ONNX.self)
    /// RunAnywhere.register(LlamaCPP.self, priority: 150)
    /// ```
    @MainActor
    static func register<M: RunAnywhereModule>(_ module: M.Type, priority: Int? = nil) {
        ModuleRegistry.shared.register(module, priority: priority)
    }

    /// Register all discovered modules
    ///
    /// ```swift
    /// RunAnywhere.registerAllModules()
    /// ```
    @MainActor
    static func registerAllModules() {
        ModuleRegistry.shared.registerDiscoveredModules()
    }

    /// Get all registered modules
    @MainActor
    static var registeredModules: [ModuleMetadata] {
        ModuleRegistry.shared.allModules
    }

    /// Check if a capability is available
    @MainActor
    static func hasCapability(_ capability: CapabilityType) -> Bool {
        ModuleRegistry.shared.hasCapability(capability)
    }
}

// MARK: - Module Discovery (Thread-Safe)

/// Thread-safe storage for module auto-discovery.
///
/// This is a separate helper to allow modules to register themselves
/// for discovery during static initialization (before main actor is available).
public final class ModuleDiscovery: @unchecked Sendable {
    /// Shared lock for thread-safe access
    private static let lock = NSLock()

    /// Discovered module types
    private static var _discoveredModules: [any RunAnywhereModule.Type] = []

    /// Get all discovered modules (thread-safe)
    public static var discoveredModules: [any RunAnywhereModule.Type] {
        lock.lock()
        defer { lock.unlock() }
        return _discoveredModules
    }

    /// Register a module type for auto-discovery.
    ///
    /// Call this from your module's static initialization to enable auto-registration.
    ///
    /// ```swift
    /// extension MyModule {
    ///     static let _autoRegister: Void = {
    ///         ModuleDiscovery.register(MyModule.self)
    ///     }()
    /// }
    /// ```
    ///
    /// - Parameter module: The module type to register for discovery
    public static func register<M: RunAnywhereModule>(_ module: M.Type) {
        lock.lock()
        defer { lock.unlock() }

        // Only add if not already registered
        if !_discoveredModules.contains(where: { $0.moduleId == M.moduleId }) {
            _discoveredModules.append(module)
        }
    }

    /// Clear all discovered modules (for testing)
    public static func reset() {
        lock.lock()
        defer { lock.unlock() }
        _discoveredModules.removeAll()
    }
}
