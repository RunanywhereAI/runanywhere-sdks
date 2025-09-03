import Foundation

// MARK: - Component Factory

/// Factory for creating and managing components
public final class ComponentFactory {

    // MARK: - Properties

    /// Registered component types
    private var componentTypes: [SDKComponent: Component.Type] = [:]

    /// Active component instances
    private var activeComponents: [SDKComponent: Component] = [:]

    /// Thread safety
    private let queue = DispatchQueue(label: "com.runanywhere.componentfactory", attributes: .concurrent)

    /// Shared instance
    public static let shared = ComponentFactory()

    /// Logger
    private let logger = SDKLogger(category: "ComponentFactory")

    // MARK: - Registration

    /// Register a component type
    public func register<T: Component>(_ componentType: T.Type) {
        queue.async(flags: .barrier) { [weak self] in
            self?.componentTypes[T.componentType] = componentType
            self?.logger.debug("Registered component type: \(T.componentType.rawValue)")
        }
    }

    /// Register multiple component types
    public func registerComponents(_ components: [Component.Type]) {
        components.forEach { register($0) }
    }

    // MARK: - Component Creation

    /// Create a component with given parameters
    public func createComponent(
        type: SDKComponent,
        parameters: any ComponentInitParameters
    ) throws -> Component {

        // Check if component is already active
        if let existing = getActiveComponent(type: type) {
            logger.debug("Returning existing component: \(type.rawValue)")
            return existing
        }

        // Get registered component type
        guard let componentClass = queue.sync(execute: { componentTypes[type] }) else {
            throw SDKError.validationFailed("Component type not registered: \(type.rawValue)")
        }

        // Create component instance based on type
        let component: Component

        // Use specific initializers based on component requirements
        if let baseComponentClass = componentClass as? BaseComponent.Type {
            component = baseComponentClass.init(parameters: parameters)
        } else {
            // Fallback - component must implement its own initialization
            throw SDKError.validationFailed("Component must inherit from BaseComponent: \(type.rawValue)")
        }

        // Store active component
        queue.async(flags: .barrier) { [weak self] in
            self?.activeComponents[type] = component
        }

        logger.debug("Created component: \(type.rawValue)")
        return component
    }

    /// Get or create a component
    public func getOrCreateComponent(
        type: SDKComponent,
        parameters: any ComponentInitParameters
    ) async throws -> Component {

        if let existing = getActiveComponent(type: type) {
            // Verify parameters match or reinitialize if different
            if !parametersMatch(existing.parameters, parameters) {
                logger.debug("Reinitializing component with new parameters: \(type.rawValue)")
                try await existing.initialize(with: parameters)
            }
            return existing
        }

        return try createComponent(type: type, parameters: parameters)
    }

    // MARK: - Component Management

    /// Get active component
    public func getActiveComponent(type: SDKComponent) -> Component? {
        queue.sync { activeComponents[type] }
    }

    /// Remove component
    public func removeComponent(type: SDKComponent) async throws {
        guard let component = getActiveComponent(type: type) else { return }

        // Cleanup component
        try await component.cleanup()

        // Remove from active components
        queue.async(flags: .barrier) { [weak self] in
            self?.activeComponents.removeValue(forKey: type)
            self?.logger.debug("Removed component: \(type.rawValue)")
        }
    }

    /// Clean up all components
    public func cleanupAll() async throws {
        let components = queue.sync { Array(activeComponents.values) }

        for component in components {
            try await component.cleanup()
        }

        queue.async(flags: .barrier) { [weak self] in
            self?.activeComponents.removeAll()
            self?.logger.debug("Cleaned up all components")
        }
    }

    // MARK: - Helper Methods

    private func parametersMatch(_ params1: any ComponentInitParameters, _ params2: any ComponentInitParameters) -> Bool {
        // Simple comparison - can be enhanced based on needs
        return type(of: params1) == type(of: params2) && params1.modelId == params2.modelId
    }
}

// MARK: - Component Registration Extension

extension ComponentFactory {

