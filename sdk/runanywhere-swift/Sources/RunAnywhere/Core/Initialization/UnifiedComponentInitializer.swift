import Foundation

// MARK: - Unified Component Initializer

/// Unified initializer that works with existing adapters and services
public actor UnifiedComponentInitializer {
    // MARK: - Properties

    private let logger: SDKLogger = SDKLogger(category: "UnifiedComponentInitializer")
    private let eventBus: EventBus = EventBus.shared
    // Component factory no longer needed - create components directly
    private weak var serviceContainer: ServiceContainer?

    // Component tracking
    private var activeComponents: [SDKComponent: Component] = [:]

    // MARK: - Initialization

    public init(serviceContainer: ServiceContainer? = nil) {
        self.serviceContainer = serviceContainer ?? ServiceContainer.shared
    }

    // MARK: - Public API

    /// Initialize components using existing adapters
    public func initialize(_ configs: [UnifiedComponentConfig]) async -> InitializationResult {
        let startTime = Date()
        eventBus.publish(SDKInitializationEvent.started)

        let sortedConfigs = configs.sorted { $0.priority > $1.priority }
        let (successful, failed) = await initializeAllComponents(sortedConfigs)

        return createInitializationResult(
            successful: successful,
            failed: failed,
            startTime: startTime
        )
    }

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
            eventBus.publish(SDKInitializationEvent.completed)
        } else {
            eventBus.publish(SDKInitializationEvent.failed(
                SDKError.validationFailed("Failed: \(failed.map { $0.0.rawValue })")
            ))
        }

        return result
    }

    // MARK: - Component Initialization

    private func initializeComponent(_ config: UnifiedComponentConfig) async throws {
        guard let container = serviceContainer else {
            throw SDKError.notInitialized("Service container is not available for component initialization")
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
    }

    /// Reinitialize existing component if parameters changed
    private func reinitializeIfNeeded(_ component: Component, with parameters: any ComponentInitParameters) async throws {
        if !parametersMatch(component.parameters, parameters) {
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
        case .vlm:
            return try await createVLMComponent(config, container: container)
        case .embedding:
            return try await createEmbeddingComponent(config, container: container)
        case .speakerDiarization:
            return try await createSpeakerDiarizationComponent(config, container: container)
        case .wakeWord:
            throw SDKError.componentNotInitialized("Wake word component not yet implemented")
        case .voiceAgent:
            throw SDKError.componentNotInitialized("Voice agent should be created through createVoiceAgent method")
        }
    }

    // MARK: - Component Creation Using Existing Adapters

    private func createLLMComponent(_ config: UnifiedComponentConfig, container: ServiceContainer) async throws -> Component {
        guard let params = config.parameters as? LLMConfiguration else {
            throw SDKError.validationFailed("Invalid LLM parameters")
        }

        // Use existing LLMComponent
        return await LLMComponent(configuration: params)
    }

    private func createSTTComponent(_ config: UnifiedComponentConfig, container: ServiceContainer) async throws -> Component {
        guard let params = config.parameters as? STTConfiguration else {
            throw SDKError.validationFailed("Invalid STT parameters")
        }

        // Create simple STT component that uses adapter
        return await STTComponent(configuration: params)
    }

    private func createTTSComponent(_ config: UnifiedComponentConfig, container: ServiceContainer) async throws -> Component {
        guard let params = config.parameters as? TTSConfiguration else {
            throw SDKError.validationFailed("Invalid TTS parameters")
        }

        // Create simple TTS component
        return await TTSComponent(configuration: params)
    }

    private func createVADComponent(_ config: UnifiedComponentConfig, container: ServiceContainer) async throws -> Component {
        guard let params = config.parameters as? VADConfiguration else {
            throw SDKError.validationFailed("Invalid VAD parameters")
        }

        // VAD uses SimpleEnergyVAD directly - params is already VADConfiguration which VADComponent expects
        return await VADComponent(configuration: params)
    }

    private func createVLMComponent(_ config: UnifiedComponentConfig, container: ServiceContainer) async throws -> Component {
        guard config.parameters is VLMConfiguration else {
            throw SDKError.validationFailed("Invalid VLM parameters")
        }

        // For now, VLM is not implemented - would need adapter support
        throw SDKError.validationFailed("VLM component not yet implemented")
    }

    private func createEmbeddingComponent(_ config: UnifiedComponentConfig, container: ServiceContainer) async throws -> Component {
        // For now, Embedding is not implemented
        throw SDKError.validationFailed("Embedding component not yet implemented")
    }

    private func createSpeakerDiarizationComponent(_ config: UnifiedComponentConfig, container: ServiceContainer) async throws -> Component {
        guard let params = config.parameters as? SpeakerDiarizationConfiguration else {
            throw SDKError.validationFailed("Invalid Speaker Diarization parameters")
        }

        return await SpeakerDiarizationComponent(configuration: params)
    }

    // MARK: - Helper Methods

    private func canParallelize(_ component: SDKComponent) -> Bool {
        switch component {
        case .llm, .vlm:
            return false // Heavy memory components
        default:
            return true
        }
    }

    private func parametersMatch(_ p1: any ComponentInitParameters, _ p2: any ComponentInitParameters) -> Bool {
        type(of: p1) == type(of: p2) && p1.modelId == p2.modelId
    }

    // MARK: - Status Methods

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

    public func isReady(_ component: SDKComponent) -> Bool {
        activeComponents[component]?.isReady ?? false
    }

    public func cleanup() async throws {
        for component in activeComponents.values {
            try await component.cleanup()
        }
        activeComponents.removeAll()
    }
}
