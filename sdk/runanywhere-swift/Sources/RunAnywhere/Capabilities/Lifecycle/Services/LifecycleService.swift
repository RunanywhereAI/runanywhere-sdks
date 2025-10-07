import Foundation

/// Central lifecycle management service that coordinates all lifecycle operations
class LifecycleService {
    private let stateManager: StateManager
    private let transitionHandler: TransitionHandler
    private let observerRegistry: ObserverRegistry
    private let logger = SDKLogger(category: "LifecycleService")

    init(
        stateManager: StateManager = StateManager(),
        transitionHandler: TransitionHandler = TransitionHandler(),
        observerRegistry: ObserverRegistry = ObserverRegistry()
    ) {
        self.stateManager = stateManager
        self.transitionHandler = transitionHandler
        self.observerRegistry = observerRegistry

        setupIntegration()
    }

    // MARK: - State Management

    func getCurrentState() -> ModelLifecycleState {
        return stateManager.getCurrentState()
    }

    func transitionTo(_ newState: ModelLifecycleState) async throws {
        let oldState = stateManager.getCurrentState()

        // Validate transition
        guard transitionHandler.isValidTransition(from: oldState, to: newState) else {
            throw ModelLifecycleError.invalidTransition(from: oldState, to: newState)
        }

        logger.info("Transitioning from \(oldState) to \(newState)")

        // Execute transition
        try await transitionHandler.executeTransition(from: oldState, to: newState)

        // Update state
        stateManager.setState(newState)

        // Notify observers
        await observerRegistry.notifyStateChange(from: oldState, to: newState)

        logger.info("Successfully transitioned to \(newState)")
    }

    func getAllowedTransitions() -> Set<ModelLifecycleState> {
        let currentState = stateManager.getCurrentState()
        return transitionHandler.getAllowedTransitions(from: currentState)
    }

    // MARK: - Observer Management

    func addObserver(_ observer: ModelLifecycleObserver) {
        observerRegistry.addObserver(observer)
        logger.debug("Added lifecycle observer")
    }

    func removeObserver(_ observer: ModelLifecycleObserver) {
        observerRegistry.removeObserver(observer)
        logger.debug("Removed lifecycle observer")
    }

    // MARK: - Lifecycle Operations

    func progressToNextState() async throws {
        let currentState = stateManager.getCurrentState()
        let nextState = determineNextState(from: currentState)

        if let nextState = nextState {
            try await transitionTo(nextState)
        } else {
            logger.debug("No automatic progression available from state: \(currentState)")
        }
    }

    func handleError(_ error: Error) async throws {
        let currentState = stateManager.getCurrentState()

        logger.error("Handling error in state \(currentState): \(error)")

        // Transition to error state
        try await transitionTo(.error)

        // Notify observers of the error
        await observerRegistry.notifyError(error, in: currentState)
    }

    func reset() async throws {
        logger.info("Resetting lifecycle state machine")

        // Cleanup current state
        if stateManager.getCurrentState() != .uninitialized {
            try await transitionTo(.cleanup)
            try await transitionTo(.uninitialized)
        }

        logger.info("Lifecycle reset complete")
    }

    // MARK: - State Queries

    func isInState(_ state: ModelLifecycleState) -> Bool {
        return stateManager.getCurrentState() == state
    }

    func isInErrorState() -> Bool {
        return stateManager.getCurrentState() == .error
    }

    func isReady() -> Bool {
        return stateManager.getCurrentState() == .ready
    }

    func isProcessing() -> Bool {
        return stateManager.getCurrentState().isProcessing
    }

    func needsDownload() -> Bool {
        return stateManager.getCurrentState() == .discovered
    }

    func needsExtraction() -> Bool {
        return stateManager.getCurrentState() == .downloaded
    }

    func needsValidation() -> Bool {
        let state = stateManager.getCurrentState()
        return state == .extracted || state == .downloaded
    }

    // MARK: - Advanced Operations

    func executeStatefulOperation<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        let originalState = stateManager.getCurrentState()

        guard originalState == .ready else {
            throw ModelLifecycleError.invalidState("Operation requires ready state, current: \(originalState)")
        }

        // Transition to executing
        try await transitionTo(.executing)