    /// Register default SDK components
    public func registerDefaultComponents() {
        // Register built-in component types
        // These will be the actual component implementations

        // Example registrations (implementations to be created):
        // register(LLMComponent.self)
        // register(STTComponent.self)
        // register(TTSComponent.self)
        // register(VADComponent.self)
        // register(VLMComponent.self)
        // register(EmbeddingComponent.self)
        // register(SpeakerDiarizationComponent.self)

        logger.info("Registered default SDK components")
    }
}

// MARK: - Unified Component Manager

/// Manages component lifecycle using the factory
public actor UnifiedComponentManager {

    // MARK: - Properties

    private let factory = ComponentFactory.shared
    private let logger = SDKLogger(category: "UnifiedComponentManager")
    private let eventBus = EventBus.shared

    // MARK: - Initialization

    /// Initialize components with configurations
    public func initializeComponents(_ configs: [UnifiedComponentConfig]) async -> InitializationResult {
        let startTime = Date()
        var successful: [SDKComponent] = []
        var failed: [(SDKComponent, Error)] = []

        // Sort by priority
        let sortedConfigs = configs.sorted { $0.priority > $1.priority }

        // Emit start event
        eventBus.publish(SDKInitializationEvent.started)

        // Group by parallelization capability
        let parallelizable = sortedConfigs.filter { canParallelize($0.component) }
        let sequential = sortedConfigs.filter { !canParallelize($0.component) }

        // Initialize parallel components
        if !parallelizable.isEmpty {
            await withTaskGroup(of: (SDKComponent, Result<Void, Error>).self) { group in
                for config in parallelizable {
                    group.addTask { [weak self] in
                        do {
                            try await self?.initializeComponent(config)
                            return (config.component, .success(()))
                        } catch {
                            return (config.component, .failure(error))
                        }
                    }
                }

                for await (component, result) in group {
                    switch result {
                    case .success:
                        successful.append(component)
                    case .failure(let error):
                        failed.append((component, error))
                    }
                }
            }
        }

        // Initialize sequential components
        for config in sequential {
            do {
                try await initializeComponent(config)
                successful.append(config.component)
            } catch {
                failed.append((config.component, error))
            }
        }

        // Create result
        let result = InitializationResult(
            successful: successful,
            failed: failed,
            duration: Date().timeIntervalSince(startTime),
            timestamp: Date()
        )

        // Emit completion event
        if failed.isEmpty {
            eventBus.publish(SDKInitializationEvent.completed)
        } else {
            eventBus.publish(SDKInitializationEvent.failed(
                SDKError.validationFailed("Failed components: \(failed.map { $0.0.rawValue })")
            ))
        }

        return result
    }

    // MARK: - Component Initialization

    private func initializeComponent(_ config: UnifiedComponentConfig) async throws {
        // Get or create component
        let component = try await factory.getOrCreateComponent(
            type: config.component,
            parameters: config.parameters
        )

        // Initialize if not ready
        if !component.isReady {
            try await component.initialize(with: config.parameters)
        }
    }

    private func canParallelize(_ component: SDKComponent) -> Bool {
        // Heavy components should initialize sequentially
        switch component {
        case .llm, .vlm:
            return false
        default:
            return true
        }
    }

    // MARK: - Status Management

    /// Get status of all components
    public func getAllStatuses() -> [ComponentStatus] {
        SDKComponent.allCases.map { component in
            if let activeComponent = factory.getActiveComponent(type: component) {
                return ComponentStatus(
                    component: component,
                    state: activeComponent.state,
                    modelId: activeComponent.parameters.modelId,
                    progress: nil,
                    error: nil
                )
            } else {
                return ComponentStatus(
                    component: component,
                    state: .notInitialized,
                    modelId: nil,
                    progress: nil,
                    error: nil
                )
            }
        }
    }

    /// Get status of specific component
    public func getStatus(for component: SDKComponent) -> ComponentStatus {
        if let activeComponent = factory.getActiveComponent(type: component) {
            return ComponentStatus(
                component: component,
                state: activeComponent.state,
                modelId: activeComponent.parameters.modelId,
                progress: nil,
                error: nil
            )
        } else {
            return ComponentStatus(
                component: component,
                state: .notInitialized,
                modelId: nil,
                progress: nil,
                error: nil
            )
        }
    }

    /// Clean up all components
    public func cleanup() async throws {
        try await factory.cleanupAll()
    }
}
