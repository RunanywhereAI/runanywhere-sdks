import Foundation
import Combine

// MARK: - Base Component Implementation

/// Base implementation for SDK components providing common functionality
/// Using @unchecked Sendable as we manage thread safety internally
@MainActor
open class BaseComponent: Component, @unchecked Sendable {

    // MARK: - Properties

    /// Component type (must be overridden by subclasses)
    open class var componentType: SDKComponent {
        fatalError("Subclasses must override componentType")
    }

    /// Current state of the component
    public private(set) var state: ComponentState = .notInitialized

    /// Configuration parameters
    public private(set) var parameters: any ComponentInitParameters

    /// Logger for this component
    public let logger: SDKLogger

    /// Service container reference
    public weak var serviceContainer: ServiceContainer?

    /// Event bus for global events
    public let eventBus = EventBus.shared

    // MARK: - Initialization

    public required init(parameters: any ComponentInitParameters, serviceContainer: ServiceContainer? = nil) {
        self.parameters = parameters
        self.serviceContainer = serviceContainer ?? ServiceContainer.shared
        self.logger = SDKLogger(category: String(describing: type(of: self)))
    }

    // MARK: - Component Protocol

    /// Initialize the component (must be overridden)
    open func initialize(with parameters: any ComponentInitParameters) async throws {
        // Update parameters
        self.parameters = parameters

        // Validate parameters
        try parameters.validate()

        // Transition to checking state
        await transitionTo(state: .checking)

        // Subclasses should override and call super
        logger.debug("Initializing component: \(type(of: self).componentType.rawValue)")
    }

    /// Clean up resources (override in subclasses)
    open func cleanup() async throws {
        await transitionTo(state: .notInitialized)
        logger.debug("Cleaned up component: \(type(of: self).componentType.rawValue)")
    }

    /// Handle state transitions
    public func transitionTo(state: ComponentState) async {
        let oldState = self.state
        self.state = state

        // Publish to global event bus
        eventBus.publish(ComponentInitializationEvent.componentStateChanged(
            component: type(of: self).componentType,
            oldState: oldState,
            newState: state
        ))

        logger.debug("State transition: \(oldState.rawValue) → \(state.rawValue)")
    }

    // MARK: - Helper Methods

    /// Report progress
    public func reportProgress(_ progress: Double) {
        // Emit to global event bus if downloading
        if state == .downloading,
           let modelId = (parameters as? any ModelRequiring)?.modelId {
            eventBus.publish(ComponentInitializationEvent.componentDownloadProgress(
                component: type(of: self).componentType,
                modelId: modelId,
                progress: progress
            ))
        }
    }

    /// Report error
    public func reportError(_ error: Error) {
        eventBus.publish(ComponentInitializationEvent.componentFailed(
            component: type(of: self).componentType,
            error: error
        ))
        logger.error("Component error: \(error.localizedDescription)")
    }

    /// Report warning
    public func reportWarning(_ message: String) {
        logger.warning(message)
    }

    /// Report info
    public func reportInfo(_ message: String) {
        logger.info(message)
    }
}

// MARK: - Helper Protocol

/// Protocol for components that require a model
protocol ModelRequiring {
    var modelId: String? { get }
}
