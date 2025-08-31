import Foundation

// MARK: - Frameworks Extensions (Event-Based)

public extension RunAnywhere {

    /// Register a framework adapter with event reporting
    /// - Parameter adapter: The framework adapter to register
    static func registerFrameworkAdapter(_ adapter: UnifiedFrameworkAdapter) {
        // Access service container directly
        RunAnywhere.serviceContainer.adapterRegistry.register(adapter)

        Task {
            events.publish(SDKFrameworkEvent.adapterRegistered(
                framework: adapter.framework,
                name: String(describing: adapter)
            ))
        }
    }

    /// Get registered adapters with event reporting
    /// - Returns: Dictionary of registered adapters
    static func getRegisteredAdapters() -> [LLMFramework: UnifiedFrameworkAdapter] {
        Task {
            events.publish(SDKFrameworkEvent.adaptersRequested)
        }

        let adapters = RunAnywhere.serviceContainer.adapterRegistry.getRegisteredAdapters()

        Task {
            events.publish(SDKFrameworkEvent.adaptersRetrieved(count: adapters.count))
        }

        return adapters
    }

    /// Get available frameworks
    /// - Returns: Array of available frameworks
    static func getAvailableFrameworks() -> [LLMFramework] {
        Task {
            events.publish(SDKFrameworkEvent.frameworksRequested)
        }

        let frameworks = RunAnywhere.serviceContainer.adapterRegistry.getAvailableFrameworks()

        Task {
            events.publish(SDKFrameworkEvent.frameworksRetrieved(frameworks: frameworks))
        }

        return frameworks
    }

    /// Get framework availability information
    /// - Returns: Array of framework availability info
    static func getFrameworkAvailability() -> [FrameworkAvailability] {
        Task {
            events.publish(SDKFrameworkEvent.availabilityRequested)
        }

        let availability = RunAnywhere.serviceContainer.adapterRegistry.getFrameworkAvailability()

        Task {
            events.publish(SDKFrameworkEvent.availabilityRetrieved(availability: availability))
        }

        return availability
    }

    /// Get models for a specific framework
    /// - Parameter framework: The framework to query
    /// - Returns: Array of models for the framework
    static func getModelsForFramework(_ framework: LLMFramework) -> [ModelInfo] {
        Task {
            events.publish(SDKFrameworkEvent.modelsForFrameworkRequested(framework: framework))
        }

        let models = RunAnywhere.serviceContainer.modelRegistry.filterModels(by: ModelCriteria(framework: framework))

        Task {
            events.publish(SDKFrameworkEvent.modelsForFrameworkRetrieved(
                framework: framework,
                models: models
            ))
        }

        return models
    }

    /// Get frameworks for a specific modality
    /// - Parameter modality: The modality to query
    /// - Returns: Array of frameworks supporting the modality
    static func getFrameworks(for modality: FrameworkModality) -> [LLMFramework] {
        Task {
            events.publish(SDKFrameworkEvent.frameworksForModalityRequested(modality: modality))
        }

        let frameworks = RunAnywhere.serviceContainer.adapterRegistry.getFrameworks(for: modality)

        Task {
            events.publish(SDKFrameworkEvent.frameworksForModalityRetrieved(
                modality: modality,
                frameworks: frameworks
            ))
        }

        return frameworks
    }

    /// Get primary modality for a framework
    /// - Parameter framework: The framework to query
    /// - Returns: Primary modality of the framework
    static func getPrimaryModality(for framework: LLMFramework) -> FrameworkModality? {
        guard let adapter = RunAnywhere.serviceContainer.adapterRegistry.getAdapter(for: framework) else {
            return nil
        }
        return adapter.supportedModalities.first
    }

    /// Check if framework supports a specific modality
    /// - Parameters:
    ///   - framework: The framework to check
    ///   - modality: The modality to check
    /// - Returns: True if framework supports the modality
    static func frameworkSupports(_ framework: LLMFramework, modality: FrameworkModality) -> Bool {
        guard let adapter = RunAnywhere.serviceContainer.adapterRegistry.getAdapter(for: framework) else {
            return false
        }
        return adapter.supportedModalities.contains(modality)
    }
}
