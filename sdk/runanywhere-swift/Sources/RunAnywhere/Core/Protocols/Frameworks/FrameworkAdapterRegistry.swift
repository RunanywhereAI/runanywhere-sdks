import Foundation

/// Protocol for framework adapter registry (to be implemented by app)
public protocol FrameworkAdapterRegistry {
    /// Get adapter for a specific framework
    func getAdapter(for framework: LLMFramework) -> FrameworkAdapter?

    /// Find best adapter for a model
    func findBestAdapter(for model: ModelInfo) -> FrameworkAdapter?

    /// Register an adapter
    func register(_ adapter: FrameworkAdapter)
}
