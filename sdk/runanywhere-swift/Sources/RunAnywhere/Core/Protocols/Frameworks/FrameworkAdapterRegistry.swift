import Foundation

/// Protocol for framework adapter registry (to be implemented by app)
public protocol FrameworkAdapterRegistry {
    /// Get adapter for a specific framework
    func getAdapter(for framework: LLMFramework) -> FrameworkAdapter?

    /// Find best adapter for a model
    func findBestAdapter(for model: ModelInfo) -> FrameworkAdapter?

    /// Register an adapter
    func register(_ adapter: FrameworkAdapter)

    /// Get all registered adapters
    func getRegisteredAdapters() -> [LLMFramework: FrameworkAdapter]

    /// Get available frameworks (those with registered adapters)
    func getAvailableFrameworks() -> [LLMFramework]

    /// Get detailed framework availability information
    func getFrameworkAvailability() -> [FrameworkAvailability]
}
