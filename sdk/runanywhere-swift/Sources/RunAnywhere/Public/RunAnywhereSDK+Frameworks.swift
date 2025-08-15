import Foundation

// MARK: - Framework Management APIs

extension RunAnywhereSDK {

    /// Register a framework adapter (supports both text and voice)
    /// - Parameter adapter: The framework adapter to register
    public func registerFrameworkAdapter(_ adapter: UnifiedFrameworkAdapter) {
        serviceContainer.adapterRegistry.register(adapter)
    }

    /// Get the list of registered framework adapters
    /// - Returns: Dictionary of registered adapters by framework
    public func getRegisteredAdapters() -> [LLMFramework: UnifiedFrameworkAdapter] {
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

    /// Get frameworks that support a specific modality
    /// - Parameter modality: The modality to filter by
    /// - Returns: Array of frameworks that support the modality
    public func getFrameworks(for modality: FrameworkModality) -> [LLMFramework] {
        return serviceContainer.adapterRegistry.getFrameworks(for: modality)
    }

    /// Get the primary modality for a framework
    /// - Parameter framework: The framework to check
    /// - Returns: The primary modality of the framework
    public func getPrimaryModality(for framework: LLMFramework) -> FrameworkModality {
        return framework.primaryModality
    }

    /// Check if a framework supports a specific modality
    /// - Parameters:
    ///   - framework: The framework to check
    ///   - modality: The modality to check for
    /// - Returns: Whether the framework supports the modality
    public func frameworkSupports(_ framework: LLMFramework, modality: FrameworkModality) -> Bool {
        return framework.supportedModalities.contains(modality)
    }
}
