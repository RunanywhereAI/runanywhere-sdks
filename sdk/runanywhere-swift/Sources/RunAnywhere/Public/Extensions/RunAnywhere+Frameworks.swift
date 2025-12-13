import Foundation

// MARK: - Frameworks Extensions (Event-Based)

public extension RunAnywhere {

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
}