        do {
            let result = try await operation()

            // Transition back to ready
            try await transitionTo(.ready)

            return result
        } catch {
            // Handle error and rethrow
            try await handleError(error)
            throw error
        }
    }

    func skipToState(_ targetState: ModelLifecycleState) async throws {
        let currentState = stateManager.getCurrentState()
        let path = findShortestPath(from: currentState, to: targetState)

        guard !path.isEmpty else {
            throw ModelLifecycleError.invalidTransition(from: currentState, to: targetState)
        }

        logger.info("Skipping to state \(targetState) via path: \(path.map { $0.rawValue }.joined(separator: " -> "))")

        for state in path {
            try await transitionTo(state)
        }
    }

    // MARK: - Statistics and Monitoring

    func getLifecycleStatistics() -> LifecycleStatistics {
        let stateStats = stateManager.getStatistics()
        let transitionStats = transitionHandler.getStatistics()
        let observerStats = observerRegistry.getStatistics()

        return LifecycleStatistics(
            currentState: stateStats.currentState,
            totalTransitions: transitionStats.totalTransitions,
            errorCount: transitionStats.errorCount,
            averageTransitionTime: transitionStats.averageTransitionTime,
            observerCount: observerStats.activeObservers,
            stateHistory: stateStats.stateHistory,
            lastError: transitionStats.lastError
        )
    }

    func validateStateMachine() -> LifecycleValidationResult {
        let issues = transitionHandler.validateTransitionTable()
        let orphanedStates = findOrphanedStates()
        let unreachableStates = findUnreachableStates()

        let isValid = issues.isEmpty && orphanedStates.isEmpty && unreachableStates.isEmpty

        return LifecycleValidationResult(
            isValid: isValid,
            issues: issues,
            orphanedStates: orphanedStates,
            unreachableStates: unreachableStates
        )
    }

    // MARK: - Private Implementation

    private func setupIntegration() {
        // Connect transition handler with state manager for validation
        transitionHandler.setStateProvider(stateManager)

        // Set up error handling callback
        transitionHandler.setErrorHandler { [weak self] error in
            Task {
                try? await self?.handleError(error)
            }
        }
    }

    private func determineNextState(from currentState: ModelLifecycleState) -> ModelLifecycleState? {
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
    }

    private func findShortestPath(from start: ModelLifecycleState, to target: ModelLifecycleState) -> [ModelLifecycleState] {
        guard start != target else { return [] }

        var queue: [[ModelLifecycleState]] = [[start]]
        var visited: Set<ModelLifecycleState> = [start]

        while !queue.isEmpty {
            let path = queue.removeFirst()
            let currentState = path.last!

            let allowedTransitions = transitionHandler.getAllowedTransitions(from: currentState)

            for nextState in allowedTransitions {
                if nextState == target {
                    return Array(path.dropFirst()) + [nextState]
                }

                if !visited.contains(nextState) {
                    visited.insert(nextState)
                    queue.append(path + [nextState])
                }
            }
        }

        return [] // No path found
    }

    private func findOrphanedStates() -> [ModelLifecycleState] {
        let allStates = Set(ModelLifecycleState.allCases)
        let referencedStates = Set(transitionHandler.getAllReferencedStates())
        return Array(allStates.subtracting(referencedStates))
    }

    private func findUnreachableStates() -> [ModelLifecycleState] {
        var reachable: Set<ModelLifecycleState> = [.uninitialized]
        var toProcess: [ModelLifecycleState] = [.uninitialized]

        while !toProcess.isEmpty {
            let current = toProcess.removeFirst()
            let transitions = transitionHandler.getAllowedTransitions(from: current)

            for next in transitions {
                if !reachable.contains(next) {
                    reachable.insert(next)
                    toProcess.append(next)
                }
            }
        }

        let allStates = Set(ModelLifecycleState.allCases)
        return Array(allStates.subtracting(reachable))
    }
}

// MARK: - Data Structures

struct LifecycleStatistics {
    let currentState: ModelLifecycleState
    let totalTransitions: Int
    let errorCount: Int
    let averageTransitionTime: TimeInterval
    let observerCount: Int
    let stateHistory: [StateHistoryEntry]
    let lastError: (Error, Date)?
}

struct LifecycleValidationResult {
    let isValid: Bool
    let issues: [String]
    let orphanedStates: [ModelLifecycleState]
    let unreachableStates: [ModelLifecycleState]
}

struct StateHistoryEntry {
    let state: ModelLifecycleState
    let timestamp: Date
    let duration: TimeInterval?
}
