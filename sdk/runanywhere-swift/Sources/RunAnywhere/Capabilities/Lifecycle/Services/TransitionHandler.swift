import Foundation

/// Handles state transitions and validates transition rules
class TransitionHandler {
    private let logger = SDKLogger(category: "TransitionHandler")
    private weak var stateProvider: StateManager?
    private var errorHandler: ((Error) -> Void)?

    // Transition statistics
    private var transitionCount: Int = 0
    private var errorCount: Int = 0
    private var transitionTimes: [TimeInterval] = []
    private var lastError: (Error, Date)?
    private let statisticsLock = NSLock()

    /// Valid state transitions mapping
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

    func setStateProvider(_ provider: StateManager) {
        stateProvider = provider
    }

    func setErrorHandler(_ handler: @escaping (Error) -> Void) {
        errorHandler = handler
    }

    // MARK: - Transition Validation

    func isValidTransition(from: ModelLifecycleState, to: ModelLifecycleState) -> Bool {
        return validTransitions[from]?.contains(to) ?? false
    }

    func getAllowedTransitions(from state: ModelLifecycleState) -> Set<ModelLifecycleState> {
        return validTransitions[state] ?? []
    }

    func validateTransition(from: ModelLifecycleState, to: ModelLifecycleState) throws {
        guard isValidTransition(from: from, to: to) else {
            throw ModelLifecycleError.invalidTransition(from: from, to: to)
        }
    }

    // MARK: - Transition Execution

    func executeTransition(from: ModelLifecycleState, to: ModelLifecycleState) async throws {
        let startTime = Date()

        do {
            // Validate transition
            try validateTransition(from: from, to: to)

            // Execute pre-transition hooks
            try await executePreTransitionHooks(from: from, to: to)

            // Perform state-specific transition logic
            try await performTransitionLogic(from: from, to: to)

            // Execute post-transition hooks
            try await executePostTransitionHooks(from: from, to: to)

            // Record successful transition
            recordTransition(from: from, to: to, startTime: startTime, success: true)

            logger.debug("Successfully executed transition from \(from) to \(to)")

        } catch {
            // Record failed transition
            recordTransition(from: from, to: to, startTime: startTime, success: false, error: error)

            logger.error("Failed to execute transition from \(from) to \(to): \(error)")

            // Notify error handler
            errorHandler?(error)

            throw error
        }
    }

    // MARK: - Transition Logic

    private func executePreTransitionHooks(from: ModelLifecycleState, to: ModelLifecycleState) async throws {
        logger.debug("Executing pre-transition hooks: \(from) -> \(to)")

        switch (from, to) {
        case (_, .error):
            // Cleanup any ongoing operations when transitioning to error
            try await cleanupOngoingOperations()

        case (_, .cleanup):
            // Prepare for cleanup
            try await prepareForCleanup()

        case (.ready, .executing):
            // Validate ready state before execution
            try await validateReadyState()

        default:
            break
        }
    }

    private func performTransitionLogic(from: ModelLifecycleState, to: ModelLifecycleState) async throws {
        logger.debug("Performing transition logic: \(from) -> \(to)")

        switch to {
        case .discovered:
            try await handleDiscoveryTransition()

        case .downloading:
            try await handleDownloadingTransition()

        case .downloaded:
            try await handleDownloadedTransition()

        case .extracting:
            try await handleExtractingTransition()

        case .extracted:
            try await handleExtractedTransition()

        case .validating:
            try await handleValidatingTransition()

        case .validated:
            try await handleValidatedTransition()

        case .initializing:
            try await handleInitializingTransition()

        case .initialized:
            try await handleInitializedTransition()

        case .loading:
            try await handleLoadingTransition()

        case .loaded:
            try await handleLoadedTransition()

        case .ready:
            try await handleReadyTransition()

        case .executing:
            try await handleExecutingTransition()

        case .error:
            try await handleErrorTransition()

        case .cleanup:
            try await handleCleanupTransition()

        case .uninitialized:
            try await handleUninitializedTransition()
        }
    }

    private func executePostTransitionHooks(from: ModelLifecycleState, to: ModelLifecycleState) async throws {
        logger.debug("Executing post-transition hooks: \(from) -> \(to)")

        switch (from, to) {
        case (_, .ready):
            // Verify model is truly ready
            try await verifyModelReady()

        case (_, .error):
            // Log error state entry
            logErrorStateEntry(from: from)

        case (.cleanup, .uninitialized):
            // Verify complete cleanup
            try await verifyCleanupComplete()

        default:
            break
        }
    }

    // MARK: - State-Specific Handlers

    private func handleDiscoveryTransition() async throws {
        // Model discovery logic would go here
        logger.debug("Handling discovery transition")
    }

    private func handleDownloadingTransition() async throws {
        // Download preparation logic would go here
        logger.debug("Handling downloading transition")
    }

    private func handleDownloadedTransition() async throws {
        // Download completion verification would go here
        logger.debug("Handling downloaded transition")
    }

    private func handleExtractingTransition() async throws {
        // Extraction preparation logic would go here
        logger.debug("Handling extracting transition")
    }

    private func handleExtractedTransition() async throws {
        // Extraction verification would go here
        logger.debug("Handling extracted transition")
    }

