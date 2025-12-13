//
//  ComponentLifecycleManager.swift
//  RunAnywhere SDK
//
//  Manages component initialization and lifecycle
//

import Foundation

/// Unified initializer that manages component lifecycle
public actor ComponentLifecycleManager {

    // MARK: - Properties

    private let logger = SDKLogger(category: "ComponentLifecycleManager")
    private weak var serviceContainer: ServiceContainer?

    private var eventBus: EventBus {
        serviceContainer?.eventBus ?? ServiceContainer.shared.eventBus
    }

    // Component tracking
    private var activeComponents: [SDKComponent: Component] = [:]

    // MARK: - Initialization

    public init(serviceContainer: ServiceContainer? = nil) {
        self.serviceContainer = serviceContainer ?? ServiceContainer.shared
    }

    // MARK: - Public API

    /// Initialize components using provided configurations
    /// - Parameter configs: Array of component configurations to initialize
    /// - Returns: Result containing successful and failed components
    public func initialize(_ configs: [UnifiedComponentConfig]) async -> InitializationResult {
        let startTime = Date()
        logger.info("Initializing \(configs.count) component(s)")
        eventBus.publish(SDKInitializationEvent.started)

        let sortedConfigs = configs.sorted { $0.priority > $1.priority }
        let (successful, failed) = await initializeAllComponents(sortedConfigs)

        return createInitializationResult(
            successful: successful,
            failed: failed,
            startTime: startTime
        )
    }

    /// Initialize a single component
    /// - Parameter config: Configuration for the component
    /// - Throws: If initialization fails
    public func initializeComponent(_ config: UnifiedComponentConfig) async throws {
        guard let container = serviceContainer else {
            throw LifecycleError.componentNotInitialized(component: config.component.rawValue)
        }

        // Check if component already exists
        if let existing = activeComponents[config.component] {
            try await reinitializeIfNeeded(existing, with: config.parameters)
            return
        }

        // Create new component
        let component = try await createComponent(config, container: container)
        activeComponents[config.component] = component
        try await component.initialize(with: config.parameters)

        logger.info("Component initialized: \(config.component.rawValue)")
    }

    /// Get status for a specific component
    /// - Parameter component: The component to check
    /// - Returns: Status of the component
    public func getStatus(for component: SDKComponent) -> ComponentStatus {
        if let active = activeComponents[component] {
            return ComponentStatus(
                component: component,
                state: active.state,
                modelId: active.parameters.modelId
            )
        } else {
            return ComponentStatus(
                component: component,
                state: .notInitialized
            )
        }
    }

    /// Get statuses for all components
    /// - Returns: Array of component statuses
    public func getAllStatuses() -> [ComponentStatus] {
        SDKComponent.allCases.map { component in
            if let active = activeComponents[component] {
                return ComponentStatus(
                    component: component,
                    state: active.state,
                    modelId: active.parameters.modelId,
                    progress: nil,
                    error: nil
                )
            } else {
                return ComponentStatus(
                    component: component,
                    state: .notInitialized
                )
            }
        }
    }

    /// Check if a component is ready
    /// - Parameter component: The component to check
    /// - Returns: Whether the component is ready
    public func isReady(_ component: SDKComponent) -> Bool {
        activeComponents[component]?.isReady ?? false
    }

    /// Clean up all components
    /// - Throws: If cleanup fails
    public func cleanup() async throws {
        logger.info("Cleaning up all components")

        for (componentType, component) in activeComponents {
            do {
                try await component.cleanup()
                logger.debug("Cleaned up component: \(componentType.rawValue)")
            } catch {
                logger.error("Failed to cleanup component '\(componentType.rawValue)': \(error)")
                throw LifecycleError.componentCleanupFailed(
                    component: componentType.rawValue,
                    error: error
                )
            }
        }

        activeComponents.removeAll()
        logger.info("All components cleaned up")
    }

    // MARK: - Private Methods

    /// Initialize all components in parallel and sequential groups
    private func initializeAllComponents(_ configs: [UnifiedComponentConfig]) async -> ([SDKComponent], [(SDKComponent, Error)]) {
        let parallel = configs.filter { canParallelize($0.component) }
        let sequential = configs.filter { !canParallelize($0.component) }

        var successful: [SDKComponent] = []
        var failed: [(SDKComponent, Error)] = []

        // Initialize parallel components
        let parallelResults = await initializeParallelComponents(parallel)
        successful.append(contentsOf: parallelResults.successful)
        failed.append(contentsOf: parallelResults.failed)

        // Initialize sequential components
        let sequentialResults = await initializeSequentialComponents(sequential)
        successful.append(contentsOf: sequentialResults.successful)
        failed.append(contentsOf: sequentialResults.failed)

        return (successful, failed)
    }

    /// Initialize components that can run in parallel
    private func initializeParallelComponents(_ configs: [UnifiedComponentConfig]) async -> (successful: [SDKComponent], failed: [(SDKComponent, Error)]) {
        guard !configs.isEmpty else { return ([], []) }

        var successful: [SDKComponent] = []
        var failed: [(SDKComponent, Error)] = []

        await withTaskGroup(of: (SDKComponent, Result<Void, Error>).self) { group in
            for config in configs {
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

        return (successful, failed)
    }

    /// Initialize components sequentially
    private func initializeSequentialComponents(_ configs: [UnifiedComponentConfig]) async -> (successful: [SDKComponent], failed: [(SDKComponent, Error)]) {
        var successful: [SDKComponent] = []
        var failed: [(SDKComponent, Error)] = []

        for config in configs {
            do {
                try await initializeComponent(config)
                successful.append(config.component)
            } catch {
                failed.append((config.component, error))
            }
        }

        return (successful, failed)
    }

    /// Create the final initialization result
    private func createInitializationResult(
        successful: [SDKComponent],
        failed: [(SDKComponent, Error)],
        startTime: Date
    ) -> InitializationResult {
        let result = InitializationResult(
            successful: successful,
            failed: failed,
            duration: Date().timeIntervalSince(startTime),
            timestamp: Date()
        )

        if failed.isEmpty {
            logger.info("All components initialized successfully")
            eventBus.publish(SDKInitializationEvent.completed)
        } else {
            logger.error("Some components failed to initialize: \(failed.map { $0.0.rawValue })")
            eventBus.publish(SDKInitializationEvent.failed(
                RunAnywhereError.validationFailed("Failed: \(failed.map { $0.0.rawValue })")
            ))
        }

        return result
    }

    /// Reinitialize existing component if parameters changed
    private func reinitializeIfNeeded(_ component: Component, with parameters: any ComponentInitParameters) async throws {
        if !parametersMatch(component.parameters, parameters) {
            logger.debug("Reinitializing component with new parameters")
            try await component.initialize(with: parameters)
        }
    }

    /// Create component based on type
    private func createComponent(_ config: UnifiedComponentConfig, container: ServiceContainer) async throws -> Component {
        switch config.component {
        case .llm:
            return try await createLLMComponent(config, container: container)
        case .stt:
            return try await createSTTComponent(config, container: container)
        case .tts:
            return try await createTTSComponent(config, container: container)
        case .vad:
            return try await createVADComponent(config, container: container)
        case .embedding:
            return try await createEmbeddingComponent(config, container: container)
        case .speakerDiarization:
            return try await createSpeakerDiarizationComponent(config, container: container)
        case .voiceAgent:
            throw LifecycleError.componentNotInitialized(component: "Voice agent should be created through createVoiceAgent method")
        }
    }

    // MARK: - Component Creation Methods

    private func createLLMComponent(_ config: UnifiedComponentConfig, container: ServiceContainer) async throws -> Component {
        guard let params = config.parameters as? LLMConfiguration else {
            throw LifecycleError.invalidConfiguration(reason: "Invalid LLM parameters")
        }
        return await LLMComponent(configuration: params)
    }

    private func createSTTComponent(_ config: UnifiedComponentConfig, container: ServiceContainer) async throws -> Component {
        guard let params = config.parameters as? STTConfiguration else {
            throw LifecycleError.invalidConfiguration(reason: "Invalid STT parameters")
        }
        return await STTComponent(configuration: params)
    }

    private func createTTSComponent(_ config: UnifiedComponentConfig, container: ServiceContainer) async throws -> Component {
        guard let params = config.parameters as? TTSConfiguration else {
            throw LifecycleError.invalidConfiguration(reason: "Invalid TTS parameters")
        }
        return await TTSComponent(configuration: params)
    }

    private func createVADComponent(_ config: UnifiedComponentConfig, container: ServiceContainer) async throws -> Component {
        guard let params = config.parameters as? VADConfiguration else {
            throw LifecycleError.invalidConfiguration(reason: "Invalid VAD parameters")
        }
        return await VADComponent(configuration: params)
    }

    private func createEmbeddingComponent(_ config: UnifiedComponentConfig, container: ServiceContainer) async throws -> Component {
        throw LifecycleError.componentNotInitialized(component: "Embedding component not yet implemented")
    }

    private func createSpeakerDiarizationComponent(_ config: UnifiedComponentConfig, container: ServiceContainer) async throws -> Component {
        // Speaker Diarization uses facade pattern (SpeakerDiarization.shared) instead of Component pattern
        // Access via SpeakerDiarization.shared.configure(with: configuration) instead
        throw LifecycleError.componentNotInitialized(component: "Speaker Diarization uses SpeakerDiarization.shared facade, not Component pattern")
    }

    // MARK: - Helper Methods

    private func canParallelize(_ component: SDKComponent) -> Bool {
        switch component {
        case .llm:
            return false // Heavy memory component
        default:
            return true
        }
    }

    private func parametersMatch(_ p1: any ComponentInitParameters, _ p2: any ComponentInitParameters) -> Bool {
        type(of: p1) == type(of: p2) && p1.modelId == p2.modelId
    }
}
