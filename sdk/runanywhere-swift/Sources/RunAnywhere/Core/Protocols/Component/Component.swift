import Foundation

// MARK: - Core Component Protocol

/// Base protocol that all SDK components must implement
public protocol Component: AnyObject, Sendable {
    /// Unique identifier for this component type
    static var componentType: SDKComponent { get }

    /// Current state of the component
    var state: ComponentState { get }

    /// Configuration parameters for this component
    var parameters: any ComponentInitParameters { get }

    /// Initialize the component with given parameters
    /// - Parameter parameters: Component-specific initialization parameters
    /// - Throws: If initialization fails
    func initialize(with parameters: any ComponentInitParameters) async throws

    /// Clean up and release resources
    func cleanup() async throws

    /// Check if component is ready for use
    var isReady: Bool { get }

    /// Get current health status
    func healthCheck() async -> ComponentHealth

    /// Handle state transitions
    func transitionTo(state: ComponentState) async
}

// MARK: - Component Health

/// Health status for a component
public struct ComponentHealth: Sendable {
    public let isHealthy: Bool
    public let details: String?
    public let metrics: [String: Any]?

    public init(isHealthy: Bool, details: String? = nil, metrics: [String: Any]? = nil) {
        self.isHealthy = isHealthy
        self.details = details
        self.metrics = metrics
    }
}

// MARK: - Lifecycle Management Protocol

/// Protocol for components that need lifecycle management
public protocol LifecycleManaged: Component {
    /// Called before initialization
    func willInitialize() async throws

    /// Called after successful initialization
    func didInitialize() async

    /// Called before cleanup
    func willCleanup() async

    /// Called after cleanup
    func didCleanup() async

    /// Handle memory pressure
    func handleMemoryPressure() async
}

// MARK: - Model-Based Component

/// Protocol for components that require model loading
public protocol ModelBasedComponent: Component {
    /// Model identifier
    var modelId: String? { get }

    /// Check if model is loaded
    var isModelLoaded: Bool { get }

    /// Load the model
    func loadModel(modelId: String) async throws

    /// Unload the model
    func unloadModel() async throws

    /// Get model memory usage
    func getModelMemoryUsage() async -> Int64
}

// MARK: - Service Component

/// Protocol for components that provide services
public protocol ServiceComponent: Component {
    associatedtype ServiceType

    /// Get the underlying service instance
    func getService() -> ServiceType?

    /// Create service instance
    func createService() async throws -> ServiceType
}

// MARK: - Pipeline Component

/// Protocol for components that can be part of a pipeline
public protocol PipelineComponent: Component {
    /// Process input and return output
    associatedtype Input
    associatedtype Output

    func process(_ input: Input) async throws -> Output

    /// Check if this component can connect to another
    func canConnectTo(_ component: any Component) -> Bool
}

// MARK: - Component Initialization Result

/// Result of component initialization for observability
public struct ComponentInitResult: Sendable {
    public let component: SDKComponent
    public var success: Bool
    public let duration: TimeInterval
    public let adapter: String?
    public var error: String?
    public var metadata: [String: String]

    public init(
        component: SDKComponent,
        success: Bool,
        duration: TimeInterval,
        adapter: String? = nil,
        error: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.component = component
        self.success = success
        self.duration = duration
        self.adapter = adapter
        self.error = error
        self.metadata = metadata
    }
}

// MARK: - Default Implementations

extension Component {
    /// Default health check implementation
    public func healthCheck() async -> ComponentHealth {
        ComponentHealth(isHealthy: isReady, details: "Component state: \(state.rawValue)")
    }

    /// Default isReady implementation based on state
    public var isReady: Bool {
        state == .ready
    }
}

extension LifecycleManaged {
    /// Default empty implementations for lifecycle methods
    public func willInitialize() async throws {}
    public func didInitialize() async {}
    public func willCleanup() async {}
    public func didCleanup() async {}
    public func handleMemoryPressure() async {}
}

extension ModelBasedComponent {
    /// Default model memory usage
    public func getModelMemoryUsage() async -> Int64 {
        0 // Override in implementations
    }
}

extension PipelineComponent {
    /// Default connection check
    public func canConnectTo(_ component: any Component) -> Bool {
        true // Override for specific compatibility checks
    }
}