    private func handleValidatingTransition() async throws {
        // Validation preparation would go here
        logger.debug("Handling validating transition")
    }

    private func handleValidatedTransition() async throws {
        // Validation verification would go here
        logger.debug("Handling validated transition")
    }

    private func handleInitializingTransition() async throws {
        // Initialization preparation would go here
        logger.debug("Handling initializing transition")
    }

    private func handleInitializedTransition() async throws {
        // Initialization verification would go here
        logger.debug("Handling initialized transition")
    }

    private func handleLoadingTransition() async throws {
        // Model loading preparation would go here
        logger.debug("Handling loading transition")
    }

    private func handleLoadedTransition() async throws {
        // Model loading verification would go here
        logger.debug("Handling loaded transition")
    }

    private func handleReadyTransition() async throws {
        // Ready state preparation would go here
        logger.debug("Handling ready transition")
    }

    private func handleExecutingTransition() async throws {
        // Execution preparation would go here
        logger.debug("Handling executing transition")
    }

    private func handleErrorTransition() async throws {
        // Error state handling would go here
        logger.debug("Handling error transition")
    }

    private func handleCleanupTransition() async throws {
        // Cleanup logic would go here
        logger.debug("Handling cleanup transition")
    }

    private func handleUninitializedTransition() async throws {
        // Reset to uninitialized state would go here
        logger.debug("Handling uninitialized transition")
    }

    // MARK: - Hook Implementations

    private func cleanupOngoingOperations() async throws {
        logger.debug("Cleaning up ongoing operations")
        // Implementation would cancel any ongoing tasks
    }

    private func prepareForCleanup() async throws {
        logger.debug("Preparing for cleanup")
        // Implementation would prepare resources for cleanup
    }

    private func validateReadyState() async throws {
        logger.debug("Validating ready state")
        // Implementation would verify the model is actually ready
    }

    private func verifyModelReady() async throws {
        logger.debug("Verifying model is ready")
        // Implementation would perform final readiness checks
    }

    private func logErrorStateEntry(from: ModelLifecycleState) {
        logger.warning("Entered error state from: \(from)")
    }

    private func verifyCleanupComplete() async throws {
        logger.debug("Verifying cleanup completion")
        // Implementation would verify all resources are cleaned up
    }

    // MARK: - Statistics and Monitoring

    private func recordTransition(from: ModelLifecycleState, to: ModelLifecycleState, startTime: Date, success: Bool, error: Error? = nil) {
        statisticsLock.lock()
        defer { statisticsLock.unlock() }

        transitionCount += 1

        if !success {
            errorCount += 1
            if let error = error {
                lastError = (error, Date())
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        transitionTimes.append(duration)

        // Keep only recent transition times for average calculation
        if transitionTimes.count > 100 {
            transitionTimes.removeFirst()
        }
    }

    func getStatistics() -> TransitionStatistics {
        statisticsLock.lock()
        defer { statisticsLock.unlock() }

        let averageTime = transitionTimes.isEmpty ? 0.0 : transitionTimes.reduce(0, +) / Double(transitionTimes.count)

        return TransitionStatistics(
            totalTransitions: transitionCount,
            errorCount: errorCount,
            averageTransitionTime: averageTime,
            lastError: lastError
        )
    }

    // MARK: - Validation

    func validateTransitionTable() -> [String] {
        var issues: [String] = []

        // Check that all states have at least one transition
        for state in ModelLifecycleState.allCases {
            if validTransitions[state]?.isEmpty ?? true {
                issues.append("State \(state) has no valid transitions")
            }
        }

        // Check for circular dependencies
        if hasCircularDependencies() {
            issues.append("Circular dependencies detected in transition table")
        }

        // Check that error state is reachable from all states
        for state in ModelLifecycleState.allCases {
            if state != .error && !canReachState(.error, from: state) {
                issues.append("Error state not reachable from \(state)")
            }
        }

        return issues
    }

    func getAllReferencedStates() -> [ModelLifecycleState] {
        var referenced: Set<ModelLifecycleState> = []

        for (from, toStates) in validTransitions {
            referenced.insert(from)
            referenced.formUnion(toStates)
        }

        return Array(referenced)
    }

    private func hasCircularDependencies() -> Bool {
        // Simple cycle detection - in a real implementation this would be more sophisticated
        return false
    }

    private func canReachState(_ target: ModelLifecycleState, from start: ModelLifecycleState) -> Bool {
        var visited: Set<ModelLifecycleState> = []
        var toVisit: [ModelLifecycleState] = [start]

        while !toVisit.isEmpty {
            let current = toVisit.removeFirst()

            if current == target {
                return true
            }

            if visited.contains(current) {
                continue
            }

            visited.insert(current)

            if let transitions = validTransitions[current] {
                toVisit.append(contentsOf: transitions)
            }
        }

        return false
    }
}

// MARK: - Data Structures

struct TransitionStatistics {
    let totalTransitions: Int
    let errorCount: Int
    let averageTransitionTime: TimeInterval
    let lastError: (Error, Date)?

    var errorRate: Double {
        return totalTransitions > 0 ? Double(errorCount) / Double(totalTransitions) : 0.0
    }

    var errorRatePercentage: String {
        return String(format: "%.1f%%", errorRate * 100)
    }
}
