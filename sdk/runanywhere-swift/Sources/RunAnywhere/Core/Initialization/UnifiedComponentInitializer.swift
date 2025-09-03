import Foundation

// MARK: - Unified Component Initializer

/// Unified initializer that works with existing adapters and services
public actor UnifiedComponentInitializer {

    // MARK: - Properties

    private let logger = SDKLogger(category: "UnifiedComponentInitializer")
    private let eventBus = EventBus.shared
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
        var successful: [SDKComponent] = []
        var failed: [(SDKComponent, Error)] = []

        // Sort by priority
        let sortedConfigs = configs.sorted { $0.priority > $1.priority }

        // Emit start event
        eventBus.publish(SDKInitializationEvent.started)

        // Group by parallelization capability
        let parallel = sortedConfigs.filter { canParallelize($0.component) }
        let sequential = sortedConfigs.filter { !canParallelize($0.component) }

        // Initialize parallel components
        if !parallel.isEmpty {
            await withTaskGroup(of: (SDKComponent, Result<Void, Error>).self) { group in
                for config in parallel {
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

        // Emit completion
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
            throw SDKError.notInitialized
        }

        let component: Component

        // Check if component already exists
        if let existing = activeComponents[config.component] {
            // Re-initialize with new parameters if needed
            if !parametersMatch(existing.parameters, config.parameters) {
                try await existing.initialize(with: config.parameters)
            }
            return
        }

        // Create component based on type using existing adapters
        switch config.component {
        case .llm:
            component = try await createLLMComponent(config, container: container)
        case .stt:
            component = try await createSTTComponent(config, container: container)
        case .tts:
            component = try await createTTSComponent(config, container: container)
        case .vad:
            component = try await createVADComponent(config, container: container)
        case .vlm:
            component = try await createVLMComponent(config, container: container)
        case .embedding:
            component = try await createEmbeddingComponent(config, container: container)
        case .speakerDiarization:
            component = try await createSpeakerDiarizationComponent(config, container: container)
        case .wakeWord:
            throw SDKError.componentNotInitialized("Wake word component not yet implemented")
        case .voiceAgent:
            throw SDKError.componentNotInitialized("Voice agent should be created through createVoiceAgent method")
        }

        // Store component
        activeComponents[config.component] = component

        // Initialize component
        try await component.initialize(with: config.parameters)
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
        guard let params = config.parameters as? VLMConfiguration else {
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
