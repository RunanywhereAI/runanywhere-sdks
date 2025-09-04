import Foundation

// MARK: - Base Protocols

/// Base protocol for component inputs
public protocol ComponentInput: Sendable {
    func validate() throws
}

/// Base protocol for component outputs
public protocol ComponentOutput: Sendable {
    var timestamp: Date { get }
}

/// Base protocol for component configurations
public protocol ComponentConfiguration: Sendable {
    func validate() throws
}

/// Base protocol for component adapters
public protocol ComponentAdapter {
    associatedtype ServiceType: AnyObject
    func createService(configuration: any ComponentConfiguration) async throws -> ServiceType
}

// MARK: - Simplified Base Component

/// Service wrapper protocol that allows protocol types to be used with BaseComponent
public protocol ServiceWrapper: AnyObject {
    associatedtype ServiceProtocol
    var wrappedService: ServiceProtocol? { get set }
}

/// Generic service wrapper for any protocol
public final class AnyServiceWrapper<T>: ServiceWrapper {
    public var wrappedService: T?

    public init(_ service: T? = nil) {
        self.wrappedService = service
    }
}

/// Simplified base component for all SDK components
/// Using @unchecked Sendable as we manage thread safety with @MainActor
@MainActor
open class BaseComponent<TService: AnyObject>: Component, @unchecked Sendable {

    // MARK: - Core Properties

    /// Component type identifier
    nonisolated open class var componentType: SDKComponent {
        fatalError("Override componentType in subclass")
    }

    /// Current state (protected by MainActor) - required by Component protocol
    nonisolated(unsafe) public private(set) var state: ComponentState = .notInitialized

    /// The service that performs the actual work (protected by MainActor)
    public private(set) var service: TService?

    /// Configuration (immutable and Sendable)
    public let configuration: any ComponentConfiguration

    /// Parameters for Component protocol (bridge to configuration)
    nonisolated public var parameters: any ComponentInitParameters {
        // Bridge configuration to parameters if it conforms
        configuration as? any ComponentInitParameters ?? EmptyComponentParameters()
    }

    /// Service container for dependency injection
    public weak var serviceContainer: ServiceContainer?

    /// Event bus for publishing events
    public let eventBus = EventBus.shared

    /// Current processing stage
    public private(set) var currentStage: String?

    // MARK: - Initialization

    public init(configuration: any ComponentConfiguration, serviceContainer: ServiceContainer? = nil) {
        self.configuration = configuration
        self.serviceContainer = serviceContainer ?? ServiceContainer.shared
    }

    // MARK: - Lifecycle

    /// Initialize the component (Component protocol)
    public func initialize(with parameters: any ComponentInitParameters) async throws {
        // For now, ignore the parameters since we already have configuration
        try await initialize()
    }

    /// Initialize the component
    public func initialize() async throws {
        guard state == .notInitialized else {
            if state == .ready {
                return // Already initialized
            }
            throw SDKError.invalidState("Cannot initialize from state: \(state)")
        }

        // Emit state change event
        updateState(.initializing)

        do {
            // Stage: Validation
            currentStage = "validation"
            eventBus.publish(ComponentInitializationEvent.componentChecking(
                component: Self.componentType,
                modelId: nil
            ))
            try configuration.validate()

            // Stage: Service Creation
            currentStage = "service_creation"
            eventBus.publish(ComponentInitializationEvent.componentInitializing(
                component: Self.componentType,
                modelId: nil
            ))
            service = try await createService()

            // Stage: Service Initialization
            currentStage = "service_initialization"
            try await initializeService()

            // Component ready
            currentStage = nil
            updateState(.ready)
            eventBus.publish(ComponentInitializationEvent.componentReady(
                component: Self.componentType,
                modelId: nil
            ))
        } catch {
            updateState(.failed)
            eventBus.publish(ComponentInitializationEvent.componentFailed(
                component: Self.componentType,
                error: error
            ))
            throw error
        }
    }

    /// Create the service (override in subclass)
    open func createService() async throws -> TService {
        fatalError("Override createService() in subclass")
    }

    /// Initialize the service (override if needed)
    open func initializeService() async throws {
        // Default: no-op
        // Override in subclass if service needs initialization
    }

    /// Cleanup
    public func cleanup() async throws {
        guard state != .notInitialized else { return }

        state = .notInitialized

        // Allow subclass to perform cleanup
        try await performCleanup()

        // Clear service reference
        service = nil

        state = .notInitialized
    }

    /// Perform cleanup (override in subclass if needed)
    open func performCleanup() async throws {
        // Default: no-op
        // Override in subclass for custom cleanup
    }

    // MARK: - State Management

    /// Check if component is ready
    nonisolated public var isReady: Bool {
        state == .ready
    }

    /// Ensure component is ready for processing
    public func ensureReady() throws {
        guard state == .ready else {
            throw SDKError.componentNotReady("\(Self.componentType) is not ready. Current state: \(state)")
        }
    }

    /// Update state and emit event
    private func updateState(_ newState: ComponentState) {
        let oldState = state
        state = newState
        eventBus.publish(ComponentInitializationEvent.componentStateChanged(
            component: Self.componentType,
            oldState: oldState,
            newState: newState
        ))
    }

    // MARK: - Component Protocol Requirements

    /// State transition handler
    public func transitionTo(state: ComponentState) async {
        updateState(state)
    }
}

// MARK: - SDK Error Extension

extension SDKError {
    /// Component is not ready for the requested operation
    public static func componentNotReady(_ message: String) -> SDKError {
        SDKError.componentNotInitialized(message)
    }
}

// MARK: - Empty Component Parameters

/// Empty parameters for components that don't need configuration
private struct EmptyComponentParameters: ComponentInitParameters {
    var componentType: SDKComponent { .vad } // Default, not used
    var modelId: String? { nil }
    func validate() throws {}
}
