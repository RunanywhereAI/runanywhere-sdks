import Foundation

// MARK: - Framework Management APIs

extension RunAnywhereSDK {

    /// Register a framework adapter
    /// - Parameter adapter: The framework adapter to register
    public func registerFrameworkAdapter(_ adapter: FrameworkAdapter) {
        serviceContainer.adapterRegistry.register(adapter)
    }

    /// Get the list of registered framework adapters
    /// - Returns: Dictionary of registered adapters by framework
    public func getRegisteredAdapters() -> [LLMFramework: FrameworkAdapter] {
        return serviceContainer.adapterRegistry.getRegisteredAdapters()
    }

    /// Get available frameworks on this device (based on registered adapters)
    /// - Returns: Array of frameworks that have registered adapters
    public func getAvailableFrameworks() -> [LLMFramework] {
        return serviceContainer.adapterRegistry.getAvailableFrameworks()
    }

    /// Get detailed framework availability information
    /// - Returns: Array of framework availability details
    public func getFrameworkAvailability() -> [FrameworkAvailability] {
        return serviceContainer.adapterRegistry.getFrameworkAvailability()
    }

    /// Get models for a specific framework
    /// - Parameter framework: The framework to filter models for
    /// - Returns: Array of models compatible with the framework
    public func getModelsForFramework(_ framework: LLMFramework) -> [ModelInfo] {
        let criteria = ModelCriteria(framework: framework)
        return serviceContainer.modelRegistry.filterModels(by: criteria)
    }
}
