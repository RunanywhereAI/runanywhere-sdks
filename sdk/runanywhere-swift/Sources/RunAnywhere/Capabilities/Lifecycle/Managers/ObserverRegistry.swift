import Foundation

/// Registry for lifecycle observers with weak reference management
class ObserverRegistry {
    private var observers: [UUID: WeakObserver] = [:]
    private let observerLock = NSLock()
    private let logger = SDKLogger(category: "ObserverRegistry")

    // Statistics
    private var notificationCount: Int = 0
    private var errorNotificationCount: Int = 0
    private var lastCleanupTime: Date = Date()

    // MARK: - Observer Management

    func addObserver(_ observer: ModelLifecycleObserver) {
        observerLock.lock()
        defer { observerLock.unlock() }

        let id = UUID()
        observers[id] = WeakObserver(observer: observer)

        logger.debug("Added lifecycle observer (total: \(observers.count))")

        // Perform cleanup periodically
        performPeriodicCleanup()
    }

    func removeObserver(_ observer: ModelLifecycleObserver) {
        observerLock.lock()
        defer { observerLock.unlock() }

        let initialCount = observers.count
        observers = observers.filter { $0.value.observer !== observer }

        let removedCount = initialCount - observers.count
        if removedCount > 0 {
            logger.debug("Removed \(removedCount) observer(s) (remaining: \(observers.count))")
        }
    }

    func removeAllObservers() {
        observerLock.lock()
        defer { observerLock.unlock() }

        let count = observers.count
        observers.removeAll()

        logger.info("Removed all \(count) observers")
    }

    // MARK: - Notification Management

    func notifyStateChange(from oldState: ModelLifecycleState, to newState: ModelLifecycleState) async {
        let activeObservers = getActiveObservers()

        guard !activeObservers.isEmpty else {
            logger.debug("No observers to notify for state change: \(oldState) -> \(newState)")
            return
        }

        logger.debug("Notifying \(activeObservers.count) observers of state change: \(oldState) -> \(newState)")

        // Notify all observers concurrently
        await withTaskGroup(of: Void.self) { group in
            for observer in activeObservers {
                group.addTask {
                    observer.modelDidTransition(from: oldState, to: newState)
                }
            }
        }

        recordNotification()
    }

    func notifyError(_ error: Error, in state: ModelLifecycleState) async {
        let activeObservers = getActiveObservers()

        guard !activeObservers.isEmpty else {
            logger.debug("No observers to notify for error in state \(state)")
            return
        }

        logger.debug("Notifying \(activeObservers.count) observers of error in state \(state): \(error)")

        // Notify all observers concurrently
        await withTaskGroup(of: Void.self) { group in
            for observer in activeObservers {
                group.addTask {
                    observer.modelDidEncounterError(error, in: state)
                }
            }
        }

        recordErrorNotification()
    }

    func notifyProgress(_ progress: ModelLifecycleProgress) async {
        let activeObservers = getActiveObservers()

        guard !activeObservers.isEmpty else {
            return
        }

        // Only log progress notifications at debug level to avoid spam
        logger.debug("Notifying \(activeObservers.count) observers of progress: \(progress.percentage)%")

        // Notify observers that support progress updates
        await withTaskGroup(of: Void.self) { group in
            for observer in activeObservers {
                if let progressObserver = observer as? ModelLifecycleProgressObserver {
                    group.addTask {
                        progressObserver.modelDidUpdateProgress(progress)
                    }
                }
            }
        }

        recordNotification()
    }

    // MARK: - Observer Cleanup

    func cleanupStaleObservers() {
        observerLock.lock()
        defer { observerLock.unlock() }

        let initialCount = observers.count
        observers = observers.filter { $0.value.observer != nil }

        let removedCount = initialCount - observers.count
        if removedCount > 0 {
            logger.debug("Cleaned up \(removedCount) stale observer(s) (remaining: \(observers.count))")
        }

        lastCleanupTime = Date()
    }

    func performPeriodicCleanup() {
        let timeSinceCleanup = Date().timeIntervalSince(lastCleanupTime)

        // Cleanup every 5 minutes
        if timeSinceCleanup > 300 {
            cleanupStaleObservers()
        }
    }

    // MARK: - Observer Information

