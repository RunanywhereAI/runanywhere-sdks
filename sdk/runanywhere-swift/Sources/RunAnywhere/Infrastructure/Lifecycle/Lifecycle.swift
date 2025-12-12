//
//  Lifecycle.swift
//  RunAnywhere SDK
//
//  Public entry point for the Lifecycle capability
//  Provides unified access to model, adapter, service, and component lifecycle management
//

import Combine
import Foundation

/// Public entry point for the Lifecycle capability
/// Provides unified lifecycle management for models, adapters, services, and components
public final class Lifecycle {

    // MARK: - Shared Instance

    /// Shared singleton instance for convenient access
    public static let shared = Lifecycle()

    // MARK: - Properties

    private var _modelService: DefaultModelLifecycleService?
    private let logger = SDKLogger(category: "Lifecycle")

    // MARK: - Initialization

    /// Initialize with default configuration
    public convenience init() {
        self.init(configuration: .default)
    }

    /// Initialize with custom configuration
    /// - Parameter configuration: The lifecycle configuration
    public init(configuration: LifecycleConfiguration) {
        logger.debug("Lifecycle capability initialized")
    }

    // MARK: - Model Lifecycle

    /// Access the model lifecycle service
    public var modelService: ModelLifecycleService {
        get async {
            if let existing = _modelService {
                return existing
            }
            let newService = DefaultModelLifecycleService(
                registry: ServiceContainer.shared.modelRegistry,
                adapterRegistry: ServiceContainer.shared.adapterRegistry
            )
            _modelService = newService
            return newService
        }
    }

    /// Access the model lifecycle tracker for observing state changes
    @MainActor
    public var modelTracker: ModelLifecycleTracker {
        ModelLifecycleTracker.shared
    }

    // MARK: - Adapter Lifecycle

    /// Access the adapter registry for framework adapter management
    public var adapterRegistry: AdapterRegistry {
        ServiceContainer.shared.adapterRegistry
    }

    /// Register a framework adapter
    /// - Parameters:
    ///   - adapter: The adapter to register
    ///   - priority: Priority level (higher = preferred)
    public func registerAdapter(_ adapter: FrameworkAdapter, priority: Int = 100) {
        logger.info("Registering adapter: \(adapter.framework.rawValue) with priority \(priority)")
        adapterRegistry.register(adapter, priority: priority)
    }

    /// Get available frameworks
    /// - Returns: Array of registered frameworks
    public func availableFrameworks() -> [LLMFramework] {
        return adapterRegistry.getAvailableFrameworks()
    }

    /// Get frameworks supporting a specific modality
    /// - Parameter modality: The modality to filter by
    /// - Returns: Array of frameworks
    public func frameworks(for modality: FrameworkModality) -> [LLMFramework] {
        return adapterRegistry.getFrameworks(for: modality)
    }

    // MARK: - Service Lifecycle

    private var _serviceLifecycleManager: ServiceLifecycleManager?

    /// Access the service lifecycle manager
    public var serviceLifecycle: ServiceLifecycleManager {
        get async {
            if let existing = _serviceLifecycleManager {
                return existing
            }
            let newManager = ServiceLifecycleManager()
            _serviceLifecycleManager = newManager
            return newManager
        }
    }

    /// Register a lifecycle-aware service
    /// - Parameters:
    ///   - service: The service to register
    ///   - name: Unique name for the service
    public func registerService(_ service: LifecycleAwareService, name: String) async {
        logger.info("Registering lifecycle-aware service: \(name)")
        await serviceLifecycle.register(service, name: name)
    }

    /// Start all registered services
    public func startAllServices() async throws {
        logger.info("Starting all lifecycle-aware services")
        try await serviceLifecycle.startAll()
    }

    /// Stop all registered services
    public func stopAllServices() async throws {
        logger.info("Stopping all lifecycle-aware services")
        try await serviceLifecycle.stopAll()
    }

    // MARK: - Component Lifecycle

    private var _componentLifecycleManager: ComponentLifecycleManager?

    /// Access the component lifecycle manager
    public var componentLifecycle: ComponentLifecycleManager {
        get async {
            if let existing = _componentLifecycleManager {
                return existing
            }
            let newManager = ComponentLifecycleManager()
            _componentLifecycleManager = newManager
            return newManager
        }
    }

    /// Initialize SDK components
    /// - Parameter configs: Array of component configurations
    /// - Returns: Initialization result
    public func initializeComponents(_ configs: [UnifiedComponentConfig]) async -> InitializationResult {
        logger.info("Initializing \(configs.count) components")
        return await componentLifecycle.initialize(configs)
    }

    /// Get component status
    /// - Parameter component: The component to check
    /// - Returns: Current status
    public func componentStatus(for component: SDKComponent) async -> ComponentStatus {
        return await componentLifecycle.getStatus(for: component)
    }

    /// Check if a component is ready
    /// - Parameter component: The component to check
    /// - Returns: True if ready
    public func isComponentReady(_ component: SDKComponent) async -> Bool {
        return await componentLifecycle.isReady(component)
    }

    // MARK: - Model Convenience Methods

    /// Load a model by identifier
    /// - Parameters:
    ///   - modelId: The model identifier
    ///   - modality: The modality for this model (defaults to .llm)
    /// - Returns: The loaded model
    /// - Throws: LifecycleError if loading fails
    public func loadModel(_ modelId: String, modality: Modality = .llm) async throws -> LoadedModel {
        logger.info("Loading model: \(modelId) for modality: \(modality.displayName)")
        return try await modelService.loadModel(modelId, modality: modality)
    }

