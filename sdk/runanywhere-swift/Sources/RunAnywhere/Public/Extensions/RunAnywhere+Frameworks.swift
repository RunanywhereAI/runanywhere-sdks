import Foundation

// MARK: - Frameworks Extensions

public extension RunAnywhere {

    /// Get models for a specific framework
    /// - Parameter framework: The framework to query
    /// - Returns: Array of models for the framework
    static func getModelsForFramework(_ framework: InferenceFramework) -> [ModelInfo] {
        EventPublisher.shared.track(FrameworkEvent.modelsRequested(framework: framework.rawValue))

        let models = RunAnywhere.serviceContainer.modelRegistry.filterModels(by: ModelCriteria(framework: framework))

        EventPublisher.shared.track(FrameworkEvent.modelsRetrieved(
            framework: framework.rawValue,
            count: models.count
        ))

        return models
    }
}
