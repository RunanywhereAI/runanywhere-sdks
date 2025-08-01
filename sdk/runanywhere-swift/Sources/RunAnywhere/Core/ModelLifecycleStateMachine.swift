import Foundation

/// Implementation of the model lifecycle state machine
public class ModelLifecycleStateMachine: ModelLifecycleManager {
    // MARK: - Properties

    private var state: ModelLifecycleState = .uninitialized
    private let stateLock: NSLock = NSLock()
    private var observers: [UUID: WeakObserver] = [:]
    private let observerLock: NSLock = NSLock()

    /// Valid state transitions
    private let validTransitions: [ModelLifecycleState: Set<ModelLifecycleState>] = [
        .uninitialized: [.discovered],
        .discovered: [.downloading, .validated], // Skip download if already local
        .downloading: [.downloaded, .error],
        .downloaded: [.extracting, .validating], // Skip extraction if not archive
        .extracting: [.extracted, .error],
        .extracted: [.validating],
        .validating: [.validated, .error],
        .validated: [.initializing],
        .initializing: [.initialized, .error],
        .initialized: [.loading],
        .loading: [.loaded, .error],
        .loaded: [.ready, .error],
        .ready: [.executing, .cleanup],
        .executing: [.ready, .error],
        .error: [.cleanup, .discovered], // Allow retry from discovered
        .cleanup: [.uninitialized]
    ]

    // MARK: - Initialization

    public init() {}

    // MARK: - ModelLifecycleManager Protocol

    public var currentState: ModelLifecycleState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return state
    }

    public func transitionTo(_ newState: ModelLifecycleState) async throws {
        stateLock.lock()
        let oldState = state

        guard isValidTransition(from: oldState, to: newState) else {
            stateLock.unlock()
            throw ModelLifecycleError.invalidTransition(from: oldState, to: newState)
        }

        state = newState
        stateLock.unlock()

        // Notify observers asynchronously
        await notifyObservers(oldState: oldState, newState: newState)
    }

    public func addObserver(_ observer: ModelLifecycleObserver) {
        observerLock.lock()
        defer { observerLock.unlock() }

        let id = UUID()
        observers[id] = WeakObserver(observer: observer)
    }

    public func removeObserver(_ observer: ModelLifecycleObserver) {
        observerLock.lock()
        defer { observerLock.unlock() }

        observers = observers.filter { $0.value.observer !== observer }
    }

    public func isValidTransition(from: ModelLifecycleState, to: ModelLifecycleState) -> Bool {
        validTransitions[from]?.contains(to) ?? false
    }

    // MARK: - Helper Methods

    private func notifyObservers(oldState: ModelLifecycleState, newState: ModelLifecycleState) async {
        observerLock.lock()
        let activeObservers = observers.compactMap { $0.value.observer }
        observerLock.unlock()

        for observer in activeObservers {
            observer.modelDidTransition(from: oldState, to: newState)
        }
    }

    /// Notify observers of an error
    public func notifyError(_ error: Error) {
        observerLock.lock()
        let activeObservers = observers.compactMap { $0.value.observer }
        let currentState = self.state
        observerLock.unlock()

        for observer in activeObservers {
            observer.modelDidEncounterError(error, in: currentState)
        }
    }

    /// Reset to initial state
    public func reset() async throws {
        try await transitionTo(.cleanup)
        try await transitionTo(.uninitialized)
    }

    /// Get allowed transitions from current state
    public func getAllowedTransitions() -> Set<ModelLifecycleState> {
        stateLock.lock()
        defer { stateLock.unlock() }
        return validTransitions[state] ?? []
    }

    /// Check if in error state
    public var isInErrorState: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return state == .error
    }

    /// Check if ready for execution
    public var isReady: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return state == .ready
    }
}

// MARK: - Supporting Types

/// Weak observer wrapper to prevent retain cycles
private class WeakObserver {
    weak var observer: ModelLifecycleObserver?

    init(observer: ModelLifecycleObserver) {
        self.observer = observer
    }
}

// MARK: - State Machine Extensions

public extension ModelLifecycleStateMachine {
    /// Convenience method to handle common state progressions
    func progressToNextState() async throws {
        let currentState = self.currentState

        let nextState: ModelLifecycleState? = {
            switch currentState {
            case .uninitialized:
                return .discovered
            case .discovered:
                return .downloading
            case .downloading:
                return .downloaded
            case .downloaded:
                return .extracting
            case .extracting:
                return .extracted
            case .extracted:
                return .validating
            case .validating:
                return .validated
            case .validated:
                return .initializing
            case .initializing:
                return .initialized
            case .initialized:
                return .loading
            case .loading:
                return .loaded
            case .loaded:
                return .ready
            case .ready, .executing, .error, .cleanup:
                return nil
            }
        }()

        if let nextState = nextState {
            try await transitionTo(nextState)
        }
    }

    /// Handle error state with automatic transition
    func handleError(_ error: Error) async throws {
        try await transitionTo(.error)
        notifyError(error)
    }

    /// Check if model needs download
    var needsDownload: Bool {
        currentState == .discovered
    }

    /// Check if model needs extraction
    var needsExtraction: Bool {
        currentState == .downloaded
    }

    /// Check if model needs validation
    var needsValidation: Bool {
        currentState == .extracted || currentState == .downloaded
    }
}

// MARK: - Debugging Support

extension ModelLifecycleStateMachine: CustomStringConvertible {
    public var description: String {
        "ModelLifecycleStateMachine(state: \(currentState.rawValue))"
    }
}

// MARK: - State Descriptions

public extension ModelLifecycleState {
    /// Human-readable description of the state
    var description: String {
        switch self {
        case .uninitialized:
            return "Model not initialized"
        case .discovered:
            return "Model discovered"
        case .downloading:
            return "Downloading model"
        case .downloaded:
            return "Model downloaded"
        case .extracting:
            return "Extracting model files"
        case .extracted:
            return "Model extracted"
        case .validating:
            return "Validating model"
        case .validated:
            return "Model validated"
        case .initializing:
            return "Initializing model"
        case .initialized:
            return "Model initialized"
        case .loading:
            return "Loading model"
        case .loaded:
            return "Model loaded"
        case .ready:
            return "Model ready for use"
        case .executing:
            return "Model executing"
        case .error:
            return "Error state"
        case .cleanup:
            return "Cleaning up"
        }
    }

    /// Whether this is a terminal state
    var isTerminal: Bool {
        switch self {
        case .ready, .error, .uninitialized:
            return true
        default:
            return false
        }
    }

    /// Whether this state represents active processing
    var isProcessing: Bool {
        switch self {
        case .downloading, .extracting, .validating, .initializing, .loading, .executing:
            return true
        default:
            return false
        }
    }
}
