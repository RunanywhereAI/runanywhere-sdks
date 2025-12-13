import Foundation

/// Simplified base component for all SDK components
/// Using @unchecked Sendable as we manage thread safety with @MainActor
@MainActor
open class BaseComponent<TService: AnyObject>: Component, @unchecked Sendable { // swiftlint:disable:this avoid_any_object
    // MARK: - Core Properties

    /// Component type identifier - must be overridden in subclass
    nonisolated open class var componentType: SDKComponent {
        fatalError("Override componentType in subclass")
    }

    /// Current state (protected by MainActor)
    nonisolated(unsafe) public private(set) var state: ComponentState = .notInitialized

    /// The service that performs the actual work
    public private(set) var service: TService?

    /// Configuration (immutable and Sendable)
    public let configuration: any ComponentConfiguration

    /// Parameters for Component protocol (bridge to configuration)
    nonisolated public var parameters: any ComponentInitParameters {
        configuration as? any ComponentInitParameters ?? EmptyComponentParameters()
    }

    /// Service container for dependency injection
    public weak var serviceContainer: ServiceContainer?

    /// Event bus for publishing events
    public var eventBus: EventBus {
        serviceContainer?.eventBus ?? ServiceContainer.shared.eventBus
    }

    /// Current processing stage
    public private(set) var currentStage: String?

    // MARK: - Initialization

    public init(configuration: any ComponentConfiguration, serviceContainer: ServiceContainer? = nil) {
        self.configuration = configuration
        self.serviceContainer = serviceContainer ?? ServiceContainer.shared
    }

    // MARK: - Lifecycle

    public func initialize(with parameters: any ComponentInitParameters) async throws {
        try await initialize()
    }

    public func initialize() async throws {
        guard state == .notInitialized else {
            if state == .ready { return }
            throw RunAnywhereError.invalidState("Cannot initialize from state: \(state)")
        }

        updateState(.initializing)

        do {
            currentStage = "validation"
            eventBus.publish(ComponentInitializationEvent.componentChecking(
                component: Self.componentType,
                modelId: nil
            ))
            try configuration.validate()

            currentStage = "service_creation"
            eventBus.publish(ComponentInitializationEvent.componentInitializing(
                component: Self.componentType,
                modelId: nil
            ))
            service = try await createService()

            currentStage = "service_initialization"
            try await initializeService()

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

    /// Create the service - must be overridden in subclass
    open func createService() async throws -> TService {
        fatalError("Override createService() in subclass")
    }

    /// Initialize the service - override if needed
    open func initializeService() async throws {}

    public func cleanup() async throws {
        guard state != .notInitialized else { return }

        state = .notInitialized
        try await performCleanup()
        service = nil
        state = .notInitialized
    }

    /// Perform cleanup - override in subclass if needed
    open func performCleanup() async throws {}

    // MARK: - State Management

    nonisolated public var isReady: Bool {
        state == .ready
    }

    public func ensureReady() throws {
        guard state == .ready else {
            throw RunAnywhereError.componentNotReady("\(Self.componentType) is not ready. Current state: \(state)")
        }
    }

    private func updateState(_ newState: ComponentState) {
        let oldState = state
        state = newState
        eventBus.publish(ComponentInitializationEvent.componentStateChanged(
            component: Self.componentType,
            oldState: oldState,
            newState: newState
        ))
    }

    public func transitionTo(state: ComponentState) async {
        updateState(state)
    }
}
