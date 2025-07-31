import Foundation

/// Represents the various states in a model's lifecycle
public enum ModelLifecycleState: String, CaseIterable {
    case uninitialized
    case discovered
    case downloading
    case downloaded
    case extracting
    case extracted
    case validating
    case validated
    case initializing
    case initialized
    case loading
    case loaded
    case ready
    case executing
    case error
    case cleanup
}

/// Observer protocol for model lifecycle changes
public protocol ModelLifecycleObserver: AnyObject {
    /// Called when the model transitions to a new state
    func modelDidTransition(from oldState: ModelLifecycleState, to newState: ModelLifecycleState)
    
    /// Called when an error occurs during state transition
    func modelDidEncounterError(_ error: Error, in state: ModelLifecycleState)
}

/// Protocol for managing model lifecycle states
public protocol ModelLifecycleManager {
    /// Current state of the model
    var currentState: ModelLifecycleState { get }
    
    /// Transition to a new state
    /// - Parameter state: The target state
    /// - Throws: If the transition is invalid
    func transitionTo(_ state: ModelLifecycleState) async throws
    
    /// Add an observer for state changes
    /// - Parameter observer: The observer to add
    func addObserver(_ observer: ModelLifecycleObserver)
    
    /// Remove an observer
    /// - Parameter observer: The observer to remove
    func removeObserver(_ observer: ModelLifecycleObserver)
    
    /// Check if a transition is valid
    /// - Parameters:
    ///   - from: Source state
    ///   - to: Target state
    /// - Returns: Whether the transition is valid
    func isValidTransition(from: ModelLifecycleState, to: ModelLifecycleState) -> Bool
}

/// Errors related to model lifecycle
public enum ModelLifecycleError: LocalizedError {
    case invalidTransition(from: ModelLifecycleState, to: ModelLifecycleState)
    case statePrerequisiteNotMet(String)
    case transitionFailed(Error)
    
    public var errorDescription: String? {
        switch self {
        case .invalidTransition(let from, let to):
            return "Invalid transition from \(from.rawValue) to \(to.rawValue)"
        case .statePrerequisiteNotMet(let reason):
            return "State prerequisite not met: \(reason)"
        case .transitionFailed(let error):
            return "Transition failed: \(error.localizedDescription)"
        }
    }
}