    func getActiveObserverCount() -> Int {
        observerLock.lock()
        defer { observerLock.unlock() }

        return observers.values.compactMap { $0.observer }.count
    }

    func getRegisteredObserverCount() -> Int {
        observerLock.lock()
        defer { observerLock.unlock() }

        return observers.count
    }

    func getObserverTypes() -> [String] {
        let activeObservers = getActiveObservers()
        return Array(Set(activeObservers.map { String(describing: type(of: $0)) }))
    }

    // MARK: - Statistics

    func getStatistics() -> ObserverRegistryStatistics {
        observerLock.lock()
        defer { observerLock.unlock() }

        let activeCount = observers.values.compactMap { $0.observer }.count
        let staleCount = observers.count - activeCount

        return ObserverRegistryStatistics(
            registeredObservers: observers.count,
            activeObservers: activeCount,
            staleObservers: staleCount,
            totalNotifications: notificationCount,
            errorNotifications: errorNotificationCount,
            lastCleanupTime: lastCleanupTime,
            observerTypes: getObserverTypes()
        )
    }

    func resetStatistics() {
        observerLock.lock()
        defer { observerLock.unlock() }

        notificationCount = 0
        errorNotificationCount = 0

        logger.debug("Reset observer registry statistics")
    }

    // MARK: - Observer Validation

    func validateObservers() -> ObserverValidationResult {
        let activeObservers = getActiveObservers()
        var issues: [String] = []

        // Check for duplicate observers
        let observerTypes = activeObservers.map { String(describing: type(of: $0)) }
        let uniqueTypes = Set(observerTypes)

        if observerTypes.count != uniqueTypes.count {
            issues.append("Duplicate observer types detected")
        }

        // Check for memory leaks (too many observers)
        if activeObservers.count > 20 {
            issues.append("Unusually high number of observers (\(activeObservers.count)) - potential memory leak")
        }

        // Check for stale references
        let staleCount = getRegisteredObserverCount() - getActiveObserverCount()
        if staleCount > 5 {
            issues.append("High number of stale observer references (\(staleCount))")
        }

        return ObserverValidationResult(
            isValid: issues.isEmpty,
            issues: issues,
            activeObservers: activeObservers.count,
            staleObservers: staleCount
        )
    }

    // MARK: - Debugging Support

    func dumpObserverInfo() -> [ObserverInfo] {
        let activeObservers = getActiveObservers()

        return activeObservers.enumerated().map { index, observer in
            ObserverInfo(
                index: index,
                type: String(describing: type(of: observer)),
                memoryAddress: String(describing: ObjectIdentifier(observer)),
                supportsProgress: observer is ModelLifecycleProgressObserver
            )
        }
    }

    // MARK: - Private Implementation

    private func getActiveObservers() -> [ModelLifecycleObserver] {
        observerLock.lock()
        defer { observerLock.unlock() }

        return observers.values.compactMap { $0.observer }
    }

    private func recordNotification() {
        observerLock.lock()
        defer { observerLock.unlock() }

        notificationCount += 1
    }

    private func recordErrorNotification() {
        observerLock.lock()
        defer { observerLock.unlock() }

        notificationCount += 1
        errorNotificationCount += 1
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

// MARK: - Data Structures

struct ObserverRegistryStatistics {
    let registeredObservers: Int
    let activeObservers: Int
    let staleObservers: Int
    let totalNotifications: Int
    let errorNotifications: Int
    let lastCleanupTime: Date
    let observerTypes: [String]

    var cleanupNeeded: Bool {
        return staleObservers > 0
    }

    var notificationRate: Double {
        let elapsed = Date().timeIntervalSince(lastCleanupTime)
        return elapsed > 0 ? Double(totalNotifications) / elapsed : 0.0
    }
}

struct ObserverValidationResult {
    let isValid: Bool
    let issues: [String]
    let activeObservers: Int
    let staleObservers: Int
}

struct ObserverInfo {
    let index: Int
    let type: String
    let memoryAddress: String
    let supportsProgress: Bool
}

// MARK: - Thread Safety Extensions

extension ObserverRegistry {
    /// Execute a block with exclusive access to the observer registry
    func withObserverAccess<T>(_ block: ([ModelLifecycleObserver]) throws -> T) rethrows -> T {
        let observers = getActiveObservers()
        return try block(observers)
    }
}
