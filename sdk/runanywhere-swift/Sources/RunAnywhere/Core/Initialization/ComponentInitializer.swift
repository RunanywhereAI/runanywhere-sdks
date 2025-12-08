import Combine
import Foundation

/// Manages component initialization - delegates to UnifiedComponentInitializer
/// Kept for backward compatibility with existing API
public actor ComponentInitializer {
    private let logger = SDKLogger(category: "ComponentInitializer")
    private let unifiedInitializer: UnifiedComponentInitializer

    // Services
    private weak var serviceContainer: ServiceContainer?

    public init(serviceContainer: ServiceContainer? = nil) {
        self.serviceContainer = serviceContainer ?? ServiceContainer.shared
        self.unifiedInitializer = UnifiedComponentInitializer(serviceContainer: serviceContainer)
    }

    // MARK: - Public API (Delegates to UnifiedComponentInitializer)

    /// Initialize components with unified configurations
    public func initialize(_ configs: [UnifiedComponentConfig]) async -> InitializationResult {
        await unifiedInitializer.initialize(configs)
    }

    /// Get all component statuses
    public func getAllStatuses() async -> [ComponentStatus] {
        await unifiedInitializer.getAllStatuses()
    }

    /// Get status of a specific component
    public func getStatus(for component: SDKComponent) async -> ComponentStatus {
        await unifiedInitializer.getStatus(for: component)
    }

    /// Check if a component is ready
    public func isReady(_ component: SDKComponent) async -> Bool {
        await unifiedInitializer.isReady(component)
    }

    /// Check if all components in list are ready
    public func areReady(_ components: [SDKComponent]) async -> Bool {
        for component in components where !(await unifiedInitializer.isReady(component)) {
            return false
        }
        return true
    }

    /// Get all component statuses with parameters
    public func getAllStatusesWithParameters() async -> [(status: ComponentStatus, parameters: (any ComponentInitParameters)?)] {
        // For now, return statuses without parameters
        // This can be enhanced if needed
        let statuses = await unifiedInitializer.getAllStatuses()
        return statuses.map { ($0, nil) }
    }

    /// Get initialization parameters for a component
    public func getParameters(for component: SDKComponent) -> (any ComponentInitParameters)? {
        // This would need to be implemented in UnifiedComponentInitializer if needed
        nil
    }
}
