import Foundation

/// Manages the current lifecycle state and state history
class StateManager {
    private var currentState: ModelLifecycleState = .uninitialized
    private let stateLock = NSLock()
    private let logger = SDKLogger(category: "StateManager")

    // State history tracking
    private var stateHistory: [StateHistoryEntry] = []
    private let maxHistoryEntries = 100
    private var stateStartTime: Date = Date()

    // State change callbacks
    private var stateChangeCallbacks: [(ModelLifecycleState, ModelLifecycleState) -> Void] = []

    init() {
        recordStateEntry(.uninitialized)
    }

    // MARK: - State Access

    func getCurrentState() -> ModelLifecycleState {
        stateLock.lock()
        defer { stateLock.unlock() }

        return currentState
    }

    func setState(_ newState: ModelLifecycleState) {
        stateLock.lock()
        let oldState = currentState
        currentState = newState

        // Record state change
        recordStateTransition(from: oldState, to: newState)
        stateLock.unlock()

        // Notify callbacks
        notifyStateChangeCallbacks(from: oldState, to: newState)

        logger.debug("State changed from \(oldState) to \(newState)")
    }

    func isInState(_ state: ModelLifecycleState) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }

        return currentState == state
    }

    // MARK: - State History

    func getStateHistory() -> [StateHistoryEntry] {
        stateLock.lock()
        defer { stateLock.unlock() }

        return stateHistory
    }

    func getStateHistory(since: Date) -> [StateHistoryEntry] {
        stateLock.lock()
        defer { stateLock.unlock() }

        return stateHistory.filter { $0.timestamp >= since }
    }

    func getTimeInCurrentState() -> TimeInterval {
        stateLock.lock()
        defer { stateLock.unlock() }

        return Date().timeIntervalSince(stateStartTime)
    }

    func getTimeInState(_ state: ModelLifecycleState) -> TimeInterval {
        stateLock.lock()
        defer { stateLock.unlock() }

        return stateHistory
            .filter { $0.state == state }
            .compactMap { $0.duration }
            .reduce(0, +)
    }

    func getLastStateChange() -> StateHistoryEntry? {
        stateLock.lock()
        defer { stateLock.unlock() }

        return stateHistory.last
    }

    // MARK: - State Callbacks

    func addStateChangeCallback(_ callback: @escaping (ModelLifecycleState, ModelLifecycleState) -> Void) {
        stateLock.lock()
        defer { stateLock.unlock() }

        stateChangeCallbacks.append(callback)
    }

    func clearStateChangeCallbacks() {
        stateLock.lock()
        defer { stateLock.unlock() }

        stateChangeCallbacks.removeAll()
    }

    // MARK: - State Analysis

    func getStateDurations() -> [ModelLifecycleState: TimeInterval] {
        stateLock.lock()
        defer { stateLock.unlock() }

        var durations: [ModelLifecycleState: TimeInterval] = [:]

        for entry in stateHistory {
            if let duration = entry.duration {
                durations[entry.state, default: 0] += duration
            }
        }

        return durations
    }

    func getStateTransitionCount() -> [ModelLifecycleState: Int] {
        stateLock.lock()
        defer { stateLock.unlock() }

        var counts: [ModelLifecycleState: Int] = [:]

        for entry in stateHistory {
            counts[entry.state, default: 0] += 1
        }

        return counts
    }

    func getAverageStateDuration(_ state: ModelLifecycleState) -> TimeInterval? {
        stateLock.lock()
        defer { stateLock.unlock() }

        let durations = stateHistory
            .filter { $0.state == state }
            .compactMap { $0.duration }

        guard !durations.isEmpty else { return nil }

        return durations.reduce(0, +) / Double(durations.count)
    }

    // MARK: - State Validation

    func validateStateConsistency() -> StateValidationResult {
        stateLock.lock()
        defer { stateLock.unlock() }

        var issues: [String] = []

        // Check for gaps in state history
        if stateHistory.count > 1 {
            for i in 1..<stateHistory.count {
                let previousEntry = stateHistory[i-1]
                let currentEntry = stateHistory[i]

                if let prevDuration = previousEntry.duration {
                    let expectedEndTime = previousEntry.timestamp.addingTimeInterval(prevDuration)
                    let timeDiff = abs(currentEntry.timestamp.timeIntervalSince(expectedEndTime))

                    if timeDiff > 1.0 { // More than 1 second gap
                        issues.append("Time gap detected between \(previousEntry.state) and \(currentEntry.state)")
                    }
                }
            }
        }

        // Check for impossible transitions (this would require transition rules)
        // This is a placeholder for more sophisticated validation

        let isValid = issues.isEmpty

        return StateValidationResult(
            isValid: isValid,
            issues: issues,
            currentState: currentState,
            historyCount: stateHistory.count
        )
    }

    // MARK: - Statistics

    func getStatistics() -> StateManagerStatistics {
        stateLock.lock()
        defer { stateLock.unlock() }

        let totalTime = stateHistory.compactMap { $0.duration }.reduce(0, +)
        let stateDistribution = getStateTransitionCount()
        let currentStateDuration = getTimeInCurrentState()

        return StateManagerStatistics(
            currentState: currentState,
            stateHistory: stateHistory,
            totalLifecycleTime: totalTime,
            currentStateDuration: currentStateDuration,
            stateDistribution: stateDistribution,
            historyCount: stateHistory.count
        )
    }

    // MARK: - State Management

    func reset() {
        stateLock.lock()
        defer { stateLock.unlock() }

        // Record final duration for current state
        if let lastEntry = stateHistory.last, lastEntry.duration == nil {
            let duration = Date().timeIntervalSince(lastEntry.timestamp)
            stateHistory[stateHistory.count - 1] = StateHistoryEntry(
                state: lastEntry.state,
                timestamp: lastEntry.timestamp,
                duration: duration
            )
        }

        // Reset to initial state
        currentState = .uninitialized
        stateStartTime = Date()

        // Clear history
        stateHistory.removeAll()
        recordStateEntry(.uninitialized)

        logger.info("State manager reset")
    }

    func compactHistory() {
        stateLock.lock()
        defer { stateLock.unlock() }

        if stateHistory.count > maxHistoryEntries {
            let excess = stateHistory.count - maxHistoryEntries
            stateHistory.removeFirst(excess)
            logger.debug("Compacted state history, removed \(excess) entries")
        }
    }

    // MARK: - Private Implementation

    private func recordStateEntry(_ state: ModelLifecycleState) {
        let entry = StateHistoryEntry(
            state: state,
            timestamp: Date(),
            duration: nil // Will be filled when state changes
        )

        stateHistory.append(entry)
        stateStartTime = entry.timestamp

        // Compact history if needed
        if stateHistory.count > maxHistoryEntries {
            stateHistory.removeFirst()
        }
    }

    private func recordStateTransition(from oldState: ModelLifecycleState, to newState: ModelLifecycleState) {
        let now = Date()

        // Update duration for the previous state
        if let lastIndex = stateHistory.lastIndex(where: { $0.state == oldState && $0.duration == nil }) {
            let duration = now.timeIntervalSince(stateHistory[lastIndex].timestamp)
            stateHistory[lastIndex] = StateHistoryEntry(
                state: oldState,
                timestamp: stateHistory[lastIndex].timestamp,
                duration: duration
            )
        }

        // Add new state entry
        recordStateEntry(newState)
    }

    private func notifyStateChangeCallbacks(from oldState: ModelLifecycleState, to newState: ModelLifecycleState) {
        // Create a copy to avoid holding the lock during callbacks
        stateLock.lock()
        let callbacks = stateChangeCallbacks
        stateLock.unlock()

        for callback in callbacks {
            callback(oldState, newState)
        }
    }
}

// MARK: - Data Structures

struct StateManagerStatistics {
    let currentState: ModelLifecycleState
    let stateHistory: [StateHistoryEntry]
    let totalLifecycleTime: TimeInterval
    let currentStateDuration: TimeInterval
    let stateDistribution: [ModelLifecycleState: Int]
    let historyCount: Int

    var averageStateDuration: TimeInterval {
        return historyCount > 0 ? totalLifecycleTime / Double(historyCount) : 0
    }

    var mostCommonState: ModelLifecycleState? {
        return stateDistribution.max { $0.value < $1.value }?.key
    }
}

struct StateValidationResult {
    let isValid: Bool
    let issues: [String]
    let currentState: ModelLifecycleState
    let historyCount: Int
}

// MARK: - Extensions

extension StateManager: CustomStringConvertible {
    var description: String {
        stateLock.lock()
        defer { stateLock.unlock() }

        return "StateManager(current: \(currentState), history: \(stateHistory.count) entries)"
    }
}