    /// Load a model with progress tracking
    /// - Parameters:
    ///   - modelId: The model identifier
    ///   - modality: The modality for this model
    ///   - onProgress: Callback for progress updates (0.0 to 1.0)
    /// - Returns: The loaded model
    public func loadModel(
        _ modelId: String,
        modality: Modality = .llm,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> LoadedModel {
        logger.info("Loading model with progress: \(modelId)")
        return try await modelService.loadModel(modelId, modality: modality, onProgress: onProgress)
    }

    /// Unload a model by identifier
    /// - Parameter modelId: The model identifier
    public func unloadModel(_ modelId: String) async throws {
        logger.info("Unloading model: \(modelId)")
        try await modelService.unloadModel(modelId)
    }

    /// Unload all models for a specific modality
    /// - Parameter modality: The modality to unload
    public func unloadModels(for modality: Modality) async throws {
        logger.info("Unloading all models for: \(modality.displayName)")
        try await modelService.unloadModels(for: modality)
    }

    /// Unload all loaded models
    public func unloadAllModels() async throws {
        logger.info("Unloading all models")
        try await modelService.unloadAllModels()
    }

    // MARK: - Query Methods

    /// Check if a model is loaded
    /// - Parameter modelId: The model identifier
    /// - Returns: True if the model is loaded
    public func isModelLoaded(_ modelId: String) async -> Bool {
        return await modelService.isModelLoaded(modelId)
    }

    /// Check if a model is loaded for a specific modality
    /// - Parameter modality: The modality to check
    /// - Returns: True if a model is loaded
    @MainActor
    public func isModelLoaded(for modality: Modality) -> Bool {
        return modelTracker.isModelLoaded(for: modality)
    }

    /// Get the loaded model for a specific modality
    /// - Parameter modality: The modality to query
    /// - Returns: The loaded model state if available
    @MainActor
    public func loadedModel(for modality: Modality) -> LoadedModelState? {
        return modelTracker.loadedModel(for: modality)
    }

    /// Get all currently loaded models
    /// - Returns: Array of all loaded model states
    @MainActor
    public func allLoadedModels() -> [LoadedModelState] {
        return modelTracker.allLoadedModels()
    }

    // MARK: - Service Access

    /// Get the LLM service for a loaded model
    /// - Parameter modelId: The model identifier
    /// - Returns: The LLM service if available
    public func llmService(for modelId: String) async -> (any LLMService)? {
        return await modelService.getLLMService(for: modelId)
    }

    /// Get the STT service for a loaded model
    /// - Parameter modelId: The model identifier
    /// - Returns: The STT service if available
    public func sttService(for modelId: String) async -> (any STTService)? {
        return await modelService.getSTTService(for: modelId)
    }

    /// Get the TTS service for a loaded model
    /// - Parameter modelId: The model identifier
    /// - Returns: The TTS service if available
    public func ttsService(for modelId: String) async -> (any TTSService)? {
        return await modelService.getTTSService(for: modelId)
    }

    // MARK: - Events

    /// Subscribe to model lifecycle events
    /// - Returns: A publisher that emits lifecycle events
    public var modelLifecycleEvents: AnyPublisher<ModelLifecycleEvent, Never> {
        get async {
            return await modelService.lifecycleEvents
        }
    }

    /// Subscribe to lifecycle events from the tracker (synchronous access)
    @MainActor
    public var trackerEvents: AnyPublisher<ModelLifecycleEvent, Never> {
        return modelTracker.lifecycleEvents.eraseToAnyPublisher()
    }

    // MARK: - Memory Management

    /// Get estimated memory usage for a model
    /// - Parameter modelId: The model identifier
    /// - Returns: Estimated memory in bytes
    public func estimateMemoryUsage(for modelId: String) async -> Int64 {
        return await modelService.estimateMemoryUsage(for: modelId)
    }

    /// Get total memory usage by all loaded models
    /// - Returns: Total memory in bytes
    @MainActor
    public func totalMemoryUsage() -> Int64 {
        return modelTracker.totalMemoryUsage()
    }

    /// Handle memory pressure
    public func handleMemoryPressure() async {
        logger.warning("Handling memory pressure")
        await modelService.handleMemoryPressure()
    }

    // MARK: - Cleanup

    /// Clean up all lifecycle resources
    public func cleanup() async {
        logger.info("Cleaning up Lifecycle capability")
        await _modelService?.cleanup()
        _modelService = nil

        if let serviceManager = _serviceLifecycleManager {
            try? await serviceManager.stopAll()
        }
        _serviceLifecycleManager = nil

        if let componentManager = _componentLifecycleManager {
            try? await componentManager.cleanup()
        }
        _componentLifecycleManager = nil
    }
}

// MARK: - Static Convenience Methods

public extension Lifecycle {

    /// Load a model (static convenience method)
    @discardableResult
    static func load(_ modelId: String, modality: Modality = .llm) async throws -> LoadedModel {
        return try await shared.loadModel(modelId, modality: modality)
    }

    /// Unload a model (static convenience method)
    static func unload(_ modelId: String) async throws {
        try await shared.unloadModel(modelId)
    }

    /// Check if a model is loaded (static convenience method)
    static func isLoaded(_ modelId: String) async -> Bool {
        return await shared.isModelLoaded(modelId)
    }

    /// Get the model tracker (static convenience method)
    @MainActor
    static var currentModelTracker: ModelLifecycleTracker {
        return shared.modelTracker
    }

    /// Register an adapter (static convenience method)
    static func register(_ adapter: FrameworkAdapter, priority: Int = 100) {
        shared.registerAdapter(adapter, priority: priority)
    }
}
